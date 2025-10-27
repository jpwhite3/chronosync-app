import 'dart:io';
import 'package:chronosync/data/models/event.dart';
import 'package:chronosync/data/models/series.dart';
import 'package:chronosync/logic/live_timer_bloc/live_timer_bloc.dart';
import 'package:chronosync/presentation/screens/live_timer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'live_timer_screen_test.mocks.dart';

@GenerateMocks(<Type>[LiveTimerBloc])
void main() {
  late MockLiveTimerBloc mockBloc;
  late Box<Event> eventBox;
  late Series testSeries;
  late Event testEvent;
  late Directory testDir;

  setUpAll(() async {
    // Initialize Hive for tests with temporary directory
    testDir = Directory.systemTemp.createTempSync('hive_test_');
    Hive.init(testDir.path);
    Hive.registerAdapter(EventAdapter());
    Hive.registerAdapter(SeriesAdapter());
  });

  setUp(() async {
    mockBloc = MockLiveTimerBloc();

    // Use a real event box for tests
    eventBox = await Hive.openBox<Event>('test_events');

    // Create test event (5 minute duration)
    testEvent = Event.fromDuration(
      title: 'Test Event',
      duration: const Duration(minutes: 5),
    );

    // Add event to box so HiveList can reference it
    await eventBox.add(testEvent);

    // Create series with real HiveList
    testSeries = Series(title: 'Test Series', events: HiveList(eventBox));
    testSeries.events.add(testEvent);

    when(mockBloc.stream).thenAnswer((_) => const Stream.empty());
  });

  tearDown(() async {
    await eventBox.clear();
    await eventBox.close();
  });

  tearDownAll(() async {
    await Hive.close();
    if (testDir.existsSync()) {
      testDir.deleteSync(recursive: true);
    }
  });

  Widget createWidgetUnderTest(LiveTimerState state) {
    when(mockBloc.state).thenReturn(state);

    return MaterialApp(
      home: BlocProvider<LiveTimerBloc>.value(
        value: mockBloc,
        child: const LiveTimerScreen(),
      ),
    );
  }

  group('LiveTimerScreen - Normal State', () {
    testWidgets('displays both countdown and elapsed timers', (WidgetTester tester) async {
      final DateTime now = DateTime.now();
      final LiveTimerRunning state = LiveTimerRunning(
        series: testSeries,
        currentEventIndex: 0,
        elapsedSeconds: 120, // 2 minutes elapsed
        eventStartTime: now,
        seriesStartTime: now,
        totalSeriesElapsedSeconds: 120,
      );

      await tester.pumpWidget(createWidgetUnderTest(state));

      // Verify labels
      expect(find.text('Time Remaining'), findsOneWidget);
      expect(find.text('Time Elapsed'), findsOneWidget);

      // Verify countdown shows 3 minutes remaining (5 min event - 2 min elapsed)
      expect(find.text('03:00'), findsOneWidget);

      // Verify elapsed shows 2 minutes
      expect(find.text('02:00'), findsOneWidget);
    });

    testWidgets('countdown is not red in normal state', (WidgetTester tester) async {
      final DateTime now = DateTime.now();
      final LiveTimerRunning state = LiveTimerRunning(
        series: testSeries,
        currentEventIndex: 0,
        elapsedSeconds: 60, // 1 minute elapsed, 4 minutes remaining
        eventStartTime: now,
        seriesStartTime: now,
        totalSeriesElapsedSeconds: 60,
      );

      await tester.pumpWidget(createWidgetUnderTest(state));

      // Find the countdown text widget (04:00)
      final Finder countdownFinder = find.text('04:00');
      expect(countdownFinder, findsOneWidget);

      final Text countdownWidget = tester.widget<Text>(countdownFinder);
      // Verify it's not red (should be null or theme default, not Colors.red)
      expect(countdownWidget.style?.color, isNot(Colors.red));
    });
  });

  group('LiveTimerScreen - Overtime State', () {
    testWidgets('displays negative countdown in overtime', (WidgetTester tester) async {
      final DateTime now = DateTime.now();
      final LiveTimerRunning state = LiveTimerRunning(
        series: testSeries,
        currentEventIndex: 0,
        elapsedSeconds: 360, // 6 minutes elapsed (1 min overtime)
        eventStartTime: now,
        seriesStartTime: now,
        totalSeriesElapsedSeconds: 360,
      );

      await tester.pumpWidget(createWidgetUnderTest(state));

      // Verify countdown shows negative time
      expect(find.text('-01:00'), findsOneWidget);

      // Verify elapsed continues normally
      expect(find.text('06:00'), findsOneWidget);
    });

    testWidgets('countdown turns red in overtime', (WidgetTester tester) async {
      final DateTime now = DateTime.now();
      final LiveTimerRunning state = LiveTimerRunning(
        series: testSeries,
        currentEventIndex: 0,
        elapsedSeconds: 330, // 5 minutes 30 seconds (30 seconds overtime)
        eventStartTime: now,
        seriesStartTime: now,
        totalSeriesElapsedSeconds: 330,
      );

      await tester.pumpWidget(createWidgetUnderTest(state));

      // Find the negative countdown text
      final Finder countdownFinder = find.text('-00:30');
      expect(countdownFinder, findsOneWidget);

      final Text countdownWidget = tester.widget<Text>(countdownFinder);
      expect(countdownWidget.style?.color, Colors.red);
    });

    testWidgets('elapsed timer stays default color in overtime', (
      WidgetTester tester,
    ) async {
      final DateTime now = DateTime.now();
      final LiveTimerRunning state = LiveTimerRunning(
        series: testSeries,
        currentEventIndex: 0,
        elapsedSeconds: 330, // 5 minutes 30 seconds elapsed
        eventStartTime: now,
        seriesStartTime: now,
        totalSeriesElapsedSeconds: 330,
      );

      await tester.pumpWidget(createWidgetUnderTest(state));

      // Find the elapsed timer text
      final Finder elapsedFinder = find.text('05:30');
      expect(elapsedFinder, findsOneWidget);

      final Text elapsedWidget = tester.widget<Text>(elapsedFinder);
      // Verify it's not red
      expect(elapsedWidget.style?.color, isNot(Colors.red));
    });
  });

  group('LiveTimerScreen - NEXT Button', () {
    testWidgets('NEXT button is present', (WidgetTester tester) async {
      final DateTime now = DateTime.now();
      final LiveTimerRunning state = LiveTimerRunning(
        series: testSeries,
        currentEventIndex: 0,
        elapsedSeconds: 60,
        eventStartTime: now,
        seriesStartTime: now,
        totalSeriesElapsedSeconds: 60,
      );

      await tester.pumpWidget(createWidgetUnderTest(state));

      expect(find.widgetWithText(ElevatedButton, 'NEXT'), findsOneWidget);
    });
  });
}
