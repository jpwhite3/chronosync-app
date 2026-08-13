import 'package:chronosync/domain/session/live_session.dart';
import 'package:chronosync/presentation/screens/live/live.dart';
import 'package:chronosync/presentation/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('compact lobby exposes invitations and readiness', (
    WidgetTester tester,
  ) async {
    bool? readiness;
    LobbyInvitationViewData? copiedInvitation;
    bool started = false;

    await _pumpLobby(
      tester,
      size: const Size(390, 844),
      data: _lobbyData(isHostReady: false),
      onReadyChanged: (bool value) {
        readiness = value;
      },
      onCopy: (LobbyInvitationViewData value) {
        copiedInvitation = value;
      },
      onStart: () {
        started = true;
      },
    );

    expect(find.text('Session lobby').hitTestable(), findsOneWidget);
    expect(find.text('Event run of show').hitTestable(), findsOneWidget);
    expect(
      find.bySemanticsLabel('QR code for participant invitation'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('QR code for display invitation'),
      findsOneWidget,
    );
    expect(find.text('Start session'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('I’m ready'));
    expect(readiness, isTrue);

    final Finder copyButtonFinder = find.ancestor(
      of: find.text('Copy link').first,
      matching: find.byWidgetPredicate((Widget widget) => widget is TextButton),
    );
    final TextButton copyButton = tester.widget<TextButton>(copyButtonFinder);
    copyButton.onPressed!();
    expect(copiedInvitation?.role, SessionRole.participant);
    expect(started, isFalse);
  });

  testWidgets('singular interval count is announced grammatically', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await _pumpLobby(
      tester,
      size: const Size(390, 844),
      data: _lobbyData(isHostReady: false, stepCount: 1),
    );

    expect(
      find.bySemanticsLabel('Event run of show, 1 interval, 2 connected'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('host can change a connected participant role', (
    WidgetTester tester,
  ) async {
    String? changedDeviceId;
    SessionRole? changedRole;

    await _pumpLobby(
      tester,
      size: const Size(900, 900),
      data: _lobbyData(isHostReady: true),
      onRoleChanged: (String deviceId, SessionRole role) {
        changedDeviceId = deviceId;
        changedRole = role;
      },
    );

    final Finder roleMenu = find.byType(DropdownButton<SessionRole>);
    expect(roleMenu, findsOneWidget);
    final DropdownButton<SessionRole> dropdown = tester
        .widget<DropdownButton<SessionRole>>(roleMenu);
    dropdown.onChanged!(SessionRole.controller);

    expect(changedDeviceId, 'participant-1');
    expect(changedRole, SessionRole.controller);
    expect(tester.takeException(), isNull);
  });

  testWidgets('participant management controls remain accessible', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();

    await _pumpLobby(
      tester,
      size: const Size(900, 900),
      data: _lobbyData(isHostReady: true),
      onRoleChanged: (String _, SessionRole _) {},
      onRemoveParticipant: (String _) {},
    );

    expect(find.bySemanticsLabel(RegExp(r'Role for Avery')), findsOneWidget);
    expect(find.bySemanticsLabel('Remove Avery'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('removing a participant requires explicit confirmation', (
    WidgetTester tester,
  ) async {
    String? removedDeviceId;
    await _pumpLobby(
      tester,
      size: const Size(900, 900),
      data: _lobbyData(isHostReady: true),
      onRoleChanged: (String _, SessionRole _) {},
      onRemoveParticipant: (String deviceId) => removedDeviceId = deviceId,
    );

    final Finder removeButton = find.byIcon(Icons.person_remove_outlined);
    tester
        .widget<IconButton>(
          find.ancestor(of: removeButton, matching: find.byType(IconButton)),
        )
        .onPressed!();
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();

    expect(find.text('Remove Avery?'), findsOneWidget);
    expect(find.textContaining('will lose access'), findsOneWidget);
    expect(removedDeviceId, isNull);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(removedDeviceId, isNull);

    tester
        .widget<IconButton>(
          find.ancestor(of: removeButton, matching: find.byType(IconButton)),
        )
        .onPressed!();
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();

    expect(removedDeviceId, 'participant-1');
  });

  testWidgets('expanded lobby starts only after host readiness', (
    WidgetTester tester,
  ) async {
    bool started = false;
    await _pumpLobby(
      tester,
      size: const Size(1280, 900),
      data: _lobbyData(isHostReady: true),
      onStart: () {
        started = true;
      },
    );

    await tester.tap(find.text('Start session'));
    expect(started, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact readiness actions fit at 200 percent text scale', (
    WidgetTester tester,
  ) async {
    await _pumpLobby(
      tester,
      size: const Size(320, 568),
      data: _lobbyData(isHostReady: false),
      textScale: 2,
      onReadyChanged: (bool _) {},
      onStart: () {},
    );

    expect(find.text('I’m ready'), findsOneWidget);
    expect(find.text('Start session'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpLobby(
  WidgetTester tester, {
  required Size size,
  required LobbyViewData data,
  ValueChanged<bool>? onReadyChanged,
  LobbyInvitationCallback? onCopy,
  LobbyRoleChanged? onRoleChanged,
  ValueChanged<String>? onRemoveParticipant,
  VoidCallback? onStart,
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    MaterialApp(
      theme: ChronoTheme.light(),
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: SessionLobbyScreen(
        data: data,
        onHostReadyChanged: onReadyChanged,
        onCopyInvitation: onCopy,
        onRoleChanged: onRoleChanged,
        onRemoveParticipant: onRemoveParticipant,
        onStart: onStart,
      ),
    ),
  );
  await tester.pump();
}

LobbyViewData _lobbyData({required bool isHostReady, int stepCount = 4}) {
  return LobbyViewData(
    planTitle: 'Event run of show',
    transportLabel: 'Nearby · Offline',
    stepCount: stepCount,
    totalDuration: const Duration(minutes: 45),
    isHostReady: isHostReady,
    sessionCode: 'LIME-482',
    connectionNote: 'Keep this iPhone awake and on the same Wi-Fi network.',
    participantInvitation: const LobbyInvitationViewData(
      label: 'Participant invitation',
      role: SessionRole.participant,
      link: 'https://join.chronosync.test/#participant-secret',
      detail: 'Can view and tap Got it',
    ),
    displayInvitation: const LobbyInvitationViewData(
      label: 'Display invitation',
      role: SessionRole.display,
      link: 'https://join.chronosync.test/#display-secret',
      detail: 'View only',
    ),
    participants: const <LobbyParticipantViewData>[
      LobbyParticipantViewData(
        deviceId: 'host-1',
        displayName: 'Jordan',
        role: SessionRole.host,
        connectionState: ParticipantConnectionState.connected,
        isReady: true,
        isCurrentDevice: true,
      ),
      LobbyParticipantViewData(
        deviceId: 'participant-1',
        displayName: 'Avery',
        role: SessionRole.participant,
        connectionState: ParticipantConnectionState.connected,
        isReady: true,
      ),
    ],
  );
}
