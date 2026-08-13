import 'package:chronosync/core/time/clock.dart';
import 'package:chronosync/data/portability/portability_file_service.dart';
import 'package:chronosync/data/repositories/device_identity_repository.dart';
import 'package:chronosync/data/repositories/session_history_repository.dart';
import 'package:chronosync/data/services/live_cue_service.dart';
import 'package:chronosync/domain/plan/plan.dart';
import 'package:chronosync/domain/session/live_session.dart';
import 'package:chronosync/domain/session/session_protocol.dart';
import 'package:chronosync/domain/session/session_transport.dart';
import 'package:chronosync/logic/live_session/live_session_controller.dart';
import 'package:chronosync/presentation/screens/session_flow_screen.dart';
import 'package:chronosync/presentation/theme/theme.dart';
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a recovered waiting solo session opens live, not a lobby', (
    WidgetTester tester,
  ) async {
    final DateTime initialTime = DateTime.utc(2026, 8, 11, 14);
    final _MutableClock clock = _MutableClock(initialTime);
    final _MemorySessionHistory history = _MemorySessionHistory();
    const DeviceIdentity identity = DeviceIdentity(
      deviceId: 'host-1',
      displayName: 'Event lead',
    );
    final Plan plan = Plan(
      id: 'plan-1',
      title: 'Event run of show',
      defaultCueProfile: CueProfile(),
      steps: <Step>[
        Step(
          id: 'step-1',
          planId: 'plan-1',
          position: 0,
          title: 'Opening keynote',
          durationSeconds: 120,
        ),
      ],
      createdAt: initialTime.subtract(const Duration(days: 1)),
      updatedAt: initialTime,
    );
    final LiveSessionController original =
        await LiveSessionController.createSolo(
          plan: plan,
          identity: identity,
          historyRepository: history,
          clock: clock,
        );
    final LiveSessionController recovered =
        await LiveSessionController.recoverSolo(
          session: original.session!,
          identity: identity,
          historyRepository: history,
          clock: clock,
        );
    await original.shutdown();
    original.dispose();
    final LiveCueService cueService = LiveCueService();

    await tester.pumpWidget(
      MaterialApp(
        theme: ChronoTheme.light(),
        home: SessionFlowScreen(
          plan: plan,
          identity: identity,
          historyRepository: history,
          cueService: cueService,
          fileService: const PortabilityFileService(),
          initialController: recovered,
          initialTransportLabel: 'Recovered solo session',
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Live session'), findsOneWidget);
    expect(find.text('Session lobby'), findsNothing);
    expect(find.text('Start session'), findsOneWidget);

    await recovered.shutdown();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('finishing the final step requires explicit confirmation', (
    WidgetTester tester,
  ) async {
    final DateTime initialTime = DateTime.utc(2026, 8, 11, 14);
    final _MutableClock clock = _MutableClock(initialTime);
    final _MemorySessionHistory history = _MemorySessionHistory();
    const DeviceIdentity identity = DeviceIdentity(
      deviceId: 'host-1',
      displayName: 'Event lead',
    );
    final Plan plan = Plan(
      id: 'plan-1',
      title: 'Event run of show',
      defaultCueProfile: CueProfile(),
      steps: <Step>[
        Step(
          id: 'step-1',
          planId: 'plan-1',
          position: 0,
          title: 'Opening keynote',
          durationSeconds: 120,
        ),
      ],
      createdAt: initialTime.subtract(const Duration(days: 1)),
      updatedAt: initialTime,
    );
    final LiveSessionController controller =
        await LiveSessionController.createSolo(
          plan: plan,
          identity: identity,
          historyRepository: history,
          clock: clock,
        );
    await controller.start();

    await tester.pumpWidget(
      MaterialApp(
        theme: ChronoTheme.light(),
        home: SessionFlowScreen(
          plan: plan,
          identity: identity,
          historyRepository: history,
          cueService: const _NoopCueDelivery(),
          fileService: const PortabilityFileService(),
          initialController: controller,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Finish session'), findsOneWidget);
    await tester.ensureVisible(find.text('Finish session'));
    await tester.tap(find.text('Finish session'));
    await tester.pumpAndSettle();

    expect(find.text('Finish live session?'), findsOneWidget);
    expect(controller.session?.status, LiveSessionStatus.running);

    await tester.tap(find.text('Keep running'));
    await tester.pumpAndSettle();
    expect(controller.session?.status, LiveSessionStatus.running);

    await tester.ensureVisible(find.text('Finish session'));
    await tester.tap(find.text('Finish session'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Finish session'),
      ),
    );
    for (
      int index = 0;
      index < 10 && controller.session?.status != LiveSessionStatus.ended;
      index += 1
    ) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pump();

    expect(controller.session?.status, LiveSessionStatus.ended);
    expect(controller.session?.endReason, SessionEndReason.completed);
    expect(find.text('Session summary'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('scheduled shared start moves the host out of the lobby', (
    WidgetTester tester,
  ) async {
    final DateTime initialTime = DateTime.utc(2026, 7, 28, 14);
    final _MutableClock clock = _MutableClock(initialTime);
    final _MemorySessionHistory history = _MemorySessionHistory();
    final DeviceIdentity identity = const DeviceIdentity(
      deviceId: 'host-1',
      displayName: 'Event lead',
    );
    final Plan plan = Plan(
      id: 'plan-1',
      title: 'Event run of show',
      plannedStartTime: initialTime.add(const Duration(seconds: 10)),
      defaultCueProfile: CueProfile(),
      steps: <Step>[
        Step(
          id: 'step-1',
          planId: 'plan-1',
          position: 0,
          title: 'Opening keynote',
          durationSeconds: 120,
        ),
      ],
      createdAt: initialTime.subtract(const Duration(days: 1)),
      updatedAt: initialTime,
    );
    final Invitation invitation = Invitation(
      sessionId: 'session-1',
      transport: SessionTransportKind.nearbyLan,
      endpoint: Uri.parse('http://127.0.0.1:8080'),
      capability: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      sessionSecret: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      requestedRole: SessionRole.participant,
      expiresAt: initialTime.add(const Duration(hours: 1)),
    );
    final InMemoryTransport transport = InMemoryTransportHub().createTransport(
      deviceId: identity.deviceId,
      clock: clock,
    );
    final LiveSessionController controller =
        await LiveSessionController.hostShared(
          plan: plan,
          identity: identity,
          invitation: invitation,
          transport: transport,
          historyRepository: history,
          clock: clock,
        );
    final LiveCueService cueService = LiveCueService();

    await tester.pumpWidget(
      MaterialApp(
        theme: ChronoTheme.light(),
        home: SessionFlowScreen(
          plan: plan,
          identity: identity,
          historyRepository: history,
          cueService: cueService,
          fileService: const PortabilityFileService(),
          initialController: controller,
          initialTransportLabel: 'Nearby · Wi-Fi',
        ),
      ),
    );
    expect(find.text('Session lobby'), findsOneWidget);
    expect(find.textContaining('network as everyone else.'), findsOneWidget);

    clock.advance(const Duration(seconds: 11));
    await controller.refresh();
    for (
      int index = 0;
      index < 10 && controller.session?.status == LiveSessionStatus.waiting;
      index += 1
    ) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pump();

    expect(controller.session?.status, LiveSessionStatus.running);
    expect(find.text('Session lobby'), findsNothing);
    expect(find.text('Live session'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('shared lobby Back requires confirmation before ending host', (
    WidgetTester tester,
  ) async {
    final DateTime initialTime = DateTime.utc(2026, 8, 11, 14);
    final _MutableClock clock = _MutableClock(initialTime);
    final _MemorySessionHistory history = _MemorySessionHistory();
    const DeviceIdentity identity = DeviceIdentity(
      deviceId: 'host-1',
      displayName: 'Event lead',
    );
    final Plan plan = Plan(
      id: 'plan-1',
      title: 'Event run of show',
      defaultCueProfile: CueProfile(),
      steps: <Step>[
        Step(
          id: 'step-1',
          planId: 'plan-1',
          position: 0,
          title: 'Opening keynote',
          durationSeconds: 120,
        ),
      ],
      createdAt: initialTime.subtract(const Duration(days: 1)),
      updatedAt: initialTime,
    );
    final Invitation invitation = Invitation(
      sessionId: 'session-1',
      transport: SessionTransportKind.nearbyLan,
      endpoint: Uri.parse('http://127.0.0.1:8080'),
      capability: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      sessionSecret: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      requestedRole: SessionRole.participant,
      expiresAt: initialTime.add(const Duration(hours: 1)),
    );
    final InMemoryTransport transport = InMemoryTransportHub().createTransport(
      deviceId: identity.deviceId,
      clock: clock,
    );
    final LiveSessionController controller =
        await LiveSessionController.hostShared(
          plan: plan,
          identity: identity,
          invitation: invitation,
          transport: transport,
          historyRepository: history,
          clock: clock,
        );

    await tester.pumpWidget(
      MaterialApp(
        theme: ChronoTheme.light(),
        home: SessionFlowScreen(
          plan: plan,
          identity: identity,
          historyRepository: history,
          cueService: const _NoopCueDelivery(),
          fileService: const PortabilityFileService(),
          initialController: controller,
          initialTransportLabel: 'Nearby · Wi-Fi',
        ),
      ),
    );
    await tester.pump();

    tester
        .widget<IconButton>(
          find.ancestor(
            of: find.byTooltip('Back to sequences'),
            matching: find.byType(IconButton),
          ),
        )
        .onPressed!();
    await tester.pumpAndSettle();

    expect(find.text('End shared session?'), findsOneWidget);
    expect(find.text('Session lobby'), findsOneWidget);
    expect(controller.session?.status, LiveSessionStatus.waiting);

    await tester.tap(find.text('Stay'));
    await tester.pumpAndSettle();
    expect(controller.session?.status, LiveSessionStatus.waiting);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('failed post-launch activity setup shuts down the session', (
    WidgetTester tester,
  ) async {
    final DateTime initialTime = DateTime.utc(2026, 8, 11, 14);
    final _MemorySessionHistory history = _MemorySessionHistory();
    const DeviceIdentity identity = DeviceIdentity(
      deviceId: 'host-1',
      displayName: 'Event lead',
    );
    final Plan plan = Plan(
      id: 'plan-1',
      title: 'Event run of show',
      defaultCueProfile: CueProfile(),
      steps: <Step>[
        Step(
          id: 'step-1',
          planId: 'plan-1',
          position: 0,
          title: 'Opening keynote',
          durationSeconds: 120,
        ),
      ],
      createdAt: initialTime.subtract(const Duration(days: 1)),
      updatedAt: initialTime,
    );
    final LiveSessionController pendingController =
        await LiveSessionController.createSolo(
          plan: plan,
          identity: identity,
          historyRepository: history,
          clock: _MutableClock(initialTime),
        );
    int releaseCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: ChronoTheme.light(),
        home: SessionFlowScreen(
          plan: plan,
          identity: identity,
          historyRepository: history,
          cueService: const _NoopCueDelivery(),
          fileService: const PortabilityFileService(),
          soloControllerFactory: () async => pendingController,
          acquireActivity: () async {
            throw StateError('native activity failed after allocation');
          },
          releaseActivity: () async {
            releaseCount += 1;
          },
        ),
      ),
    );

    await tester.tap(find.text('Just me'));
    for (
      int index = 0;
      index < 20 &&
          find
              .text('Could not start the session. Try again.')
              .evaluate()
              .isEmpty;
      index += 1
    ) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(
      find.text('Could not start the session. Try again.'),
      findsOneWidget,
    );
    expect(pendingController.connectionState, SessionConnectionState.closed);
    expect(releaseCount, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

final class _MutableClock implements Clock {
  _MutableClock(this._now);

  DateTime _now;

  @override
  DateTime now() => _now;

  void advance(Duration duration) {
    _now = _now.add(duration);
  }
}

final class _NoopCueDelivery implements LiveCueDelivery {
  const _NoopCueDelivery();

  @override
  Stream<LiveCue> get cues => const Stream<LiveCue>.empty();

  @override
  Future<void> evaluate(LiveSession session, DateTime now) async {}

  @override
  Future<void> unlockAudio() async {}
}

final class _MemorySessionHistory implements SessionHistoryRepository {
  final Map<String, LiveSession> _sessions = <String, LiveSession>{};

  @override
  Future<void> deleteSession(String id) async {
    _sessions.remove(id);
  }

  @override
  Future<LiveSession?> getSession(String id) async => _sessions[id];

  @override
  Future<LiveSession?> prepareStartupRecovery({
    required String hostDeviceId,
  }) async {
    for (final LiveSession session in _sessions.values.toList().reversed) {
      if (session.hostDeviceId == hostDeviceId &&
          session.status != LiveSessionStatus.ended) {
        return session;
      }
    }
    return null;
  }

  @override
  Future<List<LiveSession>> getSessions({int limit = 50}) async {
    return _sessions.values.take(limit).toList(growable: false);
  }

  @override
  Future<void> saveSession(
    LiveSession session, {
    required String hostDisplayName,
    required SessionRecoveryKind recoveryKind,
  }) async {
    _sessions[session.id] = session;
  }

  @override
  Stream<List<LiveSession>> watchSessions({int limit = 50}) {
    return Stream<List<LiveSession>>.value(
      _sessions.values.take(limit).toList(growable: false),
    );
  }
}
