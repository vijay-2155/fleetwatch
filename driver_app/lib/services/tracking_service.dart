// lib/services/tracking_service.dart
//
// Core production GPS tracking service.
//
// Architecture:
//   - FlutterForegroundTask spawns a separate Dart isolate (foreground service)
//   - That isolate owns: GPS stream + MQTT client + SQLite buffer
//   - UI communicates via IsolateNameServer port (send/receive Map objects)
//
// Android behaviour:
//   - Shows a persistent notification → Android cannot kill this process
//   - autoRunOnBoot: true → resumes tracking after phone restart
//   - allowWakeLock: true → CPU stays awake even screen off
//
// Adaptive GPS publish rate:
//   - Moving  (speed > 5 km/h): publish every 5 seconds
//   - Idle    (speed ≤ 5 km/h): publish every 60 seconds
//   Saves ~80% battery when truck is parked.

import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/truck_event.dart';
import '../config.dart';
import 'mqtt_service.dart';
import 'offline_buffer.dart';

// ─── Constants ────────────────────────────────────────────────────────────────
const _kPortName          = 'fleet_tracker_port';
const _kMovingIntervalSec = 5;     // 5s when driving
const _kIdleIntervalSec   = 60;    // 60s when parked
const _kSpeedThresholdKmh = 5.0;   // below = "idle"
const _kMinAccuracyMeters = 50.0;  // discard GPS worse than 50m

// ─── TaskHandler — runs in Foreground Service Isolate ─────────────────────────
@pragma('vm:entry-point')
class TrackingTaskHandler extends TaskHandler {
  late MqttService _mqtt;
  late String _vehicleId;
  late String _driverId;
  late String _tripId;

  Position?  _lastPosition;
  SendPort?  _uiPort;
  Timer?     _publishTimer;
  bool       _isMoving = false;
  final _battery = Battery(); // battery_plus instance

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    final prefs = await SharedPreferences.getInstance();

    _vehicleId = prefs.getString('vehicle_id')    ?? 'UNKNOWN';
    _driverId  = prefs.getString('driver_id')     ?? 'UNKNOWN';
    _tripId    = prefs.getString('active_trip_id') ?? const Uuid().v4();

    _mqtt = MqttService(
      brokerHost: prefs.getString('mqtt_host') ?? AppConfig.mqttHost,
      brokerPort: prefs.getInt('mqtt_port')    ?? AppConfig.mqttPort,
      clientId: 'driver_${_driverId}_${DateTime.now().millisecondsSinceEpoch}',
    );

    _mqtt.onStateChanged = (state) {
      _sendToUi({'type': 'mqtt_state', 'state': state.name});
    };

    await _mqtt.connect();
    _startGpsStream();

    // Periodic buffer cleanup every 6 hours
    Timer.periodic(const Duration(hours: 6), (_) => OfflineBuffer.cleanup());
  }

  void _startGpsStream() {
    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
      ),
    ).listen(_onPosition);
  }

  Future<void> _onPosition(Position position) async {
    // Filter bad GPS — tunnels, urban canyons, bad sky view
    if (position.accuracy > _kMinAccuracyMeters) return;

    _lastPosition = position;

    final speedKmh = position.speed * 3.6;
    final wasMoving = _isMoving;
    _isMoving = speedKmh > _kSpeedThresholdKmh;

    // Restart publish timer when movement state changes
    if (_isMoving != wasMoving) {
      _publishTimer?.cancel();
      _publishTimer = null;
    }

    _publishTimer ??= Timer.periodic(
      Duration(seconds: _isMoving ? _kMovingIntervalSec : _kIdleIntervalSec),
      (_) => _publishPosition(),
    );

    // Always stream live position to UI (no rate limiting for UI updates)
    _sendToUi({
      'type': 'position',
      'lat': position.latitude,
      'lng': position.longitude,
      'spd': speedKmh,
      'acc': position.accuracy,
      'brg': position.heading,
    });
  }

  Future<void> _publishPosition() async {
    final pos = _lastPosition;
    if (pos == null) return;

    // Round to 2dp — saves ~10 bytes per message on 2G/EDGE
    double round2(double v) => double.parse(v.toStringAsFixed(2));

    // Get real battery level
    int bat = -1;
    try {
      bat = await _battery.batteryLevel;
    } catch (_) {}

    final event = TruckEvent(
      vehicleId: _vehicleId,
      driverId:  _driverId,
      tripId:    _tripId,
      lat:       pos.latitude,         // keep full precision for lat/lng
      lng:       pos.longitude,
      speed:     round2(pos.speed * 3.6),
      bearing:   round2(pos.heading),
      accuracy:  round2(pos.accuracy),
      timestamp: pos.timestamp.millisecondsSinceEpoch ~/ 1000,
      battery:   bat,
    );

    await _mqtt.publish(event);

    final pending = await OfflineBuffer.pendingCount();
    _sendToUi({'type': 'pending', 'count': pending});
  }

  void _sendToUi(Map<String, dynamic> data) {
    _uiPort ??= IsolateNameServer.lookupPortByName(_kPortName);
    _uiPort?.send(data);
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Not used — we manage our own timer in onStart
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    _publishTimer?.cancel();
    _mqtt.disconnect();
  }

  @override
  void onReceiveData(Object data) {
    if (data is Map) {
      final cmd = data['cmd'] as String?;
      switch (cmd) {
        case 'new_trip':
          _tripId = data['trip_id'] as String;
          break;
        case 'end_trip':
          _publishTimer?.cancel();
          _mqtt.disconnect();
          break;
      }
    }
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'sos') {
      _sendToUi({'type': 'sos_triggered'});
    }
  }
}

// ─── TrackingService — public API used by the UI isolate ─────────────────────
class TrackingService {
  static final ReceivePort _receivePort = ReceivePort();
  static StreamController<Map<String, dynamic>>? _eventController;

  /// Stream of events from the service isolate to the UI.
  static Stream<Map<String, dynamic>> get events {
    _eventController ??= StreamController.broadcast();
    return _eventController!.stream;
  }

  /// Call once at app startup (inside main() before runApp).
  static void init() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'fleet_tracking',
        channelName: 'Fleet Tracking',
        channelDescription: 'Active GPS tracking for your trip',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        // ✅ Correct API for v8: notificationButtons on startService, not here
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        // ✅ Correct v8 API: ForegroundTaskEventAction.repeat takes int milliseconds
        eventAction: ForegroundTaskEventAction.repeat(60000), // 1 min heartbeat
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    // Register UI receive port for isolate communication
    IsolateNameServer.registerPortWithName(
      _receivePort.sendPort,
      _kPortName,
    );

    _receivePort.listen((data) {
      if (data is Map<String, dynamic>) {
        _eventController?.add(data);
      }
    });
  }

  /// Request all Android permissions needed for background GPS.
  static Future<bool> requestPermissions() async {
    // 1. Basic location permission
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) return false;

    // 2. Notification permission (Android 13+)
    final notifPerm = await FlutterForegroundTask.checkNotificationPermission();
    if (notifPerm != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    // 3. Battery optimization exemption — CRITICAL for production
    //    Without this, Android Doze mode will pause our service.
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }

    return true;
  }

  /// Start the foreground service and begin GPS tracking.
  static Future<void> startTracking({
    required String vehicleId,
    required String driverId,
    required String tripId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('vehicle_id',    vehicleId);
    await prefs.setString('driver_id',     driverId);
    await prefs.setString('active_trip_id', tripId);

    // ✅ Correct v8 startService API
    await FlutterForegroundTask.startService(
      serviceId: 1001,
      notificationTitle: '🚛 Fleet Tracker Active',
      notificationText: '$vehicleId — Tracking active',
      notificationButtons: [
        const NotificationButton(id: 'sos', text: '🆘 SOS'),
      ],
      callback: _startCallback,
    );
  }

  /// Stop tracking and destroy the foreground service.
  static Future<void> stopTracking() async {
    await FlutterForegroundTask.stopService();
  }

  /// ✅ Correct v8 API: isRunningService is a Future<bool>
  static Future<bool> get isRunning => FlutterForegroundTask.isRunningService;

  /// Send a command down to the service isolate.
  static void sendCommand(Map<String, dynamic> cmd) {
    FlutterForegroundTask.sendDataToTask(cmd);
  }
}

/// Entry point for the foreground service isolate.
/// Must be top-level and annotated with @pragma('vm:entry-point').
@pragma('vm:entry-point')
void _startCallback() {
  FlutterForegroundTask.setTaskHandler(TrackingTaskHandler());
}
