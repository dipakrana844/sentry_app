import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import '../../core/errors/failure.dart';
import '../../core/sentry/sentry_config.dart';
import '../../domain/entities/user.dart';
import '../providers.dart';

/// Controller for authentication state and operations.
/// 
/// Uses Riverpod for state management following MVVM pattern.
class LoginController extends StateNotifier<AsyncValue<User?>> {
  LoginController(this.ref) : super(const AsyncValue.data(null));

  final Ref ref;

  /// Login with email and password.
  /// 
  /// **Sentry integration:**
  /// - Logs login attempt as breadcrumb
  /// - Sets user context on success
  /// - Captures errors with context
  /// - Tags errors by error type
  Future<void> login(String email, String password) async {
    state = const AsyncValue.loading();

    // Log login attempt
    SentryConfig.addBreadcrumb(
      'Login attempt started',
      category: 'auth',
      data: {'email': email},
    );
    SentryConfig.setTag('auth_action', 'login');

    try {
      final result = await ref.read(authRepositoryProvider).login(email, password);

      result.fold(
        (failure) {
          // Handle failure
          SentryConfig.addBreadcrumb(
            'Login failed: ${failure.message}',
            category: 'auth',
            level: SentryLevel.warning,
          );
          SentryConfig.setTag('auth_error_type', failure.runtimeType.toString());

          // Capture 500 errors as issues
          if (failure is ServerFailure && failure.message == 'Server Error') {
            SentryConfig.captureException(
              Exception('Login API returned 500'),
              hint: Hint.withMap({
                'email': email,
                'failure_type': 'server_error',
              }),
            );
          }

          state = AsyncValue.error(failure, StackTrace.current);
        },
        (user) {
          // Success - set user context in Sentry
          SentryConfig.setUserContext(user.id, user.email, user.role);
          SentryConfig.addBreadcrumb(
            'Login successful',
            category: 'auth',
            level: SentryLevel.info,
          );
          SentryConfig.setTag('auth_status', 'success');

          state = AsyncValue.data(user);
        },
      );
    } catch (e, stack) {
      // Unexpected error
      SentryConfig.captureException(
        e,
        stackTrace: stack,
        hint: Hint.withMap({
          'email': email,
          'operation': 'login',
        }),
      );
      state = AsyncValue.error(e, stack);
    }
  }

  /// Set user directly (for auto-login).
  /// 
  /// Used when user is restored from local storage.
  void setUser(User user) {
    SentryConfig.setUserContext(user.id, user.email, user.role);
    state = AsyncValue.data(user);
  }

  /// Logout current user.
  /// 
  /// Clears user context from Sentry and local storage.
  Future<void> logout() async {
    SentryConfig.addBreadcrumb(
      'Logout initiated',
      category: 'auth',
    );

    try {
      await ref.read(authRepositoryProvider).logout();
      SentryConfig.clearUserContext();
      SentryConfig.setTag('auth_status', 'logged_out');
      state = const AsyncValue.data(null);
    } catch (e, stack) {
      SentryConfig.captureException(
        e,
        stackTrace: stack,
        hint: Hint.withMap({'operation': 'logout'}),
      );
    }
  }
}

final loginControllerProvider =
    StateNotifierProvider<LoginController, AsyncValue<User?>>(
  (ref) => LoginController(ref),
);
