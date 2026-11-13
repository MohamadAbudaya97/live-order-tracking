part of 'order_tracking_bloc.dart';

sealed class OrderTrackingEvent {
  const OrderTrackingEvent();
}

/// The user asked to sync again after a failed one.
final class TrackingRetryRequested extends OrderTrackingEvent {
  const TrackingRetryRequested();
}

final class TrackingCancelRequested extends OrderTrackingEvent {
  const TrackingCancelRequested();
}

final class _ConnectionChanged extends OrderTrackingEvent {
  const _ConnectionChanged(this.connected);

  final bool connected;
}

final class _OrderEventReceived extends OrderTrackingEvent {
  const _OrderEventReceived(this.event);

  final OrderEvent event;
}

final class _CourierMoved extends OrderTrackingEvent {
  const _CourierMoved(this.location);

  final CourierLocation location;
}
