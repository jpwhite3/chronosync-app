import 'dart:async';
import 'dart:convert';

import 'package:chronosync/core/time/clock.dart';
import 'package:chronosync/data/repositories/device_identity_repository.dart';
import 'package:chronosync/data/repositories/session_history_repository.dart';
import 'package:chronosync/data/services/live_cue_service.dart';
import 'package:chronosync/data/transports/online_relay_transport.dart';
import 'package:chronosync/data/transports/session_crypto.dart';
import 'package:chronosync/domain/plan/plan.dart';
import 'package:chronosync/domain/session/live_session.dart';
import 'package:chronosync/domain/session/session_command.dart';
import 'package:chronosync/domain/session/session_protocol.dart';
import 'package:chronosync/domain/session/session_reducer.dart';
import 'package:chronosync/domain/session/session_transport.dart';
import 'package:chronosync/logic/live_session/live_session_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../data/transports/fake_web_socket_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('runs timestamp-derived solo controls and history', () async {
    final _MutableClock clock = _MutableClock(DateTime.utc(2026, 7, 28, 12));
    final _MemoryHistory history = _MemoryHistory();
    final LiveSessionController controller =
        await LiveSessionController.createSolo(
          plan: _plan(),
          identity: const DeviceIdentity(deviceId: 'host', displayName: 'Alex'),
          historyRepository: history,
          clock: clock,
        );
    addTearDown(() async {
      await controller.shutdown();
      controller.dispose();
    });

    await controller.start();
    clock.advance(const Duration(seconds: 4));
    await controller.refresh();
    expect(controller.elapsed, const Duration(seconds: 4));
    expect(controller.remaining, const Duration(seconds: 6));

    await controller.pause();
    clock.advance(const Duration(minutes: 2));
    expect(controller.elapsed, const Duration(seconds: 4));
    await controller.resume();
    clock.advance(const Duration(seconds: 1));
    expect(controller.elapsed, const Duration(seconds: 5));

    await controller.adjustRemaining(60);
    expect(controller.remaining, const Duration(seconds: 65));
    expect(history.saved.last.revision, controller.session!.revision);
  });

  test('notifies timer listeners only when displayed time changes', () async {
    final _MutableClock clock = _MutableClock(DateTime.utc(2026, 7, 28, 12));
    final LiveSessionController controller =
        await LiveSessionController.createSolo(
          plan: _plan(),
          identity: const DeviceIdentity(deviceId: 'host', displayName: 'Alex'),
          historyRepository: _MemoryHistory(),
          clock: clock,
        );
    addTearDown(() async {
      await controller.shutdown();
      controller.dispose();
    });
    await controller.start();
    await controller.refresh();
    int notifications = 0;
    controller.addListener(() => notifications += 1);

    await controller.refresh();
    clock.advance(const Duration(milliseconds: 100));
    await controller.refresh();

    expect(notifications, 0);

    clock.advance(const Duration(milliseconds: 900));
    await controller.refresh();
    await controller.refresh();

    expect(notifications, 1);
    expect(controller.elapsed, const Duration(seconds: 1));
  });

  test(
    'recovers running and paused solo sessions from their timestamps',
    () async {
      final _MutableClock clock = _MutableClock(DateTime.utc(2026, 7, 28, 12));
      final _MemoryHistory history = _MemoryHistory();
      const DeviceIdentity identity = DeviceIdentity(
        deviceId: 'host',
        displayName: 'Alex',
      );
      final LiveSessionController original =
          await LiveSessionController.createSolo(
            plan: _plan(),
            identity: identity,
            historyRepository: history,
            clock: clock,
          );
      await original.start();
      final LiveSession runningSnapshot = original.session!;
      await original.shutdown();
      original.dispose();

      clock.advance(const Duration(seconds: 4));
      final LiveSessionController recoveredRunning =
          await LiveSessionController.recoverSolo(
            session: runningSnapshot,
            identity: identity,
            historyRepository: history,
            clock: clock,
          );
      expect(recoveredRunning.elapsed, const Duration(seconds: 4));
      expect(recoveredRunning.remaining, const Duration(seconds: 6));
      expect(recoveredRunning.isShared, isFalse);
      expect(history.recoveryKinds.last, SessionRecoveryKind.solo);

      await recoveredRunning.pause();
      final LiveSession pausedSnapshot = recoveredRunning.session!;
      await recoveredRunning.shutdown();
      recoveredRunning.dispose();

      clock.advance(const Duration(hours: 2));
      final LiveSessionController recoveredPaused =
          await LiveSessionController.recoverSolo(
            session: pausedSnapshot,
            identity: identity,
            historyRepository: history,
            clock: clock,
          );
      addTearDown(() async {
        await recoveredPaused.shutdown();
        recoveredPaused.dispose();
      });

      expect(recoveredPaused.elapsed, const Duration(seconds: 4));
      expect(recoveredPaused.remaining, const Duration(seconds: 6));
      expect(recoveredPaused.session!.status, LiveSessionStatus.paused);
    },
  );

  test('rejects a solo recovery that cannot retain local authority', () async {
    final DateTime startedAt = DateTime.utc(2026, 7, 28, 12);
    const DeviceIdentity identity = DeviceIdentity(
      deviceId: 'host',
      displayName: 'Alex',
    );
    final LiveSession foreignSession = LiveSession(
      id: 'foreign',
      planSnapshot: _plan().snapshot(capturedAt: startedAt),
      hostDeviceId: 'another-host',
      status: LiveSessionStatus.running,
      startedAt: startedAt,
      currentStepStartedAt: startedAt,
    );

    await expectLater(
      LiveSessionController.recoverSolo(
        session: foreignSession,
        identity: identity,
        historyRepository: _MemoryHistory(),
      ),
      throwsArgumentError,
    );
  });

  test('failed solo recovery releases its cue subscription', () async {
    final DateTime startedAt = DateTime.utc(2026, 7, 28, 12);
    final _ThrowingCueDelivery cueDelivery = _ThrowingCueDelivery();
    addTearDown(cueDelivery.dispose);

    await expectLater(
      LiveSessionController.recoverSolo(
        session: LiveSession(
          id: 'failed-recovery',
          planSnapshot: _plan().snapshot(capturedAt: startedAt),
          hostDeviceId: 'host',
          status: LiveSessionStatus.running,
          startedAt: startedAt,
          currentStepStartedAt: startedAt,
        ),
        identity: const DeviceIdentity(deviceId: 'host', displayName: 'Alex'),
        historyRepository: _MemoryHistory(),
        clock: _MutableClock(startedAt.add(const Duration(seconds: 1))),
        cueService: cueDelivery,
      ),
      throwsStateError,
    );

    expect(cueDelivery.subscriptionCancelled, isTrue);
  });

  test('auto-advances each configured step once', () async {
    final _MutableClock clock = _MutableClock(DateTime.utc(2026, 7, 28, 12));
    final LiveSessionController controller =
        await LiveSessionController.createSolo(
          plan: _plan(firstStepAutoAdvance: true),
          identity: const DeviceIdentity(deviceId: 'host', displayName: 'Alex'),
          historyRepository: _MemoryHistory(),
          clock: clock,
        );
    addTearDown(() async {
      await controller.shutdown();
      controller.dispose();
    });

    await controller.start();
    clock.advance(const Duration(seconds: 11));
    await controller.refresh();
    await _settleAsync();

    expect(controller.session!.currentStepIndex, 1);
    expect(
      controller.session!.activities
          .where(
            (Activity activity) => activity.type == ActivityType.autoAdvanced,
          )
          .length,
      1,
    );
    await controller.refresh();
    await _settleAsync();
    expect(controller.session!.currentStepIndex, 1);
  });

  test('catches up overdue auto steps at their timestamp boundaries', () async {
    final DateTime startedAt = DateTime.utc(2026, 7, 28, 12);
    final _MutableClock clock = _MutableClock(startedAt);
    final LiveSessionController controller =
        await LiveSessionController.createSolo(
          plan: _plan(firstStepAutoAdvance: true, secondStepAutoAdvance: true),
          identity: const DeviceIdentity(deviceId: 'host', displayName: 'Alex'),
          historyRepository: _MemoryHistory(),
          clock: clock,
        );
    addTearDown(() async {
      await controller.shutdown();
      controller.dispose();
    });

    await controller.start();
    clock.advance(const Duration(seconds: 45));
    await controller.refresh();

    expect(controller.session!.status, LiveSessionStatus.ended);
    expect(
      controller.session!.activities
          .firstWhere(
            (Activity activity) => activity.type == ActivityType.autoAdvanced,
          )
          .occurredAt,
      startedAt.add(const Duration(seconds: 10)),
    );
    expect(
      controller.session!.endedAt,
      startedAt.add(const Duration(seconds: 30)),
    );
  });

  test(
    'desktop shared hosts stay active when their window loses focus',
    () async {
      final _MutableClock clock = _MutableClock(DateTime.utc(2026, 7, 28, 12));
      final SessionSecrets secrets = await SessionSecrets.generate();
      final Invitation invitation = Invitation(
        sessionId: 'desktop-online-session',
        transport: SessionTransportKind.onlineRelay,
        endpoint: Uri.parse('https://relay.example.com'),
        joinUri: Uri.parse('https://app.example.com'),
        capability: secrets.capability,
        sessionSecret: secrets.sessionSecret,
        requestedRole: SessionRole.participant,
        expiresAt: clock.now().add(const Duration(hours: 1)),
      );
      final LiveSessionController host = await LiveSessionController.hostShared(
        plan: _plan(),
        identity: const DeviceIdentity(deviceId: 'host', displayName: 'Alex'),
        invitation: invitation,
        transport: _RecordingTransport('host'),
        historyRepository: _MemoryHistory(),
        clock: clock,
        requiresForegroundHosting: false,
      );
      addTearDown(() async {
        await host.shutdown();
        host.dispose();
      });

      host.didChangeAppLifecycleState(AppLifecycleState.inactive);

      expect(host.isStale, isFalse);
      expect(host.lastError, isNull);
      await host.start();
      expect(host.session!.status, LiveSessionStatus.running);
    },
  );

  test('foreground-required shared hosts freeze while backgrounded', () async {
    final _MutableClock clock = _MutableClock(DateTime.utc(2026, 7, 28, 12));
    final SessionSecrets secrets = await SessionSecrets.generate();
    final Invitation invitation = Invitation(
      sessionId: 'mobile-online-session',
      transport: SessionTransportKind.onlineRelay,
      endpoint: Uri.parse('https://relay.example.com'),
      joinUri: Uri.parse('https://app.example.com'),
      capability: secrets.capability,
      sessionSecret: secrets.sessionSecret,
      requestedRole: SessionRole.participant,
      expiresAt: clock.now().add(const Duration(hours: 1)),
    );
    final LiveSessionController host = await LiveSessionController.hostShared(
      plan: _plan(),
      identity: const DeviceIdentity(deviceId: 'host', displayName: 'Alex'),
      invitation: invitation,
      transport: _RecordingTransport('host'),
      historyRepository: _MemoryHistory(),
      clock: clock,
      requiresForegroundHosting: true,
    );
    addTearDown(() async {
      await host.shutdown();
      host.dispose();
    });

    host.didChangeAppLifecycleState(AppLifecycleState.paused);

    expect(host.isStale, isTrue);
    expect(
      host.lastError,
      'Return to ChronoSync and keep it open while hosting this shared session.',
    );
    await expectLater(host.start(), throwsStateError);
  });

  test(
    'synchronizes join, acknowledgement, promotion, and host loss',
    () async {
      final _MutableClock clock = _MutableClock(DateTime.utc(2026, 7, 28, 12));
      final SessionSecrets secrets = await SessionSecrets.generate();
      final Invitation invitation = Invitation(
        sessionId: 'shared-session',
        transport: SessionTransportKind.nearbyLan,
        endpoint: Uri.parse('http://chronosync.local/'),
        capability: secrets.capability,
        sessionSecret: secrets.sessionSecret,
        requestedRole: SessionRole.participant,
        expiresAt: clock.now().add(const Duration(hours: 1)),
      );
      final InMemoryTransportHub hub = InMemoryTransportHub();
      final InMemoryTransport hostTransport = hub.createTransport(
        deviceId: 'host',
        clock: clock,
      );
      final InMemoryTransport guestTransport = hub.createTransport(
        deviceId: 'guest',
        clock: clock,
      );
      final LiveSessionController host = await LiveSessionController.hostShared(
        plan: _plan(),
        identity: const DeviceIdentity(deviceId: 'host', displayName: 'Alex'),
        invitation: invitation,
        transport: hostTransport,
        historyRepository: _MemoryHistory(),
        clock: clock,
      );
      final LiveSessionController guest =
          await LiveSessionController.joinShared(
            identity: const DeviceIdentity(
              deviceId: 'guest',
              displayName: 'Sam',
            ),
            invitation: invitation,
            transport: guestTransport,
            historyRepository: _MemoryHistory(),
            clock: clock,
          );
      addTearDown(() async {
        await guest.shutdown();
        guest.dispose();
        await host.shutdown();
        host.dispose();
      });

      await _waitUntil(
        () => host.session!.participantFor('guest') != null && guest.isReady,
      );
      expect(guest.role, SessionRole.participant);

      await host.start();
      await _waitUntil(
        () => guest.session?.status == LiveSessionStatus.running,
      );
      await guest.acknowledge();
      await _waitUntil(
        () => host.session!.activities.any(
          (Activity activity) =>
              activity.type == ActivityType.acknowledged &&
              activity.actorDeviceId == 'guest',
        ),
      );

      await host.changeParticipantRole('guest', SessionRole.controller);
      await _waitUntil(() => guest.role == SessionRole.controller);
      await guest.pause();
      await _waitUntil(() => host.session!.status == LiveSessionStatus.paused);

      final SessionCommand forgedEnd = SessionCommand.end(
        id: 'forged-end',
        sessionId: host.session!.id,
        actorDeviceId: 'guest',
        actorRole: SessionRole.host,
        baseRevision: host.session!.revision,
        issuedAt: clock.now(),
        confirmed: true,
      );
      final SessionEnvelope forgedEnvelope =
          await SessionEnvelopeCrypto(secrets.sessionSecret).seal(
            sessionId: forgedEnd.sessionId,
            messageId: forgedEnd.id,
            senderDeviceId: 'guest',
            baseRevision: forgedEnd.baseRevision,
            sentAt: clock.now(),
            kind: SessionMessageKind.command,
            payload: <String, Object?>{
              'type': 'command',
              'command': forgedEnd.toJson(),
            },
          );
      await guestTransport.send(forgedEnvelope);
      await _settleAsync();
      expect(host.session!.status, LiveSessionStatus.paused);

      await host.resume();
      await _waitUntil(
        () => guest.session?.status == LiveSessionStatus.running,
      );
      clock.advance(const Duration(seconds: 2));
      await guest.refresh();
      final Duration remainingBeforeHostLoss = guest.remaining;
      await host.shutdown();
      await _waitUntil(() => guest.isStale);
      expect(guest.isStale, isTrue);
      clock.advance(const Duration(minutes: 5));
      await guest.refresh();
      expect(guest.remaining, remainingBeforeHostLoss);
    },
  );

  test('derives participant timers from the host clock', () async {
    final _MutableClock hostClock = _MutableClock(
      DateTime.utc(2026, 7, 28, 12),
    );
    final _MutableClock guestClock = _MutableClock(
      DateTime.utc(2026, 7, 28, 17),
    );
    final SessionSecrets secrets = await SessionSecrets.generate();
    final Invitation invitation = Invitation(
      sessionId: 'clock-session',
      transport: SessionTransportKind.nearbyLan,
      endpoint: Uri.parse('http://chronosync.local/'),
      capability: secrets.capability,
      sessionSecret: secrets.sessionSecret,
      requestedRole: SessionRole.participant,
      expiresAt: hostClock.now().add(const Duration(days: 1)),
    );
    final InMemoryTransportHub hub = InMemoryTransportHub();
    final LiveSessionController host = await LiveSessionController.hostShared(
      plan: _plan(),
      identity: const DeviceIdentity(deviceId: 'host', displayName: 'Alex'),
      invitation: invitation,
      transport: hub.createTransport(deviceId: 'host', clock: hostClock),
      historyRepository: _MemoryHistory(),
      clock: hostClock,
    );
    final LiveSessionController guest = await LiveSessionController.joinShared(
      identity: const DeviceIdentity(deviceId: 'guest', displayName: 'Sam'),
      invitation: invitation,
      transport: hub.createTransport(deviceId: 'guest', clock: guestClock),
      historyRepository: _MemoryHistory(),
      clock: guestClock,
    );
    addTearDown(() async {
      await guest.shutdown();
      guest.dispose();
      await host.shutdown();
      host.dispose();
    });

    await _waitUntil(() => guest.isReady);
    expect(guest.now, hostClock.now());

    await host.start();
    await _waitUntil(() => guest.session?.status == LiveSessionStatus.running);
    hostClock.advance(const Duration(seconds: 4));
    guestClock.advance(const Duration(seconds: 4));
    await guest.refresh();

    expect(guest.elapsed, const Duration(seconds: 4));
    expect(guest.remaining, const Duration(seconds: 6));
  });

  test(
    'tracks authenticated participant disconnects without deleting them',
    () async {
      final _MutableClock clock = _MutableClock(DateTime.utc(2026, 7, 28, 12));
      final SessionSecrets secrets = await SessionSecrets.generate();
      final Invitation invitation = Invitation(
        sessionId: 'presence-session',
        transport: SessionTransportKind.nearbyLan,
        endpoint: Uri.parse('http://chronosync.local/'),
        capability: secrets.capability,
        sessionSecret: secrets.sessionSecret,
        requestedRole: SessionRole.participant,
        expiresAt: clock.now().add(const Duration(hours: 1)),
      );
      final InMemoryTransportHub hub = InMemoryTransportHub();
      final LiveSessionController host = await LiveSessionController.hostShared(
        plan: _plan(),
        identity: const DeviceIdentity(deviceId: 'host', displayName: 'Alex'),
        invitation: invitation,
        transport: hub.createTransport(deviceId: 'host', clock: clock),
        historyRepository: _MemoryHistory(),
        clock: clock,
      );
      final LiveSessionController guest =
          await LiveSessionController.joinShared(
            identity: const DeviceIdentity(
              deviceId: 'guest',
              displayName: 'Sam',
            ),
            invitation: invitation,
            transport: hub.createTransport(deviceId: 'guest', clock: clock),
            historyRepository: _MemoryHistory(),
            clock: clock,
          );
      addTearDown(() async {
        await guest.shutdown();
        guest.dispose();
        await host.shutdown();
        host.dispose();
      });

      await _waitUntil(() => host.session!.participantFor('guest') != null);
      expect(host.connectedParticipantCount, 1);
      expect(
        host.participantConnectionState('guest'),
        ParticipantConnectionState.connected,
      );

      await guest.shutdown();
      await _waitUntil(
        () =>
            host.participantConnectionState('guest') ==
            ParticipantConnectionState.stale,
      );

      expect(host.connectedParticipantCount, 0);
      expect(host.session!.participantFor('guest'), isNotNull);
    },
  );

  test(
    'republishes the latest authoritative snapshot after reconnect',
    () async {
      final _MutableClock clock = _MutableClock(DateTime.utc(2026, 7, 28, 12));
      final SessionSecrets secrets = await SessionSecrets.generate();
      final Invitation invitation = Invitation(
        sessionId: 'recovery-session',
        transport: SessionTransportKind.onlineRelay,
        endpoint: Uri.parse('https://relay.example.com'),
        joinUri: Uri.parse('https://app.example.com'),
        capability: secrets.capability,
        sessionSecret: secrets.sessionSecret,
        requestedRole: SessionRole.participant,
        expiresAt: clock.now().add(const Duration(hours: 1)),
      );
      final _RecordingTransport transport = _RecordingTransport('host');
      final LiveSessionController host = await LiveSessionController.hostShared(
        plan: _plan(),
        identity: const DeviceIdentity(deviceId: 'host', displayName: 'Alex'),
        invitation: invitation,
        transport: transport,
        historyRepository: _MemoryHistory(),
        clock: clock,
      );
      addTearDown(() async {
        await host.shutdown();
        host.dispose();
      });
      await _settleAsync();
      transport.sent.clear();

      transport.failNextSend = true;
      await expectLater(host.start(), completes);
      expect(host.session!.revision, 1);
      expect(host.session!.status, LiveSessionStatus.running);
      expect(host.lastError, contains('saved but could not reach'));

      transport.emitState(SessionConnectionState.stale);
      transport.emitState(SessionConnectionState.hosting);
      await _waitUntil(
        () => transport.sent.any(
          (SessionEnvelope envelope) => envelope.baseRevision == 1,
        ),
      );

      expect(transport.sent.last.baseRevision, 1);
    },
  );

  test(
    'keeps timing frozen when a retained snapshot arrives while stale',
    () async {
      final _MutableClock clock = _MutableClock(DateTime.utc(2026, 7, 28, 12));
      final SessionSecrets secrets = await SessionSecrets.generate();
      final Invitation invitation = Invitation(
        sessionId: 'stale-snapshot-session',
        transport: SessionTransportKind.onlineRelay,
        endpoint: Uri.parse('https://relay.example.com'),
        joinUri: Uri.parse('https://app.example.com'),
        capability: secrets.capability,
        sessionSecret: secrets.sessionSecret,
        requestedRole: SessionRole.participant,
        expiresAt: clock.now().add(const Duration(hours: 1)),
      );
      final _RecordingTransport transport = _RecordingTransport('guest');
      final LiveSessionController guest =
          await LiveSessionController.joinShared(
            identity: const DeviceIdentity(
              deviceId: 'guest',
              displayName: 'Sam',
            ),
            invitation: invitation,
            transport: transport,
            historyRepository: _MemoryHistory(),
            clock: clock,
          );
      addTearDown(() async {
        await guest.shutdown();
        guest.dispose();
      });

      final LiveSession snapshot = LiveSession(
        id: invitation.sessionId,
        planSnapshot: _plan().snapshot(capturedAt: clock.now()),
        hostDeviceId: 'host',
        status: LiveSessionStatus.running,
        startedAt: clock.now(),
        currentStepStartedAt: clock.now(),
      );
      final SessionEnvelope envelope =
          await SessionEnvelopeCrypto(secrets.sessionSecret).seal(
            sessionId: invitation.sessionId,
            messageId: 'snapshot-1',
            senderDeviceId: 'host',
            baseRevision: snapshot.revision,
            sentAt: clock.now(),
            kind: SessionMessageKind.snapshot,
            payload: <String, Object?>{
              'type': 'snapshot',
              'session': snapshot.toJson(),
            },
          );
      await transport.emitEnvelope(envelope);
      await _waitUntil(() => guest.isReady);

      clock.advance(const Duration(seconds: 2));
      await guest.refresh();
      final Duration remainingBeforeHostLoss = guest.remaining;
      transport.emitState(SessionConnectionState.stale);
      await transport.emitEnvelope(envelope);
      await _settleAsync();

      clock.advance(const Duration(minutes: 5));
      await guest.refresh();

      expect(guest.isStale, isTrue);
      expect(guest.remaining, remainingBeforeHostLoss);
    },
  );

  test('enrolls a joining device before a fallible snapshot publish', () async {
    final _MutableClock clock = _MutableClock(DateTime.utc(2026, 7, 28, 12));
    final SessionSecrets secrets = await SessionSecrets.generate();
    final Invitation invitation = Invitation(
      sessionId: 'join-recovery-session',
      transport: SessionTransportKind.onlineRelay,
      endpoint: Uri.parse('https://relay.example.com'),
      joinUri: Uri.parse('https://app.example.com'),
      capability: secrets.capability,
      sessionSecret: secrets.sessionSecret,
      requestedRole: SessionRole.participant,
      expiresAt: clock.now().add(const Duration(hours: 1)),
    );
    final _RecordingTransport transport = _RecordingTransport('host');
    final LiveSessionController host = await LiveSessionController.hostShared(
      plan: _plan(),
      identity: const DeviceIdentity(deviceId: 'host', displayName: 'Alex'),
      invitation: invitation,
      transport: transport,
      historyRepository: _MemoryHistory(),
      clock: clock,
    );
    addTearDown(() async {
      await host.shutdown();
      host.dispose();
    });
    await _settleAsync();
    transport.sent.clear();

    const String deviceSecret = 'abcdefghijklmnopqrstuvwxyzABCDEFGH1234567890';
    final SessionCommand firstJoin = SessionCommand.join(
      id: 'first-join-command',
      sessionId: invitation.sessionId,
      actorDeviceId: 'guest',
      baseRevision: 0,
      issuedAt: clock.now(),
      displayName: 'Sam',
      requestedRole: SessionRole.participant,
      authenticationSecret: deviceSecret,
    );
    transport.failNextSend = true;
    await transport.emitEnvelope(
      await _sealCommand(
        firstJoin,
        sessionSecret: secrets.sessionSecret,
        sentAt: clock.now(),
      ),
      peerRole: SessionRole.participant,
      connectionId: 'guest-connection-1',
    );
    await _waitUntil(
      () => host.session!.participantFor('guest') != null,
      'first join transition',
    );

    final SessionCommand retryJoin = SessionCommand.join(
      id: 'retry-join-command',
      sessionId: invitation.sessionId,
      actorDeviceId: 'guest',
      baseRevision: 0,
      issuedAt: clock.now(),
      displayName: 'Sam',
      requestedRole: SessionRole.participant,
      authenticationSecret: deviceSecret,
    );
    await transport.emitEnvelope(
      await _sealCommand(
        retryJoin,
        sessionSecret: secrets.sessionSecret,
        sentAt: clock.now(),
      ),
      peerRole: SessionRole.participant,
      connectionId: 'guest-connection-2',
    );
    await _waitUntil(
      () => transport.sent.any(
        (SessionEnvelope envelope) => envelope.baseRevision == 1,
      ),
      'retry snapshot publish',
    );
    await host.start();

    final SessionCommand acknowledgement = SessionCommand.acknowledge(
      id: 'ack-after-rejoin',
      sessionId: invitation.sessionId,
      actorDeviceId: 'guest',
      actorRole: SessionRole.participant,
      baseRevision: 2,
      issuedAt: clock.now(),
      stepIndex: 0,
    );
    await transport.emitEnvelope(
      await _sealCommand(
        acknowledgement,
        sessionSecret: secrets.sessionSecret,
        sentAt: clock.now(),
      ),
      peerRole: SessionRole.participant,
      connectionId: 'guest-connection-2',
    );
    await _waitUntil(
      () => host.session!.activities.any(
        (Activity activity) => activity.commandId == acknowledgement.id,
      ),
      'acknowledgement after retry',
    );

    expect(host.session!.revision, 3);
  });

  test('keeps a stale-revision join connection open for retry', () async {
    final _MutableClock clock = _MutableClock(DateTime.utc(2026, 7, 29, 12));
    final SessionSecrets secrets = await SessionSecrets.generate();
    final Invitation invitation = Invitation(
      sessionId: 'stale-join-session',
      transport: SessionTransportKind.onlineRelay,
      endpoint: Uri.parse('https://relay.example.com'),
      joinUri: Uri.parse('https://app.example.com'),
      capability: secrets.capability,
      sessionSecret: secrets.sessionSecret,
      requestedRole: SessionRole.participant,
      expiresAt: clock.now().add(const Duration(hours: 1)),
    );
    final _RecordingTransport transport = _RecordingTransport('host');
    final LiveSessionController host = await LiveSessionController.hostShared(
      plan: _plan(),
      identity: const DeviceIdentity(deviceId: 'host', displayName: 'Alex'),
      invitation: invitation,
      transport: transport,
      historyRepository: _MemoryHistory(),
      clock: clock,
    );
    addTearDown(() async {
      await host.shutdown();
      host.dispose();
    });
    await host.start();
    transport.sent.clear();

    const String authenticationSecret = 'abcdefghijklmnopqrstuvwxyz123456';
    final SessionCommand staleJoin = SessionCommand.join(
      id: 'stale-join',
      sessionId: invitation.sessionId,
      actorDeviceId: 'guest',
      baseRevision: 0,
      issuedAt: clock.now(),
      displayName: 'Sam',
      requestedRole: SessionRole.participant,
      authenticationSecret: authenticationSecret,
    );
    await transport.emitEnvelope(
      await _sealCommand(
        staleJoin,
        sessionSecret: secrets.sessionSecret,
        sentAt: clock.now(),
      ),
      peerRole: SessionRole.participant,
      connectionId: 'guest-connection',
    );
    await _waitUntil(
      () => transport.sent.any(
        (SessionEnvelope envelope) => envelope.baseRevision == 1,
      ),
      'newer snapshot after stale join',
    );

    expect(transport.disconnectedPeers, isEmpty);

    final SessionCommand retryJoin = SessionCommand.join(
      id: 'retry-join',
      sessionId: invitation.sessionId,
      actorDeviceId: 'guest',
      baseRevision: host.session!.revision,
      issuedAt: clock.now(),
      displayName: 'Sam',
      requestedRole: SessionRole.participant,
      authenticationSecret: authenticationSecret,
    );
    await transport.emitEnvelope(
      await _sealCommand(
        retryJoin,
        sessionSecret: secrets.sessionSecret,
        sentAt: clock.now(),
      ),
      peerRole: SessionRole.participant,
      connectionId: 'guest-connection',
    );
    await _waitUntil(
      () => host.session!.participantFor('guest') != null,
      'join retry on retained connection',
    );
  });

  test(
    'retries a join against a newer snapshot after a revision race',
    () async {
      final _MutableClock clock = _MutableClock(DateTime.utc(2026, 7, 29, 12));
      final SessionSecrets secrets = await SessionSecrets.generate();
      final Invitation invitation = Invitation(
        sessionId: 'join-race-session',
        transport: SessionTransportKind.onlineRelay,
        endpoint: Uri.parse('https://relay.example.com'),
        joinUri: Uri.parse('https://app.example.com'),
        capability: secrets.capability,
        sessionSecret: secrets.sessionSecret,
        requestedRole: SessionRole.participant,
        expiresAt: clock.now().add(const Duration(hours: 1)),
      );
      final _RecordingTransport transport = _RecordingTransport('guest');
      final LiveSessionController guest =
          await LiveSessionController.joinShared(
            identity: const DeviceIdentity(
              deviceId: 'guest',
              displayName: 'Sam',
            ),
            invitation: invitation,
            transport: transport,
            historyRepository: _MemoryHistory(),
            clock: clock,
          );
      addTearDown(() async {
        await guest.shutdown();
        guest.dispose();
      });
      final LiveSession waiting = LiveSession(
        id: invitation.sessionId,
        planSnapshot: _plan().snapshot(capturedAt: clock.now()),
        hostDeviceId: 'host',
      );
      final LiveSession running = SessionReducer.applyCommand(
        session: waiting,
        command: SessionCommand.start(
          id: 'host-start',
          sessionId: waiting.id,
          actorDeviceId: 'host',
          actorRole: SessionRole.host,
          baseRevision: waiting.revision,
          issuedAt: clock.now(),
        ),
        occurredAt: clock.now(),
      ).session;

      await transport.emitEnvelope(
        await _sealSnapshot(
          waiting,
          sessionSecret: secrets.sessionSecret,
          sentAt: clock.now(),
        ),
      );
      await _waitUntil(() => transport.sent.length == 1, 'initial join');
      await transport.emitEnvelope(
        await _sealSnapshot(
          running,
          sessionSecret: secrets.sessionSecret,
          sentAt: clock.now(),
        ),
      );
      await _waitUntil(() => transport.sent.length == 2, 'join retry');

      expect(
        transport.sent.map((SessionEnvelope envelope) => envelope.baseRevision),
        <int>[0, 1],
      );
    },
  );

  test(
    'rebinds retained and removed participants on each new connection',
    () async {
      final _MutableClock clock = _MutableClock(DateTime.utc(2026, 7, 29, 12));
      final SessionSecrets secrets = await SessionSecrets.generate();
      final Invitation invitation = Invitation(
        sessionId: 'removed-reconnect-session',
        transport: SessionTransportKind.onlineRelay,
        endpoint: Uri.parse('https://relay.example.com'),
        joinUri: Uri.parse('https://app.example.com'),
        capability: secrets.capability,
        sessionSecret: secrets.sessionSecret,
        requestedRole: SessionRole.participant,
        expiresAt: clock.now().add(const Duration(hours: 1)),
      );
      final _RecordingTransport transport = _RecordingTransport('guest');
      final LiveSessionController guest =
          await LiveSessionController.joinShared(
            identity: const DeviceIdentity(
              deviceId: 'guest',
              displayName: 'Sam',
            ),
            invitation: invitation,
            transport: transport,
            historyRepository: _MemoryHistory(),
            clock: clock,
          );
      addTearDown(() async {
        await guest.shutdown();
        guest.dispose();
      });
      final LiveSession waiting = LiveSession(
        id: invitation.sessionId,
        planSnapshot: _plan().snapshot(capturedAt: clock.now()),
        hostDeviceId: 'host',
      );
      final LiveSession joined = SessionReducer.applyCommand(
        session: waiting,
        command: SessionCommand.join(
          id: 'joined-before-reconnect',
          sessionId: waiting.id,
          actorDeviceId: 'guest',
          baseRevision: waiting.revision,
          issuedAt: clock.now(),
          displayName: 'Sam',
          requestedRole: SessionRole.participant,
          authenticationSecret: 'abcdefghijklmnopqrstuvwxyz123456',
        ),
        occurredAt: clock.now(),
      ).session;
      final LiveSession advanced = SessionReducer.applyCommand(
        session: joined,
        command: SessionCommand.start(
          id: 'advanced-before-reconnect',
          sessionId: joined.id,
          actorDeviceId: 'host',
          actorRole: SessionRole.host,
          baseRevision: joined.revision,
          issuedAt: clock.now(),
        ),
        occurredAt: clock.now(),
      ).session;
      final LiveSession removed = SessionReducer.applyCommand(
        session: joined,
        command: SessionCommand.disconnectParticipant(
          id: 'removed-before-reconnect',
          sessionId: joined.id,
          actorDeviceId: 'host',
          actorRole: SessionRole.host,
          baseRevision: joined.revision,
          issuedAt: clock.now(),
          targetDeviceId: 'guest',
        ),
        occurredAt: clock.now(),
      ).session;

      await transport.emitEnvelope(
        await _sealSnapshot(
          joined,
          sessionSecret: secrets.sessionSecret,
          sentAt: clock.now(),
        ),
      );
      await _waitUntil(
        () => transport.sent.length == 1,
        'join for retained connected participant',
      );

      await transport.emitEnvelope(
        await _sealSnapshot(
          advanced,
          sessionSecret: secrets.sessionSecret,
          sentAt: clock.now(),
        ),
      );
      await _waitUntil(
        () => transport.sent.length == 2,
        'join retry after the retained snapshot advances',
      );
      await transport.emitEnvelope(
        await _sealSnapshot(
          advanced,
          sessionSecret: secrets.sessionSecret,
          sentAt: clock.now(),
        ),
      );
      await _settleAsync();
      expect(transport.sent, hasLength(2));

      transport.emitState(SessionConnectionState.stale);
      transport.emitState(SessionConnectionState.connected);
      await transport.emitEnvelope(
        await _sealSnapshot(
          removed,
          sessionSecret: secrets.sessionSecret,
          sentAt: clock.now(),
        ),
      );
      await _waitUntil(
        () => transport.sent.length == 3,
        'join after removed snapshot',
      );

      expect(transport.sent.last.baseRevision, removed.revision);
      expect(transport.sent.last.senderDeviceId, 'guest');
    },
  );

  test(
    'equal-revision online snapshot confirms rebind without join fan-out',
    () async {
      final _MutableClock clock = _MutableClock(DateTime.utc(2026, 7, 29, 12));
      final SessionSecrets secrets = await SessionSecrets.generate();
      final Invitation invitation = Invitation(
        sessionId: 'online-rebind-session',
        transport: SessionTransportKind.onlineRelay,
        endpoint: Uri.parse('https://relay.example.com'),
        joinUri: Uri.parse('https://app.example.com'),
        capability: secrets.capability,
        sessionSecret: secrets.sessionSecret,
        requestedRole: SessionRole.participant,
        expiresAt: clock.now().add(const Duration(hours: 1)),
      );
      final FakeWebSocketChannel channel = FakeWebSocketChannel();
      final List<Map<String, Object?>> outgoing = <Map<String, Object?>>[];
      channel.outgoing.listen((Object? frame) {
        if (frame is String) {
          final Object? decoded = jsonDecode(frame);
          if (decoded is Map<Object?, Object?>) {
            outgoing.add(Map<String, Object?>.from(decoded));
          }
        }
      });
      final OnlineRelayTransport transport = OnlineRelayTransport(
        deviceId: 'guest',
        heartbeatInterval: const Duration(minutes: 1),
        heartbeatTimeout: const Duration(minutes: 2),
        hostPresenceTimeout: const Duration(minutes: 2),
        now: clock.now,
        connectWebSocket: (Uri uri, Iterable<String> protocols) => channel,
      );
      final LiveSessionController guest =
          await LiveSessionController.joinShared(
            identity: const DeviceIdentity(
              deviceId: 'guest',
              displayName: 'Sam',
            ),
            invitation: invitation,
            transport: transport,
            historyRepository: _MemoryHistory(),
            deviceAuthenticationSecret: 'abcdefghijklmnopqrstuvwxyz123456',
            clock: clock,
          );
      addTearDown(() async {
        await guest.shutdown();
        guest.dispose();
        await channel.dispose();
      });
      channel.addIncoming(
        jsonEncode(<String, Object?>{
          'type': 'welcome',
          'connectionId': 'guest-connection',
          'hostConnected': true,
        }),
      );
      await _waitUntil(
        () => transport.connectionState == SessionConnectionState.connected,
        'relay host assertion',
      );

      final LiveSession waiting = LiveSession(
        id: invitation.sessionId,
        planSnapshot: _plan().snapshot(capturedAt: clock.now()),
        hostDeviceId: 'host',
      );
      final LiveSession joined = SessionReducer.applyCommand(
        session: waiting,
        command: SessionCommand.join(
          id: 'existing-online-participant',
          sessionId: waiting.id,
          actorDeviceId: 'guest',
          baseRevision: waiting.revision,
          issuedAt: clock.now(),
          displayName: 'Sam',
          requestedRole: SessionRole.participant,
          authenticationSecret: 'abcdefghijklmnopqrstuvwxyz123456',
        ),
        occurredAt: clock.now(),
      ).session;
      final LiveSession advanced = SessionReducer.applyCommand(
        session: joined,
        command: SessionCommand.start(
          id: 'host-start-after-rebind',
          sessionId: joined.id,
          actorDeviceId: 'host',
          actorRole: SessionRole.host,
          baseRevision: joined.revision,
          issuedAt: clock.now(),
        ),
        occurredAt: clock.now(),
      ).session;

      await _emitRelaySnapshot(
        channel,
        joined,
        sessionSecret: secrets.sessionSecret,
        messageId: 'retained-before-rebind',
        sentAt: clock.now(),
      );
      await _waitUntil(
        () =>
            outgoing
                .where(
                  (Map<String, Object?> frame) => frame['type'] == 'command',
                )
                .length ==
            1,
        'rebind join command',
      );
      await _emitRelaySnapshot(
        channel,
        joined,
        sessionSecret: secrets.sessionSecret,
        messageId: 'equal-revision-rebind-confirmation',
        sentAt: clock.now(),
      );
      await _emitRelaySnapshot(
        channel,
        advanced,
        sessionSecret: secrets.sessionSecret,
        messageId: 'later-session-update',
        sentAt: clock.now(),
      );
      await _settleAsync();

      expect(
        outgoing.where(
          (Map<String, Object?> frame) => frame['type'] == 'command',
        ),
        hasLength(1),
      );
      expect(guest.session?.revision, advanced.revision);
    },
  );

  test(
    'binds the transport device token to the encrypted join identity',
    () async {
      final _MutableClock clock = _MutableClock(DateTime.utc(2026, 7, 29, 12));
      final SessionSecrets secrets = await SessionSecrets.generate();
      final Invitation invitation = Invitation(
        sessionId: 'token-binding-session',
        transport: SessionTransportKind.onlineRelay,
        endpoint: Uri.parse('https://relay.example.com'),
        joinUri: Uri.parse('https://app.example.com'),
        capability: secrets.capability,
        sessionSecret: secrets.sessionSecret,
        requestedRole: SessionRole.participant,
        expiresAt: clock.now().add(const Duration(hours: 1)),
      );
      final _RecordingTransport transport = _RecordingTransport('host');
      final LiveSessionController host = await LiveSessionController.hostShared(
        plan: _plan(),
        identity: const DeviceIdentity(deviceId: 'host', displayName: 'Alex'),
        invitation: invitation,
        transport: transport,
        historyRepository: _MemoryHistory(),
        clock: clock,
      );
      addTearDown(() async {
        await host.shutdown();
        host.dispose();
      });
      const String authenticationSecret = 'abcdefghijklmnopqrstuvwxyz123456';
      SessionCommand join(String id) => SessionCommand.join(
        id: id,
        sessionId: invitation.sessionId,
        actorDeviceId: 'guest',
        baseRevision: host.session!.revision,
        issuedAt: clock.now(),
        displayName: 'Sam',
        requestedRole: SessionRole.participant,
        authenticationSecret: authenticationSecret,
      );
      final String forgedToken = await SessionDeviceToken.derive(
        deviceId: 'different-device',
        sessionSecret: secrets.sessionSecret,
      );

      await transport.emitEnvelope(
        await _sealCommand(
          join('forged-token-join'),
          sessionSecret: secrets.sessionSecret,
          sentAt: clock.now(),
        ),
        peerRole: SessionRole.participant,
        connectionId: 'forged-connection',
        deviceToken: forgedToken,
      );
      await _settleAsync();

      expect(host.session!.participantFor('guest'), isNull);
      expect(transport.disconnectedPeers, contains('forged-connection'));

      await transport.emitEnvelope(
        await _sealCommand(
          join('bound-token-join'),
          sessionSecret: secrets.sessionSecret,
          sentAt: clock.now(),
        ),
        peerRole: SessionRole.participant,
        connectionId: 'bound-connection',
      );
      await _waitUntil(
        () => host.session!.participantFor('guest') != null,
        'token-bound participant join',
      );
    },
  );

  test(
    'requires the transport-attested role to match every participant command',
    () async {
      final _MutableClock clock = _MutableClock(DateTime.utc(2026, 7, 29, 12));
      final SessionSecrets secrets = await SessionSecrets.generate();
      final Invitation invitation = Invitation(
        sessionId: 'role-binding-session',
        transport: SessionTransportKind.onlineRelay,
        endpoint: Uri.parse('https://relay.example.com'),
        joinUri: Uri.parse('https://app.example.com'),
        capability: secrets.capability,
        sessionSecret: secrets.sessionSecret,
        requestedRole: SessionRole.participant,
        expiresAt: clock.now().add(const Duration(hours: 1)),
      );
      final _RecordingTransport transport = _RecordingTransport('host');
      final LiveSessionController host = await LiveSessionController.hostShared(
        plan: _plan(),
        identity: const DeviceIdentity(deviceId: 'host', displayName: 'Alex'),
        invitation: invitation,
        transport: transport,
        historyRepository: _MemoryHistory(),
        clock: clock,
      );
      addTearDown(() async {
        await host.shutdown();
        host.dispose();
      });
      const String authenticationSecret = 'abcdefghijklmnopqrstuvwxyz123456';
      const String connectionId = 'role-bound-connection';
      final SessionCommand join = SessionCommand.join(
        id: 'role-bound-join',
        sessionId: invitation.sessionId,
        actorDeviceId: 'guest',
        baseRevision: host.session!.revision,
        issuedAt: clock.now(),
        displayName: 'Sam',
        requestedRole: SessionRole.participant,
        authenticationSecret: authenticationSecret,
      );
      await transport.emitEnvelope(
        await _sealCommand(
          join,
          sessionSecret: secrets.sessionSecret,
          sentAt: clock.now(),
        ),
        peerRole: SessionRole.participant,
        connectionId: connectionId,
      );
      await _waitUntil(() => host.session!.participantFor('guest') != null);
      await host.start();
      await host.changeParticipantRole('guest', SessionRole.controller);
      final int promotedRevision = host.session!.revision;
      const String reconnectedId = 'role-bound-reconnect';
      final SessionCommand reconnect = SessionCommand.join(
        id: 'controller-reconnect',
        sessionId: invitation.sessionId,
        actorDeviceId: 'guest',
        baseRevision: promotedRevision,
        issuedAt: clock.now(),
        displayName: 'Sam',
        requestedRole: SessionRole.participant,
        authenticationSecret: authenticationSecret,
      );
      await transport.emitEnvelope(
        await _sealCommand(
          reconnect,
          sessionSecret: secrets.sessionSecret,
          sentAt: clock.now(),
        ),
        peerRole: SessionRole.controller,
        connectionId: reconnectedId,
      );
      await _waitUntil(
        () => transport.disconnectedPeers.contains(connectionId),
      );

      final SessionCommand spoofedPause = SessionCommand.pause(
        id: 'spoofed-controller-pause',
        sessionId: invitation.sessionId,
        actorDeviceId: 'guest',
        actorRole: SessionRole.controller,
        baseRevision: promotedRevision,
        issuedAt: clock.now(),
      );
      await transport.emitEnvelope(
        await _sealCommand(
          spoofedPause,
          sessionSecret: secrets.sessionSecret,
          sentAt: clock.now(),
        ),
        peerRole: SessionRole.participant,
        connectionId: reconnectedId,
      );
      await _settleAsync();

      expect(host.session!.status, LiveSessionStatus.running);
      expect(host.session!.revision, promotedRevision);

      final SessionCommand authenticatedPause = SessionCommand.pause(
        id: 'authenticated-controller-pause',
        sessionId: invitation.sessionId,
        actorDeviceId: 'guest',
        actorRole: SessionRole.controller,
        baseRevision: promotedRevision,
        issuedAt: clock.now(),
      );
      await transport.emitEnvelope(
        await _sealCommand(
          authenticatedPause,
          sessionSecret: secrets.sessionSecret,
          sentAt: clock.now(),
        ),
        peerRole: SessionRole.controller,
        connectionId: reconnectedId,
      );
      await _waitUntil(() => host.session!.status == LiveSessionStatus.paused);
    },
  );

  test('rolls back the transport role when role persistence fails', () async {
    final _MutableClock clock = _MutableClock(DateTime.utc(2026, 7, 29, 12));
    final SessionSecrets secrets = await SessionSecrets.generate();
    final Invitation invitation = Invitation(
      sessionId: 'role-rollback-session',
      transport: SessionTransportKind.onlineRelay,
      endpoint: Uri.parse('https://relay.example.com'),
      joinUri: Uri.parse('https://app.example.com'),
      capability: secrets.capability,
      sessionSecret: secrets.sessionSecret,
      requestedRole: SessionRole.participant,
      expiresAt: clock.now().add(const Duration(hours: 1)),
    );
    final _RecordingTransport transport = _RecordingTransport('host');
    final _MemoryHistory history = _MemoryHistory();
    final LiveSessionController host = await LiveSessionController.hostShared(
      plan: _plan(),
      identity: const DeviceIdentity(deviceId: 'host', displayName: 'Alex'),
      invitation: invitation,
      transport: transport,
      historyRepository: history,
      clock: clock,
    );
    addTearDown(() async {
      await host.shutdown();
      host.dispose();
    });
    final SessionCommand join = SessionCommand.join(
      id: 'rollback-join',
      sessionId: invitation.sessionId,
      actorDeviceId: 'guest',
      baseRevision: host.session!.revision,
      issuedAt: clock.now(),
      displayName: 'Sam',
      requestedRole: SessionRole.participant,
      authenticationSecret: 'abcdefghijklmnopqrstuvwxyz123456',
    );
    await transport.emitEnvelope(
      await _sealCommand(
        join,
        sessionSecret: secrets.sessionSecret,
        sentAt: clock.now(),
      ),
      peerRole: SessionRole.participant,
      connectionId: 'rollback-connection',
    );
    await _waitUntil(() => host.session!.participantFor('guest') != null);
    final int revisionBeforePromotion = host.session!.revision;
    transport.failNextRoleUpdate = true;

    await expectLater(
      host.changeParticipantRole('guest', SessionRole.controller),
      throwsStateError,
    );
    expect(host.session!.revision, revisionBeforePromotion);
    expect(
      host.session!.participantFor('guest')?.role,
      SessionRole.participant,
    );
    transport.roleUpdates.clear();
    history.failNextSave = true;

    await expectLater(
      host.changeParticipantRole('guest', SessionRole.controller),
      throwsStateError,
    );

    expect(host.session!.revision, revisionBeforePromotion);
    expect(
      host.session!.participantFor('guest')?.role,
      SessionRole.participant,
    );
    expect(
      transport.roleUpdates.map(
        (({String deviceToken, SessionRole role}) v) => v.role,
      ),
      <SessionRole>[SessionRole.controller, SessionRole.participant],
    );
  });

  test('removing an offline participant revokes its retained token', () async {
    final _MutableClock clock = _MutableClock(DateTime.utc(2026, 7, 29, 12));
    final SessionSecrets secrets = await SessionSecrets.generate();
    final Invitation invitation = Invitation(
      sessionId: 'offline-removal-session',
      transport: SessionTransportKind.onlineRelay,
      endpoint: Uri.parse('https://relay.example.com'),
      joinUri: Uri.parse('https://app.example.com'),
      capability: secrets.capability,
      sessionSecret: secrets.sessionSecret,
      requestedRole: SessionRole.participant,
      expiresAt: clock.now().add(const Duration(hours: 1)),
    );
    final _RecordingTransport transport = _RecordingTransport('host');
    final LiveSessionController host = await LiveSessionController.hostShared(
      plan: _plan(),
      identity: const DeviceIdentity(deviceId: 'host', displayName: 'Alex'),
      invitation: invitation,
      transport: transport,
      historyRepository: _MemoryHistory(),
      clock: clock,
    );
    addTearDown(() async {
      await host.shutdown();
      host.dispose();
    });
    final String deviceToken = await SessionDeviceToken.derive(
      deviceId: 'guest',
      sessionSecret: secrets.sessionSecret,
    );
    final SessionCommand join = SessionCommand.join(
      id: 'offline-participant-join',
      sessionId: invitation.sessionId,
      actorDeviceId: 'guest',
      baseRevision: host.session!.revision,
      issuedAt: clock.now(),
      displayName: 'Sam',
      requestedRole: SessionRole.participant,
      authenticationSecret: 'abcdefghijklmnopqrstuvwxyz123456',
    );
    await transport.emitEnvelope(
      await _sealCommand(
        join,
        sessionSecret: secrets.sessionSecret,
        sentAt: clock.now(),
      ),
      peerRole: SessionRole.participant,
      connectionId: 'offline-connection',
    );
    await _waitUntil(() => host.session!.participantFor('guest') != null);
    transport.emitPeerEvent(
      SessionPeerEvent(
        peer: AuthenticatedSessionPeer(
          connectionId: 'offline-connection',
          role: SessionRole.participant,
          deviceToken: deviceToken,
        ),
        presence: SessionPeerPresence.disconnected,
      ),
    );
    await _settleAsync();

    await host.removeParticipant('guest');

    expect(transport.revokedDeviceTokens, <String>[deviceToken]);
    expect(
      host.session!.participantFor('guest')?.connectionState,
      ParticipantConnectionState.disconnected,
    );
  });

  test(
    'does not remove a participant before revocation is acknowledged',
    () async {
      final _MutableClock clock = _MutableClock(DateTime.utc(2026, 7, 29, 12));
      final SessionSecrets secrets = await SessionSecrets.generate();
      final Invitation invitation = Invitation(
        sessionId: 'revocation-ack-session',
        transport: SessionTransportKind.onlineRelay,
        endpoint: Uri.parse('https://relay.example.com'),
        joinUri: Uri.parse('https://app.example.com'),
        capability: secrets.capability,
        sessionSecret: secrets.sessionSecret,
        requestedRole: SessionRole.participant,
        expiresAt: clock.now().add(const Duration(hours: 1)),
      );
      final _RecordingTransport transport = _RecordingTransport('host');
      final LiveSessionController host = await LiveSessionController.hostShared(
        plan: _plan(),
        identity: const DeviceIdentity(deviceId: 'host', displayName: 'Alex'),
        invitation: invitation,
        transport: transport,
        historyRepository: _MemoryHistory(),
        clock: clock,
      );
      addTearDown(() async {
        await host.shutdown();
        host.dispose();
      });
      final SessionCommand join = SessionCommand.join(
        id: 'participant-before-revocation-failure',
        sessionId: invitation.sessionId,
        actorDeviceId: 'guest',
        baseRevision: host.session!.revision,
        issuedAt: clock.now(),
        displayName: 'Sam',
        requestedRole: SessionRole.participant,
        authenticationSecret: 'abcdefghijklmnopqrstuvwxyz123456',
      );
      await transport.emitEnvelope(
        await _sealCommand(
          join,
          sessionSecret: secrets.sessionSecret,
          sentAt: clock.now(),
        ),
        peerRole: SessionRole.participant,
        connectionId: 'revocation-failure-connection',
      );
      await _waitUntil(() => host.session!.participantFor('guest') != null);
      transport.failNextRevoke = true;

      await expectLater(host.removeParticipant('guest'), throwsStateError);

      expect(
        host.session!.participantFor('guest')?.connectionState,
        ParticipantConnectionState.connected,
      );
      await host.removeParticipant('guest');
      expect(
        host.session!.participantFor('guest')?.connectionState,
        ParticipantConnectionState.disconnected,
      );
    },
  );

  test('host removal evicts the authenticated participant transport', () async {
    final _MutableClock clock = _MutableClock(DateTime.utc(2026, 7, 29, 12));
    final SessionSecrets secrets = await SessionSecrets.generate();
    final Invitation invitation = Invitation(
      sessionId: 'eviction-session',
      transport: SessionTransportKind.nearbyLan,
      endpoint: Uri.parse('http://chronosync.local/'),
      capability: secrets.capability,
      sessionSecret: secrets.sessionSecret,
      requestedRole: SessionRole.participant,
      expiresAt: clock.now().add(const Duration(hours: 1)),
    );
    final InMemoryTransportHub hub = InMemoryTransportHub();
    final InMemoryTransport hostTransport = hub.createTransport(
      deviceId: 'host',
      clock: clock,
    );
    final InMemoryTransport guestTransport = hub.createTransport(
      deviceId: 'guest',
      clock: clock,
    );
    final LiveSessionController host = await LiveSessionController.hostShared(
      plan: _plan(),
      identity: const DeviceIdentity(deviceId: 'host', displayName: 'Alex'),
      invitation: invitation,
      transport: hostTransport,
      historyRepository: _MemoryHistory(),
      clock: clock,
    );
    final LiveSessionController guest = await LiveSessionController.joinShared(
      identity: const DeviceIdentity(deviceId: 'guest', displayName: 'Sam'),
      invitation: invitation,
      transport: guestTransport,
      historyRepository: _MemoryHistory(),
      clock: clock,
    );
    addTearDown(() async {
      await guest.shutdown();
      guest.dispose();
      await host.shutdown();
      host.dispose();
    });
    await _waitUntil(() => host.session!.participantFor('guest') != null);

    await host.removeParticipant('guest');
    await _waitUntil(
      () => guestTransport.connectionState == SessionConnectionState.stale,
    );
    final int removedAtRevision = guest.session!.revision;
    await host.start();
    await _settleAsync();

    expect(
      host.session!.participantFor('guest')?.connectionState,
      ParticipantConnectionState.disconnected,
    );
    expect(guest.session!.revision, removedAtRevision);
    await expectLater(
      guestTransport.send(
        SessionEnvelope(
          sessionId: invitation.sessionId,
          messageId: 'after-eviction',
          senderDeviceId: 'guest',
          baseRevision: removedAtRevision,
          sentAt: clock.now(),
          kind: SessionMessageKind.command,
          encryptedPayload: 'ciphertext',
        ),
      ),
      throwsStateError,
    );
  });

  test(
    'committed host removal survives snapshot publication failure',
    () async {
      final _MutableClock clock = _MutableClock(DateTime.utc(2026, 7, 29, 12));
      final SessionSecrets secrets = await SessionSecrets.generate();
      final Invitation invitation = Invitation(
        sessionId: 'failed-removal-publish',
        transport: SessionTransportKind.onlineRelay,
        endpoint: Uri.parse('https://relay.example.com'),
        joinUri: Uri.parse('https://app.example.com'),
        capability: secrets.capability,
        sessionSecret: secrets.sessionSecret,
        requestedRole: SessionRole.participant,
        expiresAt: clock.now().add(const Duration(hours: 1)),
      );
      final _RecordingTransport transport = _RecordingTransport('host');
      final LiveSessionController host = await LiveSessionController.hostShared(
        plan: _plan(),
        identity: const DeviceIdentity(deviceId: 'host', displayName: 'Alex'),
        invitation: invitation,
        transport: transport,
        historyRepository: _MemoryHistory(),
        clock: clock,
      );
      addTearDown(() async {
        await host.shutdown();
        host.dispose();
      });
      final SessionCommand join = SessionCommand.join(
        id: 'join-before-failed-removal',
        sessionId: invitation.sessionId,
        actorDeviceId: 'guest',
        baseRevision: host.session!.revision,
        issuedAt: clock.now(),
        displayName: 'Sam',
        requestedRole: SessionRole.participant,
        authenticationSecret: 'abcdefghijklmnopqrstuvwxyz123456',
      );
      await transport.emitEnvelope(
        await _sealCommand(
          join,
          sessionSecret: secrets.sessionSecret,
          sentAt: clock.now(),
        ),
        peerRole: SessionRole.participant,
        connectionId: 'connection-to-remove',
      );
      await _waitUntil(
        () => host.session!.participantFor('guest') != null,
        'participant enrollment',
      );
      await _settleAsync();

      transport.failNextSend = true;
      await expectLater(host.removeParticipant('guest'), completes);

      expect(
        transport.revokedDeviceTokens,
        contains(
          await SessionDeviceToken.derive(
            deviceId: 'guest',
            sessionSecret: secrets.sessionSecret,
          ),
        ),
      );
      expect(
        host.session!.participantFor('guest')?.connectionState,
        ParticipantConnectionState.disconnected,
      );
      expect(host.lastError, contains('saved but could not reach'));
    },
  );

  test('failed shared initialization closes its transport', () async {
    final _MutableClock clock = _MutableClock(DateTime.utc(2026, 7, 29, 12));
    final SessionSecrets secrets = await SessionSecrets.generate();
    final Invitation invitation = Invitation(
      sessionId: 'failed-initialization',
      transport: SessionTransportKind.onlineRelay,
      endpoint: Uri.parse('https://relay.example.com'),
      joinUri: Uri.parse('https://app.example.com'),
      capability: secrets.capability,
      sessionSecret: secrets.sessionSecret,
      requestedRole: SessionRole.participant,
      expiresAt: clock.now().add(const Duration(hours: 1)),
    );
    final _RecordingTransport failedHost = _RecordingTransport(
      'host',
      failHost: true,
    );
    final _RecordingTransport failedGuest = _RecordingTransport(
      'guest',
      failJoin: true,
    );

    await expectLater(
      LiveSessionController.hostShared(
        plan: _plan(),
        identity: const DeviceIdentity(deviceId: 'host', displayName: 'Alex'),
        invitation: invitation,
        transport: failedHost,
        historyRepository: _MemoryHistory(),
        clock: clock,
      ),
      throwsStateError,
    );
    await expectLater(
      LiveSessionController.joinShared(
        identity: const DeviceIdentity(deviceId: 'guest', displayName: 'Sam'),
        invitation: invitation,
        transport: failedGuest,
        historyRepository: _MemoryHistory(),
        clock: clock,
      ),
      throwsStateError,
    );

    expect(failedHost.closeCount, 1);
    expect(failedGuest.closeCount, 1);
  });

  test(
    'dispose blocks queued callbacks and closes transport best-effort',
    () async {
      final _MutableClock clock = _MutableClock(DateTime.utc(2026, 7, 29, 12));
      final SessionSecrets secrets = await SessionSecrets.generate();
      final Invitation invitation = Invitation(
        sessionId: 'dispose-race-session',
        transport: SessionTransportKind.onlineRelay,
        endpoint: Uri.parse('https://relay.example.com'),
        joinUri: Uri.parse('https://app.example.com'),
        capability: secrets.capability,
        sessionSecret: secrets.sessionSecret,
        requestedRole: SessionRole.participant,
        expiresAt: clock.now().add(const Duration(hours: 1)),
      );
      final _RecordingTransport transport = _RecordingTransport('host');
      final _ManualCueDelivery cues = _ManualCueDelivery();
      addTearDown(cues.dispose);
      final LiveSessionController host = await LiveSessionController.hostShared(
        plan: _plan(),
        identity: const DeviceIdentity(deviceId: 'host', displayName: 'Alex'),
        invitation: invitation,
        transport: transport,
        historyRepository: _MemoryHistory(),
        clock: clock,
        cueService: cues,
      );

      cues.emit(
        const LiveCue(
          kind: LiveCueKind.approaching,
          stepIndex: 0,
          stepTitle: 'One',
        ),
      );
      host.dispose();
      await _settleAsync();

      expect(transport.closeCount, 1);
      await host.shutdown();
      expect(transport.closeCount, 1);
    },
  );

  test(
    'evicts superseded and post-removal connections for one device',
    () async {
      final _MutableClock clock = _MutableClock(DateTime.utc(2026, 7, 29, 12));
      final SessionSecrets secrets = await SessionSecrets.generate();
      final Invitation invitation = Invitation(
        sessionId: 'reconnect-eviction',
        transport: SessionTransportKind.onlineRelay,
        endpoint: Uri.parse('https://relay.example.com'),
        joinUri: Uri.parse('https://app.example.com'),
        capability: secrets.capability,
        sessionSecret: secrets.sessionSecret,
        requestedRole: SessionRole.participant,
        expiresAt: clock.now().add(const Duration(hours: 1)),
      );
      final _RecordingTransport transport = _RecordingTransport('host');
      final LiveSessionController host = await LiveSessionController.hostShared(
        plan: _plan(),
        identity: const DeviceIdentity(deviceId: 'host', displayName: 'Alex'),
        invitation: invitation,
        transport: transport,
        historyRepository: _MemoryHistory(),
        clock: clock,
      );
      addTearDown(() async {
        await host.shutdown();
        host.dispose();
      });
      const String deviceSecret = 'a2345678901234567890123456789012';
      SessionCommand join(String id) {
        return SessionCommand.join(
          id: id,
          sessionId: invitation.sessionId,
          actorDeviceId: 'guest',
          baseRevision: host.session!.revision,
          issuedAt: clock.now(),
          displayName: 'Sam',
          requestedRole: SessionRole.participant,
          authenticationSecret: deviceSecret,
        );
      }

      await transport.emitEnvelope(
        await _sealCommand(
          join('first-join'),
          sessionSecret: secrets.sessionSecret,
          sentAt: clock.now(),
        ),
        peerRole: SessionRole.participant,
        connectionId: 'connection-1',
      );
      await _waitUntil(() => host.session!.participantFor('guest') != null);
      await transport.emitEnvelope(
        await _sealCommand(
          join('reconnect'),
          sessionSecret: secrets.sessionSecret,
          sentAt: clock.now(),
        ),
        peerRole: SessionRole.participant,
        connectionId: 'connection-2',
      );
      await _waitUntil(
        () => transport.disconnectedPeers.contains('connection-1'),
        'superseded connection eviction',
      );

      await host.removeParticipant('guest');
      expect(
        transport.revokedDeviceTokens,
        contains(
          await SessionDeviceToken.derive(
            deviceId: 'guest',
            sessionSecret: secrets.sessionSecret,
          ),
        ),
      );
      final int removedRevision = host.session!.revision;
      await transport.emitEnvelope(
        await _sealCommand(
          join('join-after-removal'),
          sessionSecret: secrets.sessionSecret,
          sentAt: clock.now(),
        ),
        peerRole: SessionRole.participant,
        connectionId: 'connection-3',
      );
      await _waitUntil(
        () => transport.disconnectedPeers.contains('connection-3'),
        'post-removal reconnect eviction',
      );

      expect(host.session!.revision, removedRevision);
      expect(
        host.session!.participantFor('guest')?.connectionState,
        ParticipantConnectionState.disconnected,
      );
    },
  );
}

Plan _plan({
  bool firstStepAutoAdvance = false,
  bool secondStepAutoAdvance = false,
}) {
  final DateTime timestamp = DateTime.utc(2026, 7, 28, 12);
  return Plan(
    id: 'plan',
    title: 'Live show',
    defaultCueProfile: CueProfile(),
    steps: <Step>[
      Step(
        id: 'one',
        planId: 'plan',
        position: 0,
        title: 'One',
        durationSeconds: 10,
        autoAdvance: firstStepAutoAdvance,
      ),
      Step(
        id: 'two',
        planId: 'plan',
        position: 1,
        title: 'Two',
        durationSeconds: 20,
        autoAdvance: secondStepAutoAdvance,
      ),
    ],
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

Future<void> _settleAsync() async {
  await Future<void>.delayed(const Duration(milliseconds: 20));
}

Future<void> _waitUntil(bool Function() predicate, [String? reason]) async {
  for (int attempt = 0; attempt < 100; attempt += 1) {
    if (predicate()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail(
    'Timed out waiting for the shared session to settle'
    '${reason == null ? '.' : ': $reason.'}',
  );
}

Future<SessionEnvelope> _sealCommand(
  SessionCommand command, {
  required String sessionSecret,
  required DateTime sentAt,
}) {
  return SessionEnvelopeCrypto(sessionSecret).seal(
    sessionId: command.sessionId,
    messageId: command.id,
    senderDeviceId: command.actorDeviceId,
    baseRevision: command.baseRevision,
    sentAt: sentAt,
    kind: SessionMessageKind.command,
    payload: <String, Object?>{'type': 'command', 'command': command.toJson()},
  );
}

Future<SessionEnvelope> _sealSnapshot(
  LiveSession session, {
  required String sessionSecret,
  required DateTime sentAt,
}) {
  return SessionEnvelopeCrypto(sessionSecret).seal(
    sessionId: session.id,
    messageId: 'snapshot-${session.revision}',
    senderDeviceId: session.hostDeviceId,
    baseRevision: session.revision,
    sentAt: sentAt,
    kind: SessionMessageKind.snapshot,
    payload: <String, Object?>{
      'type': 'snapshot',
      'session': LiveSessionSnapshot.fromSession(session).toJson(),
    },
  );
}

Future<void> _emitRelaySnapshot(
  FakeWebSocketChannel channel,
  LiveSession session, {
  required String sessionSecret,
  required String messageId,
  required DateTime sentAt,
}) async {
  final DateTime normalizedSentAt = sentAt.toUtc();
  final SessionEnvelope envelope = await SessionEnvelopeCrypto(sessionSecret)
      .seal(
        sessionId: session.id,
        messageId: messageId,
        senderDeviceId: session.hostDeviceId,
        baseRevision: session.revision,
        sentAt: normalizedSentAt,
        kind: SessionMessageKind.snapshot,
        payload: <String, Object?>{
          'type': 'snapshot',
          'session': LiveSessionSnapshot.fromSession(session).toJson(),
        },
      );
  final RelayCiphertext encrypted = await RelayPayloadCrypto(
    sessionSecret,
  ).seal(envelope);
  channel.addIncoming(
    jsonEncode(<String, Object?>{
      'type': 'snapshot',
      'messageId': messageId,
      'revision': session.revision,
      'sentAt': normalizedSentAt.toIso8601String(),
      'nonce': encrypted.nonce,
      'ciphertext': encrypted.ciphertext,
    }),
  );
}

final class _MutableClock implements Clock {
  _MutableClock(this._now);

  DateTime _now;

  @override
  DateTime now() => _now;

  void advance(Duration duration) {
    _now = _now.add(duration);
  }
}

final class _ThrowingCueDelivery implements LiveCueDelivery {
  _ThrowingCueDelivery() {
    _cues = StreamController<LiveCue>.broadcast(
      onCancel: () => subscriptionCancelled = true,
    );
  }

  late final StreamController<LiveCue> _cues;
  bool subscriptionCancelled = false;

  @override
  Stream<LiveCue> get cues => _cues.stream;

  @override
  Future<void> evaluate(LiveSession session, DateTime now) async {
    throw StateError('cue delivery failed');
  }

  @override
  Future<void> unlockAudio() async {}

  Future<void> dispose() => _cues.close();
}

final class _ManualCueDelivery implements LiveCueDelivery {
  final StreamController<LiveCue> _cues = StreamController<LiveCue>.broadcast();

  @override
  Stream<LiveCue> get cues => _cues.stream;

  @override
  Future<void> evaluate(LiveSession session, DateTime now) async {}

  @override
  Future<void> unlockAudio() async {}

  void emit(LiveCue cue) => _cues.add(cue);

  Future<void> dispose() => _cues.close();
}

final class _MemoryHistory implements SessionHistoryRepository {
  final List<LiveSession> saved = <LiveSession>[];
  final List<SessionRecoveryKind> recoveryKinds = <SessionRecoveryKind>[];
  bool failNextSave = false;

  @override
  Future<void> deleteSession(String id) async {
    saved.removeWhere((LiveSession session) => session.id == id);
  }

  @override
  Future<LiveSession?> getSession(String id) async {
    for (final LiveSession session in saved.reversed) {
      if (session.id == id) {
        return session;
      }
    }
    return null;
  }

  @override
  Future<LiveSession?> prepareStartupRecovery({
    required String hostDeviceId,
  }) async {
    for (final LiveSession session in saved.reversed) {
      if (session.hostDeviceId == hostDeviceId &&
          session.status != LiveSessionStatus.ended) {
        return session;
      }
    }
    return null;
  }

  @override
  Future<List<LiveSession>> getSessions({int limit = 50}) async {
    return saved.reversed.take(limit).toList();
  }

  @override
  Future<void> saveSession(
    LiveSession session, {
    required String hostDisplayName,
    required SessionRecoveryKind recoveryKind,
  }) async {
    if (failNextSave) {
      failNextSave = false;
      throw StateError('Simulated persistence failure.');
    }
    saved.add(session);
    recoveryKinds.add(recoveryKind);
  }

  @override
  Stream<List<LiveSession>> watchSessions({int limit = 50}) {
    return Stream<List<LiveSession>>.value(saved.reversed.take(limit).toList());
  }
}

final class _RecordingTransport implements SessionTransport {
  _RecordingTransport(
    this.deviceId, {
    this.failHost = false,
    this.failJoin = false,
  });

  @override
  final String deviceId;

  final StreamController<ReceivedSessionEnvelope> _messages =
      StreamController<ReceivedSessionEnvelope>.broadcast();
  final StreamController<SessionConnectionState> _states =
      StreamController<SessionConnectionState>.broadcast(sync: true);
  final StreamController<SessionPeerEvent> _peers =
      StreamController<SessionPeerEvent>.broadcast();
  final List<SessionEnvelope> sent = <SessionEnvelope>[];

  SessionConnectionState _state = SessionConnectionState.idle;
  bool failNextSend = false;
  bool failNextRevoke = false;
  bool failNextRoleUpdate = false;
  final bool failHost;
  final bool failJoin;
  int closeCount = 0;
  final List<String> disconnectedPeers = <String>[];
  final List<String> revokedDeviceTokens = <String>[];
  final List<({String deviceToken, SessionRole role})> roleUpdates =
      <({String deviceToken, SessionRole role})>[];
  String? _sessionSecret;

  @override
  SessionConnectionState get connectionState => _state;

  @override
  Stream<SessionConnectionState> get connectionStates => _states.stream;

  @override
  Stream<ReceivedSessionEnvelope> get messages => _messages.stream;

  @override
  Stream<SessionPeerEvent> get peerEvents => _peers.stream;

  @override
  Future<void> host(Invitation invitation) async {
    if (failHost) {
      throw StateError('Simulated host failure.');
    }
    _sessionSecret = invitation.sessionSecret;
    emitState(SessionConnectionState.hosting);
  }

  @override
  Future<void> join(Invitation invitation) async {
    if (failJoin) {
      throw StateError('Simulated join failure.');
    }
    _sessionSecret = invitation.sessionSecret;
    emitState(SessionConnectionState.connected);
  }

  @override
  Future<void> disconnectPeer(String connectionId) async {
    disconnectedPeers.add(connectionId);
  }

  @override
  Future<void> revokeDevice(String deviceToken) async {
    revokedDeviceTokens.add(deviceToken);
    if (failNextRevoke) {
      failNextRevoke = false;
      throw StateError('Simulated revocation acknowledgement failure.');
    }
  }

  @override
  Future<void> updatePeerRole(String deviceToken, SessionRole role) async {
    roleUpdates.add((deviceToken: deviceToken, role: role));
    if (failNextRoleUpdate) {
      failNextRoleUpdate = false;
      throw StateError('Simulated role update failure.');
    }
  }

  @override
  Future<void> send(SessionEnvelope envelope) async {
    if (failNextSend) {
      failNextSend = false;
      throw StateError('Simulated snapshot loss.');
    }
    sent.add(envelope);
  }

  void emitState(SessionConnectionState state) {
    _state = state;
    _states.add(state);
  }

  Future<void> emitEnvelope(
    SessionEnvelope envelope, {
    SessionRole peerRole = SessionRole.host,
    String connectionId = 'recording-host',
    String? deviceToken,
  }) async {
    final String? authenticatedDeviceToken =
        deviceToken ??
        (_sessionSecret == null
            ? null
            : await SessionDeviceToken.derive(
                deviceId: envelope.senderDeviceId,
                sessionSecret: _sessionSecret!,
              ));
    _messages.add(
      ReceivedSessionEnvelope(
        envelope: envelope,
        peer: AuthenticatedSessionPeer(
          connectionId: connectionId,
          role: peerRole,
          deviceToken: authenticatedDeviceToken,
        ),
      ),
    );
  }

  void emitPeerEvent(SessionPeerEvent event) {
    _peers.add(event);
  }

  @override
  Future<void> close() async {
    if (_state == SessionConnectionState.closed) {
      return;
    }
    closeCount += 1;
    emitState(SessionConnectionState.closed);
    await _messages.close();
    await _states.close();
    await _peers.close();
  }
}
