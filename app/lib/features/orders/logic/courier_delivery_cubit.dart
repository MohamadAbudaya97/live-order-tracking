import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api_failure.dart';
import '../data/models/courier_location.dart';
import '../data/models/order.dart';
import '../data/models/order_status.dart';
import '../data/order_repository.dart';
import 'route.dart';

class CourierDeliveryState extends Equatable {
  const CourierDeliveryState({
    required this.order,
    this.walking = false,
    this.step = 0,
    this.delivering = false,
    this.failure,
  });

  final Order order;

  /// True while the simulated walk is sending positions.
  final bool walking;

  /// How many of the walk's positions have been sent.
  final int step;
  final bool delivering;

  /// What went wrong last. It lasts for one state only.
  final ApiFailure? failure;

  CourierDeliveryState copyWith({
    Order? order,
    bool? walking,
    int? step,
    bool? delivering,
    ApiFailure? failure,
  }) => CourierDeliveryState(
    order: order ?? this.order,
    walking: walking ?? this.walking,
    step: step ?? this.step,
    delivering: delivering ?? this.delivering,
    failure: failure,
  );

  @override
  List<Object?> get props => [order, walking, step, delivering, failure];
}

/// The courier's side of one picked-up order: report positions, then deliver.
class CourierDeliveryCubit extends Cubit<CourierDeliveryState> {
  CourierDeliveryCubit(this._repository, Order order, {this.interval = const Duration(seconds: 1)})
    : super(CourierDeliveryState(order: order));

  static const routeSteps = 40;

  final OrderRepository _repository;

  /// Time between two positions. The server sends on at most one a second.
  final Duration interval;

  /// Names the walk in progress. A walk stops as soon as this has moved on.
  int _walk = 0;

  /// Stands in for a GPS: walks the straight line from pickup to drop-off and
  /// reports each point on the way.
  Future<void> simulateRoute() async {
    if (state.walking) return;

    final walk = ++_walk;
    final order = state.order;
    final heading = bearing(order.pickup, order.dropoff);
    final route = straightRoute(order.pickup, order.dropoff, steps: routeSteps);
    emit(state.copyWith(walking: true, step: 0));

    for (final (index, point) in route.indexed) {
      if (index > 0) await Future<void>.delayed(interval);
      if (walk != _walk) return;
      try {
        await _repository.sendCourierLocation(
          order.id,
          lat: point.lat,
          lng: point.lng,
          heading: heading,
        );
      } on ApiFailure catch (failure) {
        if (walk != _walk) return;
        emit(state.copyWith(walking: false, failure: failure));
        return;
      }
      if (walk != _walk) return;
      final location = CourierLocation(
        lat: point.lat,
        lng: point.lng,
        heading: heading,
        at: DateTime.now(),
      );
      emit(
        state.copyWith(
          order: state.order.copyWith(courierLocation: location),
          step: index + 1,
        ),
      );
    }
    emit(state.copyWith(walking: false));
  }

  Future<void> markDelivered() async {
    _walk++;
    emit(state.copyWith(walking: false, delivering: true));
    try {
      final order = await _repository.transition(state.order, OrderStatus.delivered);
      if (isClosed) return;
      emit(state.copyWith(order: order, delivering: false));
    } on ApiFailure catch (failure) {
      if (isClosed) return;
      emit(state.copyWith(order: failure.currentOrder, delivering: false, failure: failure));
    }
  }

  @override
  Future<void> close() {
    _walk++;
    return super.close();
  }
}
