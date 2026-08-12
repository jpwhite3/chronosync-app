import 'package:chronosync/domain/plan/plan.dart';
import 'package:chronosync/domain/session/live_session.dart';

final DateTime fixtureStart = DateTime.utc(2026, 7, 28, 19);

PlanSnapshot createPlanSnapshot({DateTime? plannedStartTime}) {
  return PlanSnapshot(
    sourcePlanId: 'plan-1',
    title: 'Live show',
    plannedStartTime: plannedStartTime,
    defaultCueProfile: CueProfile(),
    steps: <Step>[
      Step(
        id: 'step-1',
        planId: 'plan-1',
        position: 0,
        title: 'Doors',
        durationSeconds: 300,
      ),
      Step(
        id: 'step-2',
        planId: 'plan-1',
        position: 1,
        title: 'Welcome',
        durationSeconds: 120,
        autoAdvance: true,
      ),
      Step(
        id: 'step-3',
        planId: 'plan-1',
        position: 2,
        title: 'Close',
        durationSeconds: 60,
      ),
    ],
    capturedAt: fixtureStart.subtract(const Duration(hours: 1)),
  );
}

LiveSession createWaitingSession({
  Iterable<Participant> participants = const <Participant>[],
  DateTime? plannedStartTime,
}) {
  return LiveSession(
    id: 'session-1',
    planSnapshot: createPlanSnapshot(plannedStartTime: plannedStartTime),
    hostDeviceId: 'host-1',
    participants: participants,
  );
}

Participant createParticipant({
  String deviceId = 'participant-1',
  String displayName = 'Sam',
  SessionRole role = SessionRole.participant,
  ParticipantConnectionState connectionState =
      ParticipantConnectionState.connected,
}) {
  return Participant(
    deviceId: deviceId,
    displayName: displayName,
    role: role,
    joinedAt: fixtureStart.subtract(const Duration(minutes: 1)),
    connectionState: connectionState,
  );
}
