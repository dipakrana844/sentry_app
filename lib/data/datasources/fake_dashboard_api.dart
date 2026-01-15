import 'dart:math';
import '../models/task_model.dart';

class FakeDashboardApi {
  Future<List<TaskModel>> getTasks(int page, int pageSize) async {
    // Simulate Network Latency (Slow on purpose sometimes)
    int delay = Random().nextInt(2000) + 500; // 0.5s to 2.5s
    if (Random().nextDouble() < 0.1) {
      delay = 5000;
    } // 5s slow network
    await Future.delayed(Duration(milliseconds: delay));

    // Simulate Network Error
    if (Random().nextDouble() < 0.05) {
      throw Exception('Network Timeout');
    }

    // Simulate Malformed JSON (by throwing error, as if parsing failed)
    if (Random().nextDouble() < 0.05) {
      throw const FormatException('Unexpected character in JSON');
    }

    // Simulate Empty Response
    if (Random().nextDouble() < 0.05) {
      return [];
    }

    // Generate Fake Data
    return List.generate(pageSize, (index) {
      final int id = (page - 1) * pageSize + index;
      return TaskModel(
        id: 'task_$id',
        title: 'Field Task #$id',
        status: index % 3 == 0 ? 'completed' : 'pending',
        createdAt: DateTime.now().subtract(Duration(days: index)),
      );
    });
  }
}
