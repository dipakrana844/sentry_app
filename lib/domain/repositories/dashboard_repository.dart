import 'package:dartz/dartz.dart' hide Task;
import '../../core/errors/failure.dart';
import '../entities/task.dart';

abstract class DashboardRepository {
  Future<Either<Failure, List<Task>>> getTasks(int page, int pageSize);
}
