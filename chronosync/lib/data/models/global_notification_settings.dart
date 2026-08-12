import 'package:equatable/equatable.dart';
import 'package:hive/hive.dart';
import 'haptic_intensity.dart';

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
  List<Object?> get props => <Object?>[
    notificationsEnabled,
    hapticEnabled,
    hapticIntensity,
    soundEnabled,
    customSoundPath,
  ];
}

/// Frozen adapter retained for the one-release Hive migration window.
final class GlobalNotificationSettingsAdapter
    extends TypeAdapter<GlobalNotificationSettings> {
  @override
  int get typeId => 11;

  @override
  GlobalNotificationSettings read(BinaryReader reader) {
    final int fieldCount = reader.readByte();
    final Map<int, dynamic> fields = <int, dynamic>{
      for (int index = 0; index < fieldCount; index += 1)
        reader.readByte(): reader.read(),
    };
    return GlobalNotificationSettings(
      notificationsEnabled: fields[0] as bool? ?? true,
      hapticEnabled: fields[1] as bool? ?? true,
      hapticIntensity: fields[2] as HapticIntensity? ?? HapticIntensity.medium,
      soundEnabled: fields[3] as bool? ?? true,
      customSoundPath: fields[4] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, GlobalNotificationSettings object) {
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
