import 'package:chronosync/domain/session/live_session.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/nearby_client/session_presentation.dart';
import '../../domain/session/session_fixtures.dart';

void main() {
  group('fragmentFreeNearbyUrl', () {
    test('removes only the invitation fragment from the browser URL', () {
      expect(
        fragmentFreeNearbyUrl(
          Uri.parse('http://192.168.1.4:8080/join?display=1#secret-invite'),
        ).toString(),
        'http://192.168.1.4:8080/join?display=1',
      );
    });
  });

  group('normalizeNearbyDisplayName', () {
    test('trims and caps names at the domain limit', () {
      final String longName = List<String>.filled(50, 'x').join();
      final String maximumName = List<String>.filled(
        maxParticipantDisplayNameLength,
        'x',
      ).join();
      expect(normalizeNearbyDisplayName('  Stage manager  '), 'Stage manager');
      expect(normalizeNearbyDisplayName(longName), maximumName);
      expect(normalizeNearbyDisplayName('   '), isNull);
    });

    test('does not split a multi-code-unit character at the limit', () {
      final String prefix = List<String>.filled(47, 'x').join();
      final String normalized = normalizeNearbyDisplayName('$prefix😀')!;

      expect(normalized, prefix);
      expect(
        normalized.length,
        lessThanOrEqualTo(maxParticipantDisplayNameLength),
      );
    });
  });

  group('decideNearbyStoredIdentity', () {
    test('preserves a valid global device ID when session auth is missing', () {
      final NearbyStoredIdentityDecision decision = decideNearbyStoredIdentity(
        storedDeviceId: '37c7bc6a-668e-46f4-842f-326d4fd68dd3',
        storedAuthenticationSecret: null,
      );

      expect(decision.deviceId, '37c7bc6a-668e-46f4-842f-326d4fd68dd3');
      expect(decision.authenticationSecret, isNull);
      expect(decision.needsDeviceId, isFalse);
      expect(decision.needsAuthenticationSecret, isTrue);
    });

    test('repairs invalid values independently', () {
      final NearbyStoredIdentityDecision decision = decideNearbyStoredIdentity(
        storedDeviceId: 'not-a-device-id',
        storedAuthenticationSecret: 'abcdefghijklmnopqrstuvwxyz123456',
      );

      expect(decision.deviceId, isNull);
      expect(decision.authenticationSecret, 'abcdefghijklmnopqrstuvwxyz123456');
      expect(decision.needsDeviceId, isTrue);
      expect(decision.needsAuthenticationSecret, isFalse);
    });

    test(
      'reuses one device ID and each session secret across A to B to A',
      () async {
        final Map<String, String> storage = <String, String>{};
        int generatedDeviceIds = 0;
        int generatedSecrets = 0;
        const String deviceId = '37c7bc6a-668e-46f4-842f-326d4fd68dd3';
        const List<String> secrets = <String>[
          'abcdefghijklmnopqrstuvwxyz123456',
          'ABCDEFGHIJKLMNOPQRSTUVWXYZ123456',
        ];

        Future<NearbyResolvedIdentity> restore(String sessionId) {
          return restoreOrCreateNearbyIdentity(
            sessionId: sessionId,
            read: (String key) => storage[key],
            write: (String key, String value) => storage[key] = value,
            createDeviceId: () {
              generatedDeviceIds += 1;
              return deviceId;
            },
            createAuthenticationSecret: () async {
              final String secret = secrets[generatedSecrets];
              generatedSecrets += 1;
              return secret;
            },
          );
        }

        final NearbyResolvedIdentity firstA = await restore('session-a');
        final NearbyResolvedIdentity firstB = await restore('session-b');
        final NearbyResolvedIdentity secondA = await restore('session-a');

        expect(firstA.deviceId, deviceId);
        expect(firstB.deviceId, deviceId);
        expect(secondA.deviceId, deviceId);
        expect(firstA.authenticationSecret, secrets[0]);
        expect(firstB.authenticationSecret, secrets[1]);
        expect(secondA.authenticationSecret, secrets[0]);
        expect(generatedDeviceIds, 1);
        expect(generatedSecrets, 2);
        expect(storage, <String, String>{
          nearbyDeviceIdStorageKey: deviceId,
          nearbyAuthenticationStorageKey('session-a'): secrets[0],
          nearbyAuthenticationStorageKey('session-b'): secrets[1],
        });
      },
    );
  });

  group('NearbySessionPresentation', () {
    test('derives current, next, elapsed, and remaining from timestamps', () {
      final LiveSession session = LiveSession(
        id: 'session-1',
        planSnapshot: createPlanSnapshot(),
        hostDeviceId: 'host-1',
        status: LiveSessionStatus.running,
        startedAt: fixtureStart,
        currentStepStartedAt: fixtureStart,
      );

      final NearbySessionPresentation view =
          NearbySessionPresentation.fromSession(
            session: session,
            now: fixtureStart.add(const Duration(seconds: 90)),
            deviceId: 'participant-1',
            canSendCommands: true,
            invitedRole: SessionRole.participant,
          );

      expect(view.planTitle, 'Live show');
      expect(view.currentStepTitle, 'Doors');
      expect(view.nextStepTitle, 'Welcome');
      expect(view.stepPositionLabel, 'Step 1 of 3');
      expect(view.statusLabel, 'Live');
      expect(view.elapsedLabel, '01:30');
      expect(view.remainingLabel, '03:30');
      expect(view.progress, closeTo(.3, .001));
    });

    test('uses explicit overtime status and a positive overtime clock', () {
      final LiveSession session = LiveSession(
        id: 'session-1',
        planSnapshot: createPlanSnapshot(),
        hostDeviceId: 'host-1',
        status: LiveSessionStatus.running,
        startedAt: fixtureStart,
        currentStepStartedAt: fixtureStart,
      );

      final NearbySessionPresentation view =
          NearbySessionPresentation.fromSession(
            session: session,
            now: fixtureStart.add(const Duration(seconds: 330)),
            deviceId: 'participant-1',
            canSendCommands: true,
            invitedRole: SessionRole.participant,
          );

      expect(view.statusLabel, 'Overtime');
      expect(view.remainingLabel, '+00:30');
      expect(view.isOvertime, isTrue);
      expect(view.progress, 1);
    });

    test('keeps a positive fractional second visible in the countdown', () {
      final LiveSession session = LiveSession(
        id: 'session-1',
        planSnapshot: createPlanSnapshot(),
        hostDeviceId: 'host-1',
        status: LiveSessionStatus.running,
        startedAt: fixtureStart,
        currentStepStartedAt: fixtureStart,
      );

      final NearbySessionPresentation view =
          NearbySessionPresentation.fromSession(
            session: session,
            now: fixtureStart.add(
              const Duration(minutes: 4, seconds: 59, milliseconds: 100),
            ),
            deviceId: 'participant-1',
            canSendCommands: true,
            invitedRole: SessionRole.participant,
          );

      expect(view.statusLabel, 'Live');
      expect(view.remainingLabel, '00:01');
    });

    test('recognizes when a timer tick would not change the DOM', () {
      final LiveSession session = LiveSession(
        id: 'session-1',
        planSnapshot: createPlanSnapshot(),
        hostDeviceId: 'host-1',
        status: LiveSessionStatus.running,
        startedAt: fixtureStart,
        currentStepStartedAt: fixtureStart,
      );
      NearbySessionPresentation at(Duration elapsed) {
        return NearbySessionPresentation.fromSession(
          session: session,
          now: fixtureStart.add(elapsed),
          deviceId: 'participant-1',
          canSendCommands: true,
          invitedRole: SessionRole.participant,
        );
      }

      expect(
        at(
          const Duration(milliseconds: 1),
        ).hasSameDomState(at(const Duration(milliseconds: 10))),
        isTrue,
      );
      expect(
        at(
          const Duration(milliseconds: 1),
        ).hasSameDomState(at(const Duration(seconds: 1))),
        isFalse,
      );
    });

    test('reflects the current participant acknowledgement', () {
      final Participant participant = createParticipant().copyWith(
        acknowledgedStepIndex: 0,
        acknowledgedAt: fixtureStart,
      );
      final LiveSession session = LiveSession(
        id: 'session-1',
        planSnapshot: createPlanSnapshot(),
        hostDeviceId: 'host-1',
        participants: <Participant>[participant],
      );

      final NearbySessionPresentation view =
          NearbySessionPresentation.fromSession(
            session: session,
            now: fixtureStart,
            deviceId: participant.deviceId,
            canSendCommands: true,
            invitedRole: SessionRole.participant,
          );

      expect(view.hasAcknowledged, isTrue);
      expect(view.canAcknowledge, isFalse);
    });

    test('ignores an acknowledgement from an earlier step', () {
      final Participant participant = createParticipant().copyWith(
        acknowledgedStepIndex: 0,
        acknowledgedAt: fixtureStart,
      );
      final DateTime secondStepStartedAt = fixtureStart.add(
        const Duration(minutes: 5),
      );
      final LiveSession session = LiveSession(
        id: 'session-1',
        planSnapshot: createPlanSnapshot(),
        hostDeviceId: 'host-1',
        status: LiveSessionStatus.running,
        currentStepIndex: 1,
        startedAt: fixtureStart,
        currentStepStartedAt: secondStepStartedAt,
        participants: <Participant>[participant],
      );

      final NearbySessionPresentation view =
          NearbySessionPresentation.fromSession(
            session: session,
            now: secondStepStartedAt,
            deviceId: participant.deviceId,
            canSendCommands: true,
            invitedRole: SessionRole.participant,
          );

      expect(view.hasAcknowledged, isFalse);
      expect(view.canAcknowledge, isTrue);
    });

    test('uses the current role after a participant is promoted', () {
      final Participant controller = createParticipant(
        role: SessionRole.controller,
      );
      final LiveSession session = LiveSession(
        id: 'session-1',
        planSnapshot: createPlanSnapshot(),
        hostDeviceId: 'host-1',
        status: LiveSessionStatus.running,
        startedAt: fixtureStart,
        currentStepStartedAt: fixtureStart,
        participants: <Participant>[controller],
      );

      final NearbySessionPresentation view =
          NearbySessionPresentation.fromSession(
            session: session,
            now: fixtureStart,
            deviceId: controller.deviceId,
            canSendCommands: true,
            invitedRole: SessionRole.participant,
          );

      expect(view.role, SessionRole.controller);
      expect(view.roleLabel, 'Controller');
      expect(view.showsActionPanel, isTrue);
      expect(view.showsControllerControls, isTrue);
      expect(view.canPauseResume, isTrue);
      expect(view.pauseResumeLabel, 'Pause');
      expect(view.canAdvance, isTrue);
      expect(view.canSubtractMinute, isTrue);
      expect(view.canAddMinute, isTrue);
      expect(view.showsAcknowledgementControl, isTrue);
    });

    test('removes all actions after a participant becomes a display', () {
      final Participant display = createParticipant(role: SessionRole.display);
      final LiveSession session = LiveSession(
        id: 'session-1',
        planSnapshot: createPlanSnapshot(),
        hostDeviceId: 'host-1',
        status: LiveSessionStatus.running,
        startedAt: fixtureStart,
        currentStepStartedAt: fixtureStart,
        participants: <Participant>[display],
      );

      final NearbySessionPresentation view =
          NearbySessionPresentation.fromSession(
            session: session,
            now: fixtureStart,
            deviceId: display.deviceId,
            canSendCommands: true,
            invitedRole: SessionRole.participant,
          );

      expect(view.role, SessionRole.display);
      expect(view.roleLabel, 'Display');
      expect(view.showsActionPanel, isFalse);
      expect(view.showsControllerControls, isFalse);
      expect(view.showsAcknowledgementControl, isFalse);
      expect(view.canAcknowledge, isFalse);
      expect(view.canPauseResume, isFalse);
      expect(view.canAdvance, isFalse);
      expect(view.canSubtractMinute, isFalse);
      expect(view.canAddMinute, isFalse);
    });

    test('offers resume but not advance to a paused Controller', () {
      final Participant controller = createParticipant(
        role: SessionRole.controller,
      );
      final DateTime pausedAt = fixtureStart.add(const Duration(minutes: 1));
      final LiveSession session = LiveSession(
        id: 'session-1',
        planSnapshot: createPlanSnapshot(),
        hostDeviceId: 'host-1',
        status: LiveSessionStatus.paused,
        startedAt: fixtureStart,
        currentStepStartedAt: fixtureStart,
        pausedAt: pausedAt,
        participants: <Participant>[controller],
      );

      final NearbySessionPresentation view =
          NearbySessionPresentation.fromSession(
            session: session,
            now: pausedAt,
            deviceId: controller.deviceId,
            canSendCommands: true,
            invitedRole: SessionRole.participant,
          );

      expect(view.pauseResumeLabel, 'Resume');
      expect(view.canPauseResume, isTrue);
      expect(view.canAdvance, isFalse);
      expect(view.canSubtractMinute, isTrue);
      expect(view.canAddMinute, isTrue);
    });

    test('does not enable acknowledgement before the session starts', () {
      final Participant participant = createParticipant();
      final LiveSession session = createWaitingSession(
        participants: <Participant>[participant],
      );

      final NearbySessionPresentation view =
          NearbySessionPresentation.fromSession(
            session: session,
            now: fixtureStart,
            deviceId: participant.deviceId,
            canSendCommands: true,
            invitedRole: SessionRole.participant,
          );

      expect(view.canAcknowledge, isFalse);
    });
  });

  group('nearby step announcements', () {
    test(
      'announces the initial step and meaningful step or status changes',
      () {
        final LiveSession waiting = LiveSession(
          id: 'session-1',
          planSnapshot: createPlanSnapshot(),
          hostDeviceId: 'host-1',
        );
        final NearbySessionPresentation initial =
            NearbySessionPresentation.fromSession(
              session: waiting,
              now: fixtureStart,
              deviceId: 'participant-1',
              canSendCommands: false,
              invitedRole: SessionRole.participant,
            );
        final NearbySessionPresentation running =
            NearbySessionPresentation.fromSession(
              session: waiting.copyWith(
                status: LiveSessionStatus.running,
                startedAt: fixtureStart,
                currentStepStartedAt: fixtureStart,
              ),
              now: fixtureStart,
              deviceId: 'participant-1',
              canSendCommands: false,
              invitedRole: SessionRole.participant,
            );

        expect(shouldAnnounceNearbyStep(null, initial), isTrue);
        expect(shouldAnnounceNearbyStep(initial, running), isTrue);
        expect(nearbyStepAnnouncement(running), 'Live. Step 1 of 3: Doors.');
      },
    );

    test('does not announce timer-only updates', () {
      final LiveSession session = LiveSession(
        id: 'session-1',
        planSnapshot: createPlanSnapshot(),
        hostDeviceId: 'host-1',
        status: LiveSessionStatus.running,
        startedAt: fixtureStart,
        currentStepStartedAt: fixtureStart,
      );
      final NearbySessionPresentation first =
          NearbySessionPresentation.fromSession(
            session: session,
            now: fixtureStart,
            deviceId: 'participant-1',
            canSendCommands: false,
            invitedRole: SessionRole.participant,
          );
      final NearbySessionPresentation nextSecond =
          NearbySessionPresentation.fromSession(
            session: session,
            now: fixtureStart.add(const Duration(seconds: 1)),
            deviceId: 'participant-1',
            canSendCommands: false,
            invitedRole: SessionRole.participant,
          );

      expect(shouldAnnounceNearbyStep(first, nextSecond), isFalse);
    });
  });

  group('decideNearbyJoinOnSnapshot', () {
    test('retries when a newer snapshot still omits the joining device', () {
      expect(
        decideNearbyJoinOnSnapshot(
          joinSent: true,
          joinConfirmed: false,
          joinBaseRevision: 8,
          incomingRevision: 9,
          participantConnected: false,
        ),
        NearbyJoinSnapshotAction.retry,
      );
      expect(
        decideNearbyJoinOnSnapshot(
          joinSent: true,
          joinConfirmed: false,
          joinBaseRevision: 8,
          incomingRevision: 9,
          participantConnected: true,
        ),
        NearbyJoinSnapshotAction.retry,
      );
    });

    test('waits at the submitted revision and confirms connected presence', () {
      expect(
        decideNearbyJoinOnSnapshot(
          joinSent: true,
          joinConfirmed: false,
          joinBaseRevision: 8,
          incomingRevision: 8,
          participantConnected: false,
        ),
        NearbyJoinSnapshotAction.wait,
      );
      expect(
        decideNearbyJoinOnSnapshot(
          joinSent: false,
          joinConfirmed: false,
          joinBaseRevision: null,
          incomingRevision: 12,
          participantConnected: true,
        ),
        NearbyJoinSnapshotAction.send,
      );
      expect(
        decideNearbyJoinOnSnapshot(
          joinSent: true,
          joinConfirmed: false,
          joinBaseRevision: 12,
          incomingRevision: 12,
          participantConnected: true,
        ),
        NearbyJoinSnapshotAction.confirm,
      );
    });

    test('does not confirm a retained disconnected participant', () {
      expect(
        decideNearbyJoinOnSnapshot(
          joinSent: false,
          joinConfirmed: false,
          joinBaseRevision: null,
          incomingRevision: 12,
          participantConnected: false,
        ),
        NearbyJoinSnapshotAction.send,
      );
    });
  });

  test('formatClockDuration supports sessions longer than one hour', () {
    expect(
      formatClockDuration(const Duration(hours: 8, minutes: 2, seconds: 9)),
      '08:02:09',
    );
  });

  test('authenticated host time corrects a skewed browser clock', () {
    final DateTime localReceipt = DateTime.utc(2026, 7, 28, 19, 7);
    final DateTime hostSentAt = DateTime.utc(2026, 7, 28, 19, 2);
    final Duration offset = calculateHostClockOffset(
      localReceivedAt: localReceipt,
      authenticatedHostSentAt: hostSentAt,
    );

    expect(offset, const Duration(minutes: -5));
    expect(
      applyHostClockOffset(
        localReceipt.add(const Duration(seconds: 30)),
        offset,
      ),
      hostSentAt.add(const Duration(seconds: 30)),
    );
  });

  test('accepts only high-entropy base64url device secrets', () {
    expect(
      isValidDeviceAuthenticationSecret('0123456789abcdef0123456789abcdef'),
      isTrue,
    );
    expect(isValidDeviceAuthenticationSecret('too-short'), isFalse);
    expect(
      isValidDeviceAuthenticationSecret('0123456789abcdef0123456789abcde='),
      isFalse,
    );
  });
}
