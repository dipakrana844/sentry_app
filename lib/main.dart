import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'core/background/background_service.dart';
import 'core/errors/global_error_handler.dart';
import 'core/offline/offline_queue.dart';
import 'core/router/app_router.dart' show createAppRouter;
import 'core/sentry/sentry_config.dart';
import 'data/datasources/local_storage.dart';
import 'domain/entities/user.dart';
import 'presentation/auth/login_controller.dart';

Future<void> main() async {
  // CRITICAL: Initialize Sentry binding FIRST, before any other initialization
  // This must be called before SentryFlutter.init() to enable FramesTrackingIntegration
  SentryWidgetsFlutterBinding.ensureInitialized();

  // Initialize global error handlers BEFORE Sentry init
  // This ensures all errors are captured
  GlobalErrorHandler.initialize();

  // Load environment variables
  await dotenv.load(fileName: ".env");

  // Initialize local storage (for token persistence)
  await LocalStorage.init();

  // Initialize offline queue
  await OfflineQueue.init();

  // Initialize background services
  await BackgroundService.initialize();

  // Start app startup performance transaction
  // This tracks how long app initialization takes
  final startupTransaction = SentryConfig.startAppStartupTransaction();

  // Check for auto-login (stored token and user data)
  User? autoLoginUser;
  try {
    final userData = LocalStorage.getUserData();
    final token = LocalStorage.getToken();

    if (userData != null && token != null && !LocalStorage.isTokenExpired()) {
      autoLoginUser = User(
        id: userData['id'] as String,
        email: userData['email'] as String,
        role: userData['role'] as String,
        token: token,
      );

      // Set user context in Sentry for auto-logged-in user
      SentryConfig.setUserContext(
        autoLoginUser.id,
        autoLoginUser.email,
        autoLoginUser.role,
      );

      SentryConfig.addBreadcrumb(
        'Auto-login successful from stored credentials',
        category: 'auth',
        level: SentryLevel.info,
      );
    } else {
      SentryConfig.addBreadcrumb(
        'No valid stored credentials found, user must login',
        category: 'auth',
      );
    }
  } catch (e, stack) {
    SentryConfig.captureException(
      e,
      stackTrace: stack,
      hint: Hint.withMap({'operation': 'auto_login_check'}),
    );
  }

  // Finish startup transaction
  SentryConfig.finishScreenTransaction(startupTransaction);

  // Initialize Sentry and run app
  await SentryConfig.init(() {
    return ProviderScope(
      child: MyApp(autoLoginUser: autoLoginUser),
    );
  });
}

class MyApp extends ConsumerWidget {
  final User? autoLoginUser;

  const MyApp({super.key, this.autoLoginUser});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // If auto-login user exists, set it in the login controller
    if (autoLoginUser != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final controller = ref.read(loginControllerProvider.notifier);
        // Use setUser method which is public
        controller.setUser(autoLoginUser!);
      });
    }

    // Create router with ref for redirect logic
    final router = createAppRouter(ref);

    return MaterialApp.router(
      title: 'FieldOps',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent),
        useMaterial3: true,
      ),
      routerConfig: router,
    );
  }
}
