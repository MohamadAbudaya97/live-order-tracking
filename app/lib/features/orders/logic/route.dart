import 'dart:math' as math;

import '../data/models/place.dart';

typedef RoutePoint = ({double lat, double lng});

/// Evenly spaced points on the straight line from [from] to [to]. The first
/// point is one step away from [from] and the last one is [to] itself.
List<RoutePoint> straightRoute(Place from, Place to, {required int steps}) => [
  for (var step = 1; step <= steps; step++)
    (
      lat: from.lat + (to.lat - from.lat) * step / steps,
      lng: from.lng + (to.lng - from.lng) * step / steps,
    ),
];

/// Compass bearing from [from] to [to] in whole degrees: 0 is north, 90 is
/// east, always within 0 to 359.
int bearing(Place from, Place to) {
  final fromLat = _radians(from.lat);
  final toLat = _radians(to.lat);
  final deltaLng = _radians(to.lng - from.lng);

  final y = math.sin(deltaLng) * math.cos(toLat);
  final x =
      math.cos(fromLat) * math.sin(toLat) -
      math.sin(fromLat) * math.cos(toLat) * math.cos(deltaLng);
  return (math.atan2(y, x) * 180 / math.pi).round() % 360;
}

double _radians(double degrees) => degrees * math.pi / 180;
