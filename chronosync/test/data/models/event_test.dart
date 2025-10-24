import 'package:flutter_test/flutter_test.dart';
import 'package:chronosync/data/models/event.dart';

void main() {
  group('Event', () {
    test('autoProgress defaults to false', () {
      final event = Event(
        title: 'Test Event',
        durationInSeconds: 60,
      );

      expect(event.autoProgress, isFalse);
    });

    test('autoProgress can be set to true', () {
      final event = Event(
        title: 'Auto Event',
        durationInSeconds: 60,
        autoProgress: true,
      );

      expect(event.autoProgress, isTrue);
    });

    test('fromDuration constructor defaults autoProgress to false', () {
      final event = Event.fromDuration(
        title: 'Test Event',
        duration: const Duration(seconds: 120),
      );

      expect(event.autoProgress, isFalse);
      expect(event.durationInSeconds, equals(120));
    });

    test('fromDuration constructor can set autoProgress to true', () {
      final event = Event.fromDuration(
        title: 'Auto Event',
        duration: const Duration(minutes: 2),
        autoProgress: true,
      );

      expect(event.autoProgress, isTrue);
      expect(event.durationInSeconds, equals(120));
    });

    test('duration getter returns correct Duration', () {
      final event = Event(
        title: 'Test Event',
        durationInSeconds: 90,
      );

      expect(event.duration, equals(const Duration(seconds: 90)));
    });
  });
}
