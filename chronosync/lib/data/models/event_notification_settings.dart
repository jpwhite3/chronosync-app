import 'package:equatable/equatable.dart';
import 'package:hive/hive.dart';
import 'haptic_intensity.dart';

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

/// Frozen adapter retained for the one-release Hive migration window.
final class EventNotificationSettingsAdapter
    extends TypeAdapter<EventNotificationSettings> {
  @override
  int get typeId => 12;

  @override
  EventNotificationSettings read(BinaryReader reader) {
    final int fieldCount = reader.readByte();
    final Map<int, dynamic> fields = <int, dynamic>{
      for (int index = 0; index < fieldCount; index += 1)
        reader.readByte(): reader.read(),
    };
    return EventNotificationSettings(
      notificationsEnabled: fields[0] as bool?,
      hapticEnabled: fields[1] as bool?,
      hapticIntensity: fields[2] as HapticIntensity?,
      soundEnabled: fields[3] as bool?,
      customSoundPath: fields[4] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, EventNotificationSettings object) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(object.notificationsEnabled)
      ..writeByte(1)
      ..write(object.hapticEnabled)
      ..writeByte(2)
      ..write(object.hapticIntensity)
      ..writeByte(3)
      ..write(object.soundEnabled)
      ..writeByte(4)
      ..write(object.customSoundPath);
  }
}
