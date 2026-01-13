import 'package:hive_flutter/hive_flutter.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import '../../core/sentry/sentry_config.dart';

/// Local storage service using Hive for persistent data storage.
/// 
/// **Why Hive:**
/// - Fast, lightweight NoSQL database
/// - Works offline
/// - Type-safe with adapters
/// - Perfect for storing tokens, user preferences, cached data
/// 
/// **Real-world problem solved:**
/// Users don't want to log in every time they open the app. Token persistence
/// enables auto-login, improving UX. Also useful for caching data offline.
class LocalStorage {
  static const String _boxName = 'fieldops_storage';
  static const String _tokenKey = 'auth_token';
  static const String _userKey = 'user_data';
  static const String _expiryKey = 'token_expiry';

  static Box? _box;

  /// Initialize the storage box.
  /// 
  /// Must be called during app initialization (in main.dart).
  static Future<void> init() async {
    try {
      _box = await Hive.openBox(_boxName);
      SentryConfig.addBreadcrumb(
        'Local storage initialized',
        category: 'storage',
      );
    } catch (e, stack) {
      SentryConfig.captureException(
        e,
        stackTrace: stack,
        hint: Hint.withMap({'operation': 'storage_init'}),
      );
      rethrow;
    }
  }

  /// Save authentication token.
  /// 
  /// **Sentry integration:**
  /// Logs token save operation as breadcrumb (without exposing token value).
  static Future<void> saveToken(String token) async {
    try {
      await _box?.put(_tokenKey, token);
      SentryConfig.addBreadcrumb(
        'Token saved to local storage',
        category: 'auth',
      );
    } catch (e, stack) {
      SentryConfig.captureException(
        e,
        stackTrace: stack,
        hint: Hint.withMap({'operation': 'save_token'}),
      );
      rethrow;
    }
  }

  /// Get stored authentication token.
  /// 
  /// Returns null if no token is stored.
  static String? getToken() {
    try {
      final token = _box?.get(_tokenKey) as String?;
      if (token != null) {
        SentryConfig.addBreadcrumb(
          'Token retrieved from local storage',
          category: 'auth',
        );
      }
      return token;
    } catch (e, stack) {
      SentryConfig.captureException(
        e,
        stackTrace: stack,
        hint: Hint.withMap({'operation': 'get_token'}),
      );
      return null;
    }
  }

  /// Save token expiry timestamp.
  /// 
  /// Used to check if token is expired without making an API call.
  static Future<void> saveTokenExpiry(DateTime expiry) async {
    try {
      await _box?.put(_expiryKey, expiry.toIso8601String());
    } catch (e, stack) {
      SentryConfig.captureException(
        e,
        stackTrace: stack,
        hint: Hint.withMap({'operation': 'save_token_expiry'}),
      );
    }
  }

  /// Get token expiry timestamp.
  /// 
  /// Returns null if no expiry is stored.
  static DateTime? getTokenExpiry() {
    try {
      final expiryStr = _box?.get(_expiryKey) as String?;
      if (expiryStr != null) {
        return DateTime.parse(expiryStr);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Check if token is expired.
  /// 
  /// Returns true if token expiry exists and is in the past.
  static bool isTokenExpired() {
    final expiry = getTokenExpiry();
    if (expiry == null) return false;
    return DateTime.now().isAfter(expiry);
  }

  /// Save user data (for auto-login).
  /// 
  /// Stores user ID, email, and role for quick access.
  static Future<void> saveUserData({
    required String id,
    required String email,
    required String role,
  }) async {
    try {
      await _box?.put(_userKey, {
        'id': id,
        'email': email,
        'role': role,
      });
      SentryConfig.addBreadcrumb(
        'User data saved to local storage',
        category: 'auth',
      );
    } catch (e, stack) {
      SentryConfig.captureException(
        e,
        stackTrace: stack,
        hint: Hint.withMap({'operation': 'save_user_data'}),
      );
    }
  }

  /// Get stored user data.
  /// 
  /// Returns null if no user data is stored.
  static Map<String, dynamic>? getUserData() {
    try {
      final data = _box?.get(_userKey) as Map<String, dynamic>?;
      if (data != null) {
        SentryConfig.addBreadcrumb(
          'User data retrieved from local storage',
          category: 'auth',
        );
      }
      return data;
    } catch (e, stack) {
      SentryConfig.captureException(
        e,
        stackTrace: stack,
        hint: Hint.withMap({'operation': 'get_user_data'}),
      );
      return null;
    }
  }

  /// Clear all authentication data (token, user data, expiry).
  /// 
  /// Called on logout.
  static Future<void> clearAuthData() async {
    try {
      await _box?.delete(_tokenKey);
      await _box?.delete(_userKey);
      await _box?.delete(_expiryKey);
      SentryConfig.addBreadcrumb(
        'Auth data cleared from local storage',
        category: 'auth',
      );
    } catch (e, stack) {
      SentryConfig.captureException(
        e,
        stackTrace: stack,
        hint: Hint.withMap({'operation': 'clear_auth_data'}),
      );
    }
  }

  /// Clear all stored data.
  /// 
  /// Use with caution - clears everything in the storage box.
  static Future<void> clearAll() async {
    try {
      await _box?.clear();
      SentryConfig.addBreadcrumb(
        'All local storage cleared',
        category: 'storage',
      );
    } catch (e, stack) {
      SentryConfig.captureException(
        e,
        stackTrace: stack,
        hint: Hint.withMap({'operation': 'clear_all'}),
      );
    }
  }
}
