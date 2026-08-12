part of 'live_timer_bloc.dart';

abstract class LiveTimerState extends Equatable {
  const LiveTimerState();

  @override
  List<Object> get props => <Object>[];
}

class LiveTimerInitial extends LiveTimerState {}

class LiveTimerRunning extends LiveTimerState {
  final Series series;
  final int currentEventIndex;
  final int elapsedSeconds;
  final DateTime eventStartTime;
  final DateTime? seriesStartTime;
  final int totalSeriesElapsedSeconds;

  const LiveTimerRunning({
    required this.series,
    required this.currentEventIndex,
    required this.elapsedSeconds,
    required this.eventStartTime,
    this.seriesStartTime,
    this.totalSeriesElapsedSeconds = 0,
  });

  Event get currentEvent => series.events[currentEventIndex];

  int get remainingSeconds {
    final int remaining = currentEvent.duration.inSeconds - elapsedSeconds;
    return remaining < 0 ? 0 : remaining;
  }

  int get overtimeSeconds {
    final int remaining = currentEvent.duration.inSeconds - elapsedSeconds;
    return remaining < 0 ? -remaining : 0;
  }

  bool get isOvertime => currentEvent.duration.inSeconds - elapsedSeconds < 0;

  bool get isLastEvent => currentEventIndex >= series.events.length - 1;

  /// Checks auto-progression against an injected time source.
  bool shouldAutoProgressAt(DateTime now) {
    // Must have reached zero countdown
    if (remainingSeconds > 0) return false;

    // Event must have auto-progress enabled
    if (!currentEvent.autoProgress) return false;

    // Minimum 1-second display time must have elapsed
    final bool minDisplayTimeElapsed =
        now.toUtc().difference(eventStartTime.toUtc()).inSeconds >= 1;

    return minDisplayTimeElapsed;
  }

  /// Maintains the existing UI contract while timer logic uses
  /// [shouldAutoProgressAt] with an injected clock.
  bool get shouldAutoProgress => shouldAutoProgressAt(DateTime.now());

  @override
  List<Object> get props => <Object>[
    series,
    currentEventIndex,
    elapsedSeconds,
    eventStartTime,
    if (seriesStartTime != null) seriesStartTime!,
    totalSeriesElapsedSeconds,
  ];
}

class LiveTimerCompleted extends LiveTimerState {
  final SeriesStatistics statistics;

  const LiveTimerCompleted({required this.statistics});

  @override
  List<Object> get props => <Object>[statistics];
}
