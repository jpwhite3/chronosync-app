import 'package:bloc_test/bloc_test.dart';
import 'package:chronosync/data/models/event.dart';
import 'package:chronosync/data/models/series.dart';
import 'package:chronosync/logic/live_timer_bloc/live_timer_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'live_timer_bloc_test.mocks.dart';

@GenerateMocks([Box])
void main() {
  group('LiveTimerBloc', () {
    late LiveTimerBloc liveTimerBloc;
    late MockBox<Event> mockEventBox;

    setUp(() {
      mockEventBox = MockBox<Event>();
      liveTimerBloc = LiveTimerBloc();
      when(mockEventBox.name).thenReturn('events');
    });

    tearDown(() {
      liveTimerBloc.close();
    });

    test('initial state is LiveTimerInitial', () {
      expect(liveTimerBloc.state, equals(LiveTimerInitial()));
    });

    blocTest<LiveTimerBloc, LiveTimerState>(
      'emits [LiveTimerCompleted] when StartTimer is added with empty series',
      build: () => liveTimerBloc,
      act: (LiveTimerBloc bloc) {
        final Series series = Series(title: 'Empty Series', events: HiveList(mockEventBox));
        bloc.add(StartTimer(series));
      },
      expect: () => <Matcher>[
        isA<LiveTimerCompleted>(),
      ],
    );

    test('LiveTimerRunning state has correct properties', () {
      final Series series = Series(title: 'Test Series', events: HiveList(mockEventBox));
      final LiveTimerRunning state = LiveTimerRunning(
        series: series,
        currentEventIndex: 0,
        elapsedSeconds: 30,
      );

      expect(state.currentEventIndex, equals(0));
      expect(state.elapsedSeconds, equals(30));
      expect(state.series, equals(series));
    });

    test('LiveTimerCompleted state is correct', () {
      final LiveTimerCompleted state = LiveTimerCompleted();
      expect(state, isA<LiveTimerState>());
    });
  });
}
