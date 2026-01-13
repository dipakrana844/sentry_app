import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/sentry/sentry_config.dart';
import 'dashboard_controller.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);

    // Start screen load transaction
    // This tracks how long the dashboard takes to load
    final transaction = SentryConfig.startScreenTransaction('dashboard_screen');
    
    // Finish transaction when data is loaded
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Wait a bit for data to load, then finish transaction
      Future.delayed(const Duration(milliseconds: 100), () {
        final tasksAsync = ref.read(dashboardControllerProvider);
        if (tasksAsync.hasValue || tasksAsync.hasError) {
          SentryConfig.finishScreenTransaction(transaction);
        }
      });
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(dashboardControllerProvider.notifier).loadMore();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tasksAsync = ref.watch(dashboardControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('FieldOps Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.read(dashboardControllerProvider.notifier).refresh(),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              SentryConfig.addBreadcrumb('User logged out');
              SentryConfig.clearUserContext();
              context.go('/login');
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(dashboardControllerProvider.notifier).refresh(),
        child: tasksAsync.when(
          data: (tasks) {
            if (tasks.isEmpty) {
              return const Center(child: Text('No tasks found'));
            }
            return ListView.builder(
              controller: _scrollController,
              itemCount: tasks.length + 1, // +1 for loading indicator at bottom
              itemBuilder: (context, index) {
                if (index == tasks.length) {
                  // Bottom loading indicator
                  return const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Center(child: CircularProgressIndicator.adaptive()),
                  );
                }
                final task = tasks[index];
                return ListTile(
                  title: Text(task.title),
                  subtitle: Text('Status: ${task.status} | ID: ${task.id}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    SentryConfig.addBreadcrumb(
                      'Viewed Task ${task.id}',
                      category: 'navigation',
                    );
                    // Navigate to details (not implemented)
                  },
                );
              },
            );
          },
          error: (error, stack) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, color: Colors.red, size: 48),
                const SizedBox(height: 16),
                Text('Error: ${error.toString()}'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () =>
                      ref.read(dashboardControllerProvider.notifier).refresh(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
        ),
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'crash_test',
            backgroundColor: Colors.purple,
            onPressed: () {
              context.go('/crash-test');
            },
            tooltip: 'Crash Test Center',
            child: const Icon(Icons.bug_report),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'null_crash',
            backgroundColor: Colors.red,
            onPressed: () {
              // Simulate a null pointer exception to test Sentry
              String? nullString; // null
              // ignore: null_check_always_fails
              nullString!.length; // This will crash
            },
            tooltip: 'Trigger Null Pointer',
            child: const Icon(Icons.error),
          ),
        ],
      ),
    );
  }
}
