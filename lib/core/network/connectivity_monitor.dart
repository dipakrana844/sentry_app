import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import '../sentry/sentry_config.dart';

/// Network connectivity state.
enum ConnectivityStatus {
  connected,
  disconnected,
  unknown,
}

/// Monitor for network connectivity changes.
/// 
/// **Why this is needed:**
/// - Detects when device goes offline/online
/// - Triggers auto-sync when connection is restored
/// - Provides network state to UI for offline indicators
/// 
/// **Real-world problem solved:**
/// Users expect apps to work offline and sync when back online. This monitor
/// enables automatic sync and provides feedback about network state.
class ConnectivityMonitor extends StateNotifier<ConnectivityStatus> {
  ConnectivityMonitor() : super(ConnectivityStatus.unknown) {
    _init();
  }

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  final Connectivity _connectivity = Connectivity();

  /// Initialize connectivity monitoring.
  /// 
  /// Starts listening to connectivity changes and logs them to Sentry.
  Future<void> _init() async {
    // Get initial connectivity status
    final initialResults = await _connectivity.checkConnectivity();
    _updateStatus(initialResults);

    // Listen to connectivity changes
    _subscription = _connectivity.onConnectivityChanged.listen(
      (results) {
        _updateStatus(results);
      },
      onError: (error, stack) {
        SentryConfig.captureException(
          error,
          stackTrace: stack,
          hint: Hint.withMap({'operation': 'connectivity_monitoring'}),
        );
      },
    );
  }

  /// Update connectivity status based on results.
  void _updateStatus(List<ConnectivityResult> results) {
    final wasConnected = state == ConnectivityStatus.connected;
    final isConnected = results.any(
      (result) =>
          result != ConnectivityResult.none &&
          result != ConnectivityResult.bluetooth,
    );

    ConnectivityStatus newStatus;
    if (isConnected) {
      newStatus = ConnectivityStatus.connected;
    } else {
      newStatus = ConnectivityStatus.disconnected;
    }

    // Only update if status changed
    if (newStatus != state) {
      state = newStatus;

      // Log connectivity change to Sentry
      SentryConfig.addBreadcrumb(
        'Network connectivity changed: ${isConnected ? "connected" : "disconnected"}',
        category: 'network',
        level: isConnected ? SentryLevel.info : SentryLevel.warning,
        data: {
          'connectivity_results': results.map((r) => r.toString()).toList(),
          'previous_status': wasConnected ? 'connected' : 'disconnected',
          'new_status': isConnected ? 'connected' : 'disconnected',
        },
      );

      // Set tag for filtering in Sentry
      SentryConfig.setTag('network_status', isConnected ? 'online' : 'offline');

      // If connection restored, trigger auto-sync
      if (isConnected && !wasConnected) {
        _onConnectionRestored();
      }
    }
  }

  /// Handle connection restored event.
  /// 
  /// This triggers auto-sync of offline queue.
  /// The actual sync is handled by the offline queue service.
  void _onConnectionRestored() {
    SentryConfig.addBreadcrumb(
      'Connection restored, triggering auto-sync',
      category: 'offline',
      level: SentryLevel.info,
    );

    // Emit event that connection was restored
    // This will be listened to by offline queue
    connectionRestoredController.add(DateTime.now());
  }

  /// Check current connectivity status.
  Future<bool> isConnected() async {
    final results = await _connectivity.checkConnectivity();
    return results.any(
      (result) =>
          result != ConnectivityResult.none &&
          result != ConnectivityResult.bluetooth,
    );
  }

  /// Dispose resources.
  @override
  void dispose() {
    _subscription?.cancel();
    connectionRestoredController.close();
    super.dispose();
  }
}

/// Provider for connectivity monitor.
final connectivityMonitorProvider =
    StateNotifierProvider<ConnectivityMonitor, ConnectivityStatus>(
  (ref) => ConnectivityMonitor(),
);

/// Stream controller for connection restored events.
/// 
/// Used to notify offline queue when connection is restored.
final connectionRestoredController = StreamController<DateTime>.broadcast();

/// Stream of connection restored events.
Stream<DateTime> get onConnectionRestored => connectionRestoredController.stream;
