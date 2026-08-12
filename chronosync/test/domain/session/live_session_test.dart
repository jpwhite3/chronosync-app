import 'package:chronosync/domain/session/live_session.dart';
import 'package:chronosync/domain/session/session_command.dart';
import 'package:flutter_test/flutter_test.dart';

import 'session_fixtures.dart';

void main() {
  group('LiveSession models', () {
    test('round-trips a waiting session and participant through JSON', () {
      final Participant participant = createParticipant();
      final LiveSession session = createWaitingSession(
        participants: <Participant>[participant],
      );

      expect(LiveSession.fromJson(session.toJson()), session);
      expect(Participant.fromJson(participant.toJson()), participant);
      expect(session.currentStep.id, 'step-1');
      expect(session.nextStep?.id, 'step-2');
    });

    test('rejects timestamp combinations inconsistent with status', () {
      expect(
        () => LiveSession(
          id: 'session-1',
          planSnapshot: createPlanSnapshot(),
          hostDeviceId: 'host-1',
          status: LiveSessionStatus.running,
        ),
        throwsArgumentError,
      );
    });

    test('persisted session timestamps require an explicit time zone', () {
      final Map<String, Object?> sessionJson = createWaitingSession().toJson();
      final Map<String, Object?> participantJson = createParticipant().toJson()
        ..['joinedAt'] = '2026-07-28T12:00:00';
      final Map<String, Object?> commandJson = SessionCommand.start(
        id: 'start',
        sessionId: 'session-1',
        actorDeviceId: 'host-1',
        actorRole: SessionRole.host,
        baseRevision: 0,
        issuedAt: fixtureStart,
      ).toJson()..['issuedAt'] = '2026-07-28T12:00:00';
      sessionJson['startedAt'] = '2026-07-28T12:00:00';
      sessionJson['currentStepStartedAt'] = '2026-07-28T12:00:00';
      sessionJson['status'] = LiveSessionStatus.running.name;

      expect(
        () => Participant.fromJson(participantJson),
        throwsFormatException,
      );
      expect(() => SessionCommand.fromJson(commandJson), throwsFormatException);
      expect(() => LiveSession.fromJson(sessionJson), throwsFormatException);
    });

    test('pause accounting cannot exceed the corresponding wall time', () {
      expect(
        () => LiveSession(
          id: 'session-1',
          planSnapshot: createPlanSnapshot(),
          hostDeviceId: 'host-1',
          status: LiveSessionStatus.paused,
          startedAt: fixtureStart,
          currentStepStartedAt: fixtureStart.add(const Duration(minutes: 1)),
          pausedAt: fixtureStart.add(const Duration(minutes: 2)),
          currentStepPausedDuration: const Duration(minutes: 2),
          totalPausedDuration: const Duration(minutes: 2),
        ),
        throwsArgumentError,
      );
      expect(
        () => LiveSession(
          id: 'session-1',
          planSnapshot: createPlanSnapshot(),
          hostDeviceId: 'host-1',
          status: LiveSessionStatus.ended,
          startedAt: fixtureStart,
          currentStepStartedAt: fixtureStart,
          endedAt: fixtureStart.add(const Duration(minutes: 1)),
          endReason: SessionEndReason.endedByHost,
          totalPausedDuration: const Duration(minutes: 2),
        ),
        throwsArgumentError,
      );
    });

    test('rejects runtime timestamps that move backwards', () {
      expect(
        () => LiveSession(
          id: 'session-1',
          planSnapshot: createPlanSnapshot(),
          hostDeviceId: 'host-1',
          status: LiveSessionStatus.running,
          startedAt: fixtureStart,
          currentStepStartedAt: fixtureStart.subtract(
            const Duration(seconds: 1),
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => LiveSession(
          id: 'session-1',
          planSnapshot: createPlanSnapshot(),
          hostDeviceId: 'host-1',
          status: LiveSessionStatus.paused,
          startedAt: fixtureStart,
          currentStepStartedAt: fixtureStart,
          pausedAt: fixtureStart.subtract(const Duration(seconds: 1)),
        ),
        throwsArgumentError,
      );
      expect(
        () => LiveSession(
          id: 'session-1',
          planSnapshot: createPlanSnapshot(),
          hostDeviceId: 'host-1',
          status: LiveSessionStatus.ended,
          startedAt: fixtureStart,
          currentStepStartedAt: fixtureStart,
          endedAt: fixtureStart.subtract(const Duration(seconds: 1)),
          endReason: SessionEndReason.endedByHost,
        ),
        throwsArgumentError,
      );

      expect(
        LiveSession(
          id: 'cancelled-in-lobby',
          planSnapshot: createPlanSnapshot(),
          hostDeviceId: 'host-1',
          status: LiveSessionStatus.ended,
          endedAt: fixtureStart,
          endReason: SessionEndReason.endedByHost,
        ).startedAt,
        isNull,
      );
    });

    test('does not allow a participant to claim the host role', () {
      expect(
        () => createWaitingSession(
          participants: <Participant>[
            createParticipant(role: SessionRole.host),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('bounds participant identity fields used by wire snapshots', () {
      final Participant boundary = Participant(
        deviceId: 'd' * maxSessionDeviceIdLength,
        displayName: 'n' * maxParticipantDisplayNameLength,
        role: SessionRole.participant,
        joinedAt: fixtureStart,
      );

      expect(boundary.deviceId, hasLength(maxSessionDeviceIdLength));
      expect(boundary.displayName, hasLength(maxParticipantDisplayNameLength));
      expect(
        () => Participant(
          deviceId: 'd' * (maxSessionDeviceIdLength + 1),
          displayName: 'Sam',
          role: SessionRole.participant,
          joinedAt: fixtureStart,
        ),
        throwsArgumentError,
      );
      expect(
        () => Participant.fromJson(<String, Object?>{
          ...boundary.toJson(),
          'displayName': 'n' * (maxParticipantDisplayNameLength + 1),
        }),
        throwsArgumentError,
      );
    });

    test('bounds retained participant history', () {
      final List<Participant> maximum = List<Participant>.generate(
        maxSessionParticipants,
        (int index) => Participant(
          deviceId: 'participant-$index',
          displayName: 'Person $index',
          role: SessionRole.participant,
          joinedAt: fixtureStart,
          connectionState: ParticipantConnectionState.disconnected,
        ),
      );

      expect(
        createWaitingSession(participants: maximum).participants,
        hasLength(maxSessionParticipants),
      );
      expect(
        () => createWaitingSession(
          participants: <Participant>[
            ...maximum,
            Participant(
              deviceId: 'participant-over-limit',
              displayName: 'One too many',
              role: SessionRole.participant,
              joinedAt: fixtureStart,
            ),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('bounds participants that can be connected or stale', () {
      final List<Participant> maximum = List<Participant>.generate(
        maxConnectedSessionParticipants,
        (int index) => Participant(
          deviceId: 'participant-$index',
          displayName: 'Person $index',
          role: SessionRole.participant,
          joinedAt: fixtureStart,
          connectionState: index.isEven
              ? ParticipantConnectionState.connected
              : ParticipantConnectionState.stale,
        ),
      );

      expect(
        createWaitingSession(participants: maximum).participants,
        hasLength(maxConnectedSessionParticipants),
      );
      expect(
        () => createWaitingSession(
          participants: <Participant>[
            ...maximum,
            Participant(
              deviceId: 'participant-over-connected-limit',
              displayName: 'One too many',
              role: SessionRole.participant,
              joinedAt: fixtureStart,
            ),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('activity payload is deeply immutable and JSON-safe', () {
      final Map<String, Object?> payload = <String, Object?>{
        'nested': <String, Object?>{
          'items': <Object?>['one'],
        },
      };
      final Activity activity = Activity(
        id: 'activity-1',
        commandId: 'command-1',
        sessionId: 'session-1',
        revision: 1,
        type: ActivityType.acknowledged,
        stepIndex: 0,
        stepId: 'step-1',
        actorDeviceId: 'participant-1',
        actorRole: SessionRole.participant,
        occurredAt: fixtureStart,
        payload: payload,
      );

      (payload['nested']! as Map<String, Object?>)['later'] = true;
      final Map<Object?, Object?> nested =
          activity.payload['nested']! as Map<Object?, Object?>;
      final List<Object?> items = nested['items']! as List<Object?>;

      expect(nested, isNot(contains('later')));
      expect(() => items.add('two'), throwsUnsupportedError);
      expect(Activity.fromJson(activity.toJson()), activity);
    });

    test('requires a complete consecutive activity history', () {
      final Activity revisionTwo = Activity(
        id: 'activity-2',
        commandId: 'command-2',
        sessionId: 'session-1',
        revision: 2,
        type: ActivityType.started,
        stepIndex: 0,
        stepId: 'step-1',
        actorDeviceId: 'host-1',
        actorRole: SessionRole.host,
        occurredAt: fixtureStart,
      );

      expect(
        () => LiveSession(
          id: 'session-1',
          planSnapshot: createPlanSnapshot(),
          hostDeviceId: 'host-1',
          revision: 2,
          activities: <Activity>[revisionTwo],
        ),
        throwsArgumentError,
      );
    });

    test('rejects activity references outside the plan snapshot', () {
      Activity activity({required int? stepIndex, required String? stepId}) {
        return Activity(
          id: 'activity-1',
          commandId: 'command-1',
          sessionId: 'session-1',
          revision: 1,
          type: ActivityType.participantJoined,
          stepIndex: stepIndex,
          stepId: stepId,
          actorDeviceId: 'participant-1',
          actorRole: SessionRole.participant,
          occurredAt: fixtureStart,
        );
      }

      for (final Activity invalid in <Activity>[
        activity(stepIndex: 99, stepId: 'missing-step'),
        activity(stepIndex: 0, stepId: 'wrong-step'),
        activity(stepIndex: 0, stepId: null),
      ]) {
        expect(
          () => LiveSession(
            id: 'session-1',
            planSnapshot: createPlanSnapshot(),
            hostDeviceId: 'host-1',
            revision: 1,
            activities: <Activity>[invalid],
          ),
          throwsArgumentError,
        );
      }

      expect(
        LiveSession(
          id: 'session-1',
          planSnapshot: createPlanSnapshot(),
          hostDeviceId: 'host-1',
          revision: 1,
          activities: <Activity>[activity(stepIndex: null, stepId: null)],
        ).revision,
        1,
      );
    });

    test('rejects activity history whose timestamps move backwards', () {
      Activity activity(int revision, DateTime occurredAt) {
        return Activity(
          id: 'activity-$revision',
          commandId: 'command-$revision',
          sessionId: 'session-1',
          revision: revision,
          type: ActivityType.participantJoined,
          stepIndex: 0,
          stepId: 'step-1',
          actorDeviceId: 'participant-$revision',
          actorRole: SessionRole.participant,
          occurredAt: occurredAt,
        );
      }

      expect(
        () => LiveSession(
          id: 'session-1',
          planSnapshot: createPlanSnapshot(),
          hostDeviceId: 'host-1',
          revision: 2,
          activities: <Activity>[
            activity(1, fixtureStart),
            activity(2, fixtureStart.subtract(const Duration(seconds: 1))),
          ],
        ),
        throwsArgumentError,
      );
    });
  });

  group('SessionCommand JSON', () {
    test('round-trips every command shape', () {
      final List<SessionCommand> commands = <SessionCommand>[
        SessionCommand.join(
          id: 'join',
          sessionId: 'session-1',
          actorDeviceId: 'new-1',
          baseRevision: 0,
          issuedAt: fixtureStart,
          displayName: 'Alex',
          requestedRole: SessionRole.participant,
          authenticationSecret: '0123456789abcdef0123456789abcdef',
        ),
        SessionCommand.changeRole(
          id: 'role',
          sessionId: 'session-1',
          actorDeviceId: 'host-1',
          actorRole: SessionRole.host,
          baseRevision: 0,
          issuedAt: fixtureStart,
          targetDeviceId: 'new-1',
          targetRole: SessionRole.controller,
        ),
        SessionCommand.disconnectParticipant(
          id: 'disconnect',
          sessionId: 'session-1',
          actorDeviceId: 'host-1',
          actorRole: SessionRole.host,
          baseRevision: 0,
          issuedAt: fixtureStart,
          targetDeviceId: 'new-1',
        ),
        SessionCommand.start(
          id: 'start',
          sessionId: 'session-1',
          actorDeviceId: 'host-1',
          actorRole: SessionRole.host,
          baseRevision: 0,
          issuedAt: fixtureStart,
        ),
        SessionCommand.pause(
          id: 'pause',
          sessionId: 'session-1',
          actorDeviceId: 'host-1',
          actorRole: SessionRole.host,
          baseRevision: 0,
          issuedAt: fixtureStart,
        ),
        SessionCommand.resume(
          id: 'resume',
          sessionId: 'session-1',
          actorDeviceId: 'host-1',
          actorRole: SessionRole.host,
          baseRevision: 0,
          issuedAt: fixtureStart,
        ),
        SessionCommand.advance(
          id: 'advance',
          sessionId: 'session-1',
          actorDeviceId: 'host-1',
          actorRole: SessionRole.host,
          baseRevision: 0,
          issuedAt: fixtureStart,
          automatically: true,
        ),
        SessionCommand.adjustRemaining(
          id: 'adjust',
          sessionId: 'session-1',
          actorDeviceId: 'host-1',
          actorRole: SessionRole.host,
          baseRevision: 0,
          issuedAt: fixtureStart,
          adjustmentSeconds: -60,
        ),
        SessionCommand.jump(
          id: 'jump',
          sessionId: 'session-1',
          actorDeviceId: 'host-1',
          actorRole: SessionRole.host,
          baseRevision: 0,
          issuedAt: fixtureStart,
          targetStepIndex: 2,
          confirmed: true,
        ),
        SessionCommand.acknowledge(
          id: 'ack',
          sessionId: 'session-1',
          actorDeviceId: 'participant-1',
          actorRole: SessionRole.participant,
          baseRevision: 0,
          issuedAt: fixtureStart,
          stepIndex: 0,
        ),
        SessionCommand.end(
          id: 'end',
          sessionId: 'session-1',
          actorDeviceId: 'host-1',
          actorRole: SessionRole.host,
          baseRevision: 0,
          issuedAt: fixtureStart,
          confirmed: true,
        ),
      ];

      for (final SessionCommand command in commands) {
        expect(
          SessionCommand.fromJson(command.toJson()),
          command,
          reason: command.type.name,
        );
      }
    });

    test('public join rejects Controller and Host roles', () {
      for (final SessionRole role in <SessionRole>[
        SessionRole.controller,
        SessionRole.host,
      ]) {
        expect(
          () => SessionCommand.join(
            id: 'join',
            sessionId: 'session-1',
            actorDeviceId: 'new-1',
            baseRevision: 0,
            issuedAt: fixtureStart,
            displayName: 'Alex',
            requestedRole: role,
            authenticationSecret: '0123456789abcdef0123456789abcdef',
          ),
          throwsArgumentError,
        );
      }
    });

    test('join commands enforce snapshot-safe participant identity limits', () {
      SessionCommand command({required String deviceId, required String name}) {
        return SessionCommand.join(
          id: 'join',
          sessionId: 'session-1',
          actorDeviceId: deviceId,
          baseRevision: 0,
          issuedAt: fixtureStart,
          displayName: name,
          requestedRole: SessionRole.participant,
          authenticationSecret: 'a' * 32,
        );
      }

      expect(
        command(
          deviceId: 'd' * maxSessionDeviceIdLength,
          name: 'n' * maxParticipantDisplayNameLength,
        ).displayName,
        hasLength(maxParticipantDisplayNameLength),
      );
      expect(
        () => command(
          deviceId: 'd' * (maxSessionDeviceIdLength + 1),
          name: 'Sam',
        ),
        throwsArgumentError,
      );
      expect(
        () => command(
          deviceId: 'guest',
          name: 'n' * (maxParticipantDisplayNameLength + 1),
        ),
        throwsArgumentError,
      );
    });
  });
}
