// HiveList remains experimental in Hive 2.x, but it is required to exercise
// compatibility with the legacy persisted data model.
// ignore_for_file: experimental_member_use

import 'package:chronosync/data/models/event.dart';
import 'package:chronosync/data/models/series.dart';
import 'package:chronosync/data/models/user_preferences.dart';
import 'package:chronosync/data/repositories/preferences_repository.dart';
import 'package:chronosync/logic/live_timer_bloc/live_timer_bloc.dart';
import 'package:chronosync/logic/settings_cubit/settings_cubit.dart';
import 'package:chronosync/presentation/widgets/dismissible_event_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mockito/mockito.dart';

void main() {
  testWidgets('active timer blocks deletion without offering an inert action', (
    WidgetTester tester,
  ) async {
    final Event event = Event(title: 'Opening keynote', durationInSeconds: 300);
    final SettingsCubit settingsCubit = SettingsCubit(
      PreferencesRepository(_BoxMock()),
    );
    final _SeriesFake series = _SeriesFake(_HiveListFake(<Event>[event]));
    final _LiveTimerBlocFake timerBloc = _LiveTimerBlocFake(
      LiveTimerRunning(
        series: series,
        currentEventIndex: 0,
        elapsedSeconds: 0,
        eventStartTime: DateTime.utc(2026, 1, 1),
      ),
    );
    bool dismissed = false;

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: <BlocProvider<dynamic>>[
          BlocProvider<SettingsCubit>.value(value: settingsCubit),
          BlocProvider<LiveTimerBloc>.value(value: timerBloc),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: DismissibleEventItem(
              event: event,
              series: series,
              index: 0,
              onDismissed: () => dismissed = true,
            ),
          ),
        ),
      ),
    );

    final Dismissible dismissible = tester.widget<Dismissible>(
      find.byType(Dismissible),
    );
    final bool? allowDeletion = await dismissible.confirmDismiss!(
      DismissDirection.startToEnd,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Cannot delete'), findsOneWidget);
    expect(
      find.text('Interval is in use. Stop the timer first.'),
      findsOneWidget,
    );
    expect(find.text('OK'), findsOneWidget);
    expect(find.text('Go to Timer'), findsNothing);
    expect(allowDeletion, isFalse);
    expect(dismissed, isFalse);

    await tester.tap(find.text('OK'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Cannot delete'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

final class _BoxMock extends Mock implements Box<UserPreferences> {}

final class _LiveTimerBlocFake extends LiveTimerBloc {
  _LiveTimerBlocFake(this._state) : super(enableAudio: false);

  final LiveTimerState _state;

  @override
  LiveTimerState get state => _state;
}

final class _HiveListFake extends Mock implements HiveList<Event> {
  _HiveListFake(this._events);

  final List<Event> _events;

  @override
  bool get isEmpty => _events.isEmpty;

  @override
  int get length => _events.length;

  @override
  Event operator [](int index) => _events[index];

  @override
  Iterator<Event> get iterator => _events.iterator;
}

final class _SeriesFake extends Mock implements Series {
  _SeriesFake(this._events);

  final HiveList<Event> _events;

  @override
  HiveList<Event> get events => _events;

  @override
  String get title => 'Event run of show';
}
