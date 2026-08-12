import 'package:chronosync/data/transports/transport_heartbeat.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TransportHeartbeat', () {
    test('recognizes only JSON pong frames', () {
      expect(TransportHeartbeat.isPong('{"type":"pong"}'), isTrue);
      expect(TransportHeartbeat.isPong('{"type":"pong","revision":4}'), isTrue);
      expect(TransportHeartbeat.isPong('{"type":"ping"}'), isFalse);
      expect(TransportHeartbeat.isPong('not-json'), isFalse);
      expect(TransportHeartbeat.isPong(<String, Object?>{}), isFalse);
    });

    test('uses a strict bounded timeout', () {
      final DateTime responseAt = DateTime.utc(2026, 7, 28, 12);
      const Duration timeout = Duration(seconds: 16);

      expect(
        TransportHeartbeat.isTimedOut(
          lastResponseAt: responseAt,
          now: responseAt.add(timeout),
          timeout: timeout,
        ),
        isFalse,
      );
      expect(
        TransportHeartbeat.isTimedOut(
          lastResponseAt: responseAt,
          now: responseAt.add(timeout).add(const Duration(microseconds: 1)),
          timeout: timeout,
        ),
        isTrue,
      );
    });
  });
}
