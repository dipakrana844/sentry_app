import 'package:dartz/dartz.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import '../../core/errors/failure.dart';
import '../../domain/entities/task.dart' as task;
import '../../domain/repositories/dashboard_repository.dart';
import '../datasources/fake_dashboard_api.dart';

class DashboardRepositoryImpl implements DashboardRepository {
  final FakeDashboardApi api;

  DashboardRepositoryImpl(this.api);

  @override
  Future<Either<Failure, List<task.Task>>> getTasks(int page, int pageSize) async {
    final transaction = Sentry.startTransaction(
      'get_tasks_transaction',
      'task.load',
      bindToScope: true,
    );

    try {
      final span = transaction.startChild(
        'fetch_tasks',
        description: 'Fetching tasks from Fake API',
      );

      final tasks = await api.getTasks(page, pageSize);

      span.finish(status: const SpanStatus.ok());

      return Right(tasks);
    } catch (e) {
      transaction.status = const SpanStatus.internalError();

      if (e is FormatException) {
        Sentry.captureException(e, hint: Hint.withMap({'page': page}));
        return const Left(ServerFailure('Data Parsing Error'));
      }

      return Left(ServerFailure(e.toString()));
    } finally {
      await transaction.finish();
    }
  }
}
