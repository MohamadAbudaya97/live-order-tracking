part of 'order_tracking_bloc.dart';

enum LiveConnection { connecting, connected, reconnecting }

class OrderTrackingState extends Equatable {
  const OrderTrackingState({
    required this.order,
    this.connection = LiveConnection.connecting,
    this.syncFailed = false,
    this.cancelling = false,
    this.cancelFailure,
  });

  final Order order;
  final LiveConnection connection;

  /// The last attempt to catch up failed, so [order] may be behind the
  /// server until [TrackingRetryRequested] or the next successful sync.
  final bool syncFailed;

  final bool cancelling;

  /// Why the last cancel did not go through. It lasts for one state only.
  final ApiFailure? cancelFailure;

  OrderTrackingState copyWith({
    Order? order,
    LiveConnection? connection,
    bool? syncFailed,
    bool? cancelling,
    ApiFailure? cancelFailure,
  }) => OrderTrackingState(
    order: order ?? this.order,
    connection: connection ?? this.connection,
    syncFailed: syncFailed ?? this.syncFailed,
    cancelling: cancelling ?? this.cancelling,
    cancelFailure: cancelFailure,
  );

  @override
  List<Object?> get props => [order, connection, syncFailed, cancelling, cancelFailure];
}
