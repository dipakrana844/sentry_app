import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import '../sentry/sentry_config.dart';

/// Background location tracker service.
/// 
/// **Why this is needed:**
/// - Tracks location even when app is in background
/// - Handles location errors gracefully
/// - Logs location updates to Sentry for debugging
/// 
/// **Real-world problem solved:**
/// Field workers need continuous location tracking. This service ensures
/// location is tracked even when app is backgrounded or device is locked.
class BackgroundLocationTracker {
  static StreamSubscription<Position>? _positionStream;
  static bool _isTracking = false;

  /// Start background location tracking.
  /// 
  /// **Sentry integration:**
  /// - Tracks tracking start/stop
  /// - Monitors location updates
  /// - Captures location errors
  static Future<void> startTracking({
    LocationAccuracy accuracy = LocationAccuracy.high,
    int distanceFilter = 10, // meters
  }) async {
    if (_isTracking) {
      SentryConfig.addBreadcrumb(
        'Background location tracking already started',
        category: 'location',
        level: SentryLevel.warning,
      );
      return;
    }

    try {
      // Check permission
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services are disabled');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permissions are denied');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permissions are permanently denied');
      }

      // Start position stream
      _positionStream = Geolocator.getPositionStream(
        locationSettings: LocationSettings(
          accuracy: accuracy,
          distanceFilter: distanceFilter,
        ),
      ).listen(
        (Position position) {
          _onLocationUpdate(position);
        },
        onError: (error, stack) {
          SentryConfig.captureException(
            error,
            stackTrace: stack,
            hint: Hint.withMap({
              'operation': 'background_location_tracking',
              'error_type': 'location_stream_error',
            }),
          );
        },
      );

      _isTracking = true;

      SentryConfig.addBreadcrumb(
        'Background location tracking started',
        category: 'location',
        level: SentryLevel.info,
        data: {
          'accuracy': accuracy.toString(),
          'distance_filter': distanceFilter,
        },
      );
    } catch (e, stack) {
      SentryConfig.captureException(
        e,
        stackTrace: stack,
        hint: Hint.withMap({'operation': 'start_background_location_tracking'}),
      );
      rethrow;
    }
  }

  /// Stop background location tracking.
  static void stopTracking() {
    _positionStream?.cancel();
    _positionStream = null;
    _isTracking = false;

    SentryConfig.addBreadcrumb(
      'Background location tracking stopped',
      category: 'location',
    );
  }

  /// Handle location update.
  /// 
  /// Logs location to Sentry and can save to local storage or send to server.
  static void _onLocationUpdate(Position position) {
    SentryConfig.addBreadcrumb(
      'Background location update',
      category: 'location',
      data: {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'timestamp': position.timestamp?.toIso8601String(),
      },
    );

    // In real app, you would:
    // 1. Save to local database
    // 2. Send to server if online
    // 3. Queue for sync if offline
  }

  /// Check if tracking is active.
  static bool get isTracking => _isTracking;
}
