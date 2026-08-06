import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'screens/ai_status_screen.dart';
import 'screens/control_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/hive_details_screen.dart';
import 'screens/hornet_detection_screen.dart';
import 'screens/live_monitoring_screen.dart';
import 'screens/login_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/security_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/statistics_screen.dart';
import 'theme/app_theme.dart';
import 'utils/app_routes.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  _seedDemoData();
  runApp(const BeeGuardApp());
}
Future<void> _initializeFirebase() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await _seedDemoData();
  } catch (error, stackTrace) {
    debugPrint('Firebase startup skipped: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}

Future<void> _seedDemoData() async {
  try {
    final database = FirebaseDatabase.instance.ref();
    final hiveStatusSnapshot = await database.child('hive_status').get();

    if (hiveStatusSnapshot.exists) {
      return;
    }

    await database.update({
      'hive_status': {
        'temperature': 34.2,
        'humidity': 61.8,
        'weight': 24.3,
        'water_level': 70,
        'sound_result': 'Normal',
        'health_score': 87,
        'last_sync': '13:00:00',
      },
      'ai_status': {
        'sound_result': 'Normal',
        'confidence': 94,
        'last_analysis': 'Today at 13:00',
        'model_version': 'TinyML v1.0',
      },
      'commands': {
        'smoke_pump': false,
        'pump': false,
        'pump_mode': 'water',
        'buzzer': false,
        'entrance': 'open',
        'emergency_lock': false,
      },
      'hornet_detection': {
        'detected': false,
        'entrance_status': 'open',
        'last_detection': 'No detection yet',
        'image_url': '',
      },
      'production': {
        'today_weight': 24.3,
        'yesterday_weight': 23.8,
        'estimated_honey': 0.5,
      },
      'settings': {
        'temp_max': 36,
        'temp_min': 32,
        'humidity_max': 70,
        'notifications_enabled': true,
      },
    });
  } catch (error, stackTrace) {
    debugPrint('Demo data seed skipped: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}

class BeeGuardApp extends StatelessWidget {
  const BeeGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BeeGuard',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      initialRoute: AppRoutes.splash,
      routes: {
        AppRoutes.splash: (context) => const SplashScreen(),
        AppRoutes.login: (context) => const LoginScreen(),
        AppRoutes.dashboard: (context) => const DashboardScreen(),
        AppRoutes.hiveDetails: (context) => const HiveDetailsScreen(),
        AppRoutes.liveMonitoring: (context) => const LiveMonitoringScreen(),
        AppRoutes.aiStatus: (context) => const AiStatusScreen(),
        AppRoutes.control: (context) => const ControlScreen(),
        AppRoutes.security: (context) => const SecurityScreen(),
        AppRoutes.hornetDetection: (context) => const HornetDetectionScreen(),
        AppRoutes.notifications: (context) => const NotificationsScreen(),
        AppRoutes.statistics: (context) => const StatisticsScreen(),
        AppRoutes.profile: (context) => const ProfileScreen(),
        AppRoutes.settings: (context) => const SettingsScreen(),
      },
    );
  }
}
