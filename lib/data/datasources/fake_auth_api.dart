import 'dart:math';
import 'package:dio/dio.dart';
import '../models/user_model.dart';

class FakeAuthApi {
  Future<UserModel> login(String email, String password) async {
    // Simulate network delay
    await Future.delayed(const Duration(seconds: 1));

    // Simulate 500 API Error randomly (10% chance)
    if (Random().nextDouble() < 0.1) {
      throw DioException(
        requestOptions: RequestOptions(path: '/login'),
        response: Response(
          requestOptions: RequestOptions(path: '/login'),
          statusCode: 500,
          statusMessage: 'Internal Server Error',
        ),
        type: DioExceptionType.badResponse,
      );
    }

    // Simulate Invalid Credentials
    if (password == 'wrong') {
      throw DioException(
        requestOptions: RequestOptions(path: '/login'),
        response: Response(
          requestOptions: RequestOptions(path: '/login'),
          statusCode: 401,
          statusMessage: 'Unauthorized',
        ),
        type: DioExceptionType.badResponse,
      );
    }

    // Success
    return const UserModel(
      id: 'user_123',
      email: 'user@fieldops.com',
      role: 'field_agent',
      token: 'fake_jwt_token_xyz',
    );
  }
}
