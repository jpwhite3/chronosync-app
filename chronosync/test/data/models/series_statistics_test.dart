import 'package:flutter_test/flutter_test.dart';
import 'package:chronosync/data/models/series_statistics.dart';

void main() {
  group('SeriesStatistics', () {
    group('basic properties', () {
      test('creates instance with required fields', () {
        final SeriesStatistics stats = const SeriesStatistics(
          eventCount: 5,
          expectedTimeSeconds: 300,
          actualTimeSeconds: 320,
        );

        expect(stats.eventCount, equals(5));
        expect(stats.expectedTimeSeconds, equals(300));
        expect(stats.actualTimeSeconds, equals(320));
      });
    });

    group('computed properties', () {
      test('overUnderTimeSeconds calculates difference correctly', () {
        final SeriesStatistics stats = const SeriesStatistics(
          eventCount: 3,
          expectedTimeSeconds: 180,
          actualTimeSeconds: 200,
        );

        expect(stats.overUnderTimeSeconds, equals(20));
      });

      test('isOvertime returns true when actual > expected', () {
        final SeriesStatistics stats = const SeriesStatistics(
          eventCount: 3,
          expectedTimeSeconds: 180,
          actualTimeSeconds: 200,
        );

        expect(stats.isOvertime, isTrue);
        expect(stats.isUndertime, isFalse);
        expect(stats.isOnTime, isFalse);
      });

      test('isUndertime returns true when actual < expected', () {
        final SeriesStatistics stats = const SeriesStatistics(
          eventCount: 3,
          expectedTimeSeconds: 180,
          actualTimeSeconds: 150,
        );

        expect(stats.isUndertime, isTrue);
        expect(stats.isOvertime, isFalse);
        expect(stats.isOnTime, isFalse);
      });

      test('isOnTime returns true when actual == expected', () {
        final SeriesStatistics stats = const SeriesStatistics(
          eventCount: 3,
          expectedTimeSeconds: 180,
          actualTimeSeconds: 180,
        );

        expect(stats.isOnTime, isTrue);
        expect(stats.isOvertime, isFalse);
        expect(stats.isUndertime, isFalse);
      });
    });

    group('time formatting', () {
      test('formats time under 1 hour as MM:SS', () {
        final SeriesStatistics stats = const SeriesStatistics(
          eventCount: 3,
          expectedTimeSeconds: 125, // 2:05
          actualTimeSeconds: 200, // 3:20
        );

        expect(stats.expectedTimeFormatted, equals('02:05'));
        expect(stats.actualTimeFormatted, equals('03:20'));
      });

      test('formats time over 1 hour as HH:MM:SS', () {
        final SeriesStatistics stats = const SeriesStatistics(
          eventCount: 10,
          expectedTimeSeconds: 3665, // 1:01:05
          actualTimeSeconds: 7384, // 2:03:04
        );

        expect(stats.expectedTimeFormatted, equals('01:01:05'));
        expect(stats.actualTimeFormatted, equals('02:03:04'));
      });

      test('overUnderTimeFormatted shows + prefix for overtime', () {
        final SeriesStatistics stats = const SeriesStatistics(
          eventCount: 3,
          expectedTimeSeconds: 180,
          actualTimeSeconds: 205,
        );

        expect(stats.overUnderTimeFormatted, equals('+00:25'));
      });

      test('overUnderTimeFormatted shows - prefix for undertime', () {
        final SeriesStatistics stats = const SeriesStatistics(
          eventCount: 3,
          expectedTimeSeconds: 180,
          actualTimeSeconds: 145,
        );

        expect(stats.overUnderTimeFormatted, equals('-00:35'));
      });

      test('overUnderTimeFormatted shows no prefix for on-time', () {
        final SeriesStatistics stats = const SeriesStatistics(
          eventCount: 3,
          expectedTimeSeconds: 180,
          actualTimeSeconds: 180,
        );

        expect(stats.overUnderTimeFormatted, equals('00:00'));
      });

      test('handles zero time', () {
        final SeriesStatistics stats = const SeriesStatistics(
          eventCount: 0,
          expectedTimeSeconds: 0,
          actualTimeSeconds: 0,
        );

        expect(stats.expectedTimeFormatted, equals('00:00'));
        expect(stats.actualTimeFormatted, equals('00:00'));
        expect(stats.overUnderTimeFormatted, equals('00:00'));
      });

      test('handles large hour values', () {
        final SeriesStatistics stats = const SeriesStatistics(
          eventCount: 50,
          expectedTimeSeconds: 36000, // 10:00:00
          actualTimeSeconds: 43265, // 12:01:05
        );

        expect(stats.expectedTimeFormatted, equals('10:00:00'));
        expect(stats.actualTimeFormatted, equals('12:01:05'));
        expect(stats.overUnderTimeFormatted, equals('+02:01:05'));
      });
    });

    group('equality and hashCode', () {
      test('equal instances have same values', () {
        final SeriesStatistics stats1 = const SeriesStatistics(
          eventCount: 5,
          expectedTimeSeconds: 300,
          actualTimeSeconds: 320,
        );
        final SeriesStatistics stats2 = const SeriesStatistics(
          eventCount: 5,
          expectedTimeSeconds: 300,
          actualTimeSeconds: 320,
        );

        expect(stats1, equals(stats2));
        expect(stats1.hashCode, equals(stats2.hashCode));
      });

      test('different instances are not equal', () {
        final SeriesStatistics stats1 = const SeriesStatistics(
          eventCount: 5,
          expectedTimeSeconds: 300,
          actualTimeSeconds: 320,
        );
        final SeriesStatistics stats2 = const SeriesStatistics(
          eventCount: 5,
          expectedTimeSeconds: 300,
          actualTimeSeconds: 310,
        );

        expect(stats1, isNot(equals(stats2)));
      });
    });

    group('toString', () {
      test('provides readable string representation', () {
        final SeriesStatistics stats = const SeriesStatistics(
          eventCount: 5,
          expectedTimeSeconds: 300,
          actualTimeSeconds: 320,
        );

        final String string = stats.toString();
        expect(string, contains('SeriesStatistics'));
        expect(string, contains('eventCount: 5'));
        expect(string, contains('expected: 05:00'));
        expect(string, contains('actual: 05:20'));
        expect(string, contains('over/under: +00:20'));
      });
    });
  });
}
