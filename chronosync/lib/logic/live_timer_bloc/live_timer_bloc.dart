import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:chronosync/data/models/event.dart';
import 'package:chronosync/data/models/series.dart';
import 'package:chronosync/data/models/series_statistics.dart';
import 'package:equatable/equatable.dart';
import 'package:just_audio/just_audio.dart';

part 'live_timer_event.dart';
part 'live_timer_state.dart';

class LiveTimerBloc extends Bloc<LiveTimerEvent, LiveTimerState> {
  Timer? _timer;
  AudioPlayer? _audioPlayer;
  bool _audioLoaded = false;
  final bool enableAudio;
  DateTime? _lastTickTime;

  LiveTimerBloc({this.enableAudio = true}) : super(LiveTimerInitial()) {
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
    } catch (e) {
      // Log error but don't fail - audio is optional
      print('Failed to load audio asset: $e');
      _audioLoaded = false;
      _audioPlayer?.dispose();
      _audioPlayer = null;
    }
  }

  void _onStartTimer(StartTimer event, Emitter<LiveTimerState> emit) {
    if (event.series.events.isEmpty) {
      // Calculate empty series statistics
      final stats = SeriesStatistics(
        eventCount: 0,
        expectedTimeSeconds: 0,
        actualTimeSeconds: 0,
      );
      emit(LiveTimerCompleted(statistics: stats));
      return;
    }

    final now = DateTime.now();
    emit(LiveTimerRunning(
      series: event.series,
      currentEventIndex: 0,
      elapsedSeconds: 0,
      eventStartTime: now,
      seriesStartTime: now,
      totalSeriesElapsedSeconds: 0,
    ));

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      add(TimerTick());
    });
  }

  void _onTimerTick(TimerTick event, Emitter<LiveTimerState> emit) {
    if (state is LiveTimerRunning) {
      final LiveTimerRunning currentState = state as LiveTimerRunning;
      final newElapsed = currentState.elapsedSeconds + 1;
      final newTotalElapsed = currentState.totalSeriesElapsedSeconds + 1;
      
      // Track last tick time for background handling
      _lastTickTime = DateTime.now();
      
      emit(LiveTimerRunning(
        series: currentState.series,
        currentEventIndex: currentState.currentEventIndex,
        elapsedSeconds: newElapsed,
        eventStartTime: currentState.eventStartTime,
        seriesStartTime: currentState.seriesStartTime,
        totalSeriesElapsedSeconds: newTotalElapsed,
      ));
      
      // Check if auto-progression should trigger
      final updatedState = state as LiveTimerRunning;
      if (updatedState.shouldAutoProgress) {
        add(AutoProgressTriggered());
      }
    }
  }

  void _onNextEvent(NextEvent event, Emitter<LiveTimerState> emit) {
    if (state is LiveTimerRunning) {
      final LiveTimerRunning currentState = state as LiveTimerRunning;
      final int nextIndex = currentState.currentEventIndex + 1;

      if (nextIndex >= currentState.series.events.length) {
        _timer?.cancel();
        
        // Calculate series statistics
        final stats = _calculateStatistics(currentState);
        emit(LiveTimerCompleted(statistics: stats));
      } else {
        emit(LiveTimerRunning(
          series: currentState.series,
          currentEventIndex: nextIndex,
          elapsedSeconds: 0,
          eventStartTime: DateTime.now(),
          seriesStartTime: currentState.seriesStartTime,
          totalSeriesElapsedSeconds: currentState.totalSeriesElapsedSeconds,
        ));
      }
    }
  }

  void _onAutoProgressTriggered(
    AutoProgressTriggered event,
    Emitter<LiveTimerState> emit,
  ) async {
    if (state is LiveTimerRunning) {
      final LiveTimerRunning currentState = state as LiveTimerRunning;
      
      // Play audio cue if loaded
      // TODO: Check user preference for audio enabled (will be added with settings)
      if (_audioLoaded && _audioPlayer != null) {
        try {
          await _audioPlayer!.seek(Duration.zero);
          await _audioPlayer!.play();
        } catch (e) {
          // Log error but continue - audio is optional
          print('Failed to play audio: $e');
        }
      }
      
      // Advance to next event
      final int nextIndex = currentState.currentEventIndex + 1;

      if (nextIndex >= currentState.series.events.length) {
        _timer?.cancel();
        
        // Calculate series statistics
        final stats = _calculateStatistics(currentState);
        
        // Log completion for fully automated series
        final allAutoProgressed = currentState.series.events.every((e) => e.autoProgress);
        if (allAutoProgressed) {
          print('✅ Fully automated series completed: ${currentState.series.title}');
        }
        
        emit(LiveTimerCompleted(statistics: stats));
      } else {
        emit(LiveTimerRunning(
          series: currentState.series,
          currentEventIndex: nextIndex,
          elapsedSeconds: 0,
          eventStartTime: DateTime.now(),
          seriesStartTime: currentState.seriesStartTime,
          totalSeriesElapsedSeconds: currentState.totalSeriesElapsedSeconds,
        ));
      }
    }
  }

  SeriesStatistics _calculateStatistics(LiveTimerRunning state) {
    // Calculate expected time (sum of all event durations)
    final expectedTimeSeconds = state.series.events
        .fold<int>(0, (sum, event) => sum + event.durationInSeconds);
    
    // Actual time is the total series elapsed time
    final actualTimeSeconds = state.totalSeriesElapsedSeconds;
    
    return SeriesStatistics(
      eventCount: state.series.events.length,
      expectedTimeSeconds: expectedTimeSeconds,
      actualTimeSeconds: actualTimeSeconds,
    );
  }

  void _onAppResumed(AppResumed event, Emitter<LiveTimerState> emit) {
    if (state is LiveTimerRunning && _lastTickTime != null) {
      final LiveTimerRunning currentState = state as LiveTimerRunning;
      
      // Calculate time elapsed since last tick
      final secondsInBackground = event.resumeTime.difference(_lastTickTime!).inSeconds;
      
      if (secondsInBackground > 0) {
        // Update elapsed time based on background duration
        final newElapsed = currentState.elapsedSeconds + secondsInBackground;
        final newTotalElapsed = currentState.totalSeriesElapsedSeconds + secondsInBackground;
        
        print('📱 App resumed: ${secondsInBackground}s elapsed in background');
        
        emit(LiveTimerRunning(
          series: currentState.series,
          currentEventIndex: currentState.currentEventIndex,
          elapsedSeconds: newElapsed,
          eventStartTime: currentState.eventStartTime,
          seriesStartTime: currentState.seriesStartTime,
          totalSeriesElapsedSeconds: newTotalElapsed,
        ));
        
        // Check if auto-progression should have occurred during background
        final updatedState = state as LiveTimerRunning;
        if (updatedState.shouldAutoProgress) {
          print('⏭️ Auto-progression triggered after background');
          add(AutoProgressTriggered());
        }
        
        // Update last tick time
        _lastTickTime = event.resumeTime;
      }
    }
  }

  @override
  Future<void> close() {
    _timer?.cancel();
    _audioPlayer?.dispose();
    return super.close();
  }
}
