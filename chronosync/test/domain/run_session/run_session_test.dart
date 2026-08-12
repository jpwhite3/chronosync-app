import 'package:chronosync/domain/run_session/run_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('RunSession validates step bounds at runtime', () {
    expect(
      () => RunSession(
        id: 'invalid',
        runbookId: 'runbook',
        hostPeerId: 'host',
        stepCount: 0,
      ),
      throwsArgumentError,
    );
    expect(
      () => RunSession(
        id: 'invalid',
        runbookId: 'runbook',
        hostPeerId: 'host',
        stepCount: 1,
        currentStepIndex: 1,
      ),
      throwsRangeError,
    );
  });

  const String hostPeerId = 'host-1';
  final DateTime startTime = DateTime.utc(2026, 7, 27, 9);

  RunSession createLobby() {
    return RunSession(
      id: 'session-1',
      runbookId: 'runbook-1',
      hostPeerId: hostPeerId,
      stepCount: 2,
    );
  }

  group('RunSessionReducer', () {
    test('starts a lobby with a revisioned host activity', () {
      final RunSessionTransition transition = RunSessionReducer.start(
        session: createLobby(),
        activityId: 'activity-1',
        occurredAt: startTime,
      );

      expect(transition.activity.type, RunActivityType.started);
      expect(transition.activity.revision, 1);
      expect(transition.session.status, RunSessionStatus.running);
      expect(transition.session.currentStepIndex, 0);
      expect(transition.session.startedAt, startTime);
      expect(transition.session.currentStepStartedAt, startTime);
      expect(transition.session.revision, 1);
    });

    test('uses timestamps instead of tick counts for elapsed time', () {
      final RunSessionTransition transition = RunSessionReducer.start(
        session: createLobby(),
        activityId: 'activity-1',
        occurredAt: startTime,
      );

      expect(
        transition.session.elapsedAt(
          startTime.add(const Duration(seconds: 75)),
        ),
        const Duration(seconds: 75),
      );
      expect(
        transition.session.elapsedAt(
          startTime.subtract(const Duration(seconds: 1)),
        ),
        Duration.zero,
      );
    });

    test('records participant acknowledgements without changing the step', () {
      final RunSession running = RunSessionReducer.start(
        session: createLobby(),
        activityId: 'activity-1',
        occurredAt: startTime,
      ).session;

      final RunSessionTransition transition = RunSessionReducer.acknowledge(
        session: running,
        activityId: 'activity-2',
        actorPeerId: 'operator-1',
        occurredAt: startTime.add(const Duration(seconds: 20)),
      );

      expect(transition.activity.type, RunActivityType.acknowledged);
      expect(transition.activity.actorPeerId, 'operator-1');
      expect(transition.session.currentStepIndex, 0);
      expect(transition.session.revision, 2);
    });

    test(
      'advances the host session and resets timing from the activity timestamp',
      () {
        final RunSession running = RunSessionReducer.start(
          session: createLobby(),
          activityId: 'activity-1',
          occurredAt: startTime,
        ).session;
        final DateTime nextStepTime = startTime.add(const Duration(minutes: 5));

        final RunSessionTransition transition = RunSessionReducer.advance(
          session: running,
          activityId: 'activity-2',
          occurredAt: nextStepTime,
        );

        expect(transition.activity.type, RunActivityType.advanced);
        expect(transition.activity.stepIndex, 1);
        expect(transition.session.currentStepIndex, 1);
        expect(transition.session.currentStepStartedAt, nextStepTime);
        expect(
          transition.session.elapsedAt(
            nextStepTime.add(const Duration(seconds: 10)),
          ),
          const Duration(seconds: 10),
        );
      },
    );

    test('completes when the host advances past the final step', () {
      final RunSession started = RunSessionReducer.start(
        session: createLobby(),
        activityId: 'activity-1',
        occurredAt: startTime,
      ).session;
      final RunSession finalStep = RunSessionReducer.advance(
        session: started,
        activityId: 'activity-2',
        occurredAt: startTime.add(const Duration(minutes: 5)),
      ).session;

      final RunSessionTransition transition = RunSessionReducer.advance(
        session: finalStep,
        activityId: 'activity-3',
        occurredAt: startTime.add(const Duration(minutes: 10)),
      );

      expect(transition.activity.type, RunActivityType.completed);
      expect(transition.session.status, RunSessionStatus.completed);
      expect(
        transition.session.completedAt,
        startTime.add(const Duration(minutes: 10)),
      );
      expect(
        transition.session.totalElapsedAt(
          startTime.add(const Duration(hours: 1)),
        ),
        const Duration(minutes: 10),
      );
    });

    test('rejects an activity revision gap on a participant', () {
      final RunSession lobby = createLobby();
      final RunActivity skippedRevision = RunActivity(
        id: 'activity-2',
        sessionId: lobby.id,
        revision: 2,
        type: RunActivityType.started,
        stepIndex: 0,
        actorPeerId: hostPeerId,
        occurredAt: startTime,
      );

      expect(
        () => RunSessionReducer.applyActivity(
          session: lobby,
          activity: skippedRevision,
        ),
        throwsStateError,
      );
    });

    test('round-trips a session and an activity through JSON-safe maps', () {
      final RunSessionTransition transition = RunSessionReducer.start(
        session: createLobby(),
        activityId: 'activity-1',
        occurredAt: startTime,
      );

      expect(
        RunSession.fromJson(transition.session.toJson()),
        transition.session,
      );
      expect(
        RunActivity.fromJson(transition.activity.toJson()),
        transition.activity,
      );
    });
  });
}
