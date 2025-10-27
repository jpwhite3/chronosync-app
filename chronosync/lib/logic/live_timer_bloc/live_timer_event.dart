part of 'live_timer_bloc.dart';

abstract class LiveTimerEvent extends Equatable {
  const LiveTimerEvent();

  @override
  List<Object> get props => <Object>[];
}

class StartTimer extends LiveTimerEvent {
  final Series series;

  const StartTimer(this.series);

  @override
  List<Object> get props => <Object>[series];
}

class TimerTick extends LiveTimerEvent {}

class NextEvent extends LiveTimerEvent {}

class AutoProgressTriggered extends LiveTimerEvent {}

class AppResumed extends LiveTimerEvent {
  final DateTime resumeTime;

  const AppResumed(this.resumeTime);

  @override
  List<Object> get props => <Object>[resumeTime];
}
