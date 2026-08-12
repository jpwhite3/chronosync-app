import 'package:chronosync/data/database/app_database.dart';
import 'package:chronosync/data/portability/portability_file_service.dart';
import 'package:chronosync/data/repositories/device_identity_repository.dart';
import 'package:chronosync/data/repositories/session_history_repository.dart';
import 'package:chronosync/data/services/live_cue_service.dart';
import 'package:chronosync/domain/plan/plan.dart';
import 'package:chronosync/domain/session/live_session.dart';
import 'package:chronosync/domain/session/session_protocol.dart';
import 'package:chronosync/domain/session/session_transport.dart';
import 'package:chronosync/logic/live_session/live_session_controller.dart';
import 'package:chronosync/presentation/screens/join_session_screen.dart';
import 'package:chronosync/presentation/theme/theme.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late DeviceIdentityRepository identityRepository;
  late LiveCueService cueService;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    identityRepository = DeviceIdentityRepository(database);
    cueService = LiveCueService();
  });

  tearDown(() async {
    await cueService.dispose();
    await database.close();
  });

  testWidgets('display invitations do not request an unused participant name', (
    WidgetTester tester,
  ) async {
    await _pumpJoin(
      tester,
      invitation: _invitation(role: SessionRole.display),
      identityRepository: identityRepository,
      cueService: cueService,
    );

    expect(find.text('Join as Display'), findsOneWidget);
    expect(find.text('Name for this session'), findsNothing);
    expect(find.textContaining('name is stored'), findsNothing);
    expect(
      find.text('Displays join without a name and cannot control the session.'),
      findsOneWidget,
    );
  });

  testWidgets('active participant Back requires disconnect confirmation', (
    WidgetTester tester,
  ) async {
    final _SharedControllers controllers = await _createSharedControllers();
    await _pumpJoinFromLauncher(
      tester,
      invitation: controllers.invitation,
      identityRepository: identityRepository,
      cueService: cueService,
      initialController: controllers.guest,
    );

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Disconnect from session?'), findsOneWidget);
    expect(find.text('Live session'), findsOneWidget);
    await tester.tap(find.text('Stay connected'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Live session'), findsOneWidget);

    await tester.tap(find.byTooltip('Leave live session'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Disconnect from session?'), findsOneWidget);
    await tester.tap(find.text('Disconnect'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Launcher'), findsOneWidget);
    controllers.host.dispose();
  });

  testWidgets('participant People sheet includes the host', (
    WidgetTester tester,
  ) async {
    final _SharedControllers controllers = await _createSharedControllers();
    await _pumpJoin(
      tester,
      invitation: controllers.invitation,
      identityRepository: identityRepository,
      cueService: cueService,
      initialController: controllers.guest,
    );

    await tester.tap(find.byIcon(Icons.group_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Host'), findsOneWidget);
    expect(find.text('Host · session owner'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    controllers.host.dispose();
  });

  testWidgets('join form is overflow-free at 200 percent text scale', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await _pumpJoin(
      tester,
      invitation: _invitation(),
      identityRepository: identityRepository,
      cueService: cueService,
      textScale: 2,
    );

    expect(find.text('Join as Participant'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed post-join activity setup closes the connection', (
    WidgetTester tester,
  ) async {
    final _MemoryHistory history = _MemoryHistory();
    LiveSessionController? pendingController;
    int releaseCount = 0;
    await _pumpJoin(
      tester,
      invitation: _invitation(),
      identityRepository: identityRepository,
      cueService: const _NoopCueDelivery(),
      joinControllerFactory: () async {
        return pendingController = await LiveSessionController.createSolo(
          plan: _plan(),
          identity: const DeviceIdentity(deviceId: 'guest', displayName: 'Sam'),
          historyRepository: history,
        );
      },
      acquireActivity: () async {
        throw StateError('native activity failed after allocation');
      },
      releaseActivity: () async {
        releaseCount += 1;
      },
      authenticationSecretLoader: (String _) async =>
          'a2345678901234567890123456789012',
      settle: false,
    );

    await tester.tap(find.text('Join session'));
    for (
      int index = 0;
      index < 20 &&
          find.textContaining('Could not join the session').evaluate().isEmpty;
      index += 1
    ) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(find.textContaining('Could not join the session'), findsOneWidget);
    expect(pendingController?.connectionState, SessionConnectionState.closed);
    expect(releaseCount, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

Future<void> _pumpJoin(
  WidgetTester tester, {
  required Invitation invitation,
  required DeviceIdentityRepository identityRepository,
  required LiveCueDelivery cueService,
  LiveSessionController? initialController,
  Future<LiveSessionController> Function()? joinControllerFactory,
  Future<void> Function()? acquireActivity,
  Future<void> Function()? releaseActivity,
  Future<String> Function(String sessionId)? authenticationSecretLoader,
  double textScale = 1,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ChronoTheme.light(),
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: JoinSessionScreen(
        invitation: invitation,
        localIdentity: const DeviceIdentity(
          deviceId: 'guest',
          displayName: 'Sam',
        ),
        identityRepository: identityRepository,
        historyRepository: _MemoryHistory(),
        cueService: cueService,
        fileService: const PortabilityFileService(),
        initialController: initialController,
        joinControllerFactory: joinControllerFactory,
        acquireActivity: acquireActivity,
        releaseActivity: releaseActivity,
        authenticationSecretLoader: authenticationSecretLoader,
      ),
    ),
  );
  if (initialController == null && settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Future<void> _pumpJoinFromLauncher(
  WidgetTester tester, {
  required Invitation invitation,
  required DeviceIdentityRepository identityRepository,
  required LiveCueService cueService,
  required LiveSessionController initialController,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ChronoTheme.light(),
      home: Builder(
        builder: (BuildContext context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () {
                Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(
                    builder: (BuildContext context) => JoinSessionScreen(
                      invitation: invitation,
                      localIdentity: const DeviceIdentity(
                        deviceId: 'guest',
                        displayName: 'Sam',
                      ),
                      identityRepository: identityRepository,
                      historyRepository: _MemoryHistory(),
                      cueService: cueService,
                      fileService: const PortabilityFileService(),
                      initialController: initialController,
                    ),
                  ),
                );
              },
              child: const Text('Launcher'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Launcher'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<_SharedControllers> _createSharedControllers() async {
  final Invitation invitation = _invitation();
  final InMemoryTransportHub hub = InMemoryTransportHub();
  final _MemoryHistory history = _MemoryHistory();
  final LiveSessionController host = await LiveSessionController.hostShared(
    plan: _plan(),
    identity: const DeviceIdentity(deviceId: 'host', displayName: 'Alex'),
    invitation: invitation,
    transport: hub.createTransport(deviceId: 'host'),
    historyRepository: history,
    requiresForegroundHosting: false,
  );
  final LiveSessionController guest = await LiveSessionController.joinShared(
    identity: const DeviceIdentity(deviceId: 'guest', displayName: 'Sam'),
    invitation: invitation,
    transport: hub.createTransport(deviceId: 'guest'),
    historyRepository: history,
    deviceAuthenticationSecret: 'a2345678901234567890123456789012',
  );
  for (int attempt = 0; attempt < 100 && !guest.isReady; attempt += 1) {
    await Future<void>.microtask(() {});
  }
  expect(guest.isReady, isTrue);
  return _SharedControllers(host: host, guest: guest, invitation: invitation);
}

Invitation _invitation({SessionRole role = SessionRole.participant}) {
  return Invitation(
    sessionId: 'session-1',
    transport: SessionTransportKind.nearbyLan,
    endpoint: Uri.parse('http://chronosync.local'),
    capability: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    sessionSecret: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    requestedRole: role,
    expiresAt: DateTime.utc(2035),
  );
}

Plan _plan() {
  final DateTime timestamp = DateTime.utc(2026, 1, 1);
  return Plan(
    id: 'plan-1',
    title: 'Opening night',
    defaultCueProfile: CueProfile(),
    steps: <Step>[
      Step(
        id: 'step-1',
        planId: 'plan-1',
        position: 0,
        title: 'Doors open',
        durationSeconds: 300,
      ),
    ],
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

final class _SharedControllers {
  const _SharedControllers({
    required this.host,
    required this.guest,
    required this.invitation,
  });

  final LiveSessionController host;
  final LiveSessionController guest;
  final Invitation invitation;
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

final class _MemoryHistory implements SessionHistoryRepository {
  final Map<String, LiveSession> sessions = <String, LiveSession>{};

  @override
  Future<void> deleteSession(String id) async => sessions.remove(id);

  @override
  Future<LiveSession?> getSession(String id) async => sessions[id];

  @override
  Future<List<LiveSession>> getSessions({int limit = 50}) async =>
      sessions.values.take(limit).toList(growable: false);

  @override
  Future<LiveSession?> prepareStartupRecovery({
    required String hostDeviceId,
  }) async => null;

  @override
  Future<void> saveSession(
    LiveSession session, {
    required String hostDisplayName,
    required SessionRecoveryKind recoveryKind,
  }) async => sessions[session.id] = session;

  @override
  Stream<List<LiveSession>> watchSessions({int limit = 50}) =>
      Stream<List<LiveSession>>.value(
        sessions.values.take(limit).toList(growable: false),
      );
}
