import 'package:equatable/equatable.dart';
import 'package:hive/hive.dart';
import 'haptic_intensity.dart';

part 'event_notification_settings.g.dart';

/// Per-event notification and haptic settings (optional overrides)
@HiveType(typeId: 12)
class EventNotificationSettings extends Equatable {
  @HiveField(0)
  final bool? notificationsEnabled;

  @HiveField(1)
  final bool? hapticEnabled;

  @HiveField(2)
  final HapticIntensity? hapticIntensity;

  @HiveField(3)
  final bool? soundEnabled;

  @HiveField(4)
  final String? customSoundPath;

  const EventNotificationSettings({
    this.notificationsEnabled,
    this.hapticEnabled,
    this.hapticIntensity,
    this.soundEnabled,
    this.customSoundPath,
  });

  /// No overrides (all null = use global settings)
  factory EventNotificationSettings.useGlobal() {
    return const EventNotificationSettings();
  }

  /// Check if any overrides are set
  bool get hasOverrides {
    return notificationsEnabled != null ||
        hapticEnabled != null ||
        hapticIntensity != null ||
        soundEnabled != null ||
        customSoundPath != null;
  }

  EventNotificationSettings copyWith({
    bool? notificationsEnabled,
    bool? hapticEnabled,
    HapticIntensity? hapticIntensity,
    bool? soundEnabled,
    String? customSoundPath,
  }) {
    return EventNotificationSettings(
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      hapticEnabled: hapticEnabled ?? this.hapticEnabled,
      hapticIntensity: hapticIntensity ?? this.hapticIntensity,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      customSoundPath: customSoundPath ?? this.customSoundPath,
    );
  }

  /// Clear all overrides
  EventNotificationSettings clearOverrides() {
    return EventNotificationSettings.useGlobal();
  }

  @override
  List<Object?> get props => <Object?>[
        notificationsEnabled,
        hapticEnabled,
        hapticIntensity,
        soundEnabled,
        customSoundPath,
      ];
}
