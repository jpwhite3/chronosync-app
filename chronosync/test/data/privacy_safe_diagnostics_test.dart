import 'dart:io';

import 'package:chronosync/core/time/clock.dart';
import 'package:chronosync/data/models/event.dart';
import 'package:chronosync/data/models/global_notification_settings.dart';
import 'package:chronosync/data/models/series.dart';
import 'package:chronosync/data/repositories/device_audio_repository.dart';
import 'package:chronosync/data/repositories/notification_settings_repository.dart';
import 'package:chronosync/data/services/notification_service.dart';
import 'package:chronosync/logic/live_timer_bloc/live_timer_bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

final class _FakeClock implements Clock {
  _FakeClock(this.value);

  DateTime value;

  @override
  DateTime now() => value;
}

final class _StubSettingsRepository extends NotificationSettingsRepository {
  @override
  Future<GlobalNotificationSettings> getGlobalSettings() async {
    return const GlobalNotificationSettings(
      notificationsEnabled: true,
      hapticEnabled: false,
      soundEnabled: false,
    );
  }
}

void main() {
  late DebugPrintCallback originalDebugPrint;
  late List<String> messages;

  setUp(() {
    originalDebugPrint = debugPrint;
    messages = <String>[];
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) {
        messages.add(message);
      }
    };
  });

  tearDown(() {
    debugPrint = originalDebugPrint;
  });

  test(
    'desktop audio diagnostics do not expose a selected file path',
    () async {
      const String sensitivePath = '/private/team/client-secret.aiff';

      await DeviceAudioRepository().previewSound(sensitivePath);

      expect(messages.join('\n'), isNot(contains(sensitivePath)));
    },
  );

  test('notification diagnostics do not expose event titles', () async {
    const String sensitiveTitle = 'Confidential acquisition call';
    final NotificationService service = NotificationService(
      settingsRepository: _StubSettingsRepository(),
    );
    await service.init();

    await service.onEventComplete(
      Event(title: sensitiveTitle, durationInSeconds: 60),
    );

    expect(messages.join('\n'), isNot(contains(sensitiveTitle)));
  });

  test('timer diagnostics do not expose plan or step titles', () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'chronosync_private_timer_',
    );
    Hive.init(directory.path);
    Hive.registerAdapter(EventAdapter());
    Hive.registerAdapter(SeriesAdapter());
    final Box<Event> eventBox = await Hive.openBox<Event>('private_events');
    const String sensitiveStep = 'Unannounced product launch';
    const String sensitivePlan = 'Project Snowcap';
    final Event event = Event(
      title: sensitiveStep,
      durationInSeconds: 1,
      autoProgress: true,
    );
    await eventBox.add(event);
    final Series series = Series(
      title: sensitivePlan,
      events: HiveList<Event>(eventBox)..add(event),
    );
    final DateTime start = DateTime.utc(2026, 8, 11, 12);
    final _FakeClock clock = _FakeClock(start);
    final LiveTimerBloc bloc = LiveTimerBloc(enableAudio: false, clock: clock);
    try {
      bloc.add(StartTimer(series));
      await bloc.stream.firstWhere((LiveTimerState state) {
        return state is LiveTimerRunning;
      });
      clock.value = start.add(const Duration(seconds: 1));
      bloc.add(AutoProgressTriggered());
      await bloc.stream.firstWhere((LiveTimerState state) {
        return state is LiveTimerCompleted;
      });

      final String output = messages.join('\n');
      expect(output, isNot(contains(sensitiveStep)));
      expect(output, isNot(contains(sensitivePlan)));
    } finally {
      await bloc.close();
      await Hive.close();
      await directory.delete(recursive: true);
    }
  });
}
