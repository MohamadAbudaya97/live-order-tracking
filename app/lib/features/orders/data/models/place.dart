import 'package:equatable/equatable.dart';

class Place extends Equatable {
  const Place({required this.lat, required this.lng, required this.label});

  factory Place.fromJson(Map<String, dynamic> json) => Place(
    lat: (json['lat'] as num).toDouble(),
    lng: (json['lng'] as num).toDouble(),
    label: json['label'] as String,
  );

  final double lat;
  final double lng;
  final String label;

  @override
  List<Object?> get props => [lat, lng, label];
}
