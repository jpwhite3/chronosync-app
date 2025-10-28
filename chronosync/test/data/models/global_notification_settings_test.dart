import 'package:flutter_test/flutter_test.dart';
import 'package:chronosync/data/models/global_notification_settings.dart';
import 'package:chronosync/data/models/haptic_intensity.dart';

void main() {
  group('GlobalNotificationSettings', () {
    test('defaults factory creates expected settings', () {
      final settings = GlobalNotificationSettings.defaults();

      expect(settings.notificationsEnabled, true);
      expect(settings.hapticEnabled, true);
      expect(settings.hapticIntensity, HapticIntensity.medium);
      expect(settings.soundEnabled, true);
      expect(settings.customSoundPath, null);
    });

    test('copyWith updates only specified fields', () {
      final original = GlobalNotificationSettings.defaults();
      final updated = original.copyWith(
        notificationsEnabled: false,
        hapticIntensity: HapticIntensity.strong,
      );

      expect(updated.notificationsEnabled, false);
      expect(updated.hapticIntensity, HapticIntensity.strong);
      // Other fields remain unchanged
      expect(updated.hapticEnabled, true);
      expect(updated.soundEnabled, true);
      expect(updated.customSoundPath, null);
    });

    test('equality works correctly', () {
      final settings1 = GlobalNotificationSettings.defaults();
      final settings2 = GlobalNotificationSettings.defaults();
      final settings3 = settings1.copyWith(notificationsEnabled: false);

      expect(settings1, equals(settings2));
      expect(settings1, isNot(equals(settings3)));
    });
  });
}
