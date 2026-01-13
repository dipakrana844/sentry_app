import 'package:sentry_flutter/sentry_flutter.dart';
import '../sentry/sentry_config.dart';

/// Background sync service for syncing offline queue.
/// 
/// **Why this is needed:**
/// - Syncs offline queue when app is in background
/// - Handles sync failures gracefully
/// - Tracks sync performance
/// 
/// **Real-world problem solved:**
/// Users expect data to sync even when app is backgrounded. This service
/// ensures offline actions are synced automatically.
class BackgroundSyncService {
  /// Perform background sync.
  /// 
  /// **Sentry integration:**
  /// - Tracks sync as performance transaction
  /// - Captures sync failures
  /// - Logs sync progress
  static Future<bool> sync() async {
    final transaction = SentryConfig.startCustomSpan(
      'background_sync',
      'Background sync operation',
    );

    try {
      SentryConfig.addBreadcrumb(
        'Background sync started',
        category: 'offline',
        level: SentryLevel.info,
      );

      // Import here to avoid circular dependency
      // In real app: await OfflineQueue.sync();
      await Future.delayed(const Duration(seconds: 2));

      SentryConfig.addBreadcrumb(
        'Background sync completed',
        category: 'offline',
        level: SentryLevel.info,
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
        hint: Hint.withMap({
          'operation': 'background_sync',
          'sync_type': 'background',
        }),
      );

      return false;
    }
  }

  /// Simulate app kill during sync.
  /// 
  /// This tests recovery from interrupted syncs.
  static void simulateAppKillDuringSync() {
    SentryConfig.addBreadcrumb(
      'Simulating app kill during background sync',
      category: 'offline',
      level: SentryLevel.warning,
    );

    SentryConfig.captureException(
      Exception('App killed during background sync - will resume on next sync'),
      hint: Hint.withMap({
        'operation': 'simulate_app_kill_during_sync',
        'sync_type': 'background',
      }),
    );
  }
}
