import 'package:flutter_test/flutter_test.dart';
import 'package:chronosync/data/models/haptic_intensity.dart';

void main() {
  group('HapticIntensity', () {
    test('displayName returns correct values', () {
      expect(HapticIntensity.none.displayName, 'None');
      expect(HapticIntensity.light.displayName, 'Light');
      expect(HapticIntensity.medium.displayName, 'Medium');
      expect(HapticIntensity.strong.displayName, 'Strong');
    });

    test('amplitude returns correct values for Android', () {
      expect(HapticIntensity.none.amplitude, 0);
      expect(HapticIntensity.light.amplitude, 50);
      expect(HapticIntensity.medium.amplitude, 150);
      expect(HapticIntensity.strong.amplitude, 255);
    });

    test('amplitude increases with intensity', () {
      expect(HapticIntensity.light.amplitude < HapticIntensity.medium.amplitude, true);
      expect(HapticIntensity.medium.amplitude < HapticIntensity.strong.amplitude, true);
    });
  });
}
