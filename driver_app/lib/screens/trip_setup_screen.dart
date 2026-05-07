// lib/screens/trip_setup_screen.dart
// Driver enters vehicle ID and their info before starting a trip.
// In production this would be pre-filled from login/auth.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/tracking_provider.dart';

class TripSetupScreen extends StatefulWidget {
  const TripSetupScreen({super.key});

  @override
  State<TripSetupScreen> createState() => _TripSetupScreenState();
}

class _TripSetupScreenState extends State<TripSetupScreen> {
  final _vehicleCtrl = TextEditingController();
  final _driverCtrl  = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    _vehicleCtrl.text = prefs.getString('vehicle_id') ?? '';
    _driverCtrl.text  = prefs.getString('driver_id')  ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Start New Trip'),
        backgroundColor: const Color(0xFF0D1B2A),
        foregroundColor: Colors.white,
      ),
      backgroundColor: const Color(0xFF0D1B2A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Vehicle & Driver Details',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'This info is sent with every GPS update.',
                  style: TextStyle(color: Color(0xFF8BA3BC), fontSize: 14),
                ),
                const SizedBox(height: 32),
                _buildField(
                  controller: _vehicleCtrl,
                  label: 'Vehicle Registration Number',
                  hint: 'e.g. MH12AB1234',
                  icon: Icons.local_shipping,
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                _buildField(
                  controller: _driverCtrl,
                  label: 'Driver ID / Phone',
                  hint: 'e.g. +919876543210',
                  icon: Icons.person,
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Required' : null,
                ),
                const Spacer(),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00C853),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(60),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: _loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow, size: 28),
                  label: Text(
                    _loading ? 'Starting...' : 'START TRIP',
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1),
                  ),
                  onPressed: _loading ? null : _startTrip,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      textCapitalization: TextCapitalization.characters,
      style: const TextStyle(color: Colors.white, fontSize: 16),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: Color(0xFF8BA3BC)),
        hintStyle: const TextStyle(color: Color(0xFF4A6B8A)),
        prefixIcon: Icon(icon, color: const Color(0xFF8BA3BC)),
        filled: true,
        fillColor: const Color(0xFF1A2B3C),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2A3F55)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2A3F55)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: Color(0xFF4A9EFF), width: 2),
        ),
      ),
    );
  }

  Future<void> _startTrip() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final tracker = context.read<TrackingProvider>();
    await tracker.startTrip(
      vehicleId: _vehicleCtrl.text.trim().toUpperCase(),
      driverId:  _driverCtrl.text.trim(),
    );

    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _vehicleCtrl.dispose();
    _driverCtrl.dispose();
    super.dispose();
  }
}
