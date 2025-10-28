import 'package:hive/hive.dart';

part 'haptic_intensity.g.dart';

/// Haptic feedback intensity levels
@HiveType(typeId: 10)
enum HapticIntensity {
  @HiveField(0)
  none,

  @HiveField(1)
  light,

  @HiveField(2)
  medium,

  @HiveField(3)
  strong,
}

extension HapticIntensityExtension on HapticIntensity {
  /// Display name for UI
  String get displayName {
    switch (this) {
      case HapticIntensity.none:
        return 'None';
      case HapticIntensity.light:
        return 'Light';
      case HapticIntensity.medium:
        return 'Medium';
      case HapticIntensity.strong:
        return 'Strong';
    }
  }

  /// Get amplitude value for Android vibration (0-255)
  int get amplitude {
    switch (this) {
      case HapticIntensity.none:
        return 0;
      case HapticIntensity.light:
        return 50;
      case HapticIntensity.medium:
        return 150;
      case HapticIntensity.strong:
        return 255;
    }
  }
}
