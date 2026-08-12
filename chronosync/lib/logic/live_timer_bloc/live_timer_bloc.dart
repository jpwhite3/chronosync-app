import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:chronosync/core/time/clock.dart';
import 'package:chronosync/data/models/event.dart';
import 'package:chronosync/data/models/series.dart';
import 'package:chronosync/data/models/series_statistics.dart';
import 'package:chronosync/data/services/notification_service.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

part 'live_timer_event.dart';
part 'live_timer_state.dart';

class LiveTimerBloc extends Bloc<LiveTimerEvent, LiveTimerState> {
  Timer? _timer;
  AudioPlayer? _audioPlayer;
  bool _audioLoaded = false;
  final bool enableAudio;
  final NotificationService? _notificationService;
  final Clock _clock;
  bool _autoProgressInFlight = false;
  int _transitionRevision = 0;

  LiveTimerBloc({
    this.enableAudio = true,
    NotificationService? notificationService,
    Clock? clock,
  }) : _notificationService = notificationService,
       _clock = clock ?? const SystemClock(),
       super(LiveTimerInitial()) {
    on<StartTimer>(_onStartTimer);
    on<TimerTick>(_onTimerTick);
    on<NextEvent>(_onNextEvent);
    on<AutoProgressTriggered>(_onAutoProgressTriggered);
    on<AppResumed>(_onAppResumed);
    if (enableAudio) {
      _loadAudio();
    }
  }

  Future<void> _loadAudio() async {
    try {
      _audioPlayer = AudioPlayer();
      await _audioPlayer!.setAsset('assets/audio/auto_progress_beep.mp3');
      _audioLoaded = true;
    } on Object {
      // Log error but don't fail - audio is optional
      debugPrint('The timer audio cue could not be loaded.');
      _audioLoaded = false;
      _audioPlayer?.dispose();
      _audioPlayer = null;
    }
  }

  void _onStartTimer(StartTimer event, Emitter<LiveTimerState> emit) {
    _transitionRevision += 1;
    if (event.series.events.isEmpty) {
      // Calculate empty series statistics
      final SeriesStatistics stats = const SeriesStatistics(
        eventCount: 0,
        expectedTimeSeconds: 0,
        actualTimeSeconds: 0,
      );
      emit(LiveTimerCompleted(statistics: stats));
      return;
    }

    final DateTime now = _clock.now();
    emit(
      LiveTimerRunning(
        series: event.series,
        currentEventIndex: 0,
        elapsedSeconds: 0,
        eventStartTime: now,
        seriesStartTime: now,
        totalSeriesElapsedSeconds: 0,
      ),
    );

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      add(TimerTick());
    });
  }

  void _onTimerTick(TimerTick event, Emitter<LiveTimerState> emit) {
    if (state is LiveTimerRunning) {
      final LiveTimerRunning currentState = state as LiveTimerRunning;
      final DateTime now = _clock.now();
      final int newElapsed = _secondsSince(currentState.eventStartTime, now);
      final int newTotalElapsed = _secondsSince(
        currentState.seriesStartTime ?? currentState.eventStartTime,
        now,
      );

      emit(
        LiveTimerRunning(
          series: currentState.series,
          currentEventIndex: currentState.currentEventIndex,
          elapsedSeconds: newElapsed,
          eventStartTime: currentState.eventStartTime,
          seriesStartTime: currentState.seriesStartTime,
          totalSeriesElapsedSeconds: newTotalElapsed,
        ),
      );

      // Check if auto-progression should trigger
      final LiveTimerRunning updatedState = state as LiveTimerRunning;
      if (updatedState.shouldAutoProgressAt(now)) {
        add(AutoProgressTriggered());
      }
    }
  }

  void _onNextEvent(NextEvent event, Emitter<LiveTimerState> emit) {
    if (state is LiveTimerRunning) {
      _transitionRevision += 1;
      final LiveTimerRunning currentState = state as LiveTimerRunning;
      final int nextIndex = currentState.currentEventIndex + 1;
      final DateTime now = _clock.now();
      final int totalElapsedSeconds = _secondsSince(
        currentState.seriesStartTime ?? currentState.eventStartTime,
        now,
      );

      if (nextIndex >= currentState.series.events.length) {
        _timer?.cancel();

        // Calculate series statistics
        final SeriesStatistics stats = _calculateStatistics(
          currentState,
          actualTimeSeconds: totalElapsedSeconds,
        );
        emit(LiveTimerCompleted(statistics: stats));
      } else {
        emit(
          LiveTimerRunning(
            series: currentState.series,
            currentEventIndex: nextIndex,
            elapsedSeconds: 0,
            eventStartTime: now,
            seriesStartTime: currentState.seriesStartTime,
            totalSeriesElapsedSeconds: totalElapsedSeconds,
          ),
        );
      }
    }
  }

  /// Handles automatic progression to next event when countdown reaches 00:00
  ///
  /// Logic flow:
  /// 1. Check if audio is loaded and play the progression sound cue
  /// 2. Determine if this is the last event in the series
  /// 3a. If last event: Calculate statistics and emit LiveTimerCompleted
  /// 3b. If not last: Emit new LiveTimerRunning state with next event
  ///
  /// Key behaviors:
  /// - Audio playback is optional (errors are logged but don't block progression)
  /// - Statistics include event count, expected vs actual time
  /// - Fully automated series are logged for tracking
  /// - New event starts with fresh countdown (elapsedSeconds = 0)
  /// - Series elapsed time continues accumulating across events
  void _onAutoProgressTriggered(
    AutoProgressTriggered event,
    Emitter<LiveTimerState> emit,
  ) async {
    if (state is! LiveTimerRunning || _autoProgressInFlight) {
      return;
    }
    final LiveTimerRunning currentState = state as LiveTimerRunning;
    if (!currentState.shouldAutoProgressAt(_clock.now())) {
      return;
    }

    _autoProgressInFlight = true;
    final int transitionRevision = _transitionRevision;
    final int nextIndex = currentState.currentEventIndex + 1;
    try {
      // Trigger event completion notifications/haptics.
      await _notificationService?.onEventComplete(currentState.currentEvent);

      // Play audio cue if loaded and user preference enabled.
      if (_audioLoaded && _audioPlayer != null) {
        try {
          await _audioPlayer!.seek(Duration.zero);
          await _audioPlayer!.play();
        } on Object {
          // Audio is optional and never blocks timer progression.
          debugPrint('The timer audio cue could not be played.');
        }
      }

      // A manual transition may have completed while feedback was playing.
      final LiveTimerState latest = state;
      if (transitionRevision != _transitionRevision ||
          latest is! LiveTimerRunning ||
          latest.currentEventIndex != currentState.currentEventIndex ||
          latest.eventStartTime != currentState.eventStartTime) {
        return;
      }

      final DateTime transitionTime = _clock.now();
      final int totalElapsedSeconds = _secondsSince(
        currentState.seriesStartTime ?? currentState.eventStartTime,
        transitionTime,
      );
      _transitionRevision += 1;
      if (nextIndex >= currentState.series.events.length) {
        _timer?.cancel();
        emit(
          LiveTimerCompleted(
            statistics: _calculateStatistics(
              currentState,
              actualTimeSeconds: totalElapsedSeconds,
            ),
          ),
        );
      } else {
        emit(
          LiveTimerRunning(
            series: currentState.series,
            currentEventIndex: nextIndex,
            elapsedSeconds: 0,
            eventStartTime: transitionTime,
            seriesStartTime: currentState.seriesStartTime,
            totalSeriesElapsedSeconds: totalElapsedSeconds,
          ),
        );
      }
    } finally {
      _autoProgressInFlight = false;
    }
  }

  /// Calculates aggregate statistics for series completion
  ///
  /// Computes:
  /// - eventCount: Total number of events in the series
  /// - expectedTimeSeconds: Sum of all event durations
  /// - actualTimeSeconds: Total time elapsed during series execution
  ///
  /// The SeriesStatistics model provides computed properties:
  /// - overUnderTimeSeconds: Difference between actual and expected (can be +/-)
  /// - isOvertime/isUndertime/isOnTime: Boolean flags for display
  /// - Formatted time strings for UI display
  SeriesStatistics _calculateStatistics(
    LiveTimerRunning state, {
    required int actualTimeSeconds,
  }) {
    // Calculate expected time (sum of all event durations)
    final int expectedTimeSeconds = state.series.events.fold<int>(
      0,
      (int sum, Event event) => sum + event.durationInSeconds,
    );

    return SeriesStatistics(
      eventCount: state.series.events.length,
      expectedTimeSeconds: expectedTimeSeconds,
      actualTimeSeconds: actualTimeSeconds,
    );
  }

  void _onAppResumed(AppResumed event, Emitter<LiveTimerState> emit) {
    if (state is LiveTimerRunning) {
      final LiveTimerRunning currentState = state as LiveTimerRunning;
      final DateTime resumeTime = event.resumeTime;
      final int newElapsed = _secondsSince(
        currentState.eventStartTime,
        resumeTime,
      );
      final int newTotalElapsed = _secondsSince(
        currentState.seriesStartTime ?? currentState.eventStartTime,
        resumeTime,
      );

      emit(
        LiveTimerRunning(
          series: currentState.series,
          currentEventIndex: currentState.currentEventIndex,
          elapsedSeconds: newElapsed,
          eventStartTime: currentState.eventStartTime,
          seriesStartTime: currentState.seriesStartTime,
          totalSeriesElapsedSeconds: newTotalElapsed,
        ),
      );

      // Trigger auto-progression after a background interval when appropriate.
      final LiveTimerRunning updatedState = state as LiveTimerRunning;
      if (updatedState.shouldAutoProgressAt(resumeTime)) {
        add(AutoProgressTriggered());
      }
    }
  }

  int _secondsSince(DateTime startedAt, DateTime now) {
    final int seconds = now.toUtc().difference(startedAt.toUtc()).inSeconds;
    return seconds < 0 ? 0 : seconds;
  }

  @override
  Future<void> close() {
    _timer?.cancel();
    _audioPlayer?.dispose();
    return super.close();
  }
}
