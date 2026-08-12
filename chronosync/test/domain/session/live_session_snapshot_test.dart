import 'dart:convert';

import 'package:chronosync/data/transports/session_crypto.dart';
import 'package:chronosync/domain/plan/plan.dart';
import 'package:chronosync/domain/session/live_session.dart';
import 'package:chronosync/domain/session/session_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('wire snapshots bound history without changing the source session', () {
    final LiveSession source = _loadedSession(activityCount: 200);

    final LiveSessionSnapshot snapshot = LiveSessionSnapshot.fromSession(
      source,
    );
    final LiveSession replica = LiveSessionSnapshot.fromJson(
      snapshot.toJson(),
    ).mergeOnto(null);

    expect(source.activities, hasLength(200));
    expect(source.hasCompleteActivityHistory, isTrue);
    expect(replica.activities, hasLength(maxLiveSnapshotActivities));
    expect(replica.activityRevisionOffset, 200 - maxLiveSnapshotActivities);
    expect(replica.revision, source.revision);
    expect(replica.hasCompleteActivityHistory, isFalse);
  });

  test('sequential wire snapshots retain a complete replica history', () {
    final LiveSession first = _loadedSession(activityCount: 60);
    final LiveSession second = _loadedSession(activityCount: 80);
    final LiveSession initialReplica = LiveSessionSnapshot.fromJson(
      LiveSessionSnapshot.fromSession(first).toJson(),
    ).mergeOnto(null);

    final LiveSession updatedReplica = LiveSessionSnapshot.fromJson(
      LiveSessionSnapshot.fromSession(second).toJson(),
    ).mergeOnto(initialReplica);

    expect(updatedReplica.activities, hasLength(80));
    expect(updatedReplica.activityRevisionOffset, 0);
    expect(updatedReplica.hasCompleteActivityHistory, isTrue);
  });

  test(
    'wire snapshots omit removed participants without changing host history',
    () {
      final LiveSession source = _loadedSession(
        activityCount: 2,
        participantCount: 2,
        disconnectedParticipantStart: 1,
      );

      final LiveSession snapshot = LiveSessionSnapshot.fromSession(
        source,
      ).session;

      expect(source.participants, hasLength(2));
      expect(snapshot.participants, hasLength(1));
      expect(snapshot.participants.single.deviceId, 'participant-000');
    },
  );

  test(
    'maximum acceptance-load snapshot remains below relay frame limit',
    () async {
      final LiveSession source = _loadedSession(
        activityCount: 12500,
        stepCount: 250,
        participantCount: maxSessionParticipants,
        disconnectedParticipantStart: maxConnectedSessionParticipants,
        maximumText: true,
      );
      const String secret = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
      final SessionEnvelope envelope = await SessionEnvelopeCrypto(secret).seal(
        sessionId: source.id,
        messageId: 'maximum-load-snapshot',
        senderDeviceId: source.hostDeviceId,
        baseRevision: source.revision,
        sentAt: DateTime.utc(2026, 7, 29, 12),
        kind: SessionMessageKind.snapshot,
        payload: <String, Object?>{
          'type': 'snapshot',
          'session': LiveSessionSnapshot.fromSession(source).toJson(),
        },
      );
      final RelayCiphertext relay = await RelayPayloadCrypto(
        secret,
      ).seal(envelope);
      final String frame = jsonEncode(<String, Object?>{
        'type': 'snapshot',
        'messageId': envelope.messageId,
        'revision': envelope.baseRevision,
        'sentAt': envelope.sentAt.toIso8601String(),
        'nonce': relay.nonce,
        'ciphertext': relay.ciphertext,
      });

      expect(utf8.encode(frame).length, lessThan(256 * 1024));
      expect(source.activities, hasLength(12500));
      expect(source.hasCompleteActivityHistory, isTrue);
    },
  );
}

LiveSession _loadedSession({
  required int activityCount,
  int stepCount = 2,
  int participantCount = 1,
  int? disconnectedParticipantStart,
  bool maximumText = false,
}) {
  final DateTime timestamp = DateTime.utc(2026, 7, 29, 12);
  final String planTitle = maximumText ? 'P' * 160 : 'Live show';
  final String stepTitle = maximumText ? 'S' * 240 : 'Step';
  final List<Participant> participants = List<Participant>.generate(
    participantCount,
    (int index) => Participant(
      deviceId: _participantDeviceId(index, maximumText: maximumText),
      displayName: maximumText
          ? 'N' * maxParticipantDisplayNameLength
          : 'Person $index',
      role: SessionRole.participant,
      joinedAt: timestamp,
      lastSeenRevision: activityCount,
      connectionState:
          disconnectedParticipantStart != null &&
              index >= disconnectedParticipantStart
          ? ParticipantConnectionState.disconnected
          : ParticipantConnectionState.connected,
      acknowledgedStepIndex: 0,
      acknowledgedAt: timestamp.add(Duration(seconds: activityCount)),
    ),
    growable: false,
  );
  final Plan plan = Plan(
    id: 'plan',
    title: planTitle,
    defaultCueProfile: CueProfile(),
    steps: List<Step>.generate(
      stepCount,
      (int index) => Step(
        id: 'step-${index.toString().padLeft(3, '0')}',
        planId: 'plan',
        position: index,
        title: stepTitle,
        durationSeconds: 60,
      ),
      growable: false,
    ),
    createdAt: timestamp,
    updatedAt: timestamp,
  );
  final List<Activity> activities = List<Activity>.generate(activityCount, (
    int index,
  ) {
    final int revision = index + 1;
    return Activity(
      id: 'activity-$revision',
      commandId: 'command-$revision',
      sessionId: 'session',
      revision: revision,
      type: ActivityType.acknowledged,
      stepIndex: 0,
      stepId: 'step-000',
      actorDeviceId: _participantDeviceId(
        index % participantCount,
        maximumText: maximumText,
      ),
      actorRole: SessionRole.participant,
      occurredAt: timestamp.add(Duration(seconds: revision)),
    );
  }, growable: false);
  return LiveSession(
    id: 'session',
    planSnapshot: plan.snapshot(capturedAt: timestamp),
    hostDeviceId: 'host',
    revision: activityCount,
    participants: participants,
    activities: activities,
  );
}

String _participantDeviceId(int index, {required bool maximumText}) {
  final String prefix = '${index.toString().padLeft(3, '0')}-';
  return maximumText
      ? '$prefix${'d' * (maxSessionDeviceIdLength - prefix.length)}'
      : 'participant-${index.toString().padLeft(3, '0')}';
}
