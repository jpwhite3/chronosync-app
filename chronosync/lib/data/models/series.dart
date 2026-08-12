import 'package:chronosync/data/models/event.dart';
import 'package:hive/hive.dart';

@HiveType(typeId: 0)
class Series extends HiveObject {
  @HiveField(0)
  String title;

  @HiveField(1)
  HiveList<Event> events;

  Series({required this.title, required this.events});
}

/// Frozen adapter used to read the pre-Drift series box during migration.
final class SeriesAdapter extends TypeAdapter<Series> {
  @override
  int get typeId => 0;

  @override
  Series read(BinaryReader reader) {
    final int fieldCount = reader.readByte();
    final Map<int, dynamic> fields = <int, dynamic>{
      for (int index = 0; index < fieldCount; index += 1)
        reader.readByte(): reader.read(),
    };
    return Series(
      title: fields[0] as String,
      events: (fields[1] as HiveList<dynamic>).castHiveList<Event>(),
    );
  }

  @override
  void write(BinaryWriter writer, Series object) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(object.title)
      ..writeByte(1)
      ..write(object.events);
  }
}
