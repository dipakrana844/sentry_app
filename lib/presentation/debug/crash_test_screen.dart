import 'dart:async';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import '../../core/background/background_service.dart';
import '../../core/errors/global_error_handler.dart';
import '../../core/sentry/sentry_config.dart';

/// Centralized crash test screen for debugging.
/// 
/// **Why this screen:**
/// Provides a single place to test all crash scenarios, making it easier
/// to verify Sentry integration is working correctly.
/// 
/// **Real-world problem solved:**
/// During development and QA, teams need to verify error tracking works.
/// This screen provides all crash scenarios in one place.
class CrashTestScreen extends StatelessWidget {
  const CrashTestScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crash Test Center'),
        backgroundColor: Colors.red[900],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const Text(
            'Intentional Crash Scenarios',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'These buttons intentionally trigger errors to test Sentry integration.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),

          // Null pointer crash
          _buildCrashButton(
            context,
            title: 'Null Pointer Exception',
            description: 'Triggers a null check failure',
            icon: Icons.error_outline,
            color: Colors.red,
            onPressed: () {
              String? nullString;
              // ignore: null_check_always_fails
              print(nullString!.length);
            },
          ),

          // JSON parsing error
          _buildCrashButton(
            context,
            title: 'JSON Parsing Error',
            description: 'Simulates malformed JSON response',
            icon: Icons.code,
            color: Colors.orange,
            onPressed: () {
              try {
                throw const FormatException('Unexpected character in JSON at position 42');
              } catch (e, stack) {
                SentryConfig.captureException(
                  e,
                  stackTrace: stack,
                  hint: Hint.withMap({
                    'error_type': 'json_parsing',
                    'operation': 'parse_api_response',
                  }),
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('JSON parsing error sent to Sentry')),
                );
              }
            },
          ),

          // UI thread freeze
          _buildCrashButton(
            context,
            title: 'UI Thread Freeze',
            description: 'Infinite loop in main thread (will freeze UI)',
            icon: Icons.hourglass_empty,
            color: Colors.purple,
            onPressed: () {
              SentryConfig.addBreadcrumb(
                'UI thread freeze initiated',
                category: 'debug',
                level: SentryLevel.warning,
              );

              // Simulate UI freeze (with early exit to avoid actual freeze)
              int i = 0;
              while (i < 1000000) {
                i++;
                if (i % 100000 == 0) {
                  // Log progress
                }
              }
              // Log the freeze simulation
              SentryConfig.captureException(
                Exception('UI thread freeze simulation - infinite loop detected'),
                hint: Hint.withMap({
                  'error_type': 'ui_freeze',
                  'iteration': i,
                }),
              );

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: const Text('UI freeze simulation sent to Sentry'),
                ),
              );
            },
          ),

          // Background isolate crash
          _buildCrashButton(
            context,
            title: 'Background Isolate Crash',
            description: 'Crashes a spawned isolate',
            icon: Icons.bug_report,
            color: Colors.indigo,
            onPressed: () async {
              SentryConfig.addBreadcrumb(
                'Background isolate crash test initiated',
                category: 'debug',
                level: SentryLevel.warning,
              );

              try {
                await Isolate.spawn(_isolateCrashEntryPoint, null);
              } catch (e, stack) {
                SentryConfig.captureException(
                  e,
                  stackTrace: stack,
                  hint: Hint.withMap({
                    'error_type': 'isolate_crash',
                    'operation': 'spawn_isolate',
                  }),
                );
              }

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Background isolate crash test initiated')),
              );
            },
          ),

          // Permission exception
          _buildCrashButton(
            context,
            title: 'Permission Exception',
            description: 'Simulates permission denied error',
            icon: Icons.block,
            color: Colors.orange,
            onPressed: () {
              try {
                throw Exception('Permission denied: Location access required');
              } catch (e, stack) {
                SentryConfig.captureException(
                  e,
                  stackTrace: stack,
                  hint: Hint.withMap({
                    'error_type': 'permission_exception',
                    'permission': 'location',
                    'operation': 'request_permission',
                  }),
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Permission exception sent to Sentry')),
                );
              }
            },
          ),

          // Expired token
          _buildCrashButton(
            context,
            title: 'Expired Token',
            description: 'Simulates 401 with expired token',
            icon: Icons.access_time,
            color: Colors.amber,
            onPressed: () {
              SentryConfig.captureException(
                Exception('Token expired: Please login again'),
                hint: Hint.withMap({
                  'error_type': 'expired_token',
                  'http_status': 401,
                  'message': 'Your session has expired. Please login again.',
                }),
              );
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Expired token error sent to Sentry')),
              );
            },
          ),

          // Network timeout
          _buildCrashButton(
            context,
            title: 'Network Timeout',
            description: 'Simulates network timeout error',
            icon: Icons.wifi_off,
            color: Colors.teal,
            onPressed: () {
              try {
                throw TimeoutException('Network request timed out after 30 seconds');
              } catch (e, stack) {
                SentryConfig.captureException(
                  e,
                  stackTrace: stack,
                  hint: Hint.withMap({
                    'error_type': 'network_timeout',
                    'timeout_seconds': 30,
                    'operation': 'api_request',
                  }),
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Network timeout error sent to Sentry')),
                );
              }
            },
          ),

          // Background task crash
          _buildCrashButton(
            context,
            title: 'Background Task Crash',
            description: 'Registers a background task that will crash',
            icon: Icons.work_off,
            color: Colors.deepPurple,
            onPressed: () async {
              await BackgroundService.registerCrashTestTask();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Background crash test task registered. Check Sentry after task runs.'),
                ),
              );
            },
          ),

          // Generic exception
          _buildCrashButton(
            context,
            title: 'Generic Exception',
            description: 'Throws a generic unhandled exception',
            icon: Icons.warning,
            color: Colors.red,
            onPressed: () {
              throw Exception('Intentional crash: Generic exception for testing');
            },
          ),

          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),

          // Info section
          Card(
            color: Colors.blue[50],
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'About Crash Testing',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'All crashes are sent to Sentry with proper context, tags, and breadcrumbs. '
                    'Check your Sentry dashboard to see the errors.',
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Note: Some crashes (like UI freeze) are simulated to avoid actually freezing the app.',
                    style: TextStyle(fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCrashButton(
    BuildContext context, {
    required String title,
    required String description,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.2),
          child: Icon(icon, color: color),
        ),
        title: Text(title),
        subtitle: Text(description),
        trailing: Icon(Icons.chevron_right, color: color),
        onTap: onPressed,
      ),
    );
  }
}

/// Entry point for isolate crash test.
/// 
/// This isolate will crash intentionally to test error handling.
void _isolateCrashEntryPoint(dynamic message) {
  // Set up error handler for this isolate
  GlobalErrorHandler.setupIsolateErrorHandler();

  // Do some work
  Future.delayed(const Duration(seconds: 1), () {
    // Intentionally crash
    throw Exception('Intentional crash in background isolate');
  });
}
