import 'package:chronosync/domain/plan/plan.dart';
import 'package:chronosync/domain/session/live_session.dart';

final class SessionCsvExporter {
  const SessionCsvExporter();

  String export(LiveSession session, {required String hostDisplayName}) {
    if (!session.hasCompleteActivityHistory) {
      throw StateError(
        'CSV export requires a complete activity history. '
        'Export from the host device instead.',
      );
    }
    final Map<String, String> names = <String, String>{
      for (final Participant participant in session.participants)
        participant.deviceId: participant.displayName,
      session.hostDeviceId: hostDisplayName,
    };
    final List<List<String>> rows = <List<String>>[
      <String>[
        'session_id',
        'plan',
        'revision',
        'step_index',
        'step',
        'actor',
        'role',
        'action',
        'planned_step_start',
        'actual_action_at',
        'planned_duration_seconds',
        'variance_seconds',
      ],
    ];

    for (final Activity activity in session.activities) {
      final int? stepIndex = activity.stepIndex;
      final Step? step =
          stepIndex != null &&
              stepIndex >= 0 &&
              stepIndex < session.planSnapshot.steps.length
          ? session.planSnapshot.steps[stepIndex]
          : null;
      final DateTime? baseline =
          session.planSnapshot.plannedStartTime ?? session.startedAt;
      final DateTime? plannedStepStart = baseline == null || stepIndex == null
          ? null
          : baseline.add(session.planSnapshot.plannedOffsetForStep(stepIndex));
      final int? varianceSeconds = plannedStepStart == null
          ? null
          : activity.occurredAt.difference(plannedStepStart).inSeconds;

      rows.add(<String>[
        _spreadsheetSafeText(session.id),
        _spreadsheetSafeText(session.planSnapshot.title),
        activity.revision.toString(),
        stepIndex == null ? '' : (stepIndex + 1).toString(),
        _spreadsheetSafeText(step?.title ?? ''),
        _spreadsheetSafeText(
          activity.actorDisplayName ??
              names[activity.actorDeviceId] ??
              'Unknown device',
        ),
        activity.actorRole.name,
        activity.type.name,
        plannedStepStart?.toIso8601String() ?? '',
        activity.occurredAt.toIso8601String(),
        step?.durationSeconds.toString() ?? '',
        varianceSeconds?.toString() ?? '',
      ]);
    }

    return rows
        .map<String>((List<String> row) => row.map<String>(_escape).join(','))
        .join('\r\n');
  }

  String _spreadsheetSafeText(String value) {
    if (value.isEmpty) {
      return value;
    }
    final String trimmedLeft = value.trimLeft();
    final int leadingWhitespaceLength = value.length - trimmedLeft.length;
    bool containsDangerousControl = false;
    for (int index = 0; index < leadingWhitespaceLength; index += 1) {
      final int codeUnit = value.codeUnitAt(index);
      if (codeUnit == 0x09 || codeUnit == 0x0D) {
        containsDangerousControl = true;
        break;
      }
    }
    final bool containsFormula =
        trimmedLeft.isNotEmpty && '=+-@'.contains(trimmedLeft[0]);
    return containsDangerousControl || containsFormula ? "'$value" : value;
  }

  String _escape(String value) {
    if (!value.contains(',') &&
        !value.contains('"') &&
        !value.contains('\n') &&
        !value.contains('\r')) {
      return value;
    }
    return '"${value.replaceAll('"', '""')}"';
  }
}
