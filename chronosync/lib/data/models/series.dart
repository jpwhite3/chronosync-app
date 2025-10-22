import 'package:chronosync/data/models/event.dart';
import 'package:hive/hive.dart';

part 'series.g.dart';

@HiveType(typeId: 0)
class Series extends HiveObject {
  @HiveField(0)
  String title;

  @HiveField(1)
  HiveList<Event> events;

  Series({required this.title, required this.events});
}
