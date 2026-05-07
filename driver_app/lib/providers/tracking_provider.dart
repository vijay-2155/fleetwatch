// lib/providers/tracking_provider.dart
// State management layer between TrackingService and UI.
// Uses ChangeNotifier so all widgets rebuild automatically.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../services/tracking_service.dart';
import '../services/mqtt_service.dart';
import '../services/offline_buffer.dart';

class TrackingProvider extends ChangeNotifier {
  // ── State ──────────────────────────────────────────────────────────────────
  bool isTracking = false;
  double? lat;
  double? lng;
  double speedKmh = 0;
  double gpsAccuracy = 0;
  MqttConnectionState mqttState = MqttConnectionState.disconnected;
  int pendingEvents = 0;
  String? vehicleId;
  String? driverId;
  String? activeTripId;

  StreamSubscription? _eventSub;

  TrackingProvider() {
    _listenToService();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    vehicleId  = prefs.getString('vehicle_id');
    driverId   = prefs.getString('driver_id');
    // ✅ isRunningService is Future<bool> in flutter_foreground_task v8
    isTracking = await TrackingService.isRunning;
    notifyListeners();
  }

  void _listenToService() {
    _eventSub = TrackingService.events.listen((event) {
      switch (event['type']) {
        case 'position':
          lat       = (event['lat'] as num).toDouble();
          lng       = (event['lng'] as num).toDouble();
          speedKmh  = (event['spd'] as num).toDouble();
          gpsAccuracy = (event['acc'] as num).toDouble();
          break;
        case 'mqtt_state':
          mqttState = MqttConnectionState.values.firstWhere(
            (s) => s.name == event['state'],
            orElse: () => MqttConnectionState.disconnected,
          );
          break;
        case 'pending':
          pendingEvents = event['count'] as int;
          break;
        case 'sos_triggered':
          // TODO: Trigger SOS alert flow
          break;
      }
      notifyListeners();
    });
  }

  Future<void> startTrip({
    required String vehicleId,
    required String driverId,
  }) async {
    final tripId = const Uuid().v4();
    this.vehicleId = vehicleId;
    this.driverId  = driverId;
    activeTripId   = tripId;

    final granted = await TrackingService.requestPermissions();
    if (!granted) return;

    await TrackingService.startTracking(
      vehicleId: vehicleId,
      driverId:  driverId,
      tripId:    tripId,
    );

    isTracking = true;
    notifyListeners();
  }

  Future<void> endTrip() async {
    TrackingService.sendCommand({'cmd': 'end_trip'});
    await Future.delayed(const Duration(seconds: 2)); // Let buffer flush
    await TrackingService.stopTracking();
    isTracking   = false;
    activeTripId = null;
    notifyListeners();
  }

  Future<int> get pendingCount => OfflineBuffer.pendingCount();

  String get mqttStatusLabel {
    switch (mqttState) {
      case MqttConnectionState.connected:    return 'Online';
      case MqttConnectionState.connecting:   return 'Connecting...';
      case MqttConnectionState.disconnected: return 'Offline';
    }
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }
}
