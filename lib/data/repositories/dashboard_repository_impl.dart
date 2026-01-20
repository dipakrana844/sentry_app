import 'package:dartz/dartz.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import '../../core/sentry/sentry_config.dart';
import '../../core/errors/failure.dart';
import '../../domain/entities/task.dart' as task;
import '../../domain/repositories/dashboard_repository.dart';
import '../datasources/fake_dashboard_api.dart';

class DashboardRepositoryImpl implements DashboardRepository {
  final FakeDashboardApi api;

  DashboardRepositoryImpl(this.api);

  @override
  Future<Either<Failure, List<task.Task>>> getTasks(
      int page, int pageSize) async {
    final span = SentryConfig.startCustomSpan(
      'repository.get_tasks',
      'Get tasks from API',
    );

    try {
      final tasks = await api.getTasks(page, pageSize);

      SentryConfig.finishCustomSpan(span, status: const SpanStatus.ok());

      return Right(tasks);
    } catch (e) {
      SentryConfig.finishCustomSpan(span,
          status: const SpanStatus.internalError());

      if (e is FormatException) {
        SentryConfig.captureException(e, hint: Hint.withMap({'page': page}));
        return const Left(ServerFailure('Data Parsing Error'));
      }

      return Left(ServerFailure(e.toString()));
    }
  }
}
