import 'package:equatable/equatable.dart';

class CourierLocation extends Equatable {
  const CourierLocation({required this.lat, required this.lng, required this.at, this.heading});

  factory CourierLocation.fromJson(Map<String, dynamic> json) => CourierLocation(
    lat: (json['lat'] as num).toDouble(),
    lng: (json['lng'] as num).toDouble(),
    heading: (json['heading'] as num?)?.round(),
    at: DateTime.parse(json['at'] as String),
  );

  final double lat;
  final double lng;

  /// Degrees clockwise from north, 0 to 359.
  final int? heading;
  final DateTime at;

  /// Positions are last-value-wins, so one reported before [other] is stale.
  bool isOlderThan(CourierLocation other) => at.isBefore(other.at);

  @override
  List<Object?> get props => [lat, lng, heading, at];
}
