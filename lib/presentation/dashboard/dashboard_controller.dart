import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/task.dart';
import '../providers.dart';

class DashboardController extends AsyncNotifier<List<Task>> {
  int _page = 1;
  static const int _pageSize = 10;
  bool _hasMore = true;

  @override
  FutureOr<List<Task>> build() async {
    _page = 1;
    _hasMore = true;
    return _fetchTasks(_page);
  }

  Future<List<Task>> _fetchTasks(int page) async {
    final result = await ref
        .read(dashboardRepositoryProvider)
        .getTasks(page, _pageSize);
    return result.fold<List<Task>>(
      (failure) {
        throw Exception(failure.message);
      },
      (tasks) {
        if (tasks.isEmpty) _hasMore = false;
        return tasks;
      },
    );
  }

  Future<void> loadMore() async {
    if (!_hasMore || state.isLoading) return;

    state = const AsyncLoading<List<Task>>().copyWithPrevious(state);

    try {
      final newTasks = await _fetchTasks(_page + 1);
      _page++;

      final currentTasks = state.value ?? [];
      state = AsyncData([...currentTasks, ...newTasks]);
    } catch (e, stack) {
      state = AsyncError(e, stack);
    }
  }

  Future<void> refresh() async {
    _page = 1;
    _hasMore = true;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _fetchTasks(1));
  }
}

final dashboardControllerProvider =
    AsyncNotifierProvider<DashboardController, List<Task>>(
      DashboardController.new,
    );
