import 'dart:async';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../network/connectivity_monitor.dart' show onConnectionRestored;
import '../sentry/sentry_config.dart';

/// Represents an action queued for offline sync.
class OfflineAction {
  final String id;
  final String type;
  final Map<String, dynamic> data;
  final DateTime createdAt;
  int retryCount;

  OfflineAction({
    required this.id,
    required this.type,
    required this.data,
    required this.createdAt,
    this.retryCount = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'data': data,
        'createdAt': createdAt.toIso8601String(),
        'retryCount': retryCount,
      };

  factory OfflineAction.fromJson(Map<String, dynamic> json) => OfflineAction(
        id: json['id'],
        type: json['type'],
        data: Map<String, dynamic>.from(json['data']),
        createdAt: DateTime.parse(json['createdAt']),
        retryCount: json['retryCount'] ?? 0,
      );
}

/// Queue status for tracking sync state.
enum QueueStatus {
  idle,
  syncing,
  error,
}

/// Offline queue service for queuing actions when offline and syncing when online.
/// 
/// **Why this is needed:**
/// - Allows users to perform actions offline
/// - Automatically syncs when connection is restored
/// - Tracks sync performance and errors
/// 
/// **Real-world problem solved:**
/// Field workers often work in areas with poor connectivity. This queue ensures
/// their actions aren't lost and sync automatically when they're back online.
class OfflineQueue {
  static const String _boxName = 'offline_queue';
  static const int _maxRetries = 3;
  static QueueStatus _status = QueueStatus.idle;
  static StreamSubscription<DateTime>? _connectionSubscription;

  /// Initialize offline queue and set up auto-sync on connection restore.
  /// 
  /// **Sentry integration:**
  /// - Tracks initialization
  /// - Monitors connection restore events
  static Future<void> init() async {
    try {
      // Hive is initialized in LocalStorage.init(); just ensure our box is open.
      if (!Hive.isBoxOpen(_boxName)) {
        await Hive.openBox(_boxName);
      }

      // Listen for connection restored events
      _connectionSubscription = onConnectionRestored.listen(
        (_) {
          _autoSync();
        },
        onError: (error, stack) {
          SentryConfig.captureException(
            error,
            stackTrace: stack,
            hint: Hint.withMap({'operation': 'connection_restored_listener'}),
          );
        },
      );

      SentryConfig.addBreadcrumb(
        'Offline queue initialized with auto-sync',
        category: 'offline',
      );
    } catch (e, stack) {
      SentryConfig.captureException(
        e,
        stackTrace: stack,
        hint: Hint.withMap({'operation': 'offline_queue_init'}),
      );
      // If offline queue fails to initialize we still allow the app to start.
    }
  }

  /// Add an action to the offline queue.
  /// 
  /// **Sentry integration:**
  /// - Logs action addition as breadcrumb
  /// - Tracks queue size
  static Future<void> addAction(String type, Map<String, dynamic> data) async {
    try {
      final box = Hive.box(_boxName);

      // Check for duplicate actions (same type and data within last minute)
      final now = DateTime.now();
      for (var i = 0; i < box.length; i++) {
        final item = box.getAt(i);
        final existingAction = OfflineAction.fromJson(
          Map<String, dynamic>.from(item),
        );
        if (existingAction.type == type &&
            existingAction.data.toString() == data.toString() &&
            now.difference(existingAction.createdAt).inSeconds < 60) {
          SentryConfig.addBreadcrumb(
            'Duplicate action detected and skipped: $type',
            category: 'offline',
            level: SentryLevel.warning,
          );
          return; // Skip duplicate
        }
      }

      final action = OfflineAction(
        id: '${DateTime.now().millisecondsSinceEpoch}_${type}',
        type: type,
        data: data,
        createdAt: DateTime.now(),
      );

      await box.add(action.toJson());

      // Log to Sentry
      SentryConfig.addBreadcrumb(
        'Added offline action: $type',
        category: 'offline',
        data: {
          'action_id': action.id,
          'action_type': type,
          'queue_size': box.length,
        },
      );

      // Set tag for queue size
      SentryConfig.setTag('offline_queue_size', box.length.toString());
    } catch (e, stack) {
      SentryConfig.captureException(
        e,
        stackTrace: stack,
        hint: Hint.withMap({
          'operation': 'add_offline_action',
          'action_type': type,
        }),
      );
      rethrow;
    }
  }

  /// Sync all queued actions.
  /// 
  /// **Sentry integration:**
  /// - Tracks sync as performance transaction
  /// - Logs each action sync as breadcrumb
  /// - Captures sync failures with context
  static Future<void> sync() async {
    if (_status == QueueStatus.syncing) {
      SentryConfig.addBreadcrumb(
        'Sync already in progress, skipping',
        category: 'offline',
        level: SentryLevel.warning,
      );
      return;
    }

    final box = Hive.box(_boxName);
    if (box.isEmpty) {
      SentryConfig.addBreadcrumb(
        'Sync skipped: queue is empty',
        category: 'offline',
      );
      return;
    }

    _status = QueueStatus.syncing;
    final transaction = Sentry.startTransaction(
      'offline_sync',
      'task.sync',
      bindToScope: true,
    );

    try {
      final actionsToSync = <OfflineAction>[];
      final failedActions = <OfflineAction>[];

      // Collect all actions
      for (var i = 0; i < box.length; i++) {
        final item = box.getAt(i);
        final action = OfflineAction.fromJson(Map<String, dynamic>.from(item));
        actionsToSync.add(action);
      }

      SentryConfig.addBreadcrumb(
        'Starting sync of ${actionsToSync.length} actions',
        category: 'offline',
        data: {'action_count': actionsToSync.length},
      );

      // Sync each action
      for (final action in actionsToSync) {
        final actionSpan = SentryConfig.startCustomSpan(
          'sync_action',
          'Syncing action: ${action.type}',
          transaction: transaction,
        );

        try {
          // Simulate API call with potential failure
          await Future.delayed(const Duration(milliseconds: 500));

          // Simulate sync failure (10% chance, or if retry count exceeded)
          if (action.retryCount >= _maxRetries) {
            throw Exception('Max retries exceeded for action ${action.id}');
          }

          final shouldFail = action.retryCount > 0 && action.retryCount % 2 == 0;
          if (shouldFail) {
            throw Exception('Simulated sync failure for action ${action.id}');
          }

          // Success
          SentryConfig.addBreadcrumb(
            'Synced action ${action.id} (${action.type})',
            category: 'offline',
            data: {'action_id': action.id, 'retry_count': action.retryCount},
          );

          SentryConfig.finishCustomSpan(actionSpan, status: const SpanStatus.ok());
        } catch (e, stack) {
          // Sync failed for this action
          action.retryCount++;
          failedActions.add(action);

          SentryConfig.finishCustomSpan(
            actionSpan,
            status: const SpanStatus.internalError(),
          );

          SentryConfig.captureException(
            e,
            stackTrace: stack,
            hint: Hint.withMap({
              'action_id': action.id,
              'action_type': action.type,
              'retry_count': action.retryCount,
              'operation': 'sync_action',
            }),
          );
        }
      }

      // Remove successfully synced actions
      await box.clear();

      // Re-add failed actions if retries remaining
      for (final action in failedActions) {
        if (action.retryCount < _maxRetries) {
          await box.add(action.toJson());
        } else {
          // Max retries exceeded - log as error
          SentryConfig.captureException(
            Exception('Action ${action.id} exceeded max retries'),
            hint: Hint.withMap({
              'action_type': action.type,
              'retry_count': action.retryCount,
              'action_data': action.data,
            }),
          );
        }
      }

      _status = QueueStatus.idle;
      SentryConfig.finishCustomSpan(
        transaction,
        status: const SpanStatus.ok(),
      );

      SentryConfig.addBreadcrumb(
        'Sync completed: ${actionsToSync.length - failedActions.length} succeeded, ${failedActions.length} failed',
        category: 'offline',
        data: {
          'succeeded': actionsToSync.length - failedActions.length,
          'failed': failedActions.length,
        },
      );
    } catch (e, stack) {
      _status = QueueStatus.error;
      transaction.status = const SpanStatus.internalError();
      await transaction.finish();

      SentryConfig.captureException(
        e,
        stackTrace: stack,
        hint: Hint.withMap({
          'queue_length': box.length,
          'operation': 'offline_sync',
        }),
      );
    }
  }

  /// Auto-sync when connection is restored.
  /// 
  /// Called automatically by connection monitor.
  static Future<void> _autoSync() async {
    SentryConfig.addBreadcrumb(
      'Auto-sync triggered by connection restore',
      category: 'offline',
      level: SentryLevel.info,
    );
    await sync();
  }

  /// Get current queue status.
  static QueueStatus getStatus() => _status;

  /// Get queue size.
  static int getQueueSize() {
    try {
      final box = Hive.box(_boxName);
      return box.length;
    } catch (e) {
      return 0;
    }
  }

  /// Simulate app kill during sync.
  /// 
  /// This is a debug function to test recovery from interrupted syncs.
  static void simulateAppKillDuringSync() {
    SentryConfig.addBreadcrumb(
      'Simulating app kill during sync',
      category: 'offline',
      level: SentryLevel.warning,
    );

    // This would normally happen if app is killed
    // In real scenario, sync would resume on next app start
    _status = QueueStatus.idle;

    SentryConfig.captureException(
      Exception('App killed during sync - queue preserved for next sync'),
      hint: Hint.withMap({
        'queue_size': getQueueSize(),
        'operation': 'simulate_app_kill',
      }),
    );
  }

  /// Dispose resources.
  static void dispose() {
    _connectionSubscription?.cancel();
  }
}
