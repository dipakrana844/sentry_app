import 'dart:async';
import 'dart:isolate';

import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:workmanager/workmanager.dart';
import '../errors/global_error_handler.dart';
import '../sentry/sentry_config.dart';

/// Background service manager for handling background tasks.
/// 
/// **Why this is needed:**
/// - Allows tasks to run when app is in background or killed
/// - Enables background location tracking
/// - Handles background sync operations
/// 
/// **Real-world problem solved:**
/// Field workers need location tracking even when app is backgrounded.
/// Background services ensure critical operations continue running.
class BackgroundService {
  static const String locationTaskName = 'backgroundLocationTask';
  static const String syncTaskName = 'backgroundSyncTask';
  static const String crashTestTaskName = 'backgroundCrashTestTask';

  /// Initialize background service.
  /// 
  /// Must be called during app initialization.
  static Future<void> initialize() async {
    try {
      await Workmanager().initialize(
        callbackDispatcher,
        isInDebugMode: const bool.fromEnvironment('dart.vm.product') == false,
      );

      SentryConfig.addBreadcrumb(
        'Background service initialized',
        category: 'background',
        level: SentryLevel.info,
      );
    } catch (e, stack) {
      SentryConfig.captureException(
        e,
        stackTrace: stack,
        hint: Hint.withMap({'operation': 'background_service_init'}),
      );
      rethrow;
    }
  }

  /// Register periodic background location tracking.
  /// 
  /// **Sentry integration:**
  /// - Tracks task registration
  /// - Monitors task execution
  static Future<void> registerLocationTracking({
    Duration frequency = const Duration(minutes: 15),
  }) async {
    try {
      await Workmanager().registerPeriodicTask(
        locationTaskName,
        locationTaskName,
        frequency: frequency,
        constraints: Constraints(
          networkType: NetworkType.notRequired,
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: false,
        ),
      );

      SentryConfig.addBreadcrumb(
        'Background location tracking registered',
        category: 'background',
        data: {'frequency_minutes': frequency.inMinutes},
      );
    } catch (e, stack) {
      SentryConfig.captureException(
        e,
        stackTrace: stack,
        hint: Hint.withMap({'operation': 'register_location_tracking'}),
      );
    }
  }

  /// Register one-time background sync task.
  static Future<void> registerSyncTask() async {
    try {
      await Workmanager().registerOneOffTask(
        syncTaskName,
        syncTaskName,
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: false,
          requiresCharging: false,
        ),
      );

      SentryConfig.addBreadcrumb(
        'Background sync task registered',
        category: 'background',
      );
    } catch (e, stack) {
      SentryConfig.captureException(
        e,
        stackTrace: stack,
        hint: Hint.withMap({'operation': 'register_sync_task'}),
      );
    }
  }

  /// Cancel background location tracking.
  static Future<void> cancelLocationTracking() async {
    try {
      await Workmanager().cancelByUniqueName(locationTaskName);
      SentryConfig.addBreadcrumb(
        'Background location tracking cancelled',
        category: 'background',
      );
    } catch (e, stack) {
      SentryConfig.captureException(
        e,
        stackTrace: stack,
        hint: Hint.withMap({'operation': 'cancel_location_tracking'}),
      );
    }
  }

  /// Register background crash test task (for testing).
  static Future<void> registerCrashTestTask() async {
    try {
      await Workmanager().registerOneOffTask(
        crashTestTaskName,
        crashTestTaskName,
      );

      SentryConfig.addBreadcrumb(
        'Background crash test task registered',
        category: 'background',
        level: SentryLevel.warning,
      );
    } catch (e, stack) {
      SentryConfig.captureException(
        e,
        stackTrace: stack,
        hint: Hint.withMap({'operation': 'register_crash_test_task'}),
      );
    }
  }
}

/// Top-level function for background task callback.
/// 
/// This runs in a separate isolate, so we need to set up error handling.
@pragma('vm:entry-point')
void callbackDispatcher() {
  // Set up error handler for background isolate
  GlobalErrorHandler.setupIsolateErrorHandler();

  Workmanager().executeTask((task, inputData) async {
    try {
      SentryConfig.addBreadcrumb(
        'Background task started: $task',
        category: 'background',
        data: inputData,
      );

      switch (task) {
        case BackgroundService.locationTaskName:
          return await _handleLocationTask(inputData);
        case BackgroundService.syncTaskName:
          return await _handleSyncTask(inputData);
        case BackgroundService.crashTestTaskName:
          return await _handleCrashTestTask(inputData);
        default:
          SentryConfig.captureException(
            Exception('Unknown background task: $task'),
            hint: Hint.withMap({'task_name': task}),
          );
          return false;
      }
    } catch (e, stack) {
      SentryConfig.captureException(
        e,
        stackTrace: stack,
        hint: Hint.withMap({
          'task': task,
          'input_data': inputData,
          'operation': 'background_task_execution',
        }),
      );
      return false;
    }
  });
}

/// Handle background location tracking task.
Future<bool> _handleLocationTask(Map<String, dynamic>? inputData) async {
  final transaction = SentryConfig.startCustomSpan(
    'background_location_task',
    'Background location tracking',
  );

  try {
    // Simulate location tracking
    await Future.delayed(const Duration(seconds: 2));

    SentryConfig.addBreadcrumb(
      'Background location tracked',
      category: 'background',
      data: {
        'timestamp': DateTime.now().toIso8601String(),
        'task': 'location_tracking',
      },
    );

    SentryConfig.finishCustomSpan(transaction, status: const SpanStatus.ok());
    return true;
  } catch (e, stack) {
    SentryConfig.finishCustomSpan(
      transaction,
      status: const SpanStatus.internalError(),
    );
    SentryConfig.captureException(
      e,
      stackTrace: stack,
      hint: Hint.withMap({'operation': 'background_location_task'}),
    );
    return false;
  }
}

/// Handle background sync task.
Future<bool> _handleSyncTask(Map<String, dynamic>? inputData) async {
  final transaction = SentryConfig.startCustomSpan(
    'background_sync_task',
    'Background sync operation',
  );

  try {
    // Import here to avoid circular dependency
    // In real app, you'd call OfflineQueue.sync()
    await Future.delayed(const Duration(seconds: 1));

    SentryConfig.addBreadcrumb(
      'Background sync completed',
      category: 'background',
    );

    SentryConfig.finishCustomSpan(transaction, status: const SpanStatus.ok());
    return true;
  } catch (e, stack) {
    SentryConfig.finishCustomSpan(
      transaction,
      status: const SpanStatus.internalError(),
    );
    SentryConfig.captureException(
      e,
      stackTrace: stack,
      hint: Hint.withMap({'operation': 'background_sync_task'}),
    );
    return false;
  }
}

/// Handle background crash test task.
/// 
/// This intentionally crashes to test background isolate error handling.
Future<bool> _handleCrashTestTask(Map<String, dynamic>? inputData) async {
  try {
    SentryConfig.addBreadcrumb(
      'Background crash test task started',
      category: 'background',
      level: SentryLevel.warning,
    );

    // Simulate some work
    await Future.delayed(const Duration(seconds: 1));

      // Intentionally crash
      throw Exception('Intentional crash in background isolate');
  } catch (e, stack) {
    // Error handler will catch this
    SentryConfig.captureException(
      e,
      stackTrace: stack,
      hint: Hint.withMap({
        'operation': 'background_crash_test',
        'isolate_type': 'background',
      }),
    );
    rethrow; // Re-throw to test error handling
  }
}
