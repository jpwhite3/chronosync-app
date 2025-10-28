import 'package:equatable/equatable.dart';
import 'package:hive/hive.dart';
import 'haptic_intensity.dart';

part 'global_notification_settings.g.dart';

/// Global notification and haptic settings
@HiveType(typeId: 11)
class GlobalNotificationSettings extends Equatable {
  @HiveField(0)
  final bool notificationsEnabled;

  @HiveField(1)
  final bool hapticEnabled;

  @HiveField(2)
  final HapticIntensity hapticIntensity;

  @HiveField(3)
  final bool soundEnabled;

  @HiveField(4)
  final String? customSoundPath;

  const GlobalNotificationSettings({
    this.notificationsEnabled = true,
    this.hapticEnabled = true,
    this.hapticIntensity = HapticIntensity.medium,
    this.soundEnabled = true,
    this.customSoundPath,
  });

  /// Default settings (all enabled, medium haptic, system sound)
  factory GlobalNotificationSettings.defaults() {
    return const GlobalNotificationSettings();
  }

  GlobalNotificationSettings copyWith({
    bool? notificationsEnabled,
    bool? hapticEnabled,
    HapticIntensity? hapticIntensity,
    bool? soundEnabled,
    String? customSoundPath,
  }) {
    return GlobalNotificationSettings(
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      hapticEnabled: hapticEnabled ?? this.hapticEnabled,
      hapticIntensity: hapticIntensity ?? this.hapticIntensity,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      customSoundPath: customSoundPath ?? this.customSoundPath,
    );
  }

  @override
  List<Object?> get props => [
        notificationsEnabled,
        hapticEnabled,
        hapticIntensity,
        soundEnabled,
        customSoundPath,
      ];
}
