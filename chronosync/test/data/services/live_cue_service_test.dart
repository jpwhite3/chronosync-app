import 'dart:async';

import 'package:chronosync/data/services/live_cue_service.dart';
import 'package:chronosync/domain/plan/plan.dart';
import 'package:chronosync/domain/session/live_session.dart';
import 'package:chronosync/domain/session/session_command.dart';
import 'package:chronosync/domain/session/session_reducer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

import '../../domain/session/session_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'does not deliver the approaching cue before the exact boundary',
    () async {
      final LiveCueService service = LiveCueService();
      final List<LiveCue> cues = <LiveCue>[];
      final StreamSubscription<LiveCue> subscription = service.cues.listen(
        cues.add,
      );
      final LiveSession session = _runningSession();

      await service.evaluate(
        session,
        fixtureStart.add(const Duration(milliseconds: 239100)),
      );
      await Future<void>.delayed(Duration.zero);

      expect(cues, isEmpty);

      await service.evaluate(
        session,
        fixtureStart.add(const Duration(minutes: 4)),
      );
      await Future<void>.delayed(Duration.zero);

      expect(cues.single.kind, LiveCueKind.approaching);

      await subscription.cancel();
      await service.dispose();
    },
  );

  test('delivers enabled visual, sound, and haptic channels once', () async {
    final _RecordingAudioPlayer audio = _RecordingAudioPlayer();
    final _RecordingHaptics haptics = _RecordingHaptics();
    final LiveCueService service = LiveCueService(
      audioPlayer: audio,
      haptics: haptics,
    );
    final List<LiveCue> cues = <LiveCue>[];
    final StreamSubscription<LiveCue> subscription = service.cues.listen(
      cues.add,
    );
    await service.unlockAudio();
    final LiveSession session = _runningSession();

    await service.evaluate(
      session,
      fixtureStart.add(const Duration(minutes: 4)),
    );
    await service.evaluate(
      session,
      fixtureStart.add(const Duration(minutes: 4)),
    );
    await Future<void>.delayed(Duration.zero);

    expect(cues, hasLength(1));
    expect(audio.playCalls, 1);
    expect(haptics.kinds, <LiveCueKind>[LiveCueKind.approaching]);

    await subscription.cancel();
    await service.dispose();
  });

  test('respects disabled channels', () async {
    final _RecordingAudioPlayer audio = _RecordingAudioPlayer();
    final _RecordingHaptics haptics = _RecordingHaptics();
    final LiveCueService service = LiveCueService(
      audioPlayer: audio,
      haptics: haptics,
    );
    final List<LiveCue> cues = <LiveCue>[];
    final StreamSubscription<LiveCue> subscription = service.cues.listen(
      cues.add,
    );
    await service.unlockAudio();

    await service.evaluate(
      _runningSession(
        cueProfile: CueProfile(
          visualEnabled: false,
          soundEnabled: false,
          hapticEnabled: false,
        ),
      ),
      fixtureStart.add(const Duration(minutes: 4)),
    );
    await Future<void>.delayed(Duration.zero);

    expect(cues, isEmpty);
    expect(audio.playCalls, 0);
    expect(haptics.kinds, isEmpty);

    await subscription.cancel();
    await service.dispose();
  });

  test('isolates channel failures from the remaining cue delivery', () async {
    final _RecordingAudioPlayer audio = _RecordingAudioPlayer(failPlay: true);
    final _RecordingHaptics haptics = _RecordingHaptics(fail: true);
    final LiveCueService service = LiveCueService(
      audioPlayer: audio,
      haptics: haptics,
    );
    final List<LiveCue> cues = <LiveCue>[];
    final StreamSubscription<LiveCue> subscription = service.cues.listen(
      cues.add,
    );
    await service.unlockAudio();

    await expectLater(
      service.evaluate(
        _runningSession(),
        fixtureStart.add(const Duration(minutes: 4)),
      ),
      completes,
    );
    await Future<void>.delayed(Duration.zero);

    expect(cues, hasLength(1));
    expect(audio.playCalls, 1);
    expect(haptics.kinds, <LiveCueKind>[LiveCueKind.approaching]);

    await subscription.cancel();
    await service.dispose();
  });

  test('delivers approaching cue again when a step is revisited', () async {
    final LiveCueService service = LiveCueService();
    final List<LiveCue> cues = <LiveCue>[];
    final StreamSubscription<LiveCue> subscription = service.cues.listen(
      cues.add,
    );
    LiveSession session = createWaitingSession();
    session = SessionReducer.applyCommand(
      session: session,
      command: SessionCommand.start(
        id: 'start',
        sessionId: session.id,
        actorDeviceId: session.hostDeviceId,
        actorRole: SessionRole.host,
        baseRevision: session.revision,
        issuedAt: fixtureStart,
      ),
      occurredAt: fixtureStart,
    ).session;
    await service.evaluate(
      session,
      fixtureStart.add(const Duration(minutes: 4)),
    );

    session = SessionReducer.applyCommand(
      session: session,
      command: SessionCommand.advance(
        id: 'advance',
        sessionId: session.id,
        actorDeviceId: session.hostDeviceId,
        actorRole: SessionRole.host,
        baseRevision: session.revision,
        issuedAt: fixtureStart.add(const Duration(minutes: 4)),
      ),
      occurredAt: fixtureStart.add(const Duration(minutes: 4)),
    ).session;
    session = SessionReducer.applyCommand(
      session: session,
      command: SessionCommand.jump(
        id: 'jump-back',
        sessionId: session.id,
        actorDeviceId: session.hostDeviceId,
        actorRole: SessionRole.host,
        baseRevision: session.revision,
        issuedAt: fixtureStart.add(const Duration(minutes: 5)),
        targetStepIndex: 0,
        confirmed: true,
      ),
      occurredAt: fixtureStart.add(const Duration(minutes: 5)),
    ).session;
    await service.evaluate(
      session,
      fixtureStart.add(const Duration(minutes: 9)),
    );

    expect(
      cues.where((LiveCue cue) => cue.kind == LiveCueKind.approaching),
      hasLength(2),
    );

    await subscription.cancel();
    await service.dispose();
  });
}

LiveSession _runningSession({CueProfile? cueProfile}) {
  final PlanSnapshot snapshot = createPlanSnapshot();
  LiveSession session = LiveSession(
    id: 'cue-session',
    planSnapshot: PlanSnapshot(
      sourcePlanId: snapshot.sourcePlanId,
      title: snapshot.title,
      defaultCueProfile: cueProfile ?? snapshot.defaultCueProfile,
      steps: snapshot.steps,
      capturedAt: snapshot.capturedAt,
    ),
    hostDeviceId: 'host-1',
  );
  session = SessionReducer.applyCommand(
    session: session,
    command: SessionCommand.start(
      id: 'start-cue-session',
      sessionId: session.id,
      actorDeviceId: session.hostDeviceId,
      actorRole: SessionRole.host,
      baseRevision: session.revision,
      issuedAt: fixtureStart,
    ),
    occurredAt: fixtureStart,
  ).session;
  return session;
}

final class _RecordingAudioPlayer extends Fake implements AudioPlayer {
  _RecordingAudioPlayer({this.failPlay = false});

  final bool failPlay;
  int playCalls = 0;

  @override
  Future<void> dispose() async {}

  @override
  Future<void> play() async {
    playCalls += 1;
    if (failPlay) {
      throw StateError('audio failed');
    }
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {}

  @override
  Future<Duration?> setAsset(
    String assetPath, {
    String? package,
    bool preload = true,
    Duration? initialPosition,
    dynamic tag,
  }) async => Duration.zero;
}

final class _RecordingHaptics implements LiveCueHaptics {
  _RecordingHaptics({this.fail = false});

  final bool fail;
  final List<LiveCueKind> kinds = <LiveCueKind>[];

  @override
  Future<void> deliver(LiveCueKind kind) async {
    kinds.add(kind);
    if (fail) {
      throw StateError('haptics failed');
    }
  }
}
