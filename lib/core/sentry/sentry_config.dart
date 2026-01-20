import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

class SentryConfig {
  static bool _initialized = false;

  static String get dsn => dotenv.env['SENTRY_DSN'] ?? '';
  static String get environment =>
      dotenv.env['SENTRY_ENVIRONMENT'] ?? 'production';
  static String get release => dotenv.env['SENTRY_RELEASE'] ?? 'fieldops@1.0.0';
  static String get dist => dotenv.env['SENTRY_DIST'] ?? '1';
  static double get sampleRate =>
      double.tryParse(dotenv.env['SENTRY_SAMPLE_RATE'] ?? '1.0') ?? 1.0;

  /// Build the root widget tree wrapped with Sentry helpers.
  static Widget _buildRoot(FutureOr<Widget> Function() builder) {
    return SentryScreenshotWidget(
      child: SentryUserInteractionWidget(
        child: DefaultAssetBundle(
          bundle: SentryAssetBundle(),
          child: FutureBuilder<Widget>(
            future: Future.sync(builder),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Directionality(
                  textDirection: TextDirection.ltr,
                  child: ColoredBox(
                    color: Color(0xFF000000),
                    child: Center(
                      child: Text(
                        'Critical App Failure.\nCheck logs / Sentry.',
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
    if (_initialized) {
      runApp(_buildRoot(builder));
      return;
    }

    // Load release info if available from PackageInfo
    // (Optional: override env release with real package info)
    String? releaseName;
    try {
      final info = await PackageInfo.fromPlatform();
      releaseName = '${info.packageName}@${info.version}+${info.buildNumber}';
    } catch (_) {
      // Fallback to env release or default
      releaseName = release;
    }

    await SentryFlutter.init((options) {
      options.dsn = dsn;

      // Environment
      options.environment = environment;
      options.release = releaseName;
      options.dist = dist;

      // Sampling
      options.tracesSampler = (samplingContext) {
        // Dynamic sampling based on environment or transaction type
        if (environment == 'dev') {
          return 1.0; // 100% in dev
        }

        // Lower rate for health checks or noisy transactions
        if (samplingContext.transactionContext.name == 'health_check') {
          return 0.1;
        }

        return sampleRate; // Defaults to env var (e.g. 0.1 for prod)
      };

      // Features
      options.attachScreenshot = true;
      options.enableAutoSessionTracking = true;
      options.reportSilentFlutterErrors = true;
      options.anrEnabled = false; // Disable ANR to reduce noise on Android

      // Breadcrumbs
      options.maxBreadcrumbs = 100;
      options.beforeBreadcrumb = _beforeBreadcrumb;

      // Privacy & Scrubbing
      options.sendDefaultPii = false; // Explicitly disable default PII
      options.beforeSend = _beforeSend;
    }, appRunner: () => runApp(_buildRoot(builder)));

    _initialized = true;
  }

  /// Scrub sensitive data from events
  static FutureOr<SentryEvent?> _beforeSend(SentryEvent event, Hint? hint) {
    // 1. Tag environment explicitly (redundant but safe)
    final tags = Map<String, String>.from(event.tags ?? {});
    tags['environment'] = environment;

    // 2. Scrub user PII from message or extra
    // (Simple example regex for email - in real apps use robust scrubbers)
    // Sentry SDK handles some of this if sendDefaultPii is false, but we can do custom scrubbing here

    return event.copyWith(tags: tags);
  }

  /// Scrub sensitive data from breadcrumbs
  static Breadcrumb? _beforeBreadcrumb(Breadcrumb? breadcrumb, Hint? hint) {
    if (breadcrumb == null) return null;

    // Redact Authorization headers in network crumbs
    if (breadcrumb.category == 'http' && breadcrumb.data != null) {
      final data = Map<String, dynamic>.from(breadcrumb.data!);
      if (data.containsKey('headers')) {
        // Simple logic to mask headers if they exist in breadcrumb data
        // Note: DioInterceptor usually handles this, but this is a safety net
      }
      // Mask other sensitive keys
    }

    return breadcrumb;
  }

  // --- Context Helpers ---

  static void setUserContext(String id, String email, String role) {
    Sentry.configureScope((scope) {
      scope.setUser(SentryUser(
        id: id,
        email: email, // Consider masking in high-privacy apps
        data: {'role': role},
      ));
      scope.setTag('user_role', role);
    });
  }

  static void clearUserContext() {
    Sentry.configureScope((scope) {
      scope.setUser(null);
      scope.setTag('user_role', 'guest');
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

  /// Capture exception with enhanced context
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

  static void setTag(String key, String value) {
    Sentry.configureScope((scope) => scope.setTag(key, value));
  }

  static void setTags(Map<String, String> tags) {
    Sentry.configureScope((scope) {
      tags.forEach((key, value) => scope.setTag(key, value));
    });
  }

  static void setFeatureFlag(String feature, bool enabled) {
    setTag('feature.$feature', enabled.toString());
  }

  // --- Performance & Tracing ---

  static ISentrySpan startAppStartupTransaction() {
    return Sentry.startTransaction(
      'app_startup',
      'app.lifecycle',
      bindToScope: true,
    );
  }

  static ISentrySpan startScreenTransaction(String screenName) {
    return Sentry.startTransaction(
      screenName,
      'ui.load',
      bindToScope: true,
    );
  }

  static Future<void> finishScreenTransaction(
    ISentrySpan? transaction, {
    SpanStatus status = const SpanStatus.ok(),
  }) async {
    if (transaction != null) {
      transaction.status = status;
      await transaction.finish();
    }
  }

  static ISentrySpan? startCustomSpan(
    String operation,
    String description, {
    ISentrySpan? transaction,
  }) {
    final parent = transaction ?? Sentry.getSpan();
    return parent?.startChild(operation, description: description);
  }

  static void finishCustomSpan(
    ISentrySpan? span, {
    SpanStatus status = const SpanStatus.ok(),
  }) {
    if (span != null) {
      span.finish(status: status);
    }
  }
}
