import 'package:chronosync/data/portability/session_csv_exporter.dart';
import 'package:chronosync/domain/plan/plan.dart';
import 'package:chronosync/domain/session/live_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rejects export when the activity history is incomplete', () {
    final LiveSession session = _incompleteSession();

    expect(
      () => const SessionCsvExporter().export(
        session,
        hostDisplayName: 'Event lead',
      ),
      throwsA(
        isA<StateError>().having(
          (StateError error) => error.message,
          'message',
          contains('complete activity history'),
        ),
      ),
    );
  });

  test(
    'neutralizes formulas in untrusted text without changing numeric fields',
    () {
      final DateTime startedAt = DateTime.utc(2026, 7, 29, 12);
      final PlanSnapshot snapshot = PlanSnapshot(
        sourcePlanId: 'plan-1',
        title: '=PLAN',
        plannedStartTime: startedAt,
        defaultCueProfile: CueProfile(),
        steps: <Step>[
          Step(
            id: 'step-1',
            planId: 'plan-1',
            position: 0,
            title: '+STEP',
            durationSeconds: 60,
          ),
        ],
        capturedAt: startedAt.subtract(const Duration(hours: 1)),
      );
      final Participant participant = Participant(
        deviceId: 'participant-1',
        displayName: '-PARTICIPANT',
        role: SessionRole.participant,
        joinedAt: startedAt.subtract(const Duration(minutes: 1)),
      );
      final List<Activity> activities = <Activity>[
        Activity(
          id: 'activity-1',
          commandId: 'command-1',
          sessionId: '=SESSION',
          revision: 1,
          type: ActivityType.acknowledged,
          stepIndex: 0,
          stepId: 'step-1',
          actorDeviceId: participant.deviceId,
          actorRole: participant.role,
          occurredAt: startedAt.subtract(const Duration(seconds: 1)),
        ),
        Activity(
          id: 'activity-2',
          commandId: 'command-2',
          sessionId: '=SESSION',
          revision: 2,
          type: ActivityType.started,
          stepIndex: 0,
          stepId: 'step-1',
          actorDeviceId: 'host-1',
          actorRole: SessionRole.host,
          occurredAt: startedAt,
        ),
      ];
      final LiveSession session = LiveSession(
        id: '=SESSION',
        planSnapshot: snapshot,
        hostDeviceId: 'host-1',
        status: LiveSessionStatus.running,
        revision: activities.length,
        startedAt: startedAt,
        currentStepStartedAt: startedAt,
        participants: <Participant>[participant],
        activities: activities,
      );

      final String csv = const SessionCsvExporter().export(
        session,
        hostDisplayName: '@HOST',
      );

      expect(csv, contains("'=PLAN"));
      expect(csv, contains("'+STEP"));
      expect(csv, contains("'-PARTICIPANT"));
      expect(csv, contains("'@HOST"));
      expect(csv, contains("'=SESSION"));
      expect(csv, contains(',-1\r\n'));
      expect(csv, isNot(contains(",'-1\r\n")));

      for (final String unsafeHostName in <String>[
        ' =HOST',
        '\t=HOST',
        '\r=HOST',
        '\tHOST',
        '\rHOST',
      ]) {
        final String prefixedCsv = const SessionCsvExporter().export(
          session,
          hostDisplayName: unsafeHostName,
        );
        expect(
          prefixedCsv,
          contains("'$unsafeHostName"),
          reason: 'leading whitespace must not hide a spreadsheet formula',
        );
      }
    },
  );
}

LiveSession _incompleteSession() {
  final DateTime startedAt = DateTime.utc(2026, 7, 29, 12);
  final PlanSnapshot snapshot = PlanSnapshot(
    sourcePlanId: 'plan-1',
    title: 'Event run of show',
    defaultCueProfile: CueProfile(),
    steps: <Step>[
      Step(
        id: 'step-1',
        planId: 'plan-1',
        position: 0,
        title: 'Opening keynote',
        durationSeconds: 60,
      ),
    ],
    capturedAt: startedAt.subtract(const Duration(hours: 1)),
  );
  final Activity recentActivity = Activity(
    id: 'activity-5',
    commandId: 'command-5',
    sessionId: 'session-1',
    revision: 5,
    type: ActivityType.acknowledged,
    stepIndex: 0,
    stepId: 'step-1',
    actorDeviceId: 'participant-1',
    actorRole: SessionRole.participant,
    occurredAt: startedAt.add(const Duration(seconds: 30)),
  );
  return LiveSession(
    id: 'session-1',
    planSnapshot: snapshot,
    hostDeviceId: 'host-1',
    status: LiveSessionStatus.running,
    revision: 5,
    activityRevisionOffset: 4,
    startedAt: startedAt,
    currentStepStartedAt: startedAt,
    activities: <Activity>[recentActivity],
  );
}
