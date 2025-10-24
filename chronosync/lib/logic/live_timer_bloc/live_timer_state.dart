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
    final remaining = currentEvent.duration.inSeconds - elapsedSeconds;
    return remaining < 0 ? 0 : remaining;
  }

  int get overtimeSeconds {
    final remaining = currentEvent.duration.inSeconds - elapsedSeconds;
    return remaining < 0 ? -remaining : 0;
  }

  bool get isOvertime => currentEvent.duration.inSeconds - elapsedSeconds < 0;
  
  bool get isLastEvent => currentEventIndex >= series.events.length - 1;
  
  /// Check if auto-progression should occur
  bool get shouldAutoProgress {
    // Must have reached zero countdown
    if (remainingSeconds > 0) return false;
    
    // Event must have auto-progress enabled
    if (!currentEvent.autoProgress) return false;
    
    // Minimum 1-second display time must have elapsed
    final minDisplayTimeElapsed = 
        DateTime.now().difference(eventStartTime).inSeconds >= 1;
    
    return minDisplayTimeElapsed;
  }

  @override
  List<Object> get props => [
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
  List<Object> get props => [statistics];
}
