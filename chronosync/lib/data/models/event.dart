import 'package:hive/hive.dart';

part 'event.g.dart';

@HiveType(typeId: 1)
class Event extends HiveObject {
  @HiveField(0)
  String title;

  @HiveField(1)
  int durationInSeconds;

  Event({required this.title, required this.durationInSeconds});

  // Helper getter to get Duration object
  Duration get duration => Duration(seconds: durationInSeconds);
  
  // Helper constructor for convenience
  Event.fromDuration({required this.title, required Duration duration})
      : durationInSeconds = duration.inSeconds;
}
