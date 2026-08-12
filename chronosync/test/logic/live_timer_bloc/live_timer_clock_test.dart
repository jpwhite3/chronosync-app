// HiveList remains experimental in Hive 2.x, but it is required to exercise
// compatibility with the legacy persisted data model.
// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:io';

import 'package:chronosync/core/time/clock.dart';
import 'package:chronosync/data/models/event.dart';
import 'package:chronosync/data/models/series.dart';
import 'package:chronosync/data/repositories/notification_settings_repository.dart';
import 'package:chronosync/data/services/notification_service.dart';
import 'package:chronosync/logic/live_timer_bloc/live_timer_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

class FakeClock implements Clock {
  FakeClock(this.value);

  DateTime value;

  @override
  DateTime now() => value;
}

final class BlockingNotificationService extends NotificationService {
  BlockingNotificationService()
    : super(settingsRepository: NotificationSettingsRepository());

  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  Future<void> onEventComplete(Event event) async {
    if (!started.isCompleted) {
      started.complete();
    }
    await release.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory testDirectory;
  late Box<Event> eventBox;

  setUpAll(() async {
    testDirectory = Directory.systemTemp.createTempSync('chronosync_clock_');
    Hive.init(testDirectory.path);
    Hive.registerAdapter(EventAdapter());
    Hive.registerAdapter(SeriesAdapter());
  });

  setUp(() async {
    eventBox = await Hive.openBox<Event>('clock_events');
  });

  tearDown(() async {
    await eventBox.deleteFromDisk();
  });

  tearDownAll(() async {
    await Hive.close();
    if (testDirectory.existsSync()) {
      testDirectory.deleteSync(recursive: true);
    }
  });

  test(
    'derives timer state from timestamps after a background resume',
    () async {
      final DateTime startTime = DateTime.utc(2026, 7, 27, 9);
      final FakeClock clock = FakeClock(startTime);
      final Event event = Event.fromDuration(
        title: 'Opening remarks',
        duration: const Duration(minutes: 5),
      );
      await eventBox.add(event);
      final Series series = Series(
        title: 'Conference',
        events: HiveList<Event>(eventBox)..add(event),
      );
      final LiveTimerBloc bloc = LiveTimerBloc(
        enableAudio: false,
        clock: clock,
      );

      bloc.add(StartTimer(series));
      await Future<void>.delayed(Duration.zero);

      clock.value = startTime.add(const Duration(minutes: 3, seconds: 15));
      bloc.add(AppResumed(clock.now()));
      await Future<void>.delayed(Duration.zero);

      final LiveTimerRunning state = bloc.state as LiveTimerRunning;
      expect(state.elapsedSeconds, 195);
      expect(state.totalSeriesElapsedSeconds, 195);
      expect(state.remainingSeconds, 105);

      await bloc.close();
    },
  );

  test('a delayed auto-progress cannot overwrite a manual advance', () async {
    final DateTime startTime = DateTime.utc(2026, 7, 27, 9);
    final FakeClock clock = FakeClock(startTime);
    final List<Event> events = <Event>[
      Event(title: 'Opening remarks', durationInSeconds: 1, autoProgress: true),
      Event(title: 'Keynote', durationInSeconds: 300),
    ];
    await eventBox.addAll(events);
    final Series series = Series(
      title: 'Conference',
      events: HiveList<Event>(eventBox)..addAll(events),
    );
    final BlockingNotificationService notifications =
        BlockingNotificationService();
    final LiveTimerBloc bloc = LiveTimerBloc(
      enableAudio: false,
      clock: clock,
      notificationService: notifications,
    );
    try {
      bloc.add(StartTimer(series));
      await bloc.stream.firstWhere((LiveTimerState state) {
        return state is LiveTimerRunning;
      });
      clock.value = startTime.add(const Duration(seconds: 1));
      bloc.add(AutoProgressTriggered());
      await notifications.started.future;

      bloc.add(NextEvent());
      await bloc.stream.firstWhere((LiveTimerState state) {
        return state is LiveTimerRunning && state.currentEventIndex == 1;
      });
      final DateTime manualStart =
          (bloc.state as LiveTimerRunning).eventStartTime;
      clock.value = startTime.add(const Duration(seconds: 10));
      notifications.release.complete();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final LiveTimerRunning current = bloc.state as LiveTimerRunning;
      expect(current.currentEventIndex, 1);
      expect(current.eventStartTime, manualStart);
    } finally {
      if (!notifications.release.isCompleted) {
        notifications.release.complete();
      }
      await bloc.close();
    }
  });
}
