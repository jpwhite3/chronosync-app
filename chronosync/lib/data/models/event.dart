import 'package:hive/hive.dart';
import 'event_notification_settings.dart';

@HiveType(typeId: 1)
class Event extends HiveObject {
  @HiveField(0)
  String title;

  @HiveField(1)
  int durationInSeconds;

  @HiveField(2)
  bool autoProgress;

  @HiveField(3)
  EventNotificationSettings? notificationSettings;

  Event({
    required this.title,
    required this.durationInSeconds,
    this.autoProgress = false,
    this.notificationSettings,
  });

  // Helper getter to get Duration object
  Duration get duration => Duration(seconds: durationInSeconds);

  // Helper constructor for convenience
  Event.fromDuration({
    required this.title,
    required Duration duration,
    this.autoProgress = false,
    this.notificationSettings,
  }) : durationInSeconds = duration.inSeconds;
}

/// Frozen adapter used to read the pre-Drift event box during migration.
final class EventAdapter extends TypeAdapter<Event> {
  @override
  int get typeId => 1;

  @override
  Event read(BinaryReader reader) {
    final int fieldCount = reader.readByte();
    final Map<int, dynamic> fields = <int, dynamic>{
      for (int index = 0; index < fieldCount; index += 1)
        reader.readByte(): reader.read(),
    };
    return Event(
      title: fields[0] as String,
      durationInSeconds: fields[1] as int,
      autoProgress: fields[2] as bool? ?? false,
      notificationSettings: fields[3] as EventNotificationSettings?,
    );
  }

  @override
  void write(BinaryWriter writer, Event object) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(object.title)
      ..writeByte(1)
      ..write(object.durationInSeconds)
      ..writeByte(2)
      ..write(object.autoProgress)
      ..writeByte(3)
      ..write(object.notificationSettings);
  }
}
