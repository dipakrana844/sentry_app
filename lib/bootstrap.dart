import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'core/background/background_service.dart';
import 'core/errors/global_error_handler.dart';
import 'core/offline/offline_queue.dart';
import 'core/sentry/sentry_config.dart';
import 'data/datasources/local_storage.dart';
import 'domain/entities/user.dart';

/// Bootstrap function to initialize services and run the app.
///
/// **Why this pattern:**
/// separating the app initialization logic from the `main` entry point makes
/// testing easier and keeps the code organized. It also allows for a consistent
/// error handling wrapper (Sentry, in this case) around the entire app startup.
///
/// **Real-world best practice:**
/// Top-tier Flutter apps use a bootstrap function to handle:
/// - Environment configuration
/// - Service initialization (Storage, API clients, etc.)
/// - Global error handling setup
/// - Zone-based error capture
Future<void> bootstrap(
  FutureOr<Widget> Function(User? autoLoginUser) builder,
) async {
  // CRITICAL: Initialize Sentry binding FIRST, before any other initialization
  // This must be called before SentryFlutter.init() to enable FramesTrackingIntegration
  SentryWidgetsFlutterBinding.ensureInitialized();

  // Initialize global error handlers BEFORE Sentry init
  GlobalErrorHandler.initialize();

  // Load environment variables
  await dotenv.load(fileName: '.env');

  // Initialize local storage (for token persistence)
  await LocalStorage.init();

  // Initialize offline queue
  await OfflineQueue.init();

  // Initialize background services
  await BackgroundService.initialize();

  // Start app startup performance transaction
  final startupTransaction = SentryConfig.startAppStartupTransaction();

  // Check for auto-login (stored token and user data)
  final autoLoginUser = _checkAutoLogin();

  // Finish startup transaction
  SentryConfig.finishScreenTransaction(startupTransaction);

  // Initialize Sentry and run app
  await SentryConfig.init(() async {
    return await builder(autoLoginUser);
  });
}

User? _checkAutoLogin() {
  try {
    final userData = LocalStorage.getUserData();
    final token = LocalStorage.getToken();

    if (userData != null && token != null && !LocalStorage.isTokenExpired()) {
      final user = User(
        id: userData['id'] as String,
        email: userData['email'] as String,
        role: userData['role'] as String,
        token: token,
      );

      // Set user context in Sentry for auto-logged-in user
      SentryConfig.setUserContext(user.id, user.email, user.role);

      SentryConfig.addBreadcrumb(
        'Auto-login successful from stored credentials',
        category: 'auth',
        level: SentryLevel.info,
      );

      return user;
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
  return null;
}
