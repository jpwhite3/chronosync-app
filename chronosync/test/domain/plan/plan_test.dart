import 'package:chronosync/domain/plan/plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final DateTime createdAt = DateTime.utc(2026, 7, 28, 12);
  final DateTime updatedAt = createdAt.add(const Duration(minutes: 5));

  Step step({
    required String id,
    required int position,
    int durationSeconds = 60,
    CueProfile? cueOverride,
  }) {
    return Step(
      id: id,
      planId: 'plan-1',
      position: position,
      title: 'Step $id',
      durationSeconds: durationSeconds,
      cueOverride: cueOverride,
    );
  }

  Plan plan({Iterable<Step>? steps}) {
    return Plan(
      id: 'plan-1',
      title: 'Evening show',
      plannedStartTime: DateTime.utc(2026, 7, 29, 19),
      defaultCueProfile: CueProfile(),
      steps:
          steps ??
          <Step>[
            step(id: 'step-1', position: 0, durationSeconds: 90),
            step(
              id: 'step-2',
              position: 1,
              durationSeconds: 30,
              cueOverride: CueProfile(approachingSeconds: 10),
            ),
          ],
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  group('Plan models', () {
    test('rejects titles that cannot be persisted by the local database', () {
      expect(
        () => plan().copyWith(
          title: List<String>.filled(maxPlanTitleLength + 1, 'P').join(),
        ),
        throwsArgumentError,
      );
      expect(
        () => Step(
          id: 'step-too-long',
          planId: 'plan-1',
          position: 0,
          title: List<String>.filled(maxStepTitleLength + 1, 'S').join(),
          durationSeconds: 60,
        ),
        throwsArgumentError,
      );
    });

    test('bounds step durations to the supported editor range', () {
      expect(
        Step(
          id: 'maximum',
          planId: 'plan-1',
          position: 0,
          title: 'Maximum duration',
          durationSeconds: maxStepDurationSeconds,
        ).durationSeconds,
        maxStepDurationSeconds,
      );
      expect(
        () => Step(
          id: 'too-long',
          planId: 'plan-1',
          position: 0,
          title: 'Too long',
          durationSeconds: maxStepDurationSeconds + 1,
        ),
        throwsArgumentError,
      );
    });

    test('sorts steps by stable position and calculates total duration', () {
      final Plan value = plan(
        steps: <Step>[
          step(id: 'step-2', position: 1, durationSeconds: 30),
          step(id: 'step-1', position: 0, durationSeconds: 90),
        ],
      );

      expect(value.steps.map((Step item) => item.id), <String>[
        'step-1',
        'step-2',
      ]);
      expect(value.totalDuration, const Duration(minutes: 2));
    });

    test('defensively copies its ordered step collection', () {
      final List<Step> mutableSteps = <Step>[step(id: 'step-1', position: 0)];
      final Plan value = plan(steps: mutableSteps);

      mutableSteps.add(step(id: 'step-2', position: 1));

      expect(value.steps, hasLength(1));
      expect(
        () => value.steps.add(step(id: 'step-2', position: 1)),
        throwsUnsupportedError,
      );
    });

    test('rejects gaps, duplicate IDs, and cross-plan steps', () {
      expect(
        () => plan(steps: <Step>[step(id: 'step-1', position: 1)]),
        throwsArgumentError,
      );
      expect(
        () => plan(
          steps: <Step>[
            step(id: 'same', position: 0),
            step(id: 'same', position: 1),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => plan(
          steps: <Step>[
            Step(
              id: 'other',
              planId: 'other-plan',
              position: 0,
              title: 'Other',
              durationSeconds: 10,
            ),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('caps plans at the supported 250-step session size', () {
      final List<Step> maximum = List<Step>.generate(
        maxPlanSteps,
        (int index) => step(id: 'step-$index', position: index),
      );

      expect(plan(steps: maximum).steps, hasLength(maxPlanSteps));
      expect(
        () => plan(
          steps: <Step>[
            ...maximum,
            step(id: 'step-$maxPlanSteps', position: maxPlanSteps),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('copyWith preserves identity and can clear a scheduled start', () {
      final Plan original = plan();
      final Plan changed = original.copyWith(
        title: 'Updated show',
        plannedStartTime: null,
        updatedAt: updatedAt.add(const Duration(minutes: 1)),
      );

      expect(changed.id, original.id);
      expect(changed.title, 'Updated show');
      expect(changed.plannedStartTime, isNull);
      expect(changed.steps, original.steps);
    });

    test('round-trips plan, step, cue profile, and snapshot JSON', () {
      final Plan original = plan();
      final Plan decoded = Plan.fromJson(original.toJson());
      final PlanSnapshot snapshot = original.snapshot(
        capturedAt: updatedAt.add(const Duration(minutes: 1)),
      );

      expect(decoded, original);
      expect(
        Step.fromJson(original.steps.first.toJson()),
        original.steps.first,
      );
      expect(
        CueProfile.fromJson(original.defaultCueProfile.toJson()),
        original.defaultCueProfile,
      );
      expect(PlanSnapshot.fromJson(snapshot.toJson()), snapshot);
      expect(snapshot.plannedOffsetForStep(1), const Duration(seconds: 90));
    });

    test('rejects unsupported schema versions', () {
      final Map<String, Object?> json = plan().toJson()
        ..['schemaVersion'] = 999;

      expect(() => Plan.fromJson(json), throwsFormatException);
    });

    test('persisted timestamps require an explicit time zone', () {
      final Map<String, Object?> missingZone = plan().toJson()
        ..['createdAt'] = '2026-07-28T12:00:00';
      final Map<String, Object?> explicitOffset = plan().toJson()
        ..['createdAt'] = '2026-07-28T08:00:00-04:00';

      expect(() => Plan.fromJson(missingZone), throwsFormatException);
      expect(Plan.fromJson(explicitOffset).createdAt, createdAt);
    });
  });

  group('CueProfile', () {
    test('rejects non-positive thresholds through the public constructor', () {
      expect(() => CueProfile(approachingSeconds: 0), throwsArgumentError);
      expect(() => CueProfile(overdueSeconds: -1), throwsArgumentError);
    });

    test('rejects invalid persisted cue thresholds as malformed JSON', () {
      final Map<String, Object?> json = CueProfile().toJson()
        ..['approachingSeconds'] = 0;

      expect(() => CueProfile.fromJson(json), throwsFormatException);
    });

    test('omits the default approaching cue for short steps', () {
      final CueProfile profile = CueProfile(approachingSeconds: 60);

      expect(
        profile.includesApproachingCueFor(const Duration(seconds: 30)),
        isFalse,
      );
      expect(
        profile.includesApproachingCueFor(
          const Duration(seconds: 30),
          isStepOverride: true,
        ),
        isTrue,
      );
      expect(
        profile.includesApproachingCueFor(const Duration(seconds: 61)),
        isTrue,
      );
    });
  });
}
