import 'package:chronosync/domain/session/live_session.dart';
import 'package:chronosync/domain/session/session_command.dart';
import 'package:chronosync/domain/session/session_reducer.dart';
import 'package:flutter_test/flutter_test.dart';

import 'session_fixtures.dart';

void main() {
  test(
    'a representative long session appends without rebuilding full history',
    () {
      final LiveSession waiting = createWaitingSession();
      final LiveSession initial = SessionReducer.applyCommand(
        session: waiting,
        command: SessionCommand.start(
          id: 'start',
          sessionId: waiting.id,
          actorDeviceId: waiting.hostDeviceId,
          actorRole: SessionRole.host,
          baseRevision: waiting.revision,
          issuedAt: fixtureStart,
        ),
        occurredAt: fixtureStart,
      ).session;
      LiveSession current = initial;

      for (int index = 0; index < 12500; index += 1) {
        final int revision = current.revision + 1;
        current = SessionReducer.applyActivity(
          session: current,
          activity: Activity(
            id: 'activity-$revision',
            commandId: 'command-$revision',
            sessionId: current.id,
            revision: revision,
            type: ActivityType.remainingAdjusted,
            stepIndex: current.currentStepIndex,
            stepId: current.currentStep.id,
            actorDeviceId: current.hostDeviceId,
            actorRole: SessionRole.host,
            occurredAt: fixtureStart.add(Duration(microseconds: revision)),
            payload: <String, Object?>{
              'adjustmentSeconds': index.isEven ? 1 : -1,
            },
          ),
        );
      }

      expect(
        current.debugSharesActivityStorageWith(initial),
        isTrue,
        reason: 'Linear appends must structurally share authoritative history.',
      );
      expect(current.activities, hasLength(12501));
      expect(current.hasCompleteActivityHistory, isTrue);
      expect(current.hasProcessedCommand('command-2'), isTrue);
      expect(current.hasProcessedCommand('command-12501'), isTrue);

      // A prior immutable session keeps its original window and command index,
      // even though newer versions share append-only backing storage.
      expect(initial.activities, hasLength(1));
      expect(initial.hasProcessedCommand('command-2'), isFalse);
      expect(
        () => initial.activities.add(current.activities.last),
        throwsUnsupportedError,
      );
      expect(
        () => initial.activities.removeWhere((Activity _) => false),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'appending to an older session forks without corrupting either branch',
    () {
      final LiveSession waiting = createWaitingSession();
      final LiveSession base = SessionReducer.applyCommand(
        session: waiting,
        command: SessionCommand.start(
          id: 'start',
          sessionId: waiting.id,
          actorDeviceId: waiting.hostDeviceId,
          actorRole: SessionRole.host,
          baseRevision: waiting.revision,
          issuedAt: fixtureStart,
        ),
        occurredAt: fixtureStart,
      ).session;
      final LiveSession left = SessionReducer.applyActivity(
        session: base,
        activity: _adjustment(session: base, id: 'left', adjustmentSeconds: 1),
      );
      final LiveSession right = SessionReducer.applyActivity(
        session: base,
        activity: _adjustment(
          session: base,
          id: 'right',
          adjustmentSeconds: -1,
        ),
      );

      expect(base.activities, hasLength(1));
      expect(left.activities.map((Activity value) => value.id), <String>[
        'start',
        'left',
      ]);
      expect(right.activities.map((Activity value) => value.id), <String>[
        'start',
        'right',
      ]);
      expect(left.hasProcessedCommand('right'), isFalse);
      expect(right.hasProcessedCommand('left'), isFalse);
      expect(right.debugSharesActivityStorageWith(left), isFalse);
    },
  );

  test('indexed appends still reject a duplicate activity ID', () {
    final LiveSession waiting = createWaitingSession();
    final LiveSession base = SessionReducer.applyCommand(
      session: waiting,
      command: SessionCommand.start(
        id: 'start',
        sessionId: waiting.id,
        actorDeviceId: waiting.hostDeviceId,
        actorRole: SessionRole.host,
        baseRevision: waiting.revision,
        issuedAt: fixtureStart,
      ),
      occurredAt: fixtureStart,
    ).session;

    expect(
      () => SessionReducer.applyActivity(
        session: base,
        activity: Activity(
          id: 'start',
          commandId: 'different-command',
          sessionId: base.id,
          revision: base.revision + 1,
          type: ActivityType.remainingAdjusted,
          stepIndex: base.currentStepIndex,
          stepId: base.currentStep.id,
          actorDeviceId: base.hostDeviceId,
          actorRole: SessionRole.host,
          occurredAt: fixtureStart.add(const Duration(microseconds: 2)),
          payload: const <String, Object?>{'adjustmentSeconds': 1},
        ),
      ),
      throwsArgumentError,
    );
    expect(base.activities, hasLength(1));
  });
}

Activity _adjustment({
  required LiveSession session,
  required String id,
  required int adjustmentSeconds,
}) {
  return Activity(
    id: id,
    commandId: id,
    sessionId: session.id,
    revision: session.revision + 1,
    type: ActivityType.remainingAdjusted,
    stepIndex: session.currentStepIndex,
    stepId: session.currentStep.id,
    actorDeviceId: session.hostDeviceId,
    actorRole: SessionRole.host,
    occurredAt: fixtureStart.add(Duration(microseconds: session.revision + 1)),
    payload: <String, Object?>{'adjustmentSeconds': adjustmentSeconds},
  );
}
