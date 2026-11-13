import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../../core/api_failure.dart';
import '../data/models/order.dart';
import '../data/order_repository.dart';

class PlaceOrderState extends Equatable {
  const PlaceOrderState({this.submitting = false, this.placed, this.failure});

  final bool submitting;
  final Order? placed;
  final ApiFailure? failure;

  @override
  List<Object?> get props => [submitting, placed, failure];
}

class PlaceOrderCubit extends Cubit<PlaceOrderState> {
  PlaceOrderCubit(this._repository, {String Function()? newKey})
    : _newKey = newKey ?? const Uuid().v4,
      super(const PlaceOrderState());

  final OrderRepository _repository;
  final String Function() _newKey;

  /// The idempotency key of an attempt whose outcome is not known yet.
  String? _pendingKey;

  Future<void> placeDemoOrder() async {
    if (state.submitting) return;

    // A key stands for one intended order, not for one request. It is kept
    // until the server has answered, so trying again after a lost answer
    // sends the same key and gets the order the first request created.
    final key = _pendingKey ??= _newKey();
    emit(const PlaceOrderState(submitting: true));
    try {
      final order = await _repository.placeDemoOrder(idempotencyKey: key);
      _pendingKey = null;
      if (isClosed) return;
      emit(PlaceOrderState(placed: order));
    } on ApiFailure catch (failure) {
      if (!failure.outcomeUnknown) _pendingKey = null;
      if (isClosed) return;
      emit(PlaceOrderState(failure: failure));
    }
  }
}
