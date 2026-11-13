import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../data/models/courier_location.dart';
import '../../data/models/place.dart';

/// Pickup, drop-off and, once there is one, the courier's position.
class TrackingMap extends StatelessWidget {
  const TrackingMap({super.key, required this.pickup, required this.dropoff, this.courier});

  final Place pickup;
  final Place dropoff;
  final CourierLocation? courier;

  @override
  Widget build(BuildContext context) {
    final courier = this.courier;
    final from = LatLng(pickup.lat, pickup.lng);
    final to = LatLng(dropoff.lat, dropoff.lng);

    return FlutterMap(
      options: MapOptions(
        initialCameraFit: CameraFit.bounds(
          bounds: LatLngBounds(from, to),
          padding: const EdgeInsets.all(56),
        ),
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'dev.abudaya.live_order_tracking',
        ),
        MarkerLayer(
          markers: [
            Marker(point: from, width: 36, height: 36, child: const _Pin(Icons.storefront)),
            Marker(point: to, width: 36, height: 36, child: const _Pin(Icons.home)),
          ],
        ),
        if (courier != null) _CourierLayer(location: courier),
        const SimpleAttributionWidget(source: Text('OpenStreetMap')),
      ],
    );
  }
}

/// Positions arrive about once a second. Gliding from the last one to the new
/// one over that same second makes the marker move instead of jump.
class _CourierLayer extends StatelessWidget {
  const _CourierLayer({required this.location});

  final CourierLocation location;

  @override
  Widget build(BuildContext context) {
    final heading = location.heading;

    return TweenAnimationBuilder<LatLng>(
      tween: _LatLngTween(end: LatLng(location.lat, location.lng)),
      duration: const Duration(seconds: 1),
      builder: (context, point, _) => MarkerLayer(
        markers: [
          Marker(
            point: point,
            width: 40,
            height: 40,
            child: Transform.rotate(
              // The arrow points north, which is heading 0.
              angle: (heading ?? 0) * math.pi / 180,
              child: _Pin(heading == null ? Icons.circle : Icons.navigation, courier: true),
            ),
          ),
        ],
      ),
    );
  }
}

class _LatLngTween extends Tween<LatLng> {
  _LatLngTween({super.end});

  @override
  LatLng lerp(double t) => LatLng(
    lerpDouble(begin!.latitude, end!.latitude, t)!,
    lerpDouble(begin!.longitude, end!.longitude, t)!,
  );
}

class _Pin extends StatelessWidget {
  const _Pin(this.icon, {this.courier = false});

  final IconData icon;
  final bool courier;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: courier ? scheme.primary : scheme.surface,
        shape: BoxShape.circle,
        boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
      ),
      child: Icon(icon, size: 20, color: courier ? scheme.onPrimary : scheme.onSurface),
    );
  }
}
