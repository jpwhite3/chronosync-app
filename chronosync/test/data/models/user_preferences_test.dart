import 'package:flutter_test/flutter_test.dart';
import 'package:chronosync/data/models/user_preferences.dart';

void main() {
  group('UserPreferences', () {
    test('swipeDirection defaults to ltr', () {
      final prefs = UserPreferences();

      expect(prefs.swipeDirection, equals('ltr'));
      expect(prefs.swipeDirectionEnum, equals(SwipeDirection.ltr));
    });

    test('autoProgressAudioEnabled defaults to true', () {
      final prefs = UserPreferences();

      expect(prefs.autoProgressAudioEnabled, isTrue);
    });

    test('can set autoProgressAudioEnabled to false', () {
      final prefs = UserPreferences(
        autoProgressAudioEnabled: false,
      );

      expect(prefs.autoProgressAudioEnabled, isFalse);
    });

    test('can set both swipeDirection and audioProgressAudioEnabled', () {
      final prefs = UserPreferences(
        swipeDirection: 'rtl',
        autoProgressAudioEnabled: false,
      );

      expect(prefs.swipeDirection, equals('rtl'));
      expect(prefs.swipeDirectionEnum, equals(SwipeDirection.rtl));
      expect(prefs.autoProgressAudioEnabled, isFalse);
    });
  });

  group('SwipeDirection', () {
    test('ltr enum has correct value', () {
      expect(SwipeDirection.ltr.value, equals('ltr'));
    });

    test('rtl enum has correct value', () {
      expect(SwipeDirection.rtl.value, equals('rtl'));
    });
  });
}
