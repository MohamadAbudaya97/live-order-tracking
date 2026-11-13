import 'package:flutter_test/flutter_test.dart';
import 'package:live_order_tracking/features/orders/data/models/place.dart';
import 'package:live_order_tracking/features/orders/logic/route.dart';

void main() {
  const origin = Place(lat: 0, lng: 0, label: 'Origin');

  test('bearing is measured clockwise from north and stays within 0 to 359', () {
    expect(bearing(origin, const Place(lat: 1, lng: 0, label: 'North')), 0);
    expect(bearing(origin, const Place(lat: 0, lng: 1, label: 'East')), 90);
    expect(bearing(origin, const Place(lat: -1, lng: 0, label: 'South')), 180);
    expect(bearing(origin, const Place(lat: 0, lng: -1, label: 'West')), 270);
    expect(bearing(origin, const Place(lat: 1, lng: -0.001, label: 'Just west of north')), 0);
  });

  test('a straight route is evenly spaced and ends on the destination', () {
    final route = straightRoute(origin, const Place(lat: 4, lng: 8, label: 'There'), steps: 4);

    expect(route, [
      (lat: 1.0, lng: 2.0),
      (lat: 2.0, lng: 4.0),
      (lat: 3.0, lng: 6.0),
      (lat: 4.0, lng: 8.0),
    ]);
  });
}
