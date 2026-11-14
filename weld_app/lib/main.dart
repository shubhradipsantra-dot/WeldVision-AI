import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// ✅ Core Services & Providers
import 'providers/user_provider.dart';
import 'services/notification_service.dart';
import 'theme/app_theme.dart';

// ✅ Screens
import 'screens/login_screen.dart';
import 'screens/landing_screen.dart';
import 'screens/training_progress_screen.dart';

// Global navigator key for notification routing
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  // Ensure Flutter bindings are initialized before using platform channels
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // 1. Initialize Notification Service
    await NotificationService.instance.init(
      navigatorKey: navigatorKey,
      trainingRouteBuilder: (jobId) => MaterialPageRoute(
        builder: (_) => TrainingProgressScreen(jobId: jobId),
      ),
    );

    // 2. Initialize User Provider (checks for existing secure session)
    final userProvider = UserProvider();
    await userProvider.initialize();

    // 3. Run the App
    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => userProvider),
        ],
        child: const WeldVisionApp(),
      ),
    );
  } catch (e) {
    // Fallback in case of critical initialization failure
    debugPrint('Failed to initialize app: $e');
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text('Failed to initialize application.'),
          ),
        ),
      ),
    );
  }
}

class WeldVisionApp extends StatelessWidget {
  const WeldVisionApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WeldVision AI',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: AppTheme.darkTheme,
      home: Consumer<UserProvider>(
        builder: (context, userProvider, child) {
          return userProvider.isLoggedIn
              ? const LandingScreen()
              : const LoginScreen();
        },
      ),
    );
  }
}
