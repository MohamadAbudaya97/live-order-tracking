import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

import 'api_failure.dart';

/// One Socket.IO namespace, reduced to what the app needs from it: whether
/// it is connected, named events, and a request that waits for its ack.
class SocketClient {
  SocketClient({required String url, required String token})
    : _socket = io.io(
        url,
        io.OptionBuilder()
            .setTransports(['websocket'])
            .setAuth({'token': token})
            .disableAutoConnect()
            // A connection of its own instead of the one the package caches
            // per host, so that disposing this client really closes it.
            .enableForceNew()
            .build(),
      ) {
    _socket
      ..onConnect((_) => _connected.add(true))
      ..onDisconnect((_) => _connected.add(false))
      ..onConnectError((_) => _connected.add(false));
  }

  static const _ackTimeout = Duration(seconds: 5);

  final io.Socket _socket;
  final _connected = StreamController<bool>.broadcast();

  /// True on every connect and reconnect, false when the connection drops or
  /// an attempt fails. The package keeps retrying on its own.
  Stream<bool> get connected => _connected.stream;

  void connect() => _socket.connect();

  void on(String event, void Function(Map<String, dynamic> payload) handler) {
    _socket.on(event, (payload) => handler(payload as Map<String, dynamic>));
  }

  /// Sends [event] and completes with the server's acknowledgement. Fails
  /// with a network [ApiFailure] when none arrives in time, which also takes
  /// the request out of the send buffer so it cannot go out late.
  Future<Map<String, dynamic>> request(String event, Map<String, dynamic> payload) {
    final answer = Completer<Map<String, dynamic>>();
    _socket
        .timeout(_ackTimeout.inMilliseconds)
        .emitWithAck(
          event,
          payload,
          ack: (Object? error, [Object? ack]) {
            if (error == null && ack is Map<String, dynamic>) {
              answer.complete(ack);
            } else {
              answer.completeError(const ApiFailure(ApiErrorCode.network));
            }
          },
        );
    return answer.future;
  }

  void dispose() {
    _socket.dispose();
    unawaited(_connected.close());
  }
}
