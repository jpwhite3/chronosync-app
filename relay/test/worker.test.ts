import { env } from "cloudflare:workers";
import {
  runDurableObjectAlarm,
  runInDurableObject,
  SELF,
} from "cloudflare:test";
import { describe, expect, it } from "vitest";
import {
  CONNECTION_HEARTBEAT_TIMEOUT_MS,
  MAX_CONNECTIONS,
  MAX_CREATE_BODY_BYTES,
  MAX_ENCRYPTED_PAYLOAD_BYTES,
  MAX_MESSAGE_BYTES,
  MAX_RETAINED_DEVICES,
  RATE_LIMIT_MESSAGES,
  ROOM_TTL_MS,
} from "../src/constants";
import type {
  RoomConfig,
  SocketAttachment,
} from "../src/protocol";

interface CreatedRoom {
  protocolVersion: number;
  roomId: string;
  websocketPath: string;
  expiresAt: string;
  capabilities: {
    host: string;
    controller: string;
    participant: string;
    display: string;
  };
}

describe("ChronoSync relay", () => {
  it("reports health without exposing room data", async () => {
    const response = await SELF.fetch("https://relay.test/health");

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      status: "ok",
      service: "chronosync-relay",
      protocolVersion: 1,
    });
  });

  it("creates an anonymous room with role-scoped capabilities", async () => {
    const room = await createRoom();

    expect(room.protocolVersion).toBe(1);
    expect(room.roomId).toMatch(/^[A-Za-z0-9_-]{20,64}$/);
    expect(room.websocketPath).toBe(
      `/v1/rooms/${room.roomId}/connect`,
    );
    expect(Date.parse(room.expiresAt)).toBeGreaterThan(Date.now());
    expect(new Set(Object.values(room.capabilities)).size).toBe(4);
  });

  it("measures the room creation body when Content-Length is absent", async () => {
    const body = new ReadableStream<Uint8Array>({
      start(controller): void {
        controller.enqueue(
          new TextEncoder().encode("x".repeat(MAX_CREATE_BODY_BYTES + 1)),
        );
        controller.close();
      },
    });
    const request = new Request("https://relay.test/v1/rooms", {
      method: "POST",
      body,
    });
    expect(request.headers.has("Content-Length")).toBe(false);

    const response = await SELF.fetch(request);

    expect(response.status).toBe(413);
    await expect(response.json()).resolves.toMatchObject({
      error: { code: "request_too_large" },
    });
  });

  it("rejects an invalid WebSocket capability", async () => {
    const room = await createRoom();
    const response = await connect(
      room,
      "host",
      "invalid_capability_token_that_is_long_enough",
    );

    expect(response.status).toBe(401);
  });

  it("accepts a maximum encrypted payload plus its JSON envelope", async () => {
    const room = await createRoom();
    const host = await openSocket(
      await connect(room, "host", room.capabilities.host),
    );
    await nextMessageOfType(host, "welcome");
    const snapshot = {
      type: "snapshot",
      messageId: "snapshot_maximum_payload",
      revision: 0,
      sentAt: "2026-07-28T12:00:00.000Z",
      nonce: "abcdefghijklmnop",
      ciphertext: "a".repeat(MAX_ENCRYPTED_PAYLOAD_BYTES),
    };

    host.send(JSON.stringify(snapshot));

    await expect(nextMessageOfType(host, "snapshot")).resolves.toEqual(
      snapshot,
    );
    host.close();
  });

  it("closes an oversized frame before trying to parse it", async () => {
    const room = await createRoom();
    const participant = await openSocket(
      await connect(
        room,
        "participant",
        room.capabilities.participant,
      ),
    );
    await nextMessageOfType(participant, "welcome");
    const closed = nextClose(participant);

    participant.send("x".repeat(MAX_MESSAGE_BYTES + 1));

    await expect(closed).resolves.toMatchObject({ code: 1009 });
  });

  it("retains the latest host snapshot for later participants", async () => {
    const room = await createRoom();
    const host = await openSocket(
      await connect(room, "host", room.capabilities.host),
    );
    expect(await nextMessageOfType(host, "welcome")).toMatchObject({
      expiresAt: room.expiresAt,
    });

    const snapshot = {
      type: "snapshot",
      messageId: "snapshot_001",
      revision: 0,
      sentAt: "2026-07-28T12:00:00.000Z",
      nonce: "abcdefghijklmnop",
      ciphertext: "encrypted_snapshot",
    };
    host.send(JSON.stringify(snapshot));
    expect(await nextMessageOfType(host, "snapshot")).toEqual(snapshot);

    const participant = await openSocket(
      await connect(
        room,
        "participant",
        room.capabilities.participant,
      ),
    );
    await nextMessageOfType(participant, "welcome");
    expect(await nextMessageOfType(participant, "snapshot")).toEqual(
      snapshot,
    );

    host.close();
    participant.close();
  });

  it("accepts revision gaps while rejecting rollback snapshots", async () => {
    const room = await createRoom();
    const host = await openSocket(
      await connect(room, "host", room.capabilities.host),
    );
    await nextMessageOfType(host, "welcome");

    const initialSnapshot = {
      type: "snapshot",
      messageId: "snapshot_initial",
      revision: 0,
      sentAt: "2026-07-28T12:00:00.000Z",
      nonce: "abcdefghijklmnop",
      ciphertext: "encrypted_initial",
    };
    host.send(JSON.stringify(initialSnapshot));
    await nextMessageOfType(host, "snapshot");

    const recoveredSnapshot = {
      type: "snapshot",
      messageId: "snapshot_recovered",
      revision: 3,
      sentAt: "2026-07-28T12:00:03.000Z",
      nonce: "abcdefghijklmnop",
      ciphertext: "encrypted_recovered",
    };
    host.send(JSON.stringify(recoveredSnapshot));
    expect(await nextMessageOfType(host, "snapshot")).toEqual(
      recoveredSnapshot,
    );

    host.send(JSON.stringify(recoveredSnapshot));
    expect(await nextMessageOfType(host, "snapshot_accepted"))
      .toMatchObject({
        messageId: "snapshot_recovered",
        revision: 3,
        duplicate: true,
      });

    host.send(
      JSON.stringify({
        ...recoveredSnapshot,
        messageId: "snapshot_rollback",
        revision: 2,
        ciphertext: "encrypted_rollback",
      }),
    );
    expect(await nextMessageOfType(host, "error")).toMatchObject({
      code: "revision_conflict",
      currentRevision: 3,
    });

    const participant = await openSocket(
      await connect(
        room,
        "participant",
        room.capabilities.participant,
      ),
    );
    await nextMessageOfType(participant, "welcome");
    expect(await nextMessageOfType(participant, "snapshot")).toEqual(
      recoveredSnapshot,
    );

    host.close();
    participant.close();
  });

  it("refreshes and broadcasts an active host snapshot at the retained revision", async () => {
    const room = await createRoom();
    const host = await openSocket(
      await connect(room, "host", room.capabilities.host),
    );
    const hostWelcome = await nextMessageOfType(host, "welcome");

    const initialSnapshot = {
      type: "snapshot",
      messageId: "snapshot_initial",
      revision: 3,
      sentAt: "2026-07-28T12:00:03.000Z",
      nonce: "abcdefghijklmnop",
      ciphertext: "encrypted_initial",
    };
    host.send(JSON.stringify(initialSnapshot));
    await nextMessageOfType(host, "snapshot");

    const participant = await openSocket(
      await connect(
        room,
        "participant",
        room.capabilities.participant,
      ),
    );
    await nextMessageOfType(participant, "welcome");
    await expect(
      nextMessageOfType(participant, "snapshot"),
    ).resolves.toEqual(initialSnapshot);

    const refreshedSnapshot = {
      ...initialSnapshot,
      messageId: "snapshot_refreshed",
      sentAt: "2026-07-28T12:00:04.000Z",
      ciphertext: "encrypted_refreshed",
    };
    const hostRefresh = nextMessageOfType(host, "snapshot");
    const participantRefresh = nextMessageOfType(
      participant,
      "snapshot",
    );
    host.send(JSON.stringify(refreshedSnapshot));

    await expect(hostRefresh).resolves.toEqual(refreshedSnapshot);
    await expect(participantRefresh).resolves.toEqual(
      refreshedSnapshot,
    );

    const noDuplicateBroadcast = expectNoMessageOfType(
      participant,
      "snapshot",
    );
    host.send(JSON.stringify(refreshedSnapshot));
    await expect(
      nextMessageOfType(host, "snapshot_accepted"),
    ).resolves.toMatchObject({
      messageId: "snapshot_refreshed",
      revision: 3,
      duplicate: true,
    });
    await noDuplicateBroadcast;

    host.send(
      JSON.stringify({
        ...refreshedSnapshot,
        messageId: "snapshot_rollback",
        revision: 2,
      }),
    );
    await expect(nextMessageOfType(host, "error")).resolves.toMatchObject({
      code: "revision_conflict",
      currentRevision: 3,
    });

    const display = await openSocket(
      await connect(room, "display", room.capabilities.display),
    );
    await nextMessageOfType(display, "welcome");
    await expect(
      nextMessageOfType(display, "snapshot"),
    ).resolves.toEqual(refreshedSnapshot);

    await setConnectionRateCount(
      room,
      String(hostWelcome.connectionId),
      RATE_LIMIT_MESSAGES,
    );
    const hostClosed = nextClose(host);
    host.send(
      JSON.stringify({
        ...refreshedSnapshot,
        messageId: "snapshot_rate_limited",
      }),
    );
    await expect(nextMessageOfType(host, "error")).resolves.toMatchObject({
      code: "rate_limited",
    });
    await expect(hostClosed).resolves.toMatchObject({ code: 1013 });

    participant.close();
    display.close();
  });

  it("forwards opaque participant commands only to the host", async () => {
    const room = await createRoom();
    const host = await openSocket(
      await connect(room, "host", room.capabilities.host),
    );
    await nextMessageOfType(host, "welcome");
    host.send(
      JSON.stringify({
        type: "snapshot",
        messageId: "snapshot_001",
        revision: 0,
        sentAt: "2026-07-28T12:00:00.000Z",
        nonce: "abcdefghijklmnop",
        ciphertext: "encrypted_snapshot",
      }),
    );
    await nextMessageOfType(host, "snapshot");

    const participantDeviceToken = "q".repeat(43);
    const participant = await openSocket(
      await connect(
        room,
        "participant",
        room.capabilities.participant,
        participantDeviceToken,
      ),
    );
    await nextMessageOfType(participant, "welcome");
    await nextMessageOfType(participant, "snapshot");

    const command = {
      type: "command",
      messageId: "command_001",
      baseRevision: 0,
      sentAt: "2026-07-28T12:00:00.000Z",
      nonce: "abcdefghijklmnop",
      ciphertext: "encrypted_acknowledgement",
    };
    participant.send(JSON.stringify(command));

    const forwarded = await nextMessageOfType(host, "command");
    expect(forwarded).toMatchObject(command);
    expect(forwarded).toMatchObject({
      sender: {
        role: "participant",
        deviceToken: participantDeviceToken,
      },
    });
    expect(await nextMessageOfType(participant, "command_forwarded"))
      .toMatchObject({
        messageId: "command_001",
        duplicate: false,
      });

    host.close();
    participant.close();
  });

  it("expires a half-open host and reports authoritative absence", async () => {
    const room = await createRoom();
    const host = await openSocket(
      await connect(room, "host", room.capabilities.host),
    );
    await nextMessageOfType(host, "welcome");
    host.send(
      JSON.stringify({
        type: "snapshot",
        messageId: "snapshot_for_liveness",
        revision: 0,
        sentAt: "2026-07-28T12:00:00.000Z",
        nonce: "abcdefghijklmnop",
        ciphertext: "encrypted_snapshot",
      }),
    );
    await nextMessageOfType(host, "snapshot");
    const participant = await openSocket(
      await connect(
        room,
        "participant",
        room.capabilities.participant,
      ),
    );
    expect(await nextMessageOfType(participant, "welcome")).toMatchObject({
      hostConnected: true,
    });
    await nextMessageOfType(participant, "snapshot");

    await ageHostHeartbeat(room);
    const hostClosed = nextClose(host);
    const presenceReceived = nextMessageOfType(participant, "presence");
    const pongReceived = nextMessageOfType(participant, "pong");
    participant.send(JSON.stringify({ type: "ping" }));

    await expect(pongReceived).resolves.toMatchObject({
      hostConnected: false,
    });
    await expect(presenceReceived).resolves.toMatchObject({
      hostConnected: false,
      counts: {
        host: 0,
        participant: 1,
      },
    });
    await expect(hostClosed).resolves.toMatchObject({
      code: 4002,
      reason: "Host heartbeat timeout",
    });

    participant.send(
      JSON.stringify({
        type: "command",
        messageId: "command_without_host",
        baseRevision: 0,
        sentAt: "2026-07-28T12:00:00.000Z",
        nonce: "abcdefghijklmnop",
        ciphertext: "encrypted_acknowledgement",
      }),
    );
    expect(await nextMessageOfType(participant, "error")).toMatchObject({
      code: "host_unavailable",
    });

    const hostReturned = nextMessageOfType(
      participant,
      "presence",
      (message: Record<string, unknown>): boolean =>
        message.hostConnected === true,
    );
    const replacementHost = await openSocket(
      await connect(room, "host", room.capabilities.host),
    );
    await nextMessageOfType(replacementHost, "welcome");
    await expect(hostReturned).resolves.toMatchObject({
      hostConnected: true,
      counts: {
        host: 1,
        participant: 1,
      },
    });

    replacementHost.close();
    participant.close();
  });

  it("expires stale participant and display sockets before routing", async () => {
    const room = await createRoom();
    const host = await openSocket(
      await connect(room, "host", room.capabilities.host),
    );
    await nextMessageOfType(host, "welcome");
    host.send(
      JSON.stringify({
        type: "snapshot",
        messageId: "snapshot_for_peer_liveness",
        revision: 0,
        sentAt: "2026-07-28T12:00:00.000Z",
        nonce: "abcdefghijklmnop",
        ciphertext: "encrypted_snapshot",
      }),
    );
    await nextMessageOfType(host, "snapshot");

    const participant = await openSocket(
      await connect(
        room,
        "participant",
        room.capabilities.participant,
      ),
    );
    const participantWelcome = await nextMessageOfType(
      participant,
      "welcome",
    );
    await nextMessageOfType(participant, "snapshot");
    const display = await openSocket(
      await connect(room, "display", room.capabilities.display),
    );
    const displayWelcome = await nextMessageOfType(display, "welcome");
    await nextMessageOfType(display, "snapshot");
    const participantConnectionId = String(
      participantWelcome.connectionId,
    );
    const displayConnectionId = String(displayWelcome.connectionId);

    await ageConnectionHeartbeats(room, [
      participantConnectionId,
      displayConnectionId,
    ]);
    const participantClosed = nextClose(participant);
    const displayClosed = nextClose(display);
    const presenceReceived = nextMessageOfType(host, "presence");
    const noForwardedCommand = expectNoMessageOfType(host, "command");
    participant.send(
      JSON.stringify({
        type: "command",
        messageId: "stale_peer_command",
        baseRevision: 0,
        sentAt: "2026-07-28T12:00:01.000Z",
        nonce: "abcdefghijklmnop",
        ciphertext: "encrypted_acknowledgement",
      }),
    );

    await expect(presenceReceived).resolves.toMatchObject({
      hostConnected: true,
      counts: {
        host: 1,
        controller: 0,
        participant: 0,
        display: 0,
      },
    });
    await expect(participantClosed).resolves.toMatchObject({
      code: 4002,
      reason: "Connection heartbeat timeout",
    });
    await expect(displayClosed).resolves.toMatchObject({
      code: 4002,
      reason: "Connection heartbeat timeout",
    });
    await noForwardedCommand;
    host.close();
  });

  it("shows opaque device tokens only to the host in presence", async () => {
    const room = await createRoom();
    const host = await openSocket(
      await connect(room, "host", room.capabilities.host),
    );
    await nextMessageOfType(host, "welcome");
    const participantDeviceToken = "v".repeat(43);
    const hostPresence = nextMessageOfType(
      host,
      "presence",
      (message) =>
        (message.counts as Record<string, number>).participant === 1,
    );
    const participant = await openSocket(
      await connect(
        room,
        "participant",
        room.capabilities.participant,
        participantDeviceToken,
      ),
    );
    await nextMessageOfType(participant, "welcome");
    const participantPresence = await nextMessageOfType(
      participant,
      "presence",
      (message) =>
        (message.counts as Record<string, number>).participant === 1,
    );

    await expect(hostPresence).resolves.toMatchObject({
      connections: expect.arrayContaining([
        expect.objectContaining({
          role: "participant",
          deviceToken: participantDeviceToken,
        }),
      ]),
    });
    expect(
      (participantPresence.connections as Record<string, unknown>[]).every(
        (connection) => connection.deviceToken === undefined,
      ),
    ).toBe(true);
    host.close();
    participant.close();
  });

  it("blocks a device before ack and closes every socket sharing its token", async () => {
    const room = await createRoom();
    const host = await openSocket(
      await connect(room, "host", room.capabilities.host),
    );
    await nextMessageOfType(host, "welcome");
    const snapshot = {
      type: "snapshot",
      messageId: "snapshot_before_eviction",
      revision: 0,
      sentAt: "2026-07-28T12:00:00.000Z",
      nonce: "abcdefghijklmnop",
      ciphertext: "encrypted_snapshot",
    };
    host.send(JSON.stringify(snapshot));
    await nextMessageOfType(host, "snapshot");

    const removedDeviceToken = "r".repeat(43);
    const participant = await openSocket(
      await connect(
        room,
        "participant",
        room.capabilities.participant,
        removedDeviceToken,
      ),
    );
    await nextMessageOfType(participant, "welcome");
    await nextMessageOfType(participant, "snapshot");
    const controller = await openSocket(
      await connect(
        room,
        "controller",
        room.capabilities.controller,
        removedDeviceToken,
      ),
    );
    await nextMessageOfType(controller, "welcome");
    await nextMessageOfType(controller, "snapshot");
    const participantClose = nextClose(participant);
    const controllerClose = nextClose(controller);
    host.send(
      JSON.stringify({
        type: "disconnect_peer",
        requestId: "disconnect_same_device",
        deviceToken: removedDeviceToken,
      }),
    );
    await expect(
      nextMessageOfType(host, "peer_disconnect_result"),
    ).resolves.toEqual({
      type: "peer_disconnect_result",
      requestId: "disconnect_same_device",
      deviceToken: removedDeviceToken,
      status: "disconnected",
      disconnectedConnections: 2,
    });
    await expect(participantClose).resolves.toMatchObject({ code: 4003 });
    await expect(controllerClose).resolves.toMatchObject({ code: 4003 });
    await expect(blockedDeviceTokens(room)).resolves.toContain(
      removedDeviceToken,
    );

    const reconnected = await openSocket(
      await connect(
        room,
        "participant",
        room.capabilities.participant,
        removedDeviceToken,
      ),
    );
    const reconnectClose = nextClose(reconnected);
    const noSnapshot = expectNoMessageOfType(reconnected, "snapshot");

    await expect(reconnectClose).resolves.toEqual({
      code: 4003,
      reason: "Removed by host",
    });
    await expect(noSnapshot).resolves.toBeUndefined();

    const replacementDevice = await openSocket(
      await connect(
        room,
        "participant",
        room.capabilities.participant,
        "n".repeat(43),
      ),
    );
    await nextMessageOfType(replacementDevice, "welcome");
    await expect(
      nextMessageOfType(replacementDevice, "snapshot"),
    ).resolves.toEqual(snapshot);
    host.close();
    replacementDevice.close();
  });

  it("tombstones an absent device and reports a correlated not-found result", async () => {
    const room = await createRoom();
    const host = await openSocket(
      await connect(room, "host", room.capabilities.host),
    );
    await nextMessageOfType(host, "welcome");
    const absentDeviceToken = "a".repeat(43);

    host.send(
      JSON.stringify({
        type: "disconnect_peer",
        requestId: "disconnect_absent_device",
        deviceToken: absentDeviceToken,
      }),
    );

    await expect(
      nextMessageOfType(host, "peer_disconnect_result"),
    ).resolves.toEqual({
      type: "peer_disconnect_result",
      requestId: "disconnect_absent_device",
      deviceToken: absentDeviceToken,
      status: "not_found",
      disconnectedConnections: 0,
    });
    await expect(blockedDeviceTokens(room)).resolves.toContain(
      absentDeviceToken,
    );

    const rejected = await openSocket(
      await connect(
        room,
        "participant",
        room.capabilities.participant,
        absentDeviceToken,
      ),
    );
    await expect(nextClose(rejected)).resolves.toMatchObject({ code: 4003 });
    host.close();
  });

  it("returns a correlated failure instead of tombstoning the active host", async () => {
    const room = await createRoom();
    const hostDeviceToken = "z".repeat(43);
    const host = await openSocket(
      await connect(
        room,
        "host",
        room.capabilities.host,
        hostDeviceToken,
      ),
    );
    await nextMessageOfType(host, "welcome");

    host.send(
      JSON.stringify({
        type: "disconnect_peer",
        requestId: "disconnect_active_host",
        deviceToken: hostDeviceToken,
      }),
    );

    await expect(
      nextMessageOfType(host, "peer_disconnect_result"),
    ).resolves.toEqual({
      type: "peer_disconnect_result",
      requestId: "disconnect_active_host",
      deviceToken: hostDeviceToken,
      status: "failed",
      disconnectedConnections: 0,
      errorCode: "active_host_token",
    });
    await expect(blockedDeviceTokens(room)).resolves.not.toContain(
      hostDeviceToken,
    );
    host.send(JSON.stringify({ type: "ping" }));
    await expect(nextMessageOfType(host, "pong")).resolves.toMatchObject({
      hostConnected: true,
    });
    host.close();
  });

  it("disconnects one connection without tombstoning its device", async () => {
    const room = await createRoom();
    const host = await openSocket(
      await connect(room, "host", room.capabilities.host),
    );
    await nextMessageOfType(host, "welcome");
    const sharedDeviceToken = "k".repeat(43);
    const participant = await openSocket(
      await connect(
        room,
        "participant",
        room.capabilities.participant,
        sharedDeviceToken,
      ),
    );
    const participantWelcome = await nextMessageOfType(
      participant,
      "welcome",
    );
    const controller = await openSocket(
      await connect(
        room,
        "controller",
        room.capabilities.controller,
        sharedDeviceToken,
      ),
    );
    await nextMessageOfType(controller, "welcome");
    const participantClose = nextClose(participant);

    host.send(
      JSON.stringify({
        type: "disconnect_connection",
        requestId: "disconnect_untrusted_connection",
        connectionId: participantWelcome.connectionId,
      }),
    );

    await expect(
      nextMessageOfType(host, "peer_disconnect_result"),
    ).resolves.toEqual({
      type: "peer_disconnect_result",
      requestId: "disconnect_untrusted_connection",
      connectionId: participantWelcome.connectionId,
      status: "disconnected",
      disconnectedConnections: 1,
    });
    await expect(participantClose).resolves.toMatchObject({ code: 4003 });
    await expect(blockedDeviceTokens(room)).resolves.not.toContain(
      sharedDeviceToken,
    );
    controller.send(JSON.stringify({ type: "ping" }));
    await expect(nextMessageOfType(controller, "pong")).resolves.toMatchObject({
      hostConnected: true,
    });

    const reconnected = await openSocket(
      await connect(
        room,
        "participant",
        room.capabilities.participant,
        sharedDeviceToken,
      ),
    );
    await expect(
      nextMessageOfType(reconnected, "welcome"),
    ).resolves.toMatchObject({
      role: "participant",
    });
    host.close();
    controller.close();
    reconnected.close();
  });

  it("rejects participant attempts to evict another connection", async () => {
    const room = await createRoom();
    const host = await openSocket(
      await connect(room, "host", room.capabilities.host),
    );
    await nextMessageOfType(host, "welcome");
    const participant = await openSocket(
      await connect(
        room,
        "participant",
        room.capabilities.participant,
      ),
    );
    await nextMessageOfType(participant, "welcome");

    participant.send(
      JSON.stringify({
        type: "disconnect_peer",
        requestId: "forbidden_disconnect",
        deviceToken: "x".repeat(43),
      }),
    );

    await expect(
      nextMessageOfType(participant, "error"),
    ).resolves.toMatchObject({
      code: "forbidden",
    });
    host.close();
    participant.close();
  });

  it("applies host-managed peer roles to live sockets and reconnects", async () => {
    const room = await createRoom();
    const host = await openSocket(
      await connect(room, "host", room.capabilities.host),
    );
    await nextMessageOfType(host, "welcome");
    host.send(
      JSON.stringify({
        type: "snapshot",
        messageId: "role_snapshot_001",
        revision: 0,
        sentAt: "2026-07-28T12:00:00.000Z",
        nonce: "abcdefghijklmnop",
        ciphertext: "encrypted_role_snapshot",
      }),
    );
    await nextMessageOfType(host, "snapshot");

    const deviceToken = "u".repeat(43);
    const participant = await openSocket(
      await connect(
        room,
        "participant",
        room.capabilities.participant,
        deviceToken,
      ),
    );
    await nextMessageOfType(participant, "welcome");

    const promoted = nextMessageOfType(host, "peer_role_result");
    host.send(
      JSON.stringify({
        type: "set_peer_role",
        requestId: "promote_device_001",
        deviceToken,
        role: "controller",
      }),
    );
    await expect(promoted).resolves.toEqual({
      type: "peer_role_result",
      requestId: "promote_device_001",
      deviceToken,
      role: "controller",
      status: "updated",
      updatedConnections: 1,
    });

    const forwardedController = nextMessageOfType(host, "command");
    participant.send(
      JSON.stringify({
        type: "command",
        messageId: "controller_command_001",
        baseRevision: 0,
        sentAt: "2026-07-28T12:00:01.000Z",
        nonce: "abcdefghijklmnop",
        ciphertext: "encrypted_controller_command",
      }),
    );
    await expect(forwardedController).resolves.toMatchObject({
      sender: {
        role: "controller",
        deviceToken,
      },
    });

    participant.close();
    const reconnected = await openSocket(
      await connect(
        room,
        "participant",
        room.capabilities.participant,
        deviceToken,
      ),
    );
    await expect(nextMessageOfType(reconnected, "welcome")).resolves.toMatchObject({
      role: "controller",
    });

    const demoted = nextMessageOfType(host, "peer_role_result");
    host.send(
      JSON.stringify({
        type: "set_peer_role",
        requestId: "demote_device_001",
        deviceToken,
        role: "participant",
      }),
    );
    await expect(demoted).resolves.toMatchObject({
      requestId: "demote_device_001",
      role: "participant",
      status: "updated",
    });

    reconnected.close();
    const afterDemotion = await openSocket(
      await connect(
        room,
        "participant",
        room.capabilities.participant,
        deviceToken,
      ),
    );
    await expect(
      nextMessageOfType(afterDemotion, "welcome"),
    ).resolves.toMatchObject({ role: "participant" });
    host.close();
    afterDemotion.close();
  });

  it("rejects participant attempts to grant controller authority", async () => {
    const room = await createRoom();
    const host = await openSocket(
      await connect(room, "host", room.capabilities.host),
    );
    await nextMessageOfType(host, "welcome");
    const deviceToken = "y".repeat(43);
    const participant = await openSocket(
      await connect(
        room,
        "participant",
        room.capabilities.participant,
        deviceToken,
      ),
    );
    await nextMessageOfType(participant, "welcome");

    participant.send(
      JSON.stringify({
        type: "set_peer_role",
        requestId: "spoof_role_001",
        deviceToken,
        role: "controller",
      }),
    );
    await expect(nextMessageOfType(participant, "error")).resolves.toMatchObject({
      code: "forbidden",
    });

    participant.close();
    const reconnected = await openSocket(
      await connect(
        room,
        "participant",
        room.capabilities.participant,
        deviceToken,
      ),
    );
    await expect(nextMessageOfType(reconnected, "welcome")).resolves.toMatchObject({
      role: "participant",
    });
    host.close();
    reconnected.close();
  });

  it("bounds retained role overrides while allowing updates at capacity", async () => {
    const room = await createRoom();
    const retainedTokens = Array.from(
      { length: MAX_RETAINED_DEVICES },
      (_, index) => index.toString(36).padStart(43, "a"),
    );
    await setRetainedDeviceState(room, {
      roleOverrides: Object.fromEntries(
        retainedTokens.map((token) => [token, "participant"]),
      ),
    });
    const host = await openSocket(
      await connect(room, "host", room.capabilities.host),
    );
    await nextMessageOfType(host, "welcome");

    host.send(
      JSON.stringify({
        type: "set_peer_role",
        requestId: "role_over_capacity",
        deviceToken: "z".repeat(43),
        role: "controller",
      }),
    );
    await expect(
      nextMessageOfType(host, "peer_role_result"),
    ).resolves.toMatchObject({
      requestId: "role_over_capacity",
      status: "failed",
      errorCode: "retained_device_limit",
    });

    host.send(
      JSON.stringify({
        type: "set_peer_role",
        requestId: "role_existing_at_capacity",
        deviceToken: retainedTokens[0],
        role: "controller",
      }),
    );
    await expect(
      nextMessageOfType(host, "peer_role_result"),
    ).resolves.toMatchObject({
      requestId: "role_existing_at_capacity",
      status: "not_found",
      role: "controller",
    });
    host.close();
  });

  it("returns a correlated failure at the revocation tombstone bound", async () => {
    const room = await createRoom();
    const blockedTokens = Array.from(
      { length: MAX_RETAINED_DEVICES },
      (_, index) => index.toString(36).padStart(43, "b"),
    );
    await setRetainedDeviceState(room, { blockedTokens });
    const host = await openSocket(
      await connect(room, "host", room.capabilities.host),
    );
    await nextMessageOfType(host, "welcome");

    host.send(
      JSON.stringify({
        type: "disconnect_peer",
        requestId: "revoke_over_capacity",
        deviceToken: "z".repeat(43),
      }),
    );

    await expect(
      nextMessageOfType(host, "peer_disconnect_result"),
    ).resolves.toMatchObject({
      requestId: "revoke_over_capacity",
      status: "failed",
      errorCode: "retained_device_limit",
    });
    await expect(blockedDeviceTokens(room)).resolves.not.toContain(
      "z".repeat(43),
    );
    host.close();
  });

  it("prevents a participant from publishing authoritative state", async () => {
    const room = await createRoom();
    const participant = await openSocket(
      await connect(
        room,
        "participant",
        room.capabilities.participant,
      ),
    );
    await nextMessageOfType(participant, "welcome");

    participant.send(
      JSON.stringify({
        type: "snapshot",
        messageId: "snapshot_001",
        revision: 0,
        sentAt: "2026-07-28T12:00:00.000Z",
        nonce: "abcdefghijklmnop",
        ciphertext: "encrypted_snapshot",
      }),
    );

    expect(await nextMessageOfType(participant, "error")).toMatchObject({
      code: "forbidden",
    });
    participant.close();
  });

  it("replaces the previous host connection", async () => {
    const room = await createRoom();
    const firstHost = await openSocket(
      await connect(room, "host", room.capabilities.host),
    );
    await nextMessageOfType(firstHost, "welcome");
    const firstHostClosed = nextClose(firstHost);

    const replacementHost = await openSocket(
      await connect(room, "host", room.capabilities.host),
    );
    await nextMessageOfType(replacementHost, "welcome");

    await expect(firstHostClosed).resolves.toMatchObject({
      code: 4001,
    });
    replacementHost.close();
  });

  it("enforces the per-room controller limit", async () => {
    const room = await createRoom();
    const controllers: WebSocket[] = [];

    for (let index = 0; index < 10; index += 1) {
      const controller = await openSocket(
        await connect(
          room,
          "controller",
          room.capabilities.controller,
        ),
      );
      await nextMessageOfType(controller, "welcome");
      controllers.push(controller);
    }

    const rejected = await connect(
      room,
      "controller",
      room.capabilities.controller,
    );
    expect(rejected.status).toBe(503);
    await expect(rejected.json()).resolves.toMatchObject({
      error: {
        code: "controller_limit",
        message: "The room has reached its Timekeeper limit.",
      },
    });

    for (const controller of controllers) {
      controller.close();
    }
  });

  it("allows 50 guests in addition to the authoritative host", async () => {
    const room = await createRoom();
    const host = await openSocket(
      await connect(room, "host", room.capabilities.host),
    );
    await nextMessageOfType(host, "welcome");
    const guests: WebSocket[] = [];

    for (let index = 0; index < MAX_CONNECTIONS; index += 1) {
      const guest = await openSocket(
        await connect(
          room,
          "display",
          room.capabilities.display,
          index.toString(36).padStart(43, "g"),
        ),
      );
      await nextMessageOfType(guest, "welcome");
      guests.push(guest);
    }

    const rejected = await connect(
      room,
      "display",
      room.capabilities.display,
      "z".repeat(43),
    );
    expect(rejected.status).toBe(503);
    await expect(rejected.json()).resolves.toMatchObject({
      error: { code: "room_full" },
    });

    host.close();
    for (const guest of guests) {
      guest.close();
    }
  });

  it(
    "reclaims stale sockets before enforcing room capacity",
    async () => {
      const room = await createRoom();
      const displays: WebSocket[] = [];
      let staleConnectionId: string | undefined;

      for (let index = 0; index < MAX_CONNECTIONS; index += 1) {
        const display = await openSocket(
          await connect(room, "display", room.capabilities.display),
        );
        const welcome = await nextMessageOfType(display, "welcome");
        staleConnectionId ??= String(welcome.connectionId);
        displays.push(display);
      }

      const full = await connect(
        room,
        "display",
        room.capabilities.display,
      );
      expect(full.status).toBe(503);
      await expect(full.json()).resolves.toMatchObject({
        error: {
          code: "room_full",
        },
      });

      if (staleConnectionId === undefined) {
        throw new Error("Expected a display connection.");
      }
      const staleDisplay = displays[0];
      if (staleDisplay === undefined) {
        throw new Error("Expected a stale display socket.");
      }
      await ageConnectionHeartbeats(room, [staleConnectionId]);
      const staleClosed = nextClose(staleDisplay);
      const replacement = await openSocket(
        await connect(room, "display", room.capabilities.display),
      );
      await nextMessageOfType(replacement, "welcome");
      await expect(staleClosed).resolves.toMatchObject({
        code: 4002,
      });

      replacement.close();
      for (const display of displays) {
        display.close();
      }
    },
    15_000,
  );

  it("rejects new sockets after the fixed capability expiry", async () => {
    const room = await createRoom();
    const host = await openSocket(
      await connect(room, "host", room.capabilities.host),
    );
    await nextMessageOfType(host, "welcome");

    await updateRoomConfig(room, (config: RoomConfig): RoomConfig => ({
      ...config,
      expiresAt: Date.now() - 1,
    }));

    const rejected = await connect(
      room,
      "participant",
      room.capabilities.participant,
    );
    expect(rejected.status).toBe(410);
    await expect(rejected.json()).resolves.toMatchObject({
      error: {
        code: "room_expired",
      },
    });

    host.send(JSON.stringify({ type: "ping" }));
    expect(await nextMessageOfType(host, "pong")).toMatchObject({
      type: "pong",
    });
    host.close();
  });

  it("derives a fixed expiry for rooms created before expiry was stored", async () => {
    const room = await createRoom();
    await updateRoomConfig(room, (config: RoomConfig): RoomConfig => {
      const legacyConfig: RoomConfig = {
        ...config,
        createdAt: Date.now() - ROOM_TTL_MS - 1,
      };
      delete legacyConfig.expiresAt;
      return legacyConfig;
    });

    const rejected = await connect(
      room,
      "participant",
      room.capabilities.participant,
    );
    expect(rejected.status).toBe(410);
    await expect(rejected.json()).resolves.toMatchObject({
      error: {
        code: "room_expired",
      },
    });
  });

  it("deletes inactive rooms when their alarm runs", async () => {
    const room = await createRoom();
    const durableObjectId = env.ROOMS.idFromName(room.roomId);
    const stub = env.ROOMS.get(durableObjectId);

    await runInDurableObject(
      stub,
      async (
        _instance: DurableObject,
        state: DurableObjectState,
      ): Promise<void> => {
        const expiredAt = Date.now() - 24 * 60 * 60 * 1000 - 1;
        await state.storage.put("lastActivityAt", expiredAt);
        await state.storage.setAlarm(Date.now() + 60_000);
      },
    );
    expect(await runDurableObjectAlarm(stub)).toBe(true);

    const response = await connect(
      room,
      "participant",
      room.capabilities.participant,
    );
    expect(response.status).toBe(404);
  });
});

async function updateRoomConfig(
  room: CreatedRoom,
  update: (config: RoomConfig) => RoomConfig,
): Promise<void> {
  const durableObjectId = env.ROOMS.idFromName(room.roomId);
  const stub = env.ROOMS.get(durableObjectId);
  await runInDurableObject(
    stub,
    async (
      _instance: DurableObject,
      state: DurableObjectState,
    ): Promise<void> => {
      const config = await state.storage.get<RoomConfig>("config");
      if (config === undefined) {
        throw new Error("Expected room config.");
      }
      await state.storage.put("config", update(config));
    },
  );
}

async function ageHostHeartbeat(room: CreatedRoom): Promise<void> {
  const durableObjectId = env.ROOMS.idFromName(room.roomId);
  const stub = env.ROOMS.get(durableObjectId);
  await runInDurableObject(
    stub,
    async (
      _instance: DurableObject,
      state: DurableObjectState,
    ): Promise<void> => {
      const host = state.getWebSockets().find((socket: WebSocket) => {
        const attachment =
          socket.deserializeAttachment() as SocketAttachment | undefined;
        return attachment?.role === "host";
      });
      if (host === undefined) {
        throw new Error("Expected a connected host.");
      }
      const attachment =
        host.deserializeAttachment() as SocketAttachment | undefined;
      if (attachment === undefined) {
        throw new Error("Expected a host attachment.");
      }
      attachment.lastSeenAt =
        Date.now() - CONNECTION_HEARTBEAT_TIMEOUT_MS - 1;
      host.serializeAttachment(attachment);
    },
  );
}

async function ageConnectionHeartbeats(
  room: CreatedRoom,
  connectionIds: string[],
): Promise<void> {
  const targets = new Set(connectionIds);
  const durableObjectId = env.ROOMS.idFromName(room.roomId);
  const stub = env.ROOMS.get(durableObjectId);
  await runInDurableObject(
    stub,
    async (
      _instance: DurableObject,
      state: DurableObjectState,
    ): Promise<void> => {
      const matched = new Set<string>();
      for (const socket of state.getWebSockets()) {
        const attachment =
          socket.deserializeAttachment() as SocketAttachment | undefined;
        if (
          attachment === undefined ||
          !targets.has(attachment.connectionId)
        ) {
          continue;
        }
        attachment.lastSeenAt =
          Date.now() - CONNECTION_HEARTBEAT_TIMEOUT_MS - 1;
        socket.serializeAttachment(attachment);
        matched.add(attachment.connectionId);
      }
      if (matched.size !== targets.size) {
        throw new Error("Expected every target relay connection.");
      }
    },
  );
}

async function setConnectionRateCount(
  room: CreatedRoom,
  connectionId: string,
  rateCount: number,
): Promise<void> {
  const durableObjectId = env.ROOMS.idFromName(room.roomId);
  const stub = env.ROOMS.get(durableObjectId);
  await runInDurableObject(
    stub,
    async (
      _instance: DurableObject,
      state: DurableObjectState,
    ): Promise<void> => {
      const socket = state.getWebSockets().find((candidate: WebSocket) => {
        const attachment =
          candidate.deserializeAttachment() as
            | SocketAttachment
            | undefined;
        return attachment?.connectionId === connectionId;
      });
      if (socket === undefined) {
        throw new Error("Expected the relay connection.");
      }
      const attachment =
        socket.deserializeAttachment() as SocketAttachment | undefined;
      if (attachment === undefined) {
        throw new Error("Expected a socket attachment.");
      }
      attachment.rateWindowStartedAt = Date.now();
      attachment.rateCount = rateCount;
      socket.serializeAttachment(attachment);
    },
  );
}

async function blockedDeviceTokens(room: CreatedRoom): Promise<string[]> {
  const durableObjectId = env.ROOMS.idFromName(room.roomId);
  const stub = env.ROOMS.get(durableObjectId);
  return runInDurableObject(
    stub,
    async (
      _instance: DurableObject,
      state: DurableObjectState,
    ): Promise<string[]> =>
      (await state.storage.get<string[]>("blockedDeviceTokens")) ?? [],
  );
}

async function setRetainedDeviceState(
  room: CreatedRoom,
  values: {
    blockedTokens?: string[];
    roleOverrides?: Record<string, "participant" | "controller" | "display">;
  },
): Promise<void> {
  const durableObjectId = env.ROOMS.idFromName(room.roomId);
  const stub = env.ROOMS.get(durableObjectId);
  await runInDurableObject(
    stub,
    async (
      _instance: DurableObject,
      state: DurableObjectState,
    ): Promise<void> => {
      if (values.blockedTokens !== undefined) {
        await state.storage.put("blockedDeviceTokens", values.blockedTokens);
      }
      if (values.roleOverrides !== undefined) {
        await state.storage.put("deviceRoleOverrides", values.roleOverrides);
      }
    },
  );
}

async function createRoom(): Promise<CreatedRoom> {
  const response = await SELF.fetch("https://relay.test/v1/rooms", {
    method: "POST",
  });
  expect(response.status).toBe(201);
  return (await response.json()) as CreatedRoom;
}

function connect(
  room: CreatedRoom,
  role: keyof CreatedRoom["capabilities"],
  capability: string,
  deviceToken = defaultDeviceToken(role),
): Promise<Response> {
  return SELF.fetch(`https://relay.test${room.websocketPath}`, {
    headers: {
      Upgrade: "websocket",
      "Sec-WebSocket-Protocol": [
        "chronosync.v1",
        `role.${role}`,
        `cap.${capability}`,
        `device.${deviceToken}`,
      ].join(", "),
    },
  });
}

function defaultDeviceToken(
  role: keyof CreatedRoom["capabilities"],
): string {
  const prefix = {
    host: "h",
    controller: "c",
    participant: "p",
    display: "d",
  }[role];
  return prefix.repeat(43);
}

async function openSocket(response: Response): Promise<WebSocket> {
  expect(response.status).toBe(101);
  expect(response.webSocket).not.toBeNull();
  const webSocket = response.webSocket;
  if (webSocket === null) {
    throw new Error("Expected WebSocket upgrade response.");
  }
  webSocket.accept();
  return webSocket;
}

function nextMessageOfType(
  webSocket: WebSocket,
  type: string,
  matches: (message: Record<string, unknown>) => boolean = (): boolean =>
    true,
): Promise<Record<string, unknown>> {
  return new Promise<Record<string, unknown>>((resolve, reject) => {
    const timeout = setTimeout(() => {
      webSocket.removeEventListener("message", listener);
      reject(new Error(`Timed out waiting for ${type}.`));
    }, 2_000);
    const listener = (event: MessageEvent): void => {
      const parsed = JSON.parse(String(event.data)) as Record<
        string,
        unknown
      >;
      if (parsed.type !== type || !matches(parsed)) {
        return;
      }
      clearTimeout(timeout);
      webSocket.removeEventListener("message", listener);
      resolve(parsed);
    };
    webSocket.addEventListener("message", listener);
  });
}

function expectNoMessageOfType(
  webSocket: WebSocket,
  type: string,
): Promise<void> {
  return new Promise<void>((resolve, reject) => {
    const timeout = setTimeout(() => {
      webSocket.removeEventListener("message", listener);
      resolve();
    }, 100);
    const listener = (event: MessageEvent): void => {
      const parsed = JSON.parse(String(event.data)) as Record<
        string,
        unknown
      >;
      if (parsed.type !== type) {
        return;
      }
      clearTimeout(timeout);
      webSocket.removeEventListener("message", listener);
      reject(new Error(`Unexpectedly received ${type}.`));
    };
    webSocket.addEventListener("message", listener);
  });
}

function nextClose(
  webSocket: WebSocket,
): Promise<{ code: number; reason: string }> {
  return new Promise<{ code: number; reason: string }>((resolve) => {
    webSocket.addEventListener(
      "close",
      (event: CloseEvent) => {
        resolve({
          code: event.code,
          reason: event.reason,
        });
      },
      { once: true },
    );
  });
}
