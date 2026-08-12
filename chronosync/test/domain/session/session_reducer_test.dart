import 'package:chronosync/domain/plan/plan.dart';
import 'package:chronosync/domain/session/live_session.dart';
import 'package:chronosync/domain/session/session_command.dart';
import 'package:chronosync/domain/session/session_reducer.dart';
import 'package:flutter_test/flutter_test.dart';

import 'session_fixtures.dart';

void main() {
  Matcher commandError(SessionCommandError error) {
    return isA<SessionCommandException>().having(
      (SessionCommandException exception) => exception.code,
      'code',
      error,
    );
  }

  SessionCommand hostStart(LiveSession session, {String id = 'start'}) {
    return SessionCommand.start(
      id: id,
      sessionId: session.id,
      actorDeviceId: session.hostDeviceId,
      actorRole: SessionRole.host,
      baseRevision: session.revision,
      issuedAt: fixtureStart,
    );
  }

  LiveSession start(LiveSession session) {
    return SessionReducer.applyCommand(
      session: session,
      command: hostStart(session),
      occurredAt: fixtureStart,
    ).session;
  }

  group('participant lifecycle and authorization', () {
    test('unknown participant joins and retry is idempotent', () {
      final LiveSession waiting = createWaitingSession();
      final SessionCommand command = SessionCommand.join(
        id: 'join-1',
        sessionId: waiting.id,
        actorDeviceId: 'new-1',
        baseRevision: 0,
        issuedAt: fixtureStart,
        displayName: '  Alex  ',
        requestedRole: SessionRole.participant,
        authenticationSecret: '0123456789abcdef0123456789abcdef',
      );

      final SessionTransition joined = SessionReducer.applyCommand(
        session: waiting,
        command: command,
        occurredAt: fixtureStart,
      );
      final SessionTransition retried = SessionReducer.applyCommand(
        session: joined.session,
        command: command,
        occurredAt: fixtureStart.add(const Duration(seconds: 1)),
      );

      expect(joined.activity?.type, ActivityType.participantJoined);
      expect(joined.session.revision, 1);
      expect(joined.session.participants.single.displayName, 'Alex');
      expect(joined.session.participants.single.role, SessionRole.participant);
      expect(retried.wasDuplicate, isTrue);
      expect(retried.activity, isNull);
      expect(identical(retried.session, joined.session), isTrue);
    });

    test('known participant cannot join again with a new command ID', () {
      final LiveSession waiting = createWaitingSession(
        participants: <Participant>[createParticipant()],
      );
      final SessionCommand command = SessionCommand.join(
        id: 'join-again',
        sessionId: waiting.id,
        actorDeviceId: 'participant-1',
        baseRevision: 0,
        issuedAt: fixtureStart,
        displayName: 'Sam',
        requestedRole: SessionRole.participant,
        authenticationSecret: '0123456789abcdef0123456789abcdef',
      );

      expect(
        () => SessionReducer.applyCommand(
          session: waiting,
          command: command,
          occurredAt: fixtureStart,
        ),
        throwsA(commandError(SessionCommandError.unauthorized)),
      );
    });

    test('host promotes, revokes, and disconnects a participant', () {
      LiveSession session = createWaitingSession(
        participants: <Participant>[createParticipant()],
      );
      session = SessionReducer.applyCommand(
        session: session,
        command: SessionCommand.changeRole(
          id: 'promote',
          sessionId: session.id,
          actorDeviceId: 'host-1',
          actorRole: SessionRole.host,
          baseRevision: session.revision,
          issuedAt: fixtureStart,
          targetDeviceId: 'participant-1',
          targetRole: SessionRole.controller,
        ),
        occurredAt: fixtureStart,
      ).session;

      expect(session.activities.last.type, ActivityType.roleChanged);
      expect(
        session.participantFor('participant-1')?.role,
        SessionRole.controller,
      );

      session = SessionReducer.applyCommand(
        session: session,
        command: SessionCommand.changeRole(
          id: 'revoke',
          sessionId: session.id,
          actorDeviceId: 'host-1',
          actorRole: SessionRole.host,
          baseRevision: session.revision,
          issuedAt: fixtureStart,
          targetDeviceId: 'participant-1',
          targetRole: SessionRole.participant,
        ),
        occurredAt: fixtureStart.add(const Duration(seconds: 1)),
      ).session;
      expect(
        session.participantFor('participant-1')?.role,
        SessionRole.participant,
      );

      session = SessionReducer.applyCommand(
        session: session,
        command: SessionCommand.disconnectParticipant(
          id: 'disconnect',
          sessionId: session.id,
          actorDeviceId: 'host-1',
          actorRole: SessionRole.host,
          baseRevision: session.revision,
          issuedAt: fixtureStart,
          targetDeviceId: 'participant-1',
        ),
        occurredAt: fixtureStart.add(const Duration(seconds: 2)),
      ).session;

      expect(
        session.participantFor('participant-1')?.connectionState,
        ParticipantConnectionState.disconnected,
      );
      expect(
        session.activities.last.type,
        ActivityType.participantDisconnected,
      );
      expect(session.revision, 3);
    });

    test('non-host cannot change roles or disconnect participants', () {
      final LiveSession session = createWaitingSession(
        participants: <Participant>[
          createParticipant(role: SessionRole.controller),
        ],
      );
      final List<SessionCommand> commands = <SessionCommand>[
        SessionCommand.changeRole(
          id: 'role',
          sessionId: session.id,
          actorDeviceId: 'participant-1',
          actorRole: SessionRole.controller,
          baseRevision: 0,
          issuedAt: fixtureStart,
          targetDeviceId: 'participant-1',
          targetRole: SessionRole.participant,
        ),
        SessionCommand.disconnectParticipant(
          id: 'disconnect',
          sessionId: session.id,
          actorDeviceId: 'participant-1',
          actorRole: SessionRole.controller,
          baseRevision: 0,
          issuedAt: fixtureStart,
          targetDeviceId: 'participant-1',
        ),
      ];

      for (final SessionCommand command in commands) {
        expect(
          () => SessionReducer.applyCommand(
            session: session,
            command: command,
            occurredAt: fixtureStart,
          ),
          throwsA(commandError(SessionCommandError.unauthorized)),
        );
      }
    });

    test('revocation immediately removes controller authority', () {
      LiveSession session = createWaitingSession(
        participants: <Participant>[
          createParticipant(role: SessionRole.controller),
        ],
      );
      session = start(session);
      session = SessionReducer.applyCommand(
        session: session,
        command: SessionCommand.changeRole(
          id: 'revoke',
          sessionId: session.id,
          actorDeviceId: 'host-1',
          actorRole: SessionRole.host,
          baseRevision: session.revision,
          issuedAt: fixtureStart,
          targetDeviceId: 'participant-1',
          targetRole: SessionRole.participant,
        ),
        occurredAt: fixtureStart.add(const Duration(seconds: 1)),
      ).session;
      final SessionCommand advance = SessionCommand.advance(
        id: 'controller-advance',
        sessionId: session.id,
        actorDeviceId: 'participant-1',
        actorRole: SessionRole.controller,
        baseRevision: session.revision,
        issuedAt: fixtureStart,
      );

      expect(
        () => SessionReducer.applyCommand(
          session: session,
          command: advance,
          occurredAt: fixtureStart.add(const Duration(seconds: 2)),
        ),
        throwsA(commandError(SessionCommandError.unauthorized)),
      );
    });
  });

  group('timing and commands', () {
    test('pause freezes active time while variance keeps increasing', () {
      LiveSession session = createWaitingSession();
      session = start(session);
      session = SessionReducer.applyCommand(
        session: session,
        command: SessionCommand.pause(
          id: 'pause',
          sessionId: session.id,
          actorDeviceId: 'host-1',
          actorRole: SessionRole.host,
          baseRevision: session.revision,
          issuedAt: fixtureStart,
        ),
        occurredAt: fixtureStart.add(const Duration(minutes: 2)),
      ).session;

      expect(
        session.elapsedAt(fixtureStart.add(const Duration(minutes: 3))),
        const Duration(minutes: 2),
      );
      expect(
        session.remainingAt(fixtureStart.add(const Duration(minutes: 3))),
        const Duration(minutes: 3),
      );
      expect(
        session.scheduleVarianceAt(
          fixtureStart.add(const Duration(minutes: 3)),
        ),
        const Duration(minutes: 1),
      );

      session = SessionReducer.applyCommand(
        session: session,
        command: SessionCommand.resume(
          id: 'resume',
          sessionId: session.id,
          actorDeviceId: 'host-1',
          actorRole: SessionRole.host,
          baseRevision: session.revision,
          issuedAt: fixtureStart,
        ),
        occurredAt: fixtureStart.add(const Duration(minutes: 4)),
      ).session;

      expect(session.totalPausedDuration, const Duration(minutes: 2));
      expect(
        session.elapsedAt(fixtureStart.add(const Duration(minutes: 5))),
        const Duration(minutes: 3),
      );
      expect(
        session.scheduleVarianceAt(
          fixtureStart.add(const Duration(minutes: 5)),
        ),
        const Duration(minutes: 2),
      );
      expect(LiveSession.fromJson(session.toJson()), session);
    });

    test('scheduled-start delay contributes to variance', () {
      final LiveSession waiting = createWaitingSession(
        plannedStartTime: fixtureStart.subtract(const Duration(minutes: 1)),
      );
      final LiveSession running = start(waiting);

      expect(
        running.scheduleVarianceAt(
          fixtureStart.add(const Duration(minutes: 2)),
        ),
        const Duration(minutes: 1),
      );
    });

    test('remaining-time adjustments accumulate and remain positive', () {
      LiveSession session = start(createWaitingSession());
      session = SessionReducer.applyCommand(
        session: session,
        command: SessionCommand.adjustRemaining(
          id: 'plus-minute',
          sessionId: session.id,
          actorDeviceId: 'host-1',
          actorRole: SessionRole.host,
          baseRevision: session.revision,
          issuedAt: fixtureStart,
          adjustmentSeconds: 60,
        ),
        occurredAt: fixtureStart.add(const Duration(seconds: 10)),
      ).session;
      session = SessionReducer.applyCommand(
        session: session,
        command: SessionCommand.adjustRemaining(
          id: 'minus-two',
          sessionId: session.id,
          actorDeviceId: 'host-1',
          actorRole: SessionRole.host,
          baseRevision: session.revision,
          issuedAt: fixtureStart,
          adjustmentSeconds: -120,
        ),
        occurredAt: fixtureStart.add(const Duration(seconds: 20)),
      ).session;

      expect(session.remainingAdjustmentSeconds, -60);
      expect(
        session.remainingAt(fixtureStart.add(const Duration(seconds: 20))),
        const Duration(seconds: 220),
      );

      final SessionCommand invalid = SessionCommand.adjustRemaining(
        id: 'remove-all',
        sessionId: session.id,
        actorDeviceId: 'host-1',
        actorRole: SessionRole.host,
        baseRevision: session.revision,
        issuedAt: fixtureStart,
        adjustmentSeconds: -240,
      );
      expect(
        () => SessionReducer.applyCommand(
          session: session,
          command: invalid,
          occurredAt: fixtureStart.add(const Duration(seconds: 21)),
        ),
        throwsA(commandError(SessionCommandError.invalidAdjustment)),
      );

      final SessionCommand excessive = SessionCommand.adjustRemaining(
        id: 'excessive',
        sessionId: session.id,
        actorDeviceId: 'host-1',
        actorRole: SessionRole.host,
        baseRevision: session.revision,
        issuedAt: fixtureStart,
        adjustmentSeconds: maxStepDurationSeconds,
      );
      expect(
        () => SessionReducer.applyCommand(
          session: session,
          command: excessive,
          occurredAt: fixtureStart.add(const Duration(seconds: 21)),
        ),
        throwsA(commandError(SessionCommandError.invalidAdjustment)),
      );
    });

    test('jump requires confirmation and resets step-local timing', () {
      LiveSession session = start(createWaitingSession());
      session = SessionReducer.applyCommand(
        session: session,
        command: SessionCommand.adjustRemaining(
          id: 'adjust',
          sessionId: session.id,
          actorDeviceId: 'host-1',
          actorRole: SessionRole.host,
          baseRevision: session.revision,
          issuedAt: fixtureStart,
          adjustmentSeconds: 60,
        ),
        occurredAt: fixtureStart.add(const Duration(seconds: 1)),
      ).session;
      final SessionCommand unconfirmed = SessionCommand.jump(
        id: 'jump-no',
        sessionId: session.id,
        actorDeviceId: 'host-1',
        actorRole: SessionRole.host,
        baseRevision: session.revision,
        issuedAt: fixtureStart,
        targetStepIndex: 2,
        confirmed: false,
      );
      expect(
        () => SessionReducer.applyCommand(
          session: session,
          command: unconfirmed,
          occurredAt: fixtureStart.add(const Duration(seconds: 10)),
        ),
        throwsA(commandError(SessionCommandError.confirmationRequired)),
      );

      session = SessionReducer.applyCommand(
        session: session,
        command: SessionCommand.jump(
          id: 'jump-yes',
          sessionId: session.id,
          actorDeviceId: 'host-1',
          actorRole: SessionRole.host,
          baseRevision: session.revision,
          issuedAt: fixtureStart,
          targetStepIndex: 2,
          confirmed: true,
        ),
        occurredAt: fixtureStart.add(const Duration(seconds: 10)),
      ).session;

      expect(session.currentStepIndex, 2);
      expect(session.remainingAdjustmentSeconds, 0);
      expect(
        session.elapsedAt(fixtureStart.add(const Duration(seconds: 15))),
        const Duration(seconds: 5),
      );
    });

    test('acknowledgement logs without advancing the step', () {
      LiveSession session = start(
        createWaitingSession(participants: <Participant>[createParticipant()]),
      );
      session = SessionReducer.applyCommand(
        session: session,
        command: SessionCommand.acknowledge(
          id: 'ack',
          sessionId: session.id,
          actorDeviceId: 'participant-1',
          actorRole: SessionRole.participant,
          baseRevision: session.revision,
          issuedAt: fixtureStart,
          stepIndex: 0,
        ),
        occurredAt: fixtureStart.add(const Duration(seconds: 5)),
      ).session;

      expect(session.currentStepIndex, 0);
      expect(session.activities.last.type, ActivityType.acknowledged);
      expect(session.activities.last.actorDeviceId, 'participant-1');
      expect(session.participantFor('participant-1')?.acknowledgedStepIndex, 0);
      expect(
        session.participantFor('participant-1')?.acknowledgedAt,
        fixtureStart.add(const Duration(seconds: 5)),
      );
    });

    test('repeated acknowledgement by the same actor and step is a no-op', () {
      LiveSession session = start(
        createWaitingSession(participants: <Participant>[createParticipant()]),
      );
      session = SessionReducer.applyCommand(
        session: session,
        command: SessionCommand.acknowledge(
          id: 'ack-first',
          sessionId: session.id,
          actorDeviceId: 'participant-1',
          actorRole: SessionRole.participant,
          baseRevision: session.revision,
          issuedAt: fixtureStart,
          stepIndex: 0,
        ),
        occurredAt: fixtureStart.add(const Duration(seconds: 5)),
      ).session;
      final SessionTransition repeated = SessionReducer.applyCommand(
        session: session,
        command: SessionCommand.acknowledge(
          id: 'ack-again',
          sessionId: session.id,
          actorDeviceId: 'participant-1',
          actorRole: SessionRole.participant,
          baseRevision: session.revision,
          issuedAt: fixtureStart,
          stepIndex: 0,
        ),
        occurredAt: fixtureStart.add(const Duration(seconds: 6)),
      );

      expect(repeated.wasDuplicate, isTrue);
      expect(repeated.activity, isNull);
      expect(identical(repeated.session, session), isTrue);
      expect(
        session.activities.where(
          (Activity activity) =>
              activity.type == ActivityType.acknowledged &&
              activity.actorDeviceId == 'participant-1' &&
              activity.stepIndex == 0,
        ),
        hasLength(1),
      );
    });

    test('a revisited step accepts a fresh acknowledgement', () {
      LiveSession session = start(
        createWaitingSession(participants: <Participant>[createParticipant()]),
      );
      session = SessionReducer.applyCommand(
        session: session,
        command: SessionCommand.acknowledge(
          id: 'ack-first-visit',
          sessionId: session.id,
          actorDeviceId: 'participant-1',
          actorRole: SessionRole.participant,
          baseRevision: session.revision,
          issuedAt: fixtureStart,
          stepIndex: 0,
        ),
        occurredAt: fixtureStart.add(const Duration(seconds: 1)),
      ).session;
      session = SessionReducer.applyCommand(
        session: session,
        command: SessionCommand.advance(
          id: 'advance-away',
          sessionId: session.id,
          actorDeviceId: 'host-1',
          actorRole: SessionRole.host,
          baseRevision: session.revision,
          issuedAt: fixtureStart,
        ),
        occurredAt: fixtureStart.add(const Duration(seconds: 2)),
      ).session;
      session = SessionReducer.applyCommand(
        session: session,
        command: SessionCommand.jump(
          id: 'jump-back',
          sessionId: session.id,
          actorDeviceId: 'host-1',
          actorRole: SessionRole.host,
          baseRevision: session.revision,
          issuedAt: fixtureStart,
          targetStepIndex: 0,
          confirmed: true,
        ),
        occurredAt: fixtureStart.add(const Duration(seconds: 3)),
      ).session;
      final SessionTransition fresh = SessionReducer.applyCommand(
        session: session,
        command: SessionCommand.acknowledge(
          id: 'ack-second-visit',
          sessionId: session.id,
          actorDeviceId: 'participant-1',
          actorRole: SessionRole.participant,
          baseRevision: session.revision,
          issuedAt: fixtureStart,
          stepIndex: 0,
        ),
        occurredAt: fixtureStart.add(const Duration(seconds: 4)),
      );

      expect(fresh.wasDuplicate, isFalse);
      expect(fresh.activity?.type, ActivityType.acknowledged);
      expect(
        fresh.session.activities.where(
          (Activity activity) =>
              activity.type == ActivityType.acknowledged &&
              activity.actorDeviceId == 'participant-1' &&
              activity.stepIndex == 0,
        ),
        hasLength(2),
      );
    });

    test('manual and automatic advances complete on the final step', () {
      LiveSession session = start(createWaitingSession());
      session = SessionReducer.applyCommand(
        session: session,
        command: SessionCommand.advance(
          id: 'advance',
          sessionId: session.id,
          actorDeviceId: 'host-1',
          actorRole: SessionRole.host,
          baseRevision: session.revision,
          issuedAt: fixtureStart,
        ),
        occurredAt: fixtureStart.add(const Duration(minutes: 5)),
      ).session;
      expect(session.activities.last.type, ActivityType.advanced);
      session = SessionReducer.applyCommand(
        session: session,
        command: SessionCommand.advance(
          id: 'auto-advance',
          sessionId: session.id,
          actorDeviceId: 'host-1',
          actorRole: SessionRole.host,
          baseRevision: session.revision,
          issuedAt: fixtureStart,
          automatically: true,
        ),
        occurredAt: fixtureStart.add(const Duration(minutes: 7)),
      ).session;
      expect(session.activities.last.type, ActivityType.autoAdvanced);
      session = SessionReducer.applyCommand(
        session: session,
        command: SessionCommand.advance(
          id: 'complete',
          sessionId: session.id,
          actorDeviceId: 'host-1',
          actorRole: SessionRole.host,
          baseRevision: session.revision,
          issuedAt: fixtureStart,
        ),
        occurredAt: fixtureStart.add(const Duration(minutes: 8)),
      ).session;

      expect(session.status, LiveSessionStatus.ended);
      expect(session.endReason, SessionEndReason.completed);
      expect(session.activities.last.type, ActivityType.ended);
      expect(
        session.totalElapsedAt(fixtureStart.add(const Duration(hours: 1))),
        const Duration(minutes: 8),
      );
    });

    test('ending requires host confirmation', () {
      final LiveSession session = start(createWaitingSession());
      final SessionCommand command = SessionCommand.end(
        id: 'end',
        sessionId: session.id,
        actorDeviceId: 'host-1',
        actorRole: SessionRole.host,
        baseRevision: session.revision,
        issuedAt: fixtureStart,
        confirmed: false,
      );

      expect(
        () => SessionReducer.applyCommand(
          session: session,
          command: command,
          occurredAt: fixtureStart.add(const Duration(minutes: 1)),
        ),
        throwsA(commandError(SessionCommandError.confirmationRequired)),
      );
    });
  });

  group('revision and replica behavior', () {
    test('rejects stale commands but accepts duplicate retry first', () {
      final LiveSession waiting = createWaitingSession();
      final SessionCommand command = hostStart(waiting);
      final LiveSession running = SessionReducer.applyCommand(
        session: waiting,
        command: command,
        occurredAt: fixtureStart,
      ).session;

      final SessionTransition duplicate = SessionReducer.applyCommand(
        session: running,
        command: command,
        occurredAt: fixtureStart.add(const Duration(seconds: 1)),
      );
      expect(duplicate.wasDuplicate, isTrue);

      final SessionCommand stale = SessionCommand.pause(
        id: 'stale',
        sessionId: running.id,
        actorDeviceId: 'host-1',
        actorRole: SessionRole.host,
        baseRevision: 0,
        issuedAt: fixtureStart,
      );
      expect(
        () => SessionReducer.applyCommand(
          session: running,
          command: stale,
          occurredAt: fixtureStart.add(const Duration(seconds: 2)),
        ),
        throwsA(commandError(SessionCommandError.staleRevision)),
      );
    });

    test('replica activity replay produces exactly the host state', () {
      final LiveSession initial = createWaitingSession();
      LiveSession host = initial;
      LiveSession replica = initial;
      final List<SessionCommand> commands = <SessionCommand>[hostStart(host)];

      for (final SessionCommand command in commands) {
        final SessionTransition transition = SessionReducer.applyCommand(
          session: host,
          command: command,
          occurredAt: fixtureStart,
        );
        host = transition.session;
        replica = SessionReducer.applyActivity(
          session: replica,
          activity: transition.activity!,
        );
      }

      final SessionCommand adjust = SessionCommand.adjustRemaining(
        id: 'adjust',
        sessionId: host.id,
        actorDeviceId: 'host-1',
        actorRole: SessionRole.host,
        baseRevision: host.revision,
        issuedAt: fixtureStart,
        adjustmentSeconds: 60,
      );
      final SessionTransition adjusted = SessionReducer.applyCommand(
        session: host,
        command: adjust,
        occurredAt: fixtureStart.add(const Duration(seconds: 10)),
      );
      host = adjusted.session;
      replica = SessionReducer.applyActivity(
        session: replica,
        activity: adjusted.activity!,
      );

      expect(replica, host);
    });

    test('replica rejects a revision gap', () {
      final LiveSession waiting = createWaitingSession();
      final Activity skipped = Activity(
        id: 'activity-2',
        commandId: 'command-2',
        sessionId: waiting.id,
        revision: 2,
        type: ActivityType.started,
        stepIndex: 0,
        stepId: 'step-1',
        actorDeviceId: 'host-1',
        actorRole: SessionRole.host,
        occurredAt: fixtureStart,
      );

      expect(
        () => SessionReducer.applyActivity(session: waiting, activity: skipped),
        throwsStateError,
      );
    });

    test('wrong session commands are rejected', () {
      final LiveSession waiting = createWaitingSession();
      final SessionCommand command = SessionCommand.start(
        id: 'start',
        sessionId: 'another-session',
        actorDeviceId: 'host-1',
        actorRole: SessionRole.host,
        baseRevision: 0,
        issuedAt: fixtureStart,
      );

      expect(
        () => SessionReducer.applyCommand(
          session: waiting,
          command: command,
          occurredAt: fixtureStart,
        ),
        throwsA(commandError(SessionCommandError.wrongSession)),
      );
    });
  });
}
