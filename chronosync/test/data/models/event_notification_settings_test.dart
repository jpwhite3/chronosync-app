import 'package:flutter_test/flutter_test.dart';
import 'package:chronosync/data/models/event_notification_settings.dart';
import 'package:chronosync/data/models/haptic_intensity.dart';

void main() {
  group('EventNotificationSettings', () {
    test('useGlobal factory creates settings with no overrides', () {
      final EventNotificationSettings settings = EventNotificationSettings.useGlobal();

      expect(settings.notificationsEnabled, null);
      expect(settings.hapticEnabled, null);
      expect(settings.hapticIntensity, null);
      expect(settings.soundEnabled, null);
      expect(settings.customSoundPath, null);
    });

    test('hasOverrides returns false when all fields are null', () {
      final EventNotificationSettings settings = EventNotificationSettings.useGlobal();
      expect(settings.hasOverrides, false);
    });

    test('hasOverrides returns true when any field is set', () {
      final EventNotificationSettings settings1 = const EventNotificationSettings(notificationsEnabled: true);
      final EventNotificationSettings settings2 = const EventNotificationSettings(hapticIntensity: HapticIntensity.strong);
      final EventNotificationSettings settings3 = const EventNotificationSettings(customSoundPath: 'sound.mp3');

      expect(settings1.hasOverrides, true);
      expect(settings2.hasOverrides, true);
      expect(settings3.hasOverrides, true);
    });

    test('clearOverrides returns settings with no overrides', () {
      final EventNotificationSettings settings = const EventNotificationSettings(
        notificationsEnabled: false,
        hapticEnabled: true,
        hapticIntensity: HapticIntensity.strong,
      );

      final EventNotificationSettings cleared = settings.clearOverrides();

      expect(cleared.hasOverrides, false);
      expect(cleared.notificationsEnabled, null);
      expect(cleared.hapticEnabled, null);
      expect(cleared.hapticIntensity, null);
    });

    test('copyWith preserves unspecified overrides', () {
      final EventNotificationSettings original = const EventNotificationSettings(
        notificationsEnabled: true,
        hapticEnabled: false,
      );

      final EventNotificationSettings updated = original.copyWith(hapticIntensity: HapticIntensity.light);

      expect(updated.notificationsEnabled, true);
      expect(updated.hapticEnabled, false);
      expect(updated.hapticIntensity, HapticIntensity.light);
    });
  });
}
