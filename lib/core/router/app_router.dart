import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../../presentation/auth/login_controller.dart';
import '../../presentation/auth/login_screen.dart';
// Screens
import '../../presentation/dashboard/dashboard_screen.dart';
import '../../presentation/debug/crash_test_screen.dart';
import '../../presentation/forms/form_screen.dart';
import '../../presentation/main_screen.dart';
import '../../presentation/maps/map_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Create app router with auto-login redirect logic.
///
/// **Why redirect:**
/// Checks if user is logged in and redirects to dashboard if authenticated,
/// otherwise shows login screen.
GoRouter createAppRouter(WidgetRef? ref) {
  return GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: '/login',
    observers: [SentryNavigatorObserver()],
    redirect: (context, state) {
      // Check auth state if we have a ref (from ProviderScope)
      if (ref != null) {
        final loginState = ref.read(loginControllerProvider);

        // If user is logged in and trying to access login, redirect to dashboard
        if (loginState.hasValue &&
            loginState.value != null &&
            state.uri.path == '/login') {
          return '/dashboard';
        }

        // If user is not logged in and trying to access protected routes, redirect to login
        if ((loginState.value == null || loginState.hasError) &&
            state.uri.path != '/login') {
          return '/login';
        }
      }

      return null; // No redirect needed
    },
    routes: [
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => MainScreen(child: child),
        routes: [
          GoRoute(
            // Use absolute paths for shell children so that
            // navigation calls like `context.go('/dashboard')`
            // resolve correctly on this go_router version.
            path: '/dashboard',
            name: 'dashboard',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/forms',
            name: 'forms',
            builder: (context, state) => const FormScreen(),
          ),
          GoRoute(
            path: '/map',
            name: 'map',
            builder: (context, state) => const MapScreen(),
          ),
          GoRoute(
            path: '/crash-test',
            name: 'crash-test',
            builder: (context, state) => const CrashTestScreen(),
          ),
        ],
      ),
    ],
  );
}

// For backward compatibility, create a default router
// This will be replaced by the one in MyApp
final appRouter = createAppRouter(null);
