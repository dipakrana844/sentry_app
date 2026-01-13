import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import '../../core/sentry/sentry_config.dart';

/// Map screen with location tracking and route drawing.
/// 
/// **Sentry integration:**
/// - Tracks permission requests and denials
/// - Monitors location updates
/// - Captures location errors (null location, permission denied)
/// - Tracks map controller errors
/// 
/// **Real-world problem solved:**
/// Field workers need to see their location and routes. This screen demonstrates
/// handling all location-related edge cases that occur in production.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? _controller;
  static const LatLng _defaultCenter = LatLng(37.7749, -122.4194); // San Francisco
  LatLng _currentCenter = _defaultCenter;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStream;
  bool _isTrackingLocation = false;
  PermissionStatus _permissionStatus = PermissionStatus.denied;

  @override
  void initState() {
    super.initState();
    // Start screen load transaction
    final transaction = SentryConfig.startScreenTransaction('map_screen');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SentryConfig.finishScreenTransaction(transaction);
    });
    _checkPermissionAndGetLocation();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  /// Check location permission and get current location.
  Future<void> _checkPermissionAndGetLocation() async {
    try {
      final status = await Permission.location.status;
      _permissionStatus = status;

      SentryConfig.addBreadcrumb(
        'Location permission status checked: $status',
        category: 'device',
        data: {'permission_status': status.toString()},
      );

      if (status.isDenied) {
        final result = await Permission.location.request();
        _permissionStatus = result;

        if (result.isDenied) {
          SentryConfig.addBreadcrumb(
            'Location permission denied by user',
            category: 'device',
            level: SentryLevel.warning,
          );
          SentryConfig.setTag('location_permission', 'denied');

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Location permission denied'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        } else if (result.isPermanentlyDenied) {
          SentryConfig.addBreadcrumb(
            'Location permission permanently denied',
            category: 'device',
            level: SentryLevel.error,
          );
          SentryConfig.captureException(
            Exception('Location permission permanently denied'),
            hint: Hint.withMap({
              'permission_status': 'permanently_denied',
              'operation': 'location_permission',
            }),
          );

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Location permission permanently denied. Please enable in settings.'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      }

      // Permission granted, get location
      await _getCurrentLocation();
    } catch (e, stack) {
      SentryConfig.captureException(
        e,
        stackTrace: stack,
        hint: Hint.withMap({
          'operation': 'check_permission',
          'permission_status': _permissionStatus.toString(),
        }),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error checking permission: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Get current location.
  Future<void> _getCurrentLocation() async {
    try {
      SentryConfig.addBreadcrumb(
        'Getting current location',
        category: 'location',
      );

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      setState(() {
        _currentPosition = position;
        _currentCenter = LatLng(position.latitude, position.longitude);
      });

      // Update map camera
      _controller?.animateCamera(
        CameraUpdate.newLatLng(_currentCenter),
      );

      // Add current location marker
      _updateCurrentLocationMarker();

      SentryConfig.addBreadcrumb(
        'Current location obtained',
        category: 'location',
        data: {
          'latitude': position.latitude,
          'longitude': position.longitude,
        },
      );
    } catch (e, stack) {
      // Handle location null scenario
      if (e.toString().contains('null') || e.toString().contains('unavailable')) {
        SentryConfig.captureException(
          Exception('Location is null or unavailable'),
          stackTrace: stack,
          hint: Hint.withMap({
            'error_type': 'location_null',
            'operation': 'get_current_location',
          }),
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location is unavailable. Please check GPS settings.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        SentryConfig.captureException(
          e,
          stackTrace: stack,
          hint: Hint.withMap({'operation': 'get_current_location'}),
        );
      }
    }
  }

  /// Start tracking location updates.
  void _startLocationTracking() {
    if (_isTrackingLocation) return;

    try {
      _isTrackingLocation = true;
      final locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Update every 10 meters
      );

      _positionStream = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        (position) {
          setState(() {
            _currentPosition = position;
            _currentCenter = LatLng(position.latitude, position.longitude);
          });

          _updateCurrentLocationMarker();
          _updateRoute();

          SentryConfig.addBreadcrumb(
            'Location updated',
            category: 'location',
            data: {
              'latitude': position.latitude,
              'longitude': position.longitude,
            },
          );
        },
        onError: (error, stack) {
          SentryConfig.captureException(
            error,
            stackTrace: stack,
            hint: Hint.withMap({'operation': 'location_tracking'}),
          );
        },
      );

      SentryConfig.addBreadcrumb(
        'Location tracking started',
        category: 'location',
        level: SentryLevel.info,
      );
    } catch (e, stack) {
      SentryConfig.captureException(
        e,
        stackTrace: stack,
        hint: Hint.withMap({'operation': 'start_location_tracking'}),
      );
    }
  }

  /// Stop tracking location updates.
  void _stopLocationTracking() {
    _positionStream?.cancel();
    _positionStream = null;
    _isTrackingLocation = false;

    SentryConfig.addBreadcrumb(
      'Location tracking stopped',
      category: 'location',
    );
  }

  /// Update current location marker.
  void _updateCurrentLocationMarker() {
    if (_currentPosition == null) return;

    setState(() {
      _markers.removeWhere((m) => m.markerId.value == 'current_location');
      _markers.add(
        Marker(
          markerId: const MarkerId('current_location'),
          position: _currentCenter,
          infoWindow: const InfoWindow(
            title: 'Current Location',
            snippet: 'You are here',
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueBlue,
          ),
        ),
      );
    });
  }

  /// Update route polyline.
  void _updateRoute() {
    // For demo, draw a route from HQ to current location
    setState(() {
      _polylines.clear();
      _polylines.add(
        Polyline(
          polylineId: const PolylineId('route'),
          points: [_defaultCenter, _currentCenter],
          color: Colors.blue,
          width: 3,
        ),
      );
    });
  }

  void _onMapCreated(GoogleMapController controller) {
    _controller = controller;

    // Add HQ marker
    setState(() {
      _markers.add(
        const Marker(
          markerId: MarkerId('hq'),
          position: _defaultCenter,
          infoWindow: InfoWindow(title: 'FieldOps HQ'),
        ),
      );
    });

    SentryConfig.addBreadcrumb(
      'Map controller initialized',
      category: 'map',
    );
  }

  void _simulatePermissionException() {
    try {
      // Simulate permission exception
      throw PermissionException(
        'Location permission denied',
        Permission.location,
      );
    } catch (e, stack) {
      SentryConfig.captureException(
        e,
        stackTrace: stack,
        hint: Hint.withMap({
          'error_type': 'permission_exception',
          'operation': 'simulate_permission_error',
        }),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Permission exception simulated and sent to Sentry'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  void _simulateLocationNull() {
    SentryConfig.captureException(
      Exception('Location is null - GPS unavailable or disabled'),
      hint: Hint.withMap({
        'error_type': 'location_null',
        'operation': 'simulate_location_null',
      }),
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location null scenario simulated and sent to Sentry'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  void _simulateMapControllerError() {
    try {
      // Simulate map controller misuse (calling method on disposed controller)
      if (_controller == null) {
        throw Exception('GoogleMapController is null');
      }
      // This would normally work, but we'll throw an error to simulate misuse
      throw Exception('GoogleMapController not initialized properly');
    } catch (e, stack) {
      SentryConfig.captureException(
        e,
        stackTrace: stack,
        hint: Hint.withMap({
          'error_type': 'map_controller_error',
          'operation': 'simulate_map_controller_error',
        }),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Map controller error simulated and sent to Sentry'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Field Map'),
        actions: [
          IconButton(
            icon: Icon(_isTrackingLocation ? Icons.stop : Icons.play_arrow),
            onPressed: _isTrackingLocation
                ? _stopLocationTracking
                : _startLocationTracking,
            tooltip: _isTrackingLocation
                ? 'Stop tracking'
                : 'Start tracking',
          ),
          IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: _getCurrentLocation,
            tooltip: 'Get current location',
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: _onMapCreated,
            initialCameraPosition: CameraPosition(
              target: _currentCenter,
              zoom: 14.0,
            ),
            markers: _markers,
            polylines: _polylines,
            myLocationEnabled: true,
            myLocationButtonEnabled: false, // Using custom button
            zoomControlsEnabled: true,
          ),
          Positioned(
            bottom: 20,
            left: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_currentPosition != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Lat: ${_currentPosition!.latitude.toStringAsFixed(6)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          Text(
                            'Lng: ${_currentPosition!.longitude.toStringAsFixed(6)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                FloatingActionButton(
                  heroTag: 'crash_map',
                  backgroundColor: Colors.red,
                  onPressed: _simulateMapControllerError,
                  child: const Icon(Icons.dangerous),
                ),
              ],
            ),
          ),

          // Debug actions (only in debug mode)
          if (const bool.fromEnvironment('dart.vm.product') == false)
            Positioned(
              bottom: 20,
              right: 20,
              child: Column(
                children: [
                  FloatingActionButton.small(
                    heroTag: 'permission_error',
                    backgroundColor: Colors.orange,
                    onPressed: _simulatePermissionException,
                    child: const Icon(Icons.block),
                  ),
                  const SizedBox(height: 8),
                  FloatingActionButton.small(
                    heroTag: 'location_null',
                    backgroundColor: Colors.orange,
                    onPressed: _simulateLocationNull,
                    child: const Icon(Icons.location_off),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Custom exception for permission errors.
class PermissionException implements Exception {
  final String message;
  final Permission permission;

  PermissionException(this.message, this.permission);

  @override
  String toString() => 'PermissionException: $message (${permission.toString()})';
}
