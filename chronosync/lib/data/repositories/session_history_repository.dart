import 'dart:convert';

import 'package:chronosync/data/database/app_database.dart';
import 'package:chronosync/domain/session/live_session.dart';
import 'package:chronosync/domain/session/session_protocol.dart';
import 'package:drift/drift.dart';

/// How a persisted session may be recovered after the process exits.
///
/// Shared sessions deliberately remain non-resumable until their transport
/// credentials and host authority can be restored safely.
enum SessionRecoveryKind { solo, sharedHost, sharedParticipant }

const int maxSessionHistoryQueryLimit = 500;

abstract interface class SessionHistoryRepository {
  Stream<List<LiveSession>> watchSessions({int limit = 50});

  Future<List<LiveSession>> getSessions({int limit = 50});

  Future<LiveSession?> getSession(String id);

  Future<LiveSession?> prepareStartupRecovery({required String hostDeviceId});

  Future<void> saveSession(
    LiveSession session, {
    required String hostDisplayName,
    required SessionRecoveryKind recoveryKind,
  });

  Future<void> deleteSession(String id);
}

final class DriftSessionHistoryRepository implements SessionHistoryRepository {
  const DriftSessionHistoryRepository(this._database);

  static const String _recoveryMetadataPrefix = 'session-recovery-kind:';

  final AppDatabase _database;

  @override
  Stream<List<LiveSession>> watchSessions({int limit = 50}) {
    _validateHistoryLimit(limit);
    final SimpleSelectStatement<$SessionRecordsTable, SessionRecord> query =
        _database.select(_database.sessionRecords)
          ..where(
            ($SessionRecordsTable table) =>
                table.status.equals(LiveSessionStatus.ended.name),
          )
          ..orderBy(<OrderClauseGenerator<$SessionRecordsTable>>[
            ($SessionRecordsTable table) =>
                OrderingTerm.desc(table.createdAtMillis),
          ])
          ..limit(limit);
    return query.watch().asyncMap(_decodeSessions);
  }

  @override
  Future<List<LiveSession>> getSessions({int limit = 50}) async {
    _validateHistoryLimit(limit);
    final List<SessionRecord> rows =
        await (_database.select(_database.sessionRecords)
              ..where(
                ($SessionRecordsTable table) =>
                    table.status.equals(LiveSessionStatus.ended.name),
              )
              ..orderBy(<OrderClauseGenerator<$SessionRecordsTable>>[
                ($SessionRecordsTable table) =>
                    OrderingTerm.desc(table.createdAtMillis),
              ])
              ..limit(limit))
            .get();
    return _decodeSessions(rows);
  }

  @override
  Future<LiveSession?> getSession(String id) async {
    final String normalizedId = _requireSessionId(id);
    final SessionRecord? row =
        await (_database.select(_database.sessionRecords)..where(
              ($SessionRecordsTable table) => table.id.equals(normalizedId),
            ))
            .getSingleOrNull();
    if (row == null) {
      return null;
    }
    final Map<String, List<ActivityRecord>> activities =
        await _activityRowsForSessions(<String>[row.id]);
    return _decodeSession(row, activities[row.id] ?? const <ActivityRecord>[]);
  }

  @override
  Future<LiveSession?> prepareStartupRecovery({
    required String hostDeviceId,
  }) async {
    final String normalizedHostDeviceId = hostDeviceId.trim();
    if (normalizedHostDeviceId.isEmpty) {
      throw ArgumentError.value(
        hostDeviceId,
        'hostDeviceId',
        'A recovery host device ID cannot be empty.',
      );
    }
    final List<SessionRecord> rows =
        await (_database.select(_database.sessionRecords)
              ..where(
                ($SessionRecordsTable table) => table.status.isIn(<String>[
                  LiveSessionStatus.waiting.name,
                  LiveSessionStatus.running.name,
                  LiveSessionStatus.paused.name,
                ]),
              )
              ..orderBy(<OrderClauseGenerator<$SessionRecordsTable>>[
                ($SessionRecordsTable table) =>
                    OrderingTerm.desc(table.createdAtMillis),
              ]))
            .get();
    final Map<String, List<ActivityRecord>> activityRows =
        await _activityRowsForSessions(
          rows.map((SessionRecord row) => row.id).toList(growable: false),
        );
    LiveSession? recoverableSession;
    for (final SessionRecord row in rows) {
      final AppMetadataRecord? recoveryMetadata =
          await (_database.select(_database.appMetadataRecords)..where(
                ($AppMetadataRecordsTable table) =>
                    table.key.equals(_recoveryMetadataKey(row.id)),
              ))
              .getSingleOrNull();
      if (recoveryMetadata?.value != SessionRecoveryKind.solo.name) {
        continue;
      }
      try {
        final LiveSession session = _decodeSession(
          row,
          activityRows[row.id] ?? const <ActivityRecord>[],
        );
        if (recoverableSession == null &&
            session.hostDeviceId == normalizedHostDeviceId &&
            session.participants.isEmpty &&
            session.hasCompleteActivityHistory) {
          recoverableSession = session;
        }
      } on Object {
        // A malformed active snapshot is not allowed to block startup. It is
        // discarded with the other non-recoverable active rows below.
      }
    }

    await _database.transaction(() async {
      for (final SessionRecord row in rows) {
        if (row.id == recoverableSession?.id) {
          continue;
        }
        await (_database.delete(
          _database.sessionRecords,
        )..where(($SessionRecordsTable table) => table.id.equals(row.id))).go();
        await _deleteRecoveryMetadata(row.id);
      }
    });
    return recoverableSession;
  }

  @override
  Future<void> saveSession(
    LiveSession session, {
    required String hostDisplayName,
    required SessionRecoveryKind recoveryKind,
  }) async {
    final String normalizedHostDisplayName = hostDisplayName.trim();
    if (normalizedHostDisplayName.isEmpty ||
        normalizedHostDisplayName.length > maxParticipantDisplayNameLength) {
      throw ArgumentError.value(
        hostDisplayName,
        'hostDisplayName',
        'A host display name must be '
            '1–$maxParticipantDisplayNameLength characters.',
      );
    }
    final Map<String, String> participantNames = <String, String>{
      for (final Participant participant in session.participants)
        participant.deviceId: participant.displayName,
      session.hostDeviceId: normalizedHostDisplayName,
    };
    await _database.transaction(() async {
      final SessionRecord? existing =
          await (_database.select(_database.sessionRecords)..where(
                ($SessionRecordsTable table) => table.id.equals(session.id),
              ))
              .getSingleOrNull();
      if (existing != null && existing.lastRevision > session.revision) {
        throw StateError(
          'A stored session cannot be replaced by an older revision.',
        );
      }
      final ActivityRecord? latestStoredActivity =
          await (_database.select(_database.activityRecords)
                ..where(
                  ($ActivityRecordsTable table) =>
                      table.sessionId.equals(session.id),
                )
                ..orderBy(<OrderClauseGenerator<$ActivityRecordsTable>>[
                  ($ActivityRecordsTable table) =>
                      OrderingTerm.desc(table.revision),
                ])
                ..limit(1))
              .getSingleOrNull();
      _validateStoredActivityTail(
        existing: existing,
        latestActivity: latestStoredActivity,
        incoming: session,
      );
      final List<Activity> newActivities = _activitiesAfterStoredTail(
        session,
        latestStoredActivity?.revision,
      );

      await _database
          .into(_database.sessionRecords)
          .insertOnConflictUpdate(
            SessionRecordsCompanion.insert(
              id: session.id,
              planId: Value<String?>(session.planSnapshot.sourcePlanId),
              planTitle: session.planSnapshot.title,
              planSnapshotJson: jsonEncode(session.planSnapshot.toJson()),
              sessionStateJson: jsonEncode(
                LiveSessionSnapshot.fromSession(session).toJson(),
              ),
              status: session.status.name,
              startedAtMillis: Value<int?>(
                session.startedAt?.millisecondsSinceEpoch,
              ),
              endedAtMillis: Value<int?>(
                session.endedAt?.millisecondsSinceEpoch,
              ),
              lastRevision: Value<int>(session.revision),
              createdAtMillis:
                  session.planSnapshot.capturedAt.millisecondsSinceEpoch,
            ),
          );

      if (session.status == LiveSessionStatus.ended) {
        await _deleteRecoveryMetadata(session.id);
      } else {
        await _database
            .into(_database.appMetadataRecords)
            .insertOnConflictUpdate(
              AppMetadataRecordsCompanion.insert(
                key: _recoveryMetadataKey(session.id),
                value: recoveryKind.name,
              ),
            );
      }

      if (newActivities.isNotEmpty) {
        await _database.batch((Batch batch) {
          batch.insertAll(
            _database.activityRecords,
            newActivities
                .map<ActivityRecordsCompanion>(
                  (Activity activity) => ActivityRecordsCompanion.insert(
                    id: activity.id,
                    sessionId: activity.sessionId,
                    revision: activity.revision,
                    commandId: Value<String?>(activity.commandId),
                    type: activity.type.name,
                    stepId: Value<String?>(activity.stepId),
                    stepIndex: Value<int?>(activity.stepIndex),
                    actorDeviceId: activity.actorDeviceId,
                    actorDisplayName:
                        activity.actorDisplayName ??
                        participantNames[activity.actorDeviceId] ??
                        'Unknown device',
                    actorRole: activity.actorRole.name,
                    occurredAtMillis:
                        activity.occurredAt.millisecondsSinceEpoch,
                    payloadJson: jsonEncode(activity.payload),
                  ),
                )
                .toList(growable: false),
          );
        });
      }
    });
  }

  @override
  Future<void> deleteSession(String id) async {
    final String normalizedId = _requireSessionId(id);
    await _database.transaction(() async {
      await (_database.delete(_database.sessionRecords)..where(
            ($SessionRecordsTable table) => table.id.equals(normalizedId),
          ))
          .go();
      await _deleteRecoveryMetadata(normalizedId);
    });
  }

  Future<void> _deleteRecoveryMetadata(String sessionId) async {
    await (_database.delete(_database.appMetadataRecords)..where(
          ($AppMetadataRecordsTable table) =>
              table.key.equals(_recoveryMetadataKey(sessionId)),
        ))
        .go();
  }

  String _recoveryMetadataKey(String sessionId) {
    return '$_recoveryMetadataPrefix$sessionId';
  }

  Future<List<LiveSession>> _decodeSessions(List<SessionRecord> rows) async {
    if (rows.isEmpty) {
      return const <LiveSession>[];
    }
    final Map<String, List<ActivityRecord>> activities =
        await _activityRowsForSessions(
          rows.map((SessionRecord row) => row.id).toList(growable: false),
        );
    return rows
        .map(
          (SessionRecord row) => _decodeSession(
            row,
            activities[row.id] ?? const <ActivityRecord>[],
          ),
        )
        .toList(growable: false);
  }

  Future<Map<String, List<ActivityRecord>>> _activityRowsForSessions(
    List<String> sessionIds,
  ) async {
    if (sessionIds.isEmpty) {
      return const <String, List<ActivityRecord>>{};
    }
    final List<ActivityRecord> rows =
        await (_database.select(_database.activityRecords)
              ..where(
                ($ActivityRecordsTable table) =>
                    table.sessionId.isIn(sessionIds),
              )
              ..orderBy(<OrderClauseGenerator<$ActivityRecordsTable>>[
                ($ActivityRecordsTable table) =>
                    OrderingTerm.asc(table.sessionId),
                ($ActivityRecordsTable table) =>
                    OrderingTerm.asc(table.revision),
              ]))
            .get();
    final Map<String, List<ActivityRecord>> result =
        <String, List<ActivityRecord>>{};
    for (final ActivityRecord row in rows) {
      result.putIfAbsent(row.sessionId, () => <ActivityRecord>[]).add(row);
    }
    return result;
  }

  LiveSession _decodeSession(
    SessionRecord row,
    List<ActivityRecord> activityRows,
  ) {
    final Object? decoded = jsonDecode(row.sessionStateJson);
    if (decoded is! Map<Object?, Object?>) {
      throw const FormatException('A stored session is malformed.');
    }
    final LiveSession session = LiveSession.fromJson(
      Map<String, Object?>.from(decoded),
    );
    if (activityRows.isEmpty) {
      return session;
    }
    final Map<String, Activity> snapshotActivities = <String, Activity>{
      for (final Activity activity in session.activities) activity.id: activity,
    };
    final List<Activity> activities = activityRows
        .map<Activity>(
          (ActivityRecord activity) => _decodeActivity(
            activity,
            fallbackCommandId: snapshotActivities[activity.id]?.commandId,
          ),
        )
        .toList(growable: false);
    return session.copyWith(
      activityRevisionOffset: activities.first.revision - 1,
      activities: activities,
    );
  }

  Activity _decodeActivity(
    ActivityRecord row, {
    required String? fallbackCommandId,
  }) {
    final Object? payload = jsonDecode(row.payloadJson);
    if (payload is! Map<Object?, Object?>) {
      throw const FormatException('A stored activity payload is malformed.');
    }
    return Activity(
      id: row.id,
      commandId: row.commandId ?? fallbackCommandId ?? row.id,
      sessionId: row.sessionId,
      revision: row.revision,
      type: ActivityType.values.byName(row.type),
      stepId: row.stepId,
      stepIndex: row.stepIndex,
      actorDeviceId: row.actorDeviceId,
      actorDisplayName: row.actorDisplayName,
      actorRole: SessionRole.values.byName(row.actorRole),
      occurredAt: DateTime.fromMillisecondsSinceEpoch(
        row.occurredAtMillis,
        isUtc: true,
      ),
      payload: Map<String, Object?>.from(payload),
    );
  }
}

void _validateStoredActivityTail({
  required SessionRecord? existing,
  required ActivityRecord? latestActivity,
  required LiveSession incoming,
}) {
  if (existing == null) {
    if (latestActivity != null) {
      throw StateError('Activity history exists without a session record.');
    }
    return;
  }
  final int? latestActivityRevision = latestActivity?.revision;
  if (existing.lastRevision == 0) {
    if (latestActivityRevision != null) {
      throw StateError(
        'A revision-zero session cannot have persisted activities.',
      );
    }
    return;
  }
  if (latestActivityRevision == null &&
      incoming.activityRevisionOffset == existing.lastRevision) {
    // A compact replica may retain only the revision offset. Its next window
    // can still begin immediately after the persisted offset.
    return;
  }
  if (latestActivityRevision != existing.lastRevision) {
    throw StateError(
      'The stored session revision does not match its activity tail.',
    );
  }
}

List<Activity> _activitiesAfterStoredTail(
  LiveSession session,
  int? latestStoredRevision,
) {
  if (latestStoredRevision == null) {
    return List<Activity>.of(session.activities, growable: false);
  }
  if (latestStoredRevision > session.revision) {
    throw StateError('Stored activity history is newer than the session.');
  }
  if (latestStoredRevision < session.activityRevisionOffset) {
    throw StateError(
      'The compact activity window cannot bridge the stored revision.',
    );
  }
  final int firstNewIndex =
      latestStoredRevision - session.activityRevisionOffset;
  if (firstNewIndex < 0 || firstNewIndex > session.activities.length) {
    throw StateError('The stored activity revision is outside the session.');
  }
  return List<Activity>.generate(
    session.activities.length - firstNewIndex,
    (int index) => session.activities[firstNewIndex + index],
    growable: false,
  );
}

void _validateHistoryLimit(int limit) {
  if (limit <= 0 || limit > maxSessionHistoryQueryLimit) {
    throw ArgumentError.value(
      limit,
      'limit',
      'A session history limit must be between 1 and '
          '$maxSessionHistoryQueryLimit.',
    );
  }
}

String _requireSessionId(String id) {
  final String normalized = id.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(id, 'id', 'A session ID cannot be empty.');
  }
  return normalized;
}
