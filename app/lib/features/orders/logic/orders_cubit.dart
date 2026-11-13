import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api_failure.dart';
import '../data/models/order.dart';
import '../data/models/order_status.dart';
import '../data/order_repository.dart';

class OrdersState extends Equatable {
  const OrdersState({this.orders, this.busyOrderId, this.failure});

  /// Null until the first load has succeeded.
  final List<Order>? orders;

  /// The order a transition is in flight for.
  final String? busyOrderId;

  /// What went wrong last. It lasts for one state only.
  final ApiFailure? failure;

  @override
  List<Object?> get props => [orders, busyOrderId, failure];
}

/// The list of orders a role works from, and the steps taken from that list.
class OrdersCubit extends Cubit<OrdersState> {
  OrdersCubit(this._repository) : super(const OrdersState());

  final OrderRepository _repository;

  Future<void> load() async {
    // Drops the last failure, so a first load that failed shows as loading
    // again and a refresh that fails twice is reported twice.
    emit(OrdersState(orders: state.orders, busyOrderId: state.busyOrderId));
    try {
      final orders = await _repository.orders();
      if (isClosed) return;
      emit(OrdersState(orders: orders, busyOrderId: state.busyOrderId));
    } on ApiFailure catch (failure) {
      if (isClosed) return;
      emit(OrdersState(orders: state.orders, busyOrderId: state.busyOrderId, failure: failure));
    }
  }

  Future<void> transition(Order order, OrderStatus to) async {
    emit(OrdersState(orders: state.orders, busyOrderId: order.id));
    try {
      final updated = await _repository.transition(order, to);
      if (isClosed) return;
      emit(OrdersState(orders: _withOrder(updated)));
    } on ApiFailure catch (failure) {
      if (isClosed) return;
      final current = failure.currentOrder;
      emit(
        OrdersState(orders: current == null ? state.orders : _withOrder(current), failure: failure),
      );
    }
  }

  List<Order>? _withOrder(Order updated) =>
      state.orders?.map((order) => order.id == updated.id ? updated : order).toList();
}
