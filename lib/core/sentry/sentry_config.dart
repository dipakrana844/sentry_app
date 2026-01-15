import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

class SentryConfig {
  static String get dsn => dotenv.env['SENTRY_DSN'] ?? '';
  static bool _initialized = false;

  /// Build the root widget tree wrapped with Sentry helpers.
  static Widget _buildRoot(FutureOr<Widget> Function() builder) {
    return SentryScreenshotWidget(
      child: SentryUserInteractionWidget(
        child: DefaultAssetBundle(
          bundle: SentryAssetBundle(),
          child: FutureBuilder<Widget>(
            // Use Future.sync so both sync and async builders are supported.
            future: Future.sync(builder),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                // If the app fails to build, don't silently show a black screen.
                // Surface a minimal error UI instead so it's obvious something failed.
                return const Directionality(
                  textDirection: TextDirection.ltr,
                  child: ColoredBox(
                    color: Color(0xFF000000),
                    child: Center(
                      child: Text(
                        'Something went wrong while starting the app.\n'
                        'Check logs / Sentry for details.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFFFFFFFF)),
                      ),
                    ),
                  ),
                );
              }

              if (snapshot.hasData) {
                return snapshot.data!;
              }

              // Simple splash/loading while the root widget is being built.
              return const ColoredBox(
                color: Color(0xFF000000),
                child: Center(child: CircularProgressIndicator.adaptive()),
              );
            },
          ),
        ),
      ),
    );
  }

  static Future<void> init(FutureOr<Widget> Function() builder) async {
    // Prevent re-initializing Sentry on hot restart; just rebuild the widget tree.
    if (_initialized) {
      runApp(_buildRoot(builder));
      return;
    }

    _initialized = true;

    await SentryFlutter.init((options) {
      options.dsn = dsn;
      options.tracesSampleRate = 1.0; // 100% capture for demo
      options.profilesSampleRate = 1.0;
      options.attachScreenshot = true; // Capture screenshots (beta)
      options.enableAutoSessionTracking = true;
      // Disable ANR tracking to avoid native ANR marker NPE noise on Android.
      options.anrEnabled = false;

      // Environment separation
      options.environment =
          'production'; // Make this dynamic based on flavor if needed
      options.release = 'fieldops@1.0.0';

      // Error tracking adjustments
      options.maxBreadcrumbs = 100;

      options.beforeSend = (event, hint) {
        return event.copyWith(
          tags: <String, String>{
            ...event.tags ?? {},
            'environment': 'production',
          },
        );
      };
    }, appRunner: () => runApp(_buildRoot(builder)));
  }

  static void setUserContext(String id, String email, String role) {
    Sentry.configureScope((scope) {
      scope.setUser(SentryUser(id: id, email: email, data: {'role': role}));
    });
  }

  static void clearUserContext() {
    Sentry.configureScope((scope) {
      scope.setUser(null);
    });
  }

  static void addBreadcrumb(
    String message, {
    String? category,
    SentryLevel? level,
    Map<String, dynamic>? data,
  }) {
    Sentry.addBreadcrumb(
      Breadcrumb(
        message: message,
        category: category ?? 'app.logic',
        level: level,
        timestamp: DateTime.now(),
        data: data,
      ),
    );
  }

  /// Capture an exception to Sentry.
  ///
  /// **Why this wrapper:**
  /// Provides a consistent way to capture exceptions with proper context.
  ///
  /// **Real-world problem solved:**
  /// Teams can standardize error reporting across the app, ensuring all
  /// exceptions include relevant context (tags, extras, breadcrumbs).
  static Future<SentryId> captureException(
    dynamic exception, {
    dynamic stackTrace,
    Hint? hint,
    ScopeCallback? withScope,
  }) {
    return Sentry.captureException(
      exception,
      stackTrace: stackTrace,
      hint: hint,
      withScope: withScope,
    );
  }

  /// Set a single tag on the current scope.
  ///
  /// **Why tags:**
  /// Tags help filter and group issues in Sentry dashboard (e.g., by feature,
  /// module, API version).
  ///
  /// **Real-world problem solved:**
  /// When debugging, you can filter issues by tag to see all errors from a
  /// specific feature or module.
  static void setTag(String key, String value) {
    Sentry.configureScope((scope) {
      scope.setTag(key, value);
    });
  }

  /// Set multiple tags at once.
  ///
  /// More efficient than calling setTag multiple times.
  static void setTags(Map<String, String> tags) {
    Sentry.configureScope((scope) {
      tags.forEach((key, value) {
        scope.setTag(key, value);
      });
    });
  }

  /// Set custom extra data on the current scope.
  ///
  /// **Why extras:**
  /// Extra data provides additional context about the error that isn't
  /// captured in tags or breadcrumbs (e.g., request payloads, user preferences).
  ///
  /// **Real-world problem solved:**
  /// When an error occurs, you can see exactly what data the user was working
  /// with, making debugging much faster.
  static void setExtra(String key, dynamic value) {
    // ignore: deprecated_member_use
    Sentry.configureScope((scope) {
      // ignore: deprecated_member_use
      scope.setExtra(key, value);
    });
  }

  /// Set multiple extra data fields at once.
  static void setExtras(Map<String, dynamic> extras) {
    // ignore: deprecated_member_use
    Sentry.configureScope((scope) {
      extras.forEach((key, value) {
        // ignore: deprecated_member_use
        scope.setExtra(key, value);
      });
    });
  }

  /// Start a performance transaction for screen load.
  ///
  /// **Why screen transactions:**
  /// Tracks how long screens take to load, helping identify performance
  /// bottlenecks in the UI.
  ///
  /// **Real-world problem solved:**
  /// Teams can identify slow screens and optimize them. Sentry shows
  /// which screens have the worst performance metrics.
  ///
  /// Returns the transaction so you can finish it later.
  static ISentrySpan startScreenTransaction(String screenName) {
    return Sentry.startTransaction(
      screenName,
      'screen.load',
      bindToScope: true,
    );
  }

  /// Finish a screen transaction with status.
  ///
  /// Call this when the screen has finished loading (e.g., in initState
  /// after data is loaded, or in a FutureBuilder when data arrives).
  static Future<void> finishScreenTransaction(
    ISentrySpan transaction, {
    SpanStatus status = const SpanStatus.ok(),
  }) async {
    transaction.status = status;
    await transaction.finish();
  }

  /// Start app startup transaction.
  ///
  /// **Why startup tracking:**
  /// Measures app cold start time, helping identify initialization bottlenecks.
  ///
  /// **Real-world problem solved:**
  /// Teams can track if app startup time degrades over releases, and identify
  /// which initialization steps are slow.
  static ISentrySpan startAppStartupTransaction() {
    return Sentry.startTransaction(
      'app_startup',
      'app.lifecycle',
      bindToScope: true,
    );
  }

  /// Start a custom span for any operation.
  ///
  /// **Why custom spans:**
  /// Track performance of specific operations (API calls, database queries,
  /// image processing, etc.).
  ///
  /// **Real-world problem solved:**
  /// Identify slow operations in production. Sentry shows which operations
  /// take the longest and affect user experience.
  static ISentrySpan? startCustomSpan(
    String operation,
    String description, {
    ISentrySpan? transaction,
  }) {
    final txn = transaction;
    return txn?.startChild(operation, description: description);
  }

  /// Finish a custom span with status.
  static void finishCustomSpan(
    ISentrySpan? span, {
    SpanStatus status = const SpanStatus.ok(),
  }) {
    span?.finish(status: status);
  }
}
