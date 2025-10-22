import 'package:hive/hive.dart';

part 'event.g.dart';

@HiveType(typeId: 1)
class Event extends HiveObject {
  @HiveField(0)
  String title;

  @HiveField(1)
  Duration duration;

  Event({required this.title, required this.duration});
}
