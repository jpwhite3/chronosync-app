import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:chronosync/data/models/event.dart';
import 'package:chronosync/data/models/series.dart';
import 'package:equatable/equatable.dart';

part 'live_timer_event.dart';
part 'live_timer_state.dart';

class LiveTimerBloc extends Bloc<LiveTimerEvent, LiveTimerState> {
  Timer? _timer;

  LiveTimerBloc() : super(LiveTimerInitial()) {
    on<StartTimer>(_onStartTimer);
    on<TimerTick>(_onTimerTick);
    on<NextEvent>(_onNextEvent);
  }

  void _onStartTimer(StartTimer event, Emitter<LiveTimerState> emit) {
    if (event.series.events.isEmpty) {
      emit(LiveTimerCompleted());
      return;
    }

    emit(LiveTimerRunning(
      series: event.series,
      currentEventIndex: 0,
      elapsedSeconds: 0,
    ));

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      add(TimerTick());
    });
  }

  void _onTimerTick(TimerTick event, Emitter<LiveTimerState> emit) {
    if (state is LiveTimerRunning) {
      final LiveTimerRunning currentState = state as LiveTimerRunning;
      emit(LiveTimerRunning(
        series: currentState.series,
        currentEventIndex: currentState.currentEventIndex,
        elapsedSeconds: currentState.elapsedSeconds + 1,
      ));
    }
  }

  void _onNextEvent(NextEvent event, Emitter<LiveTimerState> emit) {
    if (state is LiveTimerRunning) {
      final LiveTimerRunning currentState = state as LiveTimerRunning;
      final int nextIndex = currentState.currentEventIndex + 1;

      if (nextIndex >= currentState.series.events.length) {
        _timer?.cancel();
        emit(LiveTimerCompleted());
      } else {
        emit(LiveTimerRunning(
          series: currentState.series,
          currentEventIndex: nextIndex,
          elapsedSeconds: 0,
        ));
      }
    }
  }

  @override
  Future<void> close() {
    _timer?.cancel();
    return super.close();
  }
}
