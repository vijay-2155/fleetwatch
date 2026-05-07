// lib/services/mqtt_service.dart
// Production MQTT client.
// Handles: connect, auto-reconnect, QoS 1 publish, offline buffer flush.
// All runs inside the foreground service isolate.

import 'dart:async';
import 'dart:convert';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import '../models/truck_event.dart';
import 'offline_buffer.dart';

enum MqttConnectionState { disconnected, connecting, connected }

class MqttService {
  final String brokerHost;
  final int brokerPort;
  final String clientId;

  MqttServerClient? _client;
  MqttConnectionState _state = MqttConnectionState.disconnected;
  Timer? _reconnectTimer;
  Timer? _flushTimer;

  // Called by location service to report state changes
  Function(MqttConnectionState)? onStateChanged;

  MqttService({
    required this.brokerHost,
    required this.brokerPort,
    required this.clientId,
  });

  MqttConnectionState get state => _state;
  bool get isConnected => _state == MqttConnectionState.connected;

  Future<void> connect() async {
    if (_state == MqttConnectionState.connecting ||
        _state == MqttConnectionState.connected) {
      return;
    }

    _setState(MqttConnectionState.connecting);

    _client = MqttServerClient.withPort(brokerHost, clientId, brokerPort);
    _client!
      ..logging(on: false)
      ..keepAlivePeriod = 60          // 60s keepalive — saves battery vs 30s default
      ..connectTimeoutPeriod = 10000  // 10s timeout
      ..autoReconnect = true
      ..resubscribeOnAutoReconnect = true
      ..onConnected = _onConnected
      ..onDisconnected = _onDisconnected
      ..onAutoReconnect = _onAutoReconnect
      ..onAutoReconnected = _onAutoReconnected;

    // Use QoS 1 persistent session so broker remembers us on reconnect
    final connMsg = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .withWillQos(MqttQos.atLeastOnce)
        .startClean(); // persistent session — broker queues for us on disconnect

    _client!.connectionMessage = connMsg;

    try {
      await _client!.connect();
    } on NoConnectionException {
      _setState(MqttConnectionState.disconnected);
      _scheduleReconnect();
    } catch (e) {
      _setState(MqttConnectionState.disconnected);
      _scheduleReconnect();
    }
  }

  /// Publish a single event. If disconnected → write to offline buffer.
  Future<void> publish(TruckEvent event) async {
    if (!isConnected) {
      await OfflineBuffer.write(event);
      return;
    }

    final topic = 'trucks/${event.vehicleId}/location';
    final payload = jsonEncode(event.toJson());
    final builder = MqttClientPayloadBuilder()..addString(payload);

    try {
      _client!.publishMessage(
        topic,
        MqttQos.atLeastOnce, // QoS 1 — broker ACKs receipt
        builder.payload!,
        retain: false,
      );
    } catch (_) {
      // Publish failed mid-connection — buffer it
      await OfflineBuffer.write(event);
    }
  }

  /// Flush buffered offline events to broker.
  /// Called on reconnect. Publishes in batches of 500.
  Future<void> _flushOfflineBuffer() async {
    if (!isConnected) return;

    while (true) {
      final rows = await OfflineBuffer.getUnsynced(limit: 500);
      if (rows.isEmpty) break;

      final ids = <int>[];
      for (final row in rows) {
        if (!isConnected) break; // Stop if disconnected mid-flush

        final event = TruckEvent.fromDbMap(row);
        final topic = 'trucks/${event.vehicleId}/location';
        final payload = jsonEncode(event.toJson());
        final builder = MqttClientPayloadBuilder()..addString(payload);

        try {
          _client!.publishMessage(
            topic,
            MqttQos.atLeastOnce,
            builder.payload!,
          );
          ids.add(row['id'] as int);
        } catch (_) {
          break; // Connection dropped — stop flush
        }
      }

      if (ids.isNotEmpty) {
        await OfflineBuffer.markSynced(ids);
      }

      if (ids.length < 500) break; // No more to flush
    }
  }

  void _onConnected() {
    _setState(MqttConnectionState.connected);
    _reconnectTimer?.cancel();

    // Start periodic buffer flush check (every 30s)
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _flushOfflineBuffer();
    });

    // Immediate flush on connect
    _flushOfflineBuffer();
  }

  void _onDisconnected() {
    _setState(MqttConnectionState.disconnected);
    _flushTimer?.cancel();
    _scheduleReconnect();
  }

  void _onAutoReconnect() {
    _setState(MqttConnectionState.connecting);
  }

  void _onAutoReconnected() {
    _setState(MqttConnectionState.connected);
    _flushOfflineBuffer();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    // Exponential backoff would go here in v2; for now 10s fixed
    _reconnectTimer = Timer(const Duration(seconds: 10), connect);
  }

  void _setState(MqttConnectionState newState) {
    _state = newState;
    onStateChanged?.call(newState);
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _flushTimer?.cancel();
    _client?.disconnect();
    _setState(MqttConnectionState.disconnected);
  }
}
