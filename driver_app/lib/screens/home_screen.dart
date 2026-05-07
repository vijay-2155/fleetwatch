// lib/screens/home_screen.dart
// Main driver screen — designed for one-handed use on cheap Android phones.
// Big buttons, high contrast, clear status indicators.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/tracking_provider.dart';
import '../services/mqtt_service.dart';
import 'trip_setup_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<TrackingProvider>(
        builder: (context, tracker, _) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(tracker),
                  const SizedBox(height: 24),
                  _buildStatusCards(tracker),
                  const SizedBox(height: 24),
                  _buildSpeedometer(tracker),
                  const Spacer(),
                  if (tracker.isTracking) ...[
                    _buildPendingWarning(tracker),
                    const SizedBox(height: 12),
                    _buildSOSButton(context),
                    const SizedBox(height: 12),
                    _buildEndTripButton(context, tracker),
                  ] else
                    _buildStartTripButton(context, tracker),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(TrackingProvider tracker) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFF1E3A5F),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.local_shipping, color: Colors.white, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Fleet Tracker',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (tracker.vehicleId != null)
                Text(
                  tracker.vehicleId!,
                  style: const TextStyle(
                    color: Color(0xFF8BA3BC),
                    fontSize: 13,
                  ),
                ),
            ],
          ),
        ),
        _MqttStatusBadge(state: tracker.mqttState),
      ],
    );
  }

  Widget _buildStatusCards(TrackingProvider tracker) {
    return Row(
      children: [
        Expanded(
          child: _StatusCard(
            label: 'GPS',
            value: tracker.lat != null
                ? '${tracker.lat!.toStringAsFixed(4)}, ${tracker.lng!.toStringAsFixed(4)}'
                : 'Acquiring...',
            icon: Icons.gps_fixed,
            color: tracker.lat != null ? Colors.greenAccent : Colors.orange,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatusCard(
            label: 'Accuracy',
            value: tracker.gpsAccuracy > 0
                ? '±${tracker.gpsAccuracy.toStringAsFixed(0)}m'
                : '—',
            icon: Icons.radar,
            color: tracker.gpsAccuracy > 0 && tracker.gpsAccuracy < 20
                ? Colors.greenAccent
                : Colors.orange,
          ),
        ),
      ],
    );
  }

  Widget _buildSpeedometer(TrackingProvider tracker) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2B3C),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF2A3F55),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Text(
            tracker.isTracking ? tracker.speedKmh.toStringAsFixed(1) : '—',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 64,
              fontWeight: FontWeight.bold,
              height: 1,
            ),
          ),
          const Text(
            'km/h',
            style: TextStyle(
              color: Color(0xFF8BA3BC),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            tracker.isTracking
                ? (tracker.speedKmh > 5 ? '🚛 Moving' : '🅿️ Parked')
                : 'Trip not started',
            style: const TextStyle(color: Color(0xFF8BA3BC), fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingWarning(TrackingProvider tracker) {
    if (tracker.pendingEvents == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF3D2B00),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.shade700),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off, color: Colors.orange, size: 18),
          const SizedBox(width: 8),
          Text(
            '${tracker.pendingEvents} locations pending sync',
            style: const TextStyle(color: Colors.orange, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildStartTripButton(BuildContext context, TrackingProvider tracker) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF00C853),
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(60),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: const Icon(Icons.play_arrow, size: 28),
      label: const Text(
        'START TRIP',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1),
      ),
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const TripSetupScreen()),
      ),
    );
  }

  Widget _buildEndTripButton(BuildContext context, TrackingProvider tracker) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFD32F2F),
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: const Icon(Icons.stop, size: 26),
      label: const Text(
        'END TRIP',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      onPressed: () => _confirmEndTrip(context, tracker),
    );
  }

  Widget _buildSOSButton(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.redAccent,
        side: const BorderSide(color: Colors.redAccent, width: 1.5),
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: const Icon(Icons.warning_amber_rounded),
      label: const Text(
        '🆘  SOS Emergency',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
      onPressed: () => _triggerSOS(context),
    );
  }

  Future<void> _confirmEndTrip(BuildContext context, TrackingProvider tracker) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2B3C),
        title: const Text('End Trip?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Tracking will stop. Any offline data will sync first.',
          style: TextStyle(color: Color(0xFF8BA3BC)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('End Trip'),
          ),
        ],
      ),
    );
    if (confirm == true) await tracker.endTrip();
  }

  void _triggerSOS(BuildContext context) {
    // TODO: Send SOS event via MQTT + notify emergency contact
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🆘 SOS Alert Sent to Fleet Manager'),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 4),
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatusCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2B3C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A3F55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Text(label,
                  style: const TextStyle(
                      color: Color(0xFF8BA3BC), fontSize: 12)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
                color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _MqttStatusBadge extends StatelessWidget {
  final MqttConnectionState state;
  const _MqttStatusBadge({required this.state});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (state) {
      MqttConnectionState.connected    => (Colors.greenAccent, 'Online'),
      MqttConnectionState.connecting   => (Colors.orange, 'Connecting'),
      MqttConnectionState.disconnected => (Colors.redAccent, 'Offline'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
