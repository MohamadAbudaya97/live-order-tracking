import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api_failure.dart';
import '../data/models/courier_location.dart';
import '../data/models/order.dart';
import '../data/models/order_event.dart';
import '../data/models/order_status.dart';
import '../data/order_repository.dart';
import '../data/tracking_socket.dart';

part 'order_tracking_event.dart';
part 'order_tracking_state.dart';

/// Keeps one order in step with the server while its screen is open.
///
/// The order only ever moves forward: an event is applied when it is exactly
/// the next one, ignored when it was applied before, and a gap is filled from
/// the event log before anything newer is looked at.
class OrderTrackingBloc extends Bloc<OrderTrackingEvent, OrderTrackingState> {
  OrderTrackingBloc({required Order order, required this._repository, required this._socket})
    : super(OrderTrackingState(order: order)) {
    // One queue for everything that touches the order. Handling events one
    // at a time is what keeps a slow catch-up from being overtaken by the
    // events that arrive while it is in flight.
    on<OrderTrackingEvent>(_onEvent, transformer: (events, mapper) => events.asyncExpand(mapper));

    final orderId = order.id;
    _subscriptions = [
      _socket.connected.listen((connected) => add(_ConnectionChanged(connected))),
      _socket.orderEvents
          .where((event) => event.orderId == orderId)
          .listen((event) => add(_OrderEventReceived(event))),
      _socket.courierMoves
          .where((move) => move.orderId == orderId)
          .listen((move) => add(_CourierMoved(move.location))),
    ];
    _socket.connect();
  }

  final OrderRepository _repository;
  final TrackingSocket _socket;
  late final List<StreamSubscription<void>> _subscriptions;

  Future<void> _onEvent(OrderTrackingEvent event, Emitter<OrderTrackingState> emit) =>
      switch (event) {
        TrackingRetryRequested() => _subscribe(emit),
        TrackingCancelRequested() => _cancel(emit),
        _ConnectionChanged(:final connected) => _onConnectionChanged(connected, emit),
        _OrderEventReceived(:final event) => _onOrderEvent(event, emit),
        _CourierMoved(:final location) => _onCourierMoved(location, emit),
      };

  Future<void> _onConnectionChanged(bool connected, Emitter<OrderTrackingState> emit) async {
    emit(
      state.copyWith(
        connection: connected ? LiveConnection.connected : LiveConnection.reconnecting,
      ),
    );
    if (connected) await _subscribe(emit);
  }

  /// Asks the server for everything after the newest event applied here.
  /// The first connect, every reconnect and a manual retry all sync this way.
  Future<void> _subscribe(Emitter<OrderTrackingState> emit) async {
    try {
      final ack = await _socket.subscribe(state.order.id, afterSeq: state.order.lastSeq);
      final replayed = _applyInOrder(state.order, ack.missed);
      emit(state.copyWith(order: _adopt(replayed, ack.snapshot), syncFailed: false));
    } on ApiFailure {
      emit(state.copyWith(syncFailed: true));
    }
  }

  Future<void> _onOrderEvent(OrderEvent event, Emitter<OrderTrackingState> emit) async {
    final lastSeq = state.order.lastSeq;
    if (event.seq <= lastSeq) return;

    if (event.seq == lastSeq + 1) {
      emit(state.copyWith(order: event.applyTo(state.order)));
      return;
    }

    // Something in between never arrived. The early event is not kept: the
    // log returns it again, after the ones that are missing.
    try {
      final events = await _repository.eventsAfter(state.order.id, lastSeq);
      emit(state.copyWith(order: _applyInOrder(state.order, events), syncFailed: false));
    } on ApiFailure {
      emit(state.copyWith(syncFailed: true));
    }
  }

  Future<void> _onCourierMoved(CourierLocation location, Emitter<OrderTrackingState> emit) async {
    final shown = state.order.courierLocation;
    if (shown != null && location.isOlderThan(shown)) return;

    emit(state.copyWith(order: state.order.copyWith(courierLocation: location)));
  }

  Future<void> _cancel(Emitter<OrderTrackingState> emit) async {
    emit(state.copyWith(cancelling: true));
    try {
      final cancelled = await _repository.transition(state.order, OrderStatus.cancelled);
      emit(state.copyWith(order: _adopt(state.order, cancelled), cancelling: false));
    } on ApiFailure catch (failure) {
      final current = failure.currentOrder;
      emit(
        state.copyWith(
          order: current == null ? null : _adopt(state.order, current),
          cancelling: false,
          cancelFailure: failure,
        ),
      );
    }
  }

  @override
  Future<void> close() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _socket.dispose();
    return super.close();
  }
}

/// Applies [events] on top of [order], skipping any that is not the next one.
Order _applyInOrder(Order order, List<OrderEvent> events) {
  var result = order;
  for (final event in events) {
    if (event.seq == result.lastSeq + 1) result = event.applyTo(result);
  }
  return result;
}

/// A whole order from the server replaces [held] unless it is behind the
/// events already applied here. The courier position is not part of the log,
/// so the newer of the two positions is kept whichever order wins.
Order _adopt(Order held, Order fromServer) {
  final order = fromServer.lastSeq >= held.lastSeq ? fromServer : held;
  final ours = held.courierLocation;
  final theirs = fromServer.courierLocation;
  final newest = ours == null || (theirs != null && !theirs.isOlderThan(ours)) ? theirs : ours;
  return order.copyWith(courierLocation: newest);
}
