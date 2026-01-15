import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import '../../core/errors/failure.dart';
import '../../core/sentry/sentry_config.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/fake_auth_api.dart';
import '../datasources/local_storage.dart';

class AuthRepositoryImpl implements AuthRepository {
  final FakeAuthApi remoteDataSource;

  AuthRepositoryImpl(this.remoteDataSource);

  @override
  Future<Either<Failure, User>> login(String email, String password) async {
    try {
      final userModel = await remoteDataSource.login(email, password);

      // Save token and user data to local storage for auto-login
      if (userModel.token != null) {
        await LocalStorage.saveToken(userModel.token!);
        // Set token expiry to 24 hours from now
        await LocalStorage.saveTokenExpiry(
          DateTime.now().add(const Duration(hours: 24)),
        );
        await LocalStorage.saveUserData(
          id: userModel.id,
          email: userModel.email,
          role: userModel.role,
        );

        SentryConfig.addBreadcrumb(
          'User data and token saved to local storage',
          category: 'auth',
        );
      }

      return Right(userModel);
    } on DioException catch (e, stackTrace) {
      // Log to Sentry
      SentryConfig.addBreadcrumb(
        'Login API Failed: ${e.message}',
        level: SentryLevel.error,
        category: 'network',
        data: {
          'status_code': e.response?.statusCode,
          'path': e.requestOptions.path,
        },
      );

      if (e.response?.statusCode == 500) {
        // Capture 500 errors as issues
        SentryConfig.captureException(
          e,
          stackTrace: stackTrace,
          hint: Hint.withMap({
            'error_type': 'server_error',
            'status_code': 500,
            'operation': 'login',
          }),
        );
        return const Left(ServerFailure('Server Error'));
      } else if (e.response?.statusCode == 401) {
        return const Left(ServerFailure('Invalid Credentials'));
      }
      return Left(NetworkFailure(e.message ?? 'Unknown Error'));
    } catch (e, stackTrace) {
      // Log unexpected error
      SentryConfig.captureException(
        e,
        stackTrace: stackTrace,
        hint: Hint.withMap({
          'operation': 'login',
          'error_type': 'unexpected',
        }),
      );
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, User?>> getCurrentUser() async {
    try {
      // Check local storage for user data
      final userData = LocalStorage.getUserData();
      final token = LocalStorage.getToken();

      if (userData == null || token == null) {
        SentryConfig.addBreadcrumb(
          'No stored user data found',
          category: 'auth',
        );
        return const Right(null);
      }

      // Check if token is expired
      if (LocalStorage.isTokenExpired()) {
        SentryConfig.addBreadcrumb(
          'Stored token is expired',
          category: 'auth',
          level: SentryLevel.warning,
        );
        // Clear expired data
        await LocalStorage.clearAuthData();
        return const Right(null);
      }

      // Return user from stored data
      final user = User(
        id: userData['id'] as String,
        email: userData['email'] as String,
        role: userData['role'] as String,
        token: token,
      );

      SentryConfig.addBreadcrumb(
        'User retrieved from local storage',
        category: 'auth',
      );

      return Right(user);
    } catch (e, stackTrace) {
      SentryConfig.captureException(
        e,
        stackTrace: stackTrace,
        hint: Hint.withMap({'operation': 'get_current_user'}),
      );
      return const Left(CacheFailure('Failed to retrieve user data'));
    }
  }

  @override
  Future<Either<Failure, void>> logout() async {
    try {
      // Clear local storage
      await LocalStorage.clearAuthData();
      SentryConfig.addBreadcrumb(
        'User logged out, auth data cleared',
        category: 'auth',
      );
      return const Right(null);
    } catch (e, stackTrace) {
      SentryConfig.captureException(
        e,
        stackTrace: stackTrace,
        hint: Hint.withMap({'operation': 'logout'}),
      );
      return const Left(CacheFailure('Failed to logout'));
    }
  }
}
