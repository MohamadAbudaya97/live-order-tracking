import 'dart:async';

import 'package:live_order_tracking/features/orders/data/models/courier_location.dart';
import 'package:live_order_tracking/features/orders/data/models/order.dart';
import 'package:live_order_tracking/features/orders/data/models/order_event.dart';
import 'package:live_order_tracking/features/orders/data/tracking_socket.dart';

import 'fixtures.dart';

/// A socket the test drives by hand: it decides when the connection comes and
/// goes, what the server answers to a subscribe and which events arrive.
class FakeTrackingSocket implements TrackingSocket {
  FakeTrackingSocket({required Order snapshot})
    : onSubscribe = ((_) => SubscribeAck(snapshot: snapshot));

  final _connected = StreamController<bool>.broadcast();
  final _orderEvents = StreamController<OrderEvent>.broadcast();
  final _courierMoves = StreamController<CourierMove>.broadcast();

  /// The server's side of a subscribe, given the `afterSeq` it was sent.
  FutureOr<SubscribeAck> Function(int afterSeq) onSubscribe;

  /// The `afterSeq` of every subscribe so far, oldest first.
  final subscribedAfter = <int>[];

  bool connectCalled = false;
  bool disposed = false;

  void goOnline() => _connected.add(true);

  void goOffline() => _connected.add(false);

  void push(OrderEvent event) => _orderEvents.add(event);

  void moveCourier(CourierLocation location, {String of = orderId}) =>
      _courierMoves.add((orderId: of, location: location));

  @override
  Stream<bool> get connected => _connected.stream;

  @override
  Stream<OrderEvent> get orderEvents => _orderEvents.stream;

  @override
  Stream<CourierMove> get courierMoves => _courierMoves.stream;

  @override
  void connect() => connectCalled = true;

  @override
  Future<SubscribeAck> subscribe(String orderId, {required int afterSeq}) async {
    subscribedAfter.add(afterSeq);
    return onSubscribe(afterSeq);
  }

  @override
  void dispose() => disposed = true;
}
