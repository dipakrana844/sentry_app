import 'package:dio/dio.dart';
import 'package:sentry_dio/sentry_dio.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

class DioClient {
  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ),
  );

  static Dio get instance => _dio;

  static void init() {
    /// ✅ Correct Sentry integration (v9+)
    _dio.addSentry(
      captureFailedRequests: true,
      failedRequestStatusCodes: [
        SentryStatusCode.range(400, 599),
      ],
    );

    /// Optional custom tagging
    _dio.interceptors.add(
      InterceptorsWrapper(
        onError: (DioException e, handler) {
          Sentry.configureScope((scope) {
            scope.setTag('network.error_type', e.type.toString());
            if (e.response != null) {
              scope.setTag(
                'network.status_code',
                e.response!.statusCode.toString(),
              );
            }
          });
          handler.next(e);
        },
      ),
    );
  }
}
