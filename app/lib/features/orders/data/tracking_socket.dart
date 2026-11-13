import 'dart:async';

import '../../../core/api_failure.dart';
import '../../../core/socket_client.dart';
import 'models/courier_location.dart';
import 'models/order.dart';
import 'models/order_event.dart';

typedef CourierMove = ({String orderId, CourierLocation location});

typedef TrackingSocketFactory = TrackingSocket Function(String token);

/// The server's answer to a subscribe.
class SubscribeAck {
  const SubscribeAck({required this.snapshot, this.missed = const []});

  /// The order as it is now.
  final Order snapshot;

  /// Events newer than the `afterSeq` that was sent, oldest first.
  final List<OrderEvent> missed;
}

/// The realtime side of the API: the `/tracking` namespace.
abstract interface class TrackingSocket {
  /// True on every connect and reconnect, false while the connection is down.
  /// Room membership does not survive a reconnect, so each `true` calls for
  /// a new [subscribe].
  Stream<bool> get connected;

  Stream<OrderEvent> get orderEvents;

  Stream<CourierMove> get courierMoves;

  void connect();

  /// Starts live updates for an order. [afterSeq] is the newest event already
  /// applied by the caller. Throws an [ApiFailure] when the server refuses or
  /// does not answer.
  Future<SubscribeAck> subscribe(String orderId, {required int afterSeq});

  void dispose();
}

class SocketIoTrackingSocket implements TrackingSocket {
  SocketIoTrackingSocket({required String baseUrl, required String token})
    : _client = SocketClient(url: '$baseUrl/tracking', token: token) {
    _client
      ..on('order.event', (json) => _orderEvents.add(OrderEvent.fromJson(json)))
      ..on('courier.location', (json) {
        _courierMoves.add((
          orderId: json['orderId'] as String,
          location: CourierLocation.fromJson(json),
        ));
      });
  }

  final SocketClient _client;
  final _orderEvents = StreamController<OrderEvent>.broadcast();
  final _courierMoves = StreamController<CourierMove>.broadcast();

  @override
  Stream<bool> get connected => _client.connected;

  @override
  Stream<OrderEvent> get orderEvents => _orderEvents.stream;

  @override
  Stream<CourierMove> get courierMoves => _courierMoves.stream;

  @override
  void connect() => _client.connect();

  @override
  Future<SubscribeAck> subscribe(String orderId, {required int afterSeq}) async {
    final ack = await _client.request('subscribe', {'orderId': orderId, 'afterSeq': afterSeq});
    if (ack['ok'] != true) throw ApiFailure(ApiErrorCode.fromWire(ack['code']));

    return SubscribeAck(
      snapshot: Order.fromJson(ack['snapshot'] as Map<String, dynamic>),
      missed: [
        for (final event in ack['missed'] as List<dynamic>)
          OrderEvent.fromJson(event as Map<String, dynamic>),
      ],
    );
  }

  @override
  void dispose() {
    _client.dispose();
    unawaited(_orderEvents.close());
    unawaited(_courierMoves.close());
  }
}
