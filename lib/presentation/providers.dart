import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/datasources/fake_auth_api.dart';
import '../data/datasources/fake_dashboard_api.dart';
import '../data/repositories/auth_repository_impl.dart';
import '../data/repositories/dashboard_repository_impl.dart';
import '../domain/repositories/auth_repository.dart';
import '../domain/repositories/dashboard_repository.dart';

// APIs
final authApiProvider = Provider((ref) => FakeAuthApi());
final dashboardApiProvider = Provider((ref) => FakeDashboardApi());

// Repositories
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepositoryImpl(ref.read(authApiProvider));
});

final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  return DashboardRepositoryImpl(ref.read(dashboardApiProvider));
});
