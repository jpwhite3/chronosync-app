part of 'live_timer_bloc.dart';

abstract class LiveTimerState extends Equatable {
  const LiveTimerState();

  @override
  List<Object> get props => [];
}

class LiveTimerInitial extends LiveTimerState {}

class LiveTimerRunning extends LiveTimerState {
  final Series series;
  final int currentEventIndex;
  final int elapsedSeconds;

  const LiveTimerRunning({
    required this.series,
    required this.currentEventIndex,
    required this.elapsedSeconds,
  });

  Event get currentEvent => series.events[currentEventIndex];

  int get remainingSeconds => currentEvent.duration.inSeconds - elapsedSeconds;

  bool get isOvertime => remainingSeconds < 0;

  @override
  List<Object> get props => [series, currentEventIndex, elapsedSeconds];
}

class LiveTimerCompleted extends LiveTimerState {}
