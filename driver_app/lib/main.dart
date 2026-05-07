// lib/main.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'providers/tracking_provider.dart';
import 'screens/home_screen.dart';
import 'services/tracking_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize foreground task config at app start
  TrackingService.init();

  // Force portrait — truckers hold phone in one hand
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  runApp(const FleetTrackerApp());
}

class FleetTrackerApp extends StatelessWidget {
  const FleetTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => TrackingProvider(),
      child: MaterialApp(
        title: 'Fleet Tracker',
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(),
        // WithForegroundTask wraps app to handle Android back button correctly
        home: const WithForegroundTask(child: HomeScreen()),
      ),
    );
  }

  ThemeData _buildTheme() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF1E3A5F), // Deep navy
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF0D1B2A),
      fontFamily: 'Roboto',
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(56), // Large tap target for drivers
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}
