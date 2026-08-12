import 'dart:convert';

/// Shared application-level heartbeat framing for browser WebSockets.
///
/// Browsers do not expose WebSocket control-frame pings, so both relay and LAN
/// transports use these small JSON frames for bounded half-open detection.
abstract final class TransportHeartbeat {
  static const String pingFrame = '{"type":"ping"}';

  static bool isPong(Object? frame) {
    if (frame is! String) {
      return false;
    }
    try {
      final Object? decoded = jsonDecode(frame);
      return decoded is Map<Object?, Object?> && decoded['type'] == 'pong';
    } on FormatException {
      return false;
    }
  }

  static bool isTimedOut({
    required DateTime lastResponseAt,
    required DateTime now,
    required Duration timeout,
  }) {
    return now.toUtc().difference(lastResponseAt.toUtc()) > timeout;
  }
}
