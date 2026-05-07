// lib/config.dart
// ─────────────────────────────────────────────────────────
// Change MQTT_HOST to your machine's IP when testing on a
// real Android phone (not emulator).
//
// Find your IP:
//   Linux/Mac:  ip addr | grep 192
//   Windows:    ipconfig
//
// Phone and laptop must be on the SAME Wi-Fi network.
// ─────────────────────────────────────────────────────────

class AppConfig {
  // ── MQTT Broker ───────────────────────────────────────
  // For Android Emulator:  '10.0.2.2'       (maps to your localhost)
  // For Real Phone:        '192.168.31.116'  (your machine's LAN IP) ← CURRENT
  static const mqttHost = '192.168.31.116';
  static const mqttPort = 1883;

  // ── GPS Settings ──────────────────────────────────────
  static const publishIntervalMovingSec = 5;   // when speed > threshold
  static const publishIntervalIdleSec   = 60;  // when parked
  static const speedThresholdKmh        = 5.0;
  static const minAccuracyMeters        = 50.0; // discard bad GPS

  // ── Offline Buffer ────────────────────────────────────
  static const maxBufferSize = 10000; // ~27 hours of 10s pings
}
