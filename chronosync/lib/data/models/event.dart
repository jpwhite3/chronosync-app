import 'package:hive/hive.dart';

part 'event.g.dart';

@HiveType(typeId: 1)
class Event extends HiveObject {
  @HiveField(0)
  String title;

  @HiveField(1)
  int durationInSeconds;

  @HiveField(2)
  bool autoProgress;

  Event({
    required this.title,
    required this.durationInSeconds,
    this.autoProgress = false,
  });

  // Helper getter to get Duration object
  Duration get duration => Duration(seconds: durationInSeconds);
  
  // Helper constructor for convenience
  Event.fromDuration({
    required this.title,
    required Duration duration,
    this.autoProgress = false,
  }) : durationInSeconds = duration.inSeconds;
}
