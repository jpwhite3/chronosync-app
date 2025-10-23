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

  int get remainingSeconds {
    final remaining = currentEvent.duration.inSeconds - elapsedSeconds;
    return remaining < 0 ? 0 : remaining;
  }

  int get overtimeSeconds {
    final remaining = currentEvent.duration.inSeconds - elapsedSeconds;
    return remaining < 0 ? -remaining : 0;
  }

  bool get isOvertime => currentEvent.duration.inSeconds - elapsedSeconds < 0;

  @override
  List<Object> get props => [series, currentEventIndex, elapsedSeconds];
}

class LiveTimerCompleted extends LiveTimerState {}
