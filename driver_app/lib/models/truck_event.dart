// lib/models/truck_event.dart
// The single unified event struct — matches Go backend TruckEvent exactly

class TruckEvent {
  final String vehicleId; // truck registration / device ID
  final String driverId;  // driver UUID
  final String tripId;    // active trip UUID
  final double lat;
  final double lng;
  final double speed;     // km/h
  final double bearing;   // degrees
  final double accuracy;  // meters — filter bad GPS
  final int timestamp;    // unix seconds (device time)
  final int battery;      // phone battery %
  final String source;    // "mobile" | "ais140" (future hardware)

  const TruckEvent({
    required this.vehicleId,
    required this.driverId,
    required this.tripId,
    required this.lat,
    required this.lng,
    required this.speed,
    required this.bearing,
    required this.accuracy,
    required this.timestamp,
    required this.battery,
    this.source = 'mobile',
  });

  /// Convert to compact JSON map for MQTT publish
  /// Keep field names short — saves bytes on 2G/EDGE
  Map<String, dynamic> toJson() => {
        'vid': vehicleId,
        'did': driverId,
        'tid': tripId,
        'lat': lat,
        'lng': lng,
        'spd': speed,
        'brg': bearing,
        'acc': accuracy,
        'ts': timestamp,
        'bat': battery,
        'src': source,
      };

  /// For SQLite offline buffer
  Map<String, dynamic> toDbMap() => {
        ...toJson(),
        'synced': 0, // 0 = not synced, 1 = synced
      };

  factory TruckEvent.fromDbMap(Map<String, dynamic> map) => TruckEvent(
        vehicleId: map['vid'] as String,
        driverId: map['did'] as String,
        tripId: map['tid'] as String,
        lat: (map['lat'] as num).toDouble(),
        lng: (map['lng'] as num).toDouble(),
        speed: (map['spd'] as num).toDouble(),
        bearing: (map['brg'] as num).toDouble(),
        accuracy: (map['acc'] as num).toDouble(),
        timestamp: map['ts'] as int,
        battery: map['bat'] as int,
        source: map['src'] as String? ?? 'mobile',
      );
}
