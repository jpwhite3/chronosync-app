import 'package:chronosync/domain/plan/plan.dart';
import 'package:chronosync/domain/session/live_session.dart';
import 'package:chronosync/domain/session/session_command.dart';
import 'package:chronosync/domain/session/session_reducer.dart';
import 'package:chronosync/logic/live_session/live_session_view_mapper.dart';
import 'package:chronosync/presentation/screens/live/live_view_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final DateTime start = DateTime.utc(2026, 7, 28, 14);

  group('live timing phase', () {
    test('uses the current step cue override thresholds', () {
      final LiveSession session = _startSession(
        start: start,
        cueOverride: CueProfile(approachingSeconds: 15, overdueSeconds: 20),
      );

      expect(
        _map(session, start.add(const Duration(seconds: 80))).timingPhase,
        LiveTimingPhase.normal,
      );
      expect(
        _map(session, start.add(const Duration(seconds: 106))).timingPhase,
        LiveTimingPhase.approaching,
      );
      expect(
        _map(session, start.add(const Duration(seconds: 121))).timingPhase,
        LiveTimingPhase.due,
      );
      expect(
        _map(session, start.add(const Duration(seconds: 139))).timingPhase,
        LiveTimingPhase.due,
      );
      expect(
        _map(session, start.add(const Duration(seconds: 140))).timingPhase,
        LiveTimingPhase.overtime,
      );
    });

    test('omits the default approaching phase for a short step', () {
      final LiveSession session = _startSession(
        start: start,
        durationSeconds: 30,
      );

      expect(
        _map(session, start.add(const Duration(seconds: 20))).timingPhase,
        LiveTimingPhase.normal,
      );
    });

    test('keeps threshold styling neutral when visual cues are disabled', () {
      final LiveSession session = _startSession(
        start: start,
        cueOverride: CueProfile(
          approachingSeconds: 15,
          overdueSeconds: 20,
          visualEnabled: false,
        ),
      );

      for (final Duration elapsed in <Duration>[
        const Duration(seconds: 106),
        const Duration(seconds: 121),
        const Duration(seconds: 140),
      ]) {
        expect(
          _map(session, start.add(elapsed)).timingPhase,
          LiveTimingPhase.normal,
        );
      }
    });
  });

  test('maps acknowledgement names, roles, devices, and timestamps', () {
    LiveSession session = LiveSession(
      id: 'session-1',
      planSnapshot: _snapshot(),
      hostDeviceId: 'host-1',
    );
    session = _apply(
      session,
      SessionCommand.join(
        id: 'join-1',
        sessionId: session.id,
        actorDeviceId: 'participant-1',
        baseRevision: session.revision,
        issuedAt: start.subtract(const Duration(seconds: 2)),
        displayName: 'Sam Rivera',
        requestedRole: SessionRole.participant,
        authenticationSecret: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      ),
      start.subtract(const Duration(seconds: 2)),
    );
    session = _apply(
      session,
      SessionCommand.start(
        id: 'start-1',
        sessionId: session.id,
        actorDeviceId: 'host-1',
        actorRole: SessionRole.host,
        baseRevision: session.revision,
        issuedAt: start,
      ),
      start,
    );
    session = _apply(
      session,
      SessionCommand.acknowledge(
        id: 'ack-1',
        sessionId: session.id,
        actorDeviceId: 'participant-1',
        actorRole: SessionRole.participant,
        baseRevision: session.revision,
        issuedAt: start.add(const Duration(seconds: 10)),
        stepIndex: 0,
      ),
      start.add(const Duration(seconds: 10)),
    );
    session = _apply(
      session,
      SessionCommand.acknowledge(
        id: 'ack-2',
        sessionId: session.id,
        actorDeviceId: 'host-1',
        actorRole: SessionRole.host,
        baseRevision: session.revision,
        issuedAt: start.add(const Duration(seconds: 12)),
        stepIndex: 0,
      ),
      start.add(const Duration(seconds: 12)),
    );

    final LiveSessionViewData live = mapLiveSessionView(
      session: session,
      role: SessionRole.participant,
      deviceId: 'participant-1',
      currentDeviceDisplayName: 'Sam Rivera',
      hostDisplayName: 'Event lead',
      now: start.add(const Duration(seconds: 15)),
      isStale: false,
    );

    expect(live.hasAcknowledged, isTrue);
    expect(
      live.currentStepAcknowledgements
          .map<String>(
            (AcknowledgementViewData acknowledgement) =>
                acknowledgement.displayName,
          )
          .toList(),
      <String>['Sam Rivera', 'Event lead'],
    );
    expect(live.currentStepAcknowledgements.first.isCurrentDevice, isTrue);
    expect(
      live.currentStepAcknowledgements.last.acknowledgedAt,
      start.add(const Duration(seconds: 12)),
    );

    session = _apply(
      session,
      SessionCommand.end(
        id: 'end-1',
        sessionId: session.id,
        actorDeviceId: 'host-1',
        actorRole: SessionRole.host,
        baseRevision: session.revision,
        issuedAt: start.add(const Duration(seconds: 60)),
        confirmed: true,
      ),
      start.add(const Duration(seconds: 60)),
    );
    final SessionSummaryViewData summary = mapSessionSummaryView(
      session: session,
      now: start.add(const Duration(seconds: 60)),
      hostDisplayName: 'Event lead',
    );
    expect(summary.steps.single.acknowledgements, hasLength(2));
    expect(summary.steps.single.wasAcknowledged, isTrue);
  });

  test('uses the Timekeeper label when a controller name is unavailable', () {
    LiveSession session = _startSession(start: start);
    session = session.copyWith(
      revision: session.revision + 1,
      appendedActivity: Activity(
        id: 'activity-timekeeper',
        commandId: 'ack-timekeeper',
        sessionId: session.id,
        revision: session.revision + 1,
        type: ActivityType.acknowledged,
        actorDeviceId: 'controller-1',
        actorRole: SessionRole.controller,
        occurredAt: start.add(const Duration(seconds: 10)),
        stepIndex: 0,
        stepId: session.currentStep.id,
      ),
    );

    final SessionSummaryViewData summary = mapSessionSummaryView(
      session: session,
      now: start.add(const Duration(seconds: 15)),
    );

    expect(
      summary.steps.single.acknowledgements.single.displayName,
      'Timekeeper',
    );
  });

  test('marks live and summary views with incomplete activity history', () {
    final LiveSession complete = _startSession(start: start);
    final LiveSession incomplete = complete.copyWith(
      activityRevisionOffset: complete.revision,
      activities: const <Activity>[],
    );

    final LiveSessionViewData live = _map(incomplete, start);
    final SessionSummaryViewData summary = mapSessionSummaryView(
      session: incomplete,
      now: start,
    );

    expect(live.hasCompleteActivityHistory, isFalse);
    expect(summary.hasCompleteActivityHistory, isFalse);
    expect(summary.activityCount, 0);
  });

  test('keeps the actor name captured with an acknowledgement', () {
    LiveSession session = LiveSession(
      id: 'session-1',
      planSnapshot: _snapshot(),
      hostDeviceId: 'host-1',
    );
    session = _apply(
      session,
      SessionCommand.join(
        id: 'join-1',
        sessionId: session.id,
        actorDeviceId: 'participant-1',
        baseRevision: session.revision,
        issuedAt: start.subtract(const Duration(seconds: 2)),
        displayName: 'Sam Rivera',
        requestedRole: SessionRole.participant,
        authenticationSecret: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      ),
      start.subtract(const Duration(seconds: 2)),
    );
    session = _apply(
      session,
      SessionCommand.start(
        id: 'start-1',
        sessionId: session.id,
        actorDeviceId: 'host-1',
        actorRole: SessionRole.host,
        baseRevision: session.revision,
        issuedAt: start,
      ),
      start,
    );
    session = _apply(
      session,
      SessionCommand.acknowledge(
        id: 'ack-1',
        sessionId: session.id,
        actorDeviceId: 'participant-1',
        actorRole: SessionRole.participant,
        baseRevision: session.revision,
        issuedAt: start.add(const Duration(seconds: 10)),
        stepIndex: 0,
      ),
      start.add(const Duration(seconds: 10)),
    );
    session = session.copyWith(
      participants: <Participant>[
        session.participants.single.copyWith(displayName: 'Sam Lee'),
      ],
      activities: session.activities
          .map<Activity>(
            (Activity activity) => activity.type == ActivityType.acknowledged
                ? activity.withActorDisplayName('Sam Rivera')
                : activity,
          )
          .toList(growable: false),
    );

    final SessionSummaryViewData afterRename = mapSessionSummaryView(
      session: session,
      now: start.add(const Duration(seconds: 15)),
    );
    final SessionSummaryViewData afterRemoval = mapSessionSummaryView(
      session: session.copyWith(participants: const <Participant>[]),
      now: start.add(const Duration(seconds: 15)),
    );

    expect(
      afterRename.steps.single.acknowledgements.single.displayName,
      'Sam Rivera',
    );
    expect(
      afterRemoval.steps.single.acknowledgements.single.displayName,
      'Sam Rivera',
    );
  });

  test('does not mark the active step complete when the host ends early', () {
    LiveSession session = LiveSession(
      id: 'session-1',
      planSnapshot: _twoStepSnapshot(),
      hostDeviceId: 'host-1',
    );
    session = _apply(
      session,
      SessionCommand.start(
        id: 'start-1',
        sessionId: session.id,
        actorDeviceId: 'host-1',
        actorRole: SessionRole.host,
        baseRevision: session.revision,
        issuedAt: start,
      ),
      start,
    );
    session = _apply(
      session,
      SessionCommand.advance(
        id: 'advance-1',
        sessionId: session.id,
        actorDeviceId: 'host-1',
        actorRole: SessionRole.host,
        baseRevision: session.revision,
        issuedAt: start.add(const Duration(seconds: 30)),
      ),
      start.add(const Duration(seconds: 30)),
    );
    session = _apply(
      session,
      SessionCommand.end(
        id: 'end-1',
        sessionId: session.id,
        actorDeviceId: 'host-1',
        actorRole: SessionRole.host,
        baseRevision: session.revision,
        issuedAt: start.add(const Duration(seconds: 45)),
        confirmed: true,
      ),
      start.add(const Duration(seconds: 45)),
    );

    final SessionSummaryViewData summary = mapSessionSummaryView(
      session: session,
      now: start.add(const Duration(seconds: 45)),
    );

    expect(
      summary.steps.map<bool>((StepSummaryViewData step) => step.wasCompleted),
      <bool>[true, false],
    );
    expect(summary.endReason, SessionEndReason.endedByHost);
    expect(summary.startedAt, start);
  });

  test('does not invent a start time when a waiting session is ended', () {
    LiveSession session = LiveSession(
      id: 'session-1',
      planSnapshot: _snapshot(),
      hostDeviceId: 'host-1',
    );
    session = _apply(
      session,
      SessionCommand.end(
        id: 'end-waiting',
        sessionId: session.id,
        actorDeviceId: 'host-1',
        actorRole: SessionRole.host,
        baseRevision: session.revision,
        issuedAt: start,
        confirmed: true,
      ),
      start,
    );

    final SessionSummaryViewData summary = mapSessionSummaryView(
      session: session,
      now: start,
    );

    expect(summary.startedAt, isNull);
    expect(summary.endReason, SessionEndReason.endedByHost);
    expect(summary.actualDuration, Duration.zero);
    expect(summary.steps.single.wasCompleted, isFalse);
  });

  test('marks the final step complete when the plan finishes normally', () {
    LiveSession session = LiveSession(
      id: 'session-1',
      planSnapshot: _twoStepSnapshot(),
      hostDeviceId: 'host-1',
    );
    session = _apply(
      session,
      SessionCommand.start(
        id: 'start-1',
        sessionId: session.id,
        actorDeviceId: 'host-1',
        actorRole: SessionRole.host,
        baseRevision: session.revision,
        issuedAt: start,
      ),
      start,
    );
    session = _apply(
      session,
      SessionCommand.advance(
        id: 'advance-1',
        sessionId: session.id,
        actorDeviceId: 'host-1',
        actorRole: SessionRole.host,
        baseRevision: session.revision,
        issuedAt: start.add(const Duration(seconds: 30)),
      ),
      start.add(const Duration(seconds: 30)),
    );
    session = _apply(
      session,
      SessionCommand.advance(
        id: 'complete-1',
        sessionId: session.id,
        actorDeviceId: 'host-1',
        actorRole: SessionRole.host,
        baseRevision: session.revision,
        issuedAt: start.add(const Duration(seconds: 60)),
      ),
      start.add(const Duration(seconds: 60)),
    );

    final SessionSummaryViewData summary = mapSessionSummaryView(
      session: session,
      now: start.add(const Duration(seconds: 60)),
    );

    expect(
      summary.steps.map<bool>((StepSummaryViewData step) => step.wasCompleted),
      everyElement(isTrue),
    );
    expect(summary.endReason, SessionEndReason.completed);
  });
}

LiveSessionViewData _map(LiveSession session, DateTime now) {
  return mapLiveSessionView(
    session: session,
    role: SessionRole.host,
    deviceId: 'host-1',
    currentDeviceDisplayName: 'Host',
    hostDisplayName: 'Host',
    now: now,
    isStale: false,
  );
}

LiveSession _startSession({
  required DateTime start,
  int durationSeconds = 120,
  CueProfile? cueOverride,
}) {
  final LiveSession waiting = LiveSession(
    id: 'session-1',
    planSnapshot: _snapshot(
      durationSeconds: durationSeconds,
      cueOverride: cueOverride,
    ),
    hostDeviceId: 'host-1',
  );
  return _apply(
    waiting,
    SessionCommand.start(
      id: 'start-1',
      sessionId: waiting.id,
      actorDeviceId: 'host-1',
      actorRole: SessionRole.host,
      baseRevision: waiting.revision,
      issuedAt: start,
    ),
    start,
  );
}

PlanSnapshot _snapshot({int durationSeconds = 120, CueProfile? cueOverride}) {
  return PlanSnapshot(
    sourcePlanId: 'plan-1',
    title: 'Event run of show',
    defaultCueProfile: CueProfile(),
    steps: <Step>[
      Step(
        id: 'step-1',
        planId: 'plan-1',
        position: 0,
        title: 'Opening keynote',
        durationSeconds: durationSeconds,
        cueOverride: cueOverride,
      ),
    ],
    capturedAt: DateTime.utc(2026, 7, 28, 13),
  );
}

PlanSnapshot _twoStepSnapshot() {
  return PlanSnapshot(
    sourcePlanId: 'plan-1',
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
      Step(
        id: 'step-2',
        planId: 'plan-1',
        position: 1,
        title: 'Audience questions',
        durationSeconds: 120,
      ),
    ],
    capturedAt: DateTime.utc(2026, 7, 28, 13),
  );
}

LiveSession _apply(
  LiveSession session,
  SessionCommand command,
  DateTime occurredAt,
) {
  return SessionReducer.applyCommand(
    session: session,
    command: command,
    occurredAt: occurredAt,
  ).session;
}
