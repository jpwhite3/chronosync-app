import {
  CONNECTION_HEARTBEAT_TIMEOUT_MS,
  MAX_CONNECTIONS,
  MAX_CONTROLLERS,
  MAX_MESSAGE_BYTES,
  MAX_RETAINED_DEVICES,
  PROTOCOL_VERSION,
  RATE_LIMIT_MESSAGES,
  RATE_LIMIT_WINDOW_MS,
  ROLE_VALUES,
  ROOM_TTL_MS,
  type Role,
} from "./constants";
import {
  decodeWebSocketMessage,
  errorResponse,
  hashToken,
  jsonResponse,
  parseClientMessage,
  parseWebSocketCredentials,
  randomToken,
  type CommandMessage,
  type DisconnectConnectionMessage,
  type DisconnectPeerMessage,
  type Env,
  type RoomConfig,
  type SetPeerRoleMessage,
  type SnapshotMessage,
  type SocketAttachment,
  type StoredSnapshot,
} from "./protocol";

const CONFIG_KEY = "config";
const ACTIVE_HOST_CONNECTION_KEY = "activeHostConnectionId";
const LAST_ACTIVITY_KEY = "lastActivityAt";
const LATEST_REVISION_KEY = "latestRevision";
const LATEST_SNAPSHOT_KEY = "latestSnapshot";
const BLOCKED_DEVICE_TOKENS_KEY = "blockedDeviceTokens";
const DEVICE_ROLE_OVERRIDES_KEY = "deviceRoleOverrides";

type PeerRole = Exclude<Role, "host">;

export class Room implements DurableObject {
  private deleting = false;

  public constructor(
    private readonly state: DurableObjectState,
    _env: Env,
  ) {}

  public async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "POST" && url.pathname === "/create") {
      return this.createRoom(request);
    }
    if (request.method === "GET" && url.pathname === "/connect") {
      return this.handleConnect(request);
    }

    return errorResponse("not_found", "Route not found.", 404);
  }

  public async webSocketMessage(
    webSocket: WebSocket,
    rawMessage: string | ArrayBuffer,
  ): Promise<void> {
    const attachment = this.getAttachment(webSocket);
    if (attachment === undefined || this.deleting) {
      webSocket.close(1011, "Missing relay connection state");
      return;
    }

    const receivedAt = Date.now();
    if (!this.isRecentlyAlive(attachment, receivedAt)) {
      await this.expireSocket(webSocket, attachment);
      await this.expireStaleSockets(receivedAt, webSocket);
      await this.broadcastPresence(receivedAt);
      return;
    }

    if (!this.consumeRateLimit(webSocket, attachment)) {
      this.sendError(
        webSocket,
        "rate_limited",
        "Too many messages were sent.",
      );
      webSocket.close(1013, "Rate limit exceeded");
      return;
    }

    const decoded = decodeWebSocketMessage(rawMessage);
    if (decoded === undefined) {
      this.sendError(
        webSocket,
        "message_too_large",
        `Messages must be valid UTF-8 JSON no larger than ${MAX_MESSAGE_BYTES} bytes.`,
      );
      webSocket.close(1009, "Message too large");
      return;
    }

    const message = parseClientMessage(decoded);
    if (message === undefined) {
      this.sendError(
        webSocket,
        "invalid_message",
        "The message does not match relay protocol version 1.",
      );
      return;
    }

    attachment.lastSeenAt = receivedAt;
    webSocket.serializeAttachment(attachment);
    await this.touch(receivedAt);
    if (await this.expireStaleSockets(receivedAt, webSocket)) {
      await this.broadcastPresence(receivedAt);
    }

    switch (message.type) {
      case "snapshot":
        await this.handleSnapshot(webSocket, attachment, message);
        return;
      case "command":
        await this.handleCommand(webSocket, attachment, message);
        return;
      case "disconnect_peer":
        await this.handleDisconnectPeer(webSocket, attachment, message);
        return;
      case "disconnect_connection":
        await this.handleDisconnectConnection(
          webSocket,
          attachment,
          message,
        );
        return;
      case "set_peer_role":
        await this.handleSetPeerRole(webSocket, attachment, message);
        return;
      case "ping":
        const hostConnected =
          (await this.findHostSocket(receivedAt)) !== undefined;
        this.sendJson(webSocket, {
          type: "pong",
          now: new Date().toISOString(),
          latestRevision: await this.latestRevision(),
          hostConnected,
        });
        return;
      case "end_room":
        if (
          attachment.role !== "host" ||
          !(await this.isActiveHost(attachment))
        ) {
          this.sendError(
            webSocket,
            "forbidden",
            "Only the active host can end a room.",
          );
          return;
        }
        await this.deleteRoom("ended");
    }
  }

  public async webSocketClose(
    webSocket: WebSocket,
    _code: number,
    _reason: string,
    _wasClean: boolean,
  ): Promise<void> {
    if (this.deleting) {
      return;
    }
    const now = Date.now();
    await this.clearActiveHost(webSocket);
    await this.expireStaleSockets(now, webSocket);
    await this.touch(now);
    await this.broadcastPresence(now);
  }

  public async webSocketError(
    webSocket: WebSocket,
    _error: unknown,
  ): Promise<void> {
    if (this.deleting) {
      return;
    }
    const now = Date.now();
    try {
      webSocket.close(1011, "WebSocket error");
    } finally {
      await this.clearActiveHost(webSocket);
      await this.expireStaleSockets(now, webSocket);
      await this.touch(now);
      await this.broadcastPresence(now);
    }
  }

  public async alarm(): Promise<void> {
    const lastActivityAt =
      await this.state.storage.get<number>(LAST_ACTIVITY_KEY);
    if (lastActivityAt === undefined) {
      return;
    }

    const expiresAt = lastActivityAt + ROOM_TTL_MS;
    if (Date.now() < expiresAt) {
      await this.state.storage.setAlarm(expiresAt);
      return;
    }

    await this.deleteRoom("expired");
  }

  private async createRoom(request: Request): Promise<Response> {
    const existing =
      await this.state.storage.get<RoomConfig>(CONFIG_KEY);
    if (existing !== undefined) {
      return errorResponse(
        "room_exists",
        "This room has already been initialized.",
        409,
      );
    }

    const roomId = request.headers.get("X-ChronoSync-Room-Id");
    if (roomId === null) {
      return errorResponse(
        "invalid_room",
        "The room identifier is missing.",
        400,
      );
    }

    const capabilities: Record<Role, string> = {
      host: randomToken(),
      controller: randomToken(),
      participant: randomToken(),
      display: randomToken(),
    };
    const capabilityHashEntries = await Promise.all(
      ROLE_VALUES.map(
        async (role: Role): Promise<[Role, string]> => [
          role,
          await hashToken(capabilities[role]),
        ],
      ),
    );
    const capabilityHashes = Object.fromEntries(
      capabilityHashEntries,
    ) as Record<Role, string>;
    const now = Date.now();
    const config: RoomConfig = {
      protocolVersion: PROTOCOL_VERSION,
      roomId,
      createdAt: now,
      expiresAt: now + ROOM_TTL_MS,
      capabilityHashes,
    };

    await this.state.storage.put({
      [CONFIG_KEY]: config,
      [LAST_ACTIVITY_KEY]: now,
      [LATEST_REVISION_KEY]: -1,
    });
    await this.state.storage.setAlarm(now + ROOM_TTL_MS);

    return jsonResponse(
      {
        protocolVersion: PROTOCOL_VERSION,
        roomId,
        websocketPath: `/v1/rooms/${roomId}/connect`,
        expiresAt: new Date(now + ROOM_TTL_MS).toISOString(),
        capabilities,
        limits: {
          connections: MAX_CONNECTIONS,
          controllers: MAX_CONTROLLERS,
          messageBytes: MAX_MESSAGE_BYTES,
        },
      },
      201,
    );
  }

  private async handleConnect(request: Request): Promise<Response> {
    if (
      request.headers.get("Upgrade")?.toLowerCase() !== "websocket"
    ) {
      return errorResponse(
        "upgrade_required",
        "Use a WebSocket upgrade request.",
        426,
        { Upgrade: "websocket" },
      );
    }

    const config =
      await this.state.storage.get<RoomConfig>(CONFIG_KEY);
    if (config === undefined) {
      return errorResponse(
        "room_not_found",
        "The room does not exist or has expired.",
        404,
      );
    }
    const now = Date.now();
    const capabilityExpiresAt = this.capabilityExpiresAt(config);
    if (now >= capabilityExpiresAt) {
      return errorResponse(
        "room_expired",
        "The room invitation has expired.",
        410,
      );
    }

    const lastActivityAt =
      await this.state.storage.get<number>(LAST_ACTIVITY_KEY);
    if (
      lastActivityAt !== undefined &&
      now >= lastActivityAt + ROOM_TTL_MS
    ) {
      await this.deleteRoom("expired");
      return errorResponse(
        "room_expired",
        "The room has expired.",
        410,
      );
    }

    const credentials = parseWebSocketCredentials(
      request.headers.get("Sec-WebSocket-Protocol"),
    );
    if (credentials === undefined) {
      return errorResponse(
        "invalid_credentials",
        "Provide protocol, role, and capability WebSocket subprotocols.",
        401,
      );
    }

    const providedHash = await hashToken(credentials.token);
    if (providedHash !== config.capabilityHashes[credentials.role]) {
      return errorResponse(
        "invalid_credentials",
        "The role capability is invalid.",
        401,
      );
    }

    if (await this.isDeviceTokenBlocked(credentials.deviceToken)) {
      return this.closeBlockedWebSocket(
        credentials.role,
        credentials.deviceToken,
        now,
      );
    }

    if (await this.expireStaleSockets(now)) {
      await this.broadcastPresence(now);
    }
    const sockets = this.state.getWebSockets();
    const activeSockets: WebSocket[] = [];
    const activeHostConnectionId =
      await this.state.storage.get<string>(
        ACTIVE_HOST_CONNECTION_KEY,
      );
    for (const socket of sockets) {
      const attachment = this.getAttachment(socket);
      if (
        attachment === undefined ||
        !this.isRecentlyAlive(attachment, now)
      ) {
        continue;
      }
      if (credentials.role === "host" && attachment?.role === "host") {
        socket.close(4001, "Host reconnected elsewhere");
      } else if (
        attachment.role === "host" &&
        attachment.connectionId !== activeHostConnectionId
      ) {
        socket.close(4001, "Host replaced");
      } else {
        activeSockets.push(socket);
      }
    }

    const effectiveRole =
      credentials.role === "host"
        ? "host"
        : await this.effectivePeerRole(
            credentials.deviceToken,
            credentials.role,
          );
    const activeGuestCount = activeSockets.filter(
      (socket: WebSocket) => this.getAttachment(socket)?.role !== "host",
    ).length;
    if (effectiveRole !== "host" && activeGuestCount >= MAX_CONNECTIONS) {
      return errorResponse(
        "room_full",
        "The room has reached its connection limit.",
        503,
      );
    }

    if (
      effectiveRole === "controller" &&
      this.countRole(activeSockets, "controller") >= MAX_CONTROLLERS
    ) {
      return errorResponse(
        "controller_limit",
        "The room has reached its controller limit.",
        503,
      );
    }

    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair) as [
      WebSocket,
      WebSocket,
    ];
    const attachment: SocketAttachment = {
      connectionId: randomToken(12),
      role: effectiveRole,
      deviceToken: credentials.deviceToken,
      connectedAt: now,
      lastSeenAt: now,
      recentMessageIds: [],
      rateWindowStartedAt: now,
      rateCount: 0,
    };
    server.serializeAttachment(attachment);
    this.state.acceptWebSocket(server);
    if (attachment.role === "host") {
      await this.state.storage.put(
        ACTIVE_HOST_CONNECTION_KEY,
        attachment.connectionId,
      );
    }

    await this.touch(now);
    const latestRevision = await this.latestRevision();
    this.sendJson(server, {
      type: "welcome",
      protocolVersion: PROTOCOL_VERSION,
      roomId: config.roomId,
      connectionId: attachment.connectionId,
      role: attachment.role,
      latestRevision,
      hostConnected:
        attachment.role === "host" ||
        (await this.findHostSocket()) !== undefined,
      expiresAt: new Date(capabilityExpiresAt).toISOString(),
      limits: {
        messageBytes: MAX_MESSAGE_BYTES,
      },
    });

    const latestSnapshot =
      await this.state.storage.get<StoredSnapshot>(
        LATEST_SNAPSHOT_KEY,
      );
    if (latestSnapshot !== undefined) {
      this.sendJson(server, latestSnapshot);
    }
    await this.broadcastPresence(now);

    return new Response(null, {
      status: 101,
      webSocket: client,
      headers: {
        "Sec-WebSocket-Protocol": `chronosync.v${PROTOCOL_VERSION}`,
      },
    });
  }

  private async handleSnapshot(
    webSocket: WebSocket,
    attachment: SocketAttachment,
    message: SnapshotMessage,
  ): Promise<void> {
    if (attachment.role !== "host") {
      this.sendError(
        webSocket,
        "forbidden",
        "Only the host can publish authoritative snapshots.",
      );
      return;
    }
    if (!(await this.isActiveHost(attachment))) {
      this.sendError(
        webSocket,
        "host_replaced",
        "This host connection is no longer authoritative.",
      );
      return;
    }

    if (this.hasMessageId(attachment, message.messageId)) {
      this.sendJson(webSocket, {
        type: "snapshot_accepted",
        messageId: message.messageId,
        revision: await this.latestRevision(),
        duplicate: true,
      });
      return;
    }
    const retainedSnapshot =
      await this.state.storage.get<StoredSnapshot>(
        LATEST_SNAPSHOT_KEY,
      );
    if (retainedSnapshot?.messageId === message.messageId) {
      this.rememberMessageId(webSocket, attachment, message.messageId);
      this.sendJson(webSocket, {
        type: "snapshot_accepted",
        messageId: message.messageId,
        revision: retainedSnapshot.revision,
        duplicate: true,
      });
      return;
    }

    const result = await this.state.storage.transaction(
      async (
        transaction: DurableObjectTransaction,
      ): Promise<{ accepted: boolean; currentRevision: number }> => {
        const currentRevision =
          (await transaction.get<number>(LATEST_REVISION_KEY)) ?? -1;
        if (message.revision < currentRevision) {
          return { accepted: false, currentRevision };
        }
        await transaction.put(LATEST_REVISION_KEY, message.revision);
        await transaction.put(LATEST_SNAPSHOT_KEY, message);
        return {
          accepted: true,
          currentRevision: message.revision,
        };
      },
    );

    if (!result.accepted) {
      this.sendJson(webSocket, {
        type: "error",
        code: "revision_conflict",
        message:
          "Snapshots cannot precede the retained snapshot revision.",
        currentRevision: result.currentRevision,
      });
      return;
    }

    this.rememberMessageId(webSocket, attachment, message.messageId);
    this.broadcastJson(message);
  }

  private async handleCommand(
    webSocket: WebSocket,
    attachment: SocketAttachment,
    message: CommandMessage,
  ): Promise<void> {
    if (
      attachment.role !== "controller" &&
      attachment.role !== "participant"
    ) {
      this.sendError(
        webSocket,
        "forbidden",
        "This role cannot submit commands.",
      );
      return;
    }

    const currentRevision = await this.latestRevision();
    if (this.hasMessageId(attachment, message.messageId)) {
      this.sendJson(webSocket, {
        type: "command_forwarded",
        messageId: message.messageId,
        currentRevision,
        duplicate: true,
      });
      return;
    }

    if (message.baseRevision !== currentRevision) {
      this.sendJson(webSocket, {
        type: "error",
        code: "revision_conflict",
        message: "The command was based on a stale room revision.",
        currentRevision,
      });
      return;
    }

    const host = await this.findHostSocket();
    if (host === undefined) {
      this.sendError(
        webSocket,
        "host_unavailable",
        "The host is not currently connected.",
      );
      return;
    }

    this.rememberMessageId(webSocket, attachment, message.messageId);
    this.sendJson(host, {
      ...message,
      sender: {
        connectionId: attachment.connectionId,
        role: attachment.role,
        ...(attachment.deviceToken === undefined
          ? {}
          : { deviceToken: attachment.deviceToken }),
      },
    });
    this.sendJson(webSocket, {
      type: "command_forwarded",
      messageId: message.messageId,
      currentRevision,
      duplicate: false,
    });
  }

  private async handleDisconnectPeer(
    webSocket: WebSocket,
    attachment: SocketAttachment,
    message: DisconnectPeerMessage,
  ): Promise<void> {
    if (!(await this.canDisconnectPeer(attachment))) {
      this.sendError(
        webSocket,
        "forbidden",
        "Only the active host can disconnect a peer.",
      );
      return;
    }

    const hostUsesToken = this.state.getWebSockets().some(
      (socket: WebSocket): boolean => {
        const candidate = this.getAttachment(socket);
        return (
          candidate?.role === "host" &&
          candidate.deviceToken === message.deviceToken
        );
      },
    );
    if (hostUsesToken) {
      this.sendPeerDisconnectResult(webSocket, {
        requestId: message.requestId,
        deviceToken: message.deviceToken,
        status: "failed",
        disconnectedConnections: 0,
        errorCode: "active_host_token",
      });
      return;
    }

    try {
      // The durable tombstone must commit before either the acknowledgement or
      // a close that could race a reconnect attempt.
      const retained = await this.blockDeviceToken(message.deviceToken);
      if (!retained) {
        this.sendPeerDisconnectResult(webSocket, {
          requestId: message.requestId,
          deviceToken: message.deviceToken,
          status: "failed",
          disconnectedConnections: 0,
          errorCode: "retained_device_limit",
        });
        return;
      }
    } catch {
      this.sendPeerDisconnectResult(webSocket, {
        requestId: message.requestId,
        deviceToken: message.deviceToken,
        status: "failed",
        disconnectedConnections: 0,
        errorCode: "storage_unavailable",
      });
      return;
    }

    let disconnectedConnections = 0;
    for (const target of this.state.getWebSockets()) {
      const targetAttachment = this.getAttachment(target);
      if (
        targetAttachment?.role === "host" ||
        targetAttachment?.deviceToken !== message.deviceToken
      ) {
        continue;
      }
      targetAttachment.heartbeatExpired = true;
      target.serializeAttachment(targetAttachment);
      target.close(4003, "Removed by host");
      disconnectedConnections += 1;
    }

    this.sendPeerDisconnectResult(webSocket, {
      requestId: message.requestId,
      deviceToken: message.deviceToken,
      status:
        disconnectedConnections === 0 ? "not_found" : "disconnected",
      disconnectedConnections,
    });
    await this.broadcastPresence();
  }

  private async handleDisconnectConnection(
    webSocket: WebSocket,
    attachment: SocketAttachment,
    message: DisconnectConnectionMessage,
  ): Promise<void> {
    if (!(await this.canDisconnectPeer(attachment))) {
      this.sendError(
        webSocket,
        "forbidden",
        "Only the active host can disconnect a peer.",
      );
      return;
    }

    const target = this.state.getWebSockets().find((socket: WebSocket) => {
      const candidate = this.getAttachment(socket);
      return candidate?.connectionId === message.connectionId;
    });
    const targetAttachment =
      target === undefined ? undefined : this.getAttachment(target);
    if (targetAttachment?.role === "host") {
      this.sendPeerDisconnectResult(webSocket, {
        requestId: message.requestId,
        connectionId: message.connectionId,
        status: "failed",
        disconnectedConnections: 0,
        errorCode: "active_host_connection",
      });
      return;
    }
    if (target === undefined || targetAttachment === undefined) {
      this.sendPeerDisconnectResult(webSocket, {
        requestId: message.requestId,
        connectionId: message.connectionId,
        status: "not_found",
        disconnectedConnections: 0,
      });
      return;
    }

    targetAttachment.heartbeatExpired = true;
    target.serializeAttachment(targetAttachment);
    target.close(4003, "Removed by host");
    this.sendPeerDisconnectResult(webSocket, {
      requestId: message.requestId,
      connectionId: message.connectionId,
      status: "disconnected",
      disconnectedConnections: 1,
    });
    await this.broadcastPresence();
  }

  private async handleSetPeerRole(
    webSocket: WebSocket,
    attachment: SocketAttachment,
    message: SetPeerRoleMessage,
  ): Promise<void> {
    if (!(await this.canDisconnectPeer(attachment))) {
      this.sendError(
        webSocket,
        "forbidden",
        "Only the active host can update a peer role.",
      );
      return;
    }

    const sockets = this.state.getWebSockets();
    const hostUsesToken = sockets.some((socket: WebSocket): boolean => {
      const candidate = this.getAttachment(socket);
      return (
        candidate?.role === "host" &&
        candidate.deviceToken === message.deviceToken
      );
    });
    if (hostUsesToken) {
      this.sendPeerRoleResult(webSocket, {
        requestId: message.requestId,
        deviceToken: message.deviceToken,
        role: message.role,
        status: "failed",
        updatedConnections: 0,
        errorCode: "active_host_token",
      });
      return;
    }

    const targets = sockets.filter((socket: WebSocket): boolean => {
      const candidate = this.getAttachment(socket);
      return (
        candidate?.role !== "host" &&
        candidate?.deviceToken === message.deviceToken
      );
    });
    if (message.role === "controller") {
      const otherControllers = sockets.filter((socket: WebSocket): boolean => {
        const candidate = this.getAttachment(socket);
        return (
          candidate?.role === "controller" &&
          candidate.deviceToken !== message.deviceToken
        );
      }).length;
      if (otherControllers + targets.length > MAX_CONTROLLERS) {
        this.sendPeerRoleResult(webSocket, {
          requestId: message.requestId,
          deviceToken: message.deviceToken,
          role: message.role,
          status: "failed",
          updatedConnections: 0,
          errorCode: "controller_limit",
        });
        return;
      }
    }

    try {
      const retained = await this.state.storage.transaction(
        async (transaction): Promise<boolean> => {
          const overrides =
            (await transaction.get<Record<string, PeerRole>>(
              DEVICE_ROLE_OVERRIDES_KEY,
            )) ?? {};
          if (
            overrides[message.deviceToken] === undefined &&
            Object.keys(overrides).length >= MAX_RETAINED_DEVICES
          ) {
            return false;
          }
          await transaction.put(DEVICE_ROLE_OVERRIDES_KEY, {
            ...overrides,
            [message.deviceToken]: message.role,
          });
          return true;
        },
      );
      if (!retained) {
        this.sendPeerRoleResult(webSocket, {
          requestId: message.requestId,
          deviceToken: message.deviceToken,
          role: message.role,
          status: "failed",
          updatedConnections: 0,
          errorCode: "retained_device_limit",
        });
        return;
      }
    } catch {
      this.sendPeerRoleResult(webSocket, {
        requestId: message.requestId,
        deviceToken: message.deviceToken,
        role: message.role,
        status: "failed",
        updatedConnections: 0,
        errorCode: "storage_unavailable",
      });
      return;
    }

    for (const target of targets) {
      const targetAttachment = this.getAttachment(target);
      if (targetAttachment === undefined) {
        continue;
      }
      targetAttachment.role = message.role;
      target.serializeAttachment(targetAttachment);
    }
    this.sendPeerRoleResult(webSocket, {
      requestId: message.requestId,
      deviceToken: message.deviceToken,
      role: message.role,
      status: targets.length === 0 ? "not_found" : "updated",
      updatedConnections: targets.length,
    });
    await this.broadcastPresence();
  }

  private async canDisconnectPeer(
    attachment: SocketAttachment,
  ): Promise<boolean> {
    return (
      attachment.role === "host" &&
      (await this.isActiveHost(attachment))
    );
  }

  private sendPeerDisconnectResult(
    webSocket: WebSocket,
    result: {
      requestId: string;
      deviceToken?: string;
      connectionId?: string;
      status: "disconnected" | "not_found" | "failed";
      disconnectedConnections: number;
      errorCode?: string;
    },
  ): void {
    this.sendJson(webSocket, {
      type: "peer_disconnect_result",
      ...result,
    });
  }

  private sendPeerRoleResult(
    webSocket: WebSocket,
    result: {
      requestId: string;
      deviceToken: string;
      role: PeerRole;
      status: "updated" | "not_found" | "failed";
      updatedConnections: number;
      errorCode?: string;
    },
  ): void {
    this.sendJson(webSocket, {
      type: "peer_role_result",
      ...result,
    });
  }

  private async isDeviceTokenBlocked(deviceToken: string): Promise<boolean> {
    const blocked =
      (await this.state.storage.get<string[]>(
        BLOCKED_DEVICE_TOKENS_KEY,
      )) ?? [];
    return blocked.includes(deviceToken);
  }

  private async blockDeviceToken(deviceToken: string): Promise<boolean> {
    return this.state.storage.transaction(async (transaction) => {
      const blocked =
        (await transaction.get<string[]>(BLOCKED_DEVICE_TOKENS_KEY)) ?? [];
      const overrides =
        (await transaction.get<Record<string, PeerRole>>(
          DEVICE_ROLE_OVERRIDES_KEY,
        )) ?? {};
      const nextOverrides = { ...overrides };
      delete nextOverrides[deviceToken];
      if (!blocked.includes(deviceToken)) {
        if (blocked.length >= MAX_RETAINED_DEVICES) {
          return false;
        }
        await transaction.put(BLOCKED_DEVICE_TOKENS_KEY, [
          ...blocked,
          deviceToken,
        ]);
      }
      await transaction.put(DEVICE_ROLE_OVERRIDES_KEY, nextOverrides);
      return true;
    });
  }

  private async effectivePeerRole(
    deviceToken: string,
    requestedRole: PeerRole,
  ): Promise<PeerRole> {
    const overrides =
      (await this.state.storage.get<Record<string, PeerRole>>(
        DEVICE_ROLE_OVERRIDES_KEY,
      )) ?? {};
    return overrides[deviceToken] ?? requestedRole;
  }

  private closeBlockedWebSocket(
    role: Role,
    deviceToken: string,
    now: number,
  ): Response {
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair) as [
      WebSocket,
      WebSocket,
    ];
    const attachment: SocketAttachment = {
      connectionId: randomToken(12),
      role,
      deviceToken,
      connectedAt: now,
      lastSeenAt: now,
      heartbeatExpired: true,
      recentMessageIds: [],
      rateWindowStartedAt: now,
      rateCount: 0,
    };
    server.serializeAttachment(attachment);
    this.state.acceptWebSocket(server);
    server.close(4003, "Removed by host");
    return new Response(null, {
      status: 101,
      webSocket: client,
      headers: {
        "Sec-WebSocket-Protocol": `chronosync.v${PROTOCOL_VERSION}`,
      },
    });
  }

  private consumeRateLimit(
    webSocket: WebSocket,
    attachment: SocketAttachment,
  ): boolean {
    const now = Date.now();
    if (now - attachment.rateWindowStartedAt >= RATE_LIMIT_WINDOW_MS) {
      attachment.rateWindowStartedAt = now;
      attachment.rateCount = 1;
    } else {
      attachment.rateCount += 1;
    }
    webSocket.serializeAttachment(attachment);
    return attachment.rateCount <= RATE_LIMIT_MESSAGES;
  }

  private hasMessageId(
    attachment: SocketAttachment,
    messageId: string,
  ): boolean {
    return attachment.recentMessageIds.includes(messageId);
  }

  private rememberMessageId(
    webSocket: WebSocket,
    attachment: SocketAttachment,
    messageId: string,
  ): void {
    if (this.hasMessageId(attachment, messageId)) {
      return;
    }
    attachment.recentMessageIds.push(messageId);
    if (attachment.recentMessageIds.length > 16) {
      attachment.recentMessageIds.shift();
    }
    webSocket.serializeAttachment(attachment);
  }

  private async touch(now = Date.now()): Promise<void> {
    if (this.deleting) {
      return;
    }
    await this.state.storage.put(LAST_ACTIVITY_KEY, now);
    await this.state.storage.setAlarm(now + ROOM_TTL_MS);
  }

  private async latestRevision(): Promise<number> {
    return (
      (await this.state.storage.get<number>(LATEST_REVISION_KEY)) ?? -1
    );
  }

  private capabilityExpiresAt(config: RoomConfig): number {
    const storedExpiresAt = config.expiresAt;
    if (
      storedExpiresAt !== undefined &&
      Number.isFinite(storedExpiresAt) &&
      storedExpiresAt >= config.createdAt
    ) {
      return storedExpiresAt;
    }
    return config.createdAt + ROOM_TTL_MS;
  }

  private async findHostSocket(
    now = Date.now(),
  ): Promise<WebSocket | undefined> {
    const activeHostConnectionId =
      await this.state.storage.get<string>(
        ACTIVE_HOST_CONNECTION_KEY,
      );
    if (activeHostConnectionId === undefined) {
      return undefined;
    }
    const host = this.state.getWebSockets().find((socket: WebSocket) => {
      return (
        this.getAttachment(socket)?.connectionId ===
        activeHostConnectionId
      );
    });
    const attachment =
      host === undefined ? undefined : this.getAttachment(host);
    if (
      host === undefined ||
      attachment === undefined ||
      attachment.role !== "host"
    ) {
      await this.state.storage.delete(ACTIVE_HOST_CONNECTION_KEY);
      return undefined;
    }
    if (this.isRecentlyAlive(attachment, now)) {
      return host;
    }

    await this.expireSocket(host, attachment);
    await this.broadcastPresence(now);
    return undefined;
  }

  private async expireStaleSockets(
    now: number,
    except?: WebSocket,
  ): Promise<boolean> {
    let expired = false;
    for (const socket of this.state.getWebSockets()) {
      if (socket === except) {
        continue;
      }
      const attachment = this.getAttachment(socket);
      if (
        attachment === undefined ||
        attachment.heartbeatExpired === true ||
        this.isRecentlyAlive(attachment, now)
      ) {
        continue;
      }
      await this.expireSocket(socket, attachment);
      expired = true;
    }
    return expired;
  }

  private async expireSocket(
    webSocket: WebSocket,
    attachment: SocketAttachment,
  ): Promise<void> {
    if (attachment.heartbeatExpired === true) {
      return;
    }
    attachment.heartbeatExpired = true;
    webSocket.serializeAttachment(attachment);
    if (attachment.role === "host") {
      const activeHostConnectionId =
        await this.state.storage.get<string>(
          ACTIVE_HOST_CONNECTION_KEY,
        );
      if (activeHostConnectionId === attachment.connectionId) {
        await this.state.storage.delete(ACTIVE_HOST_CONNECTION_KEY);
      }
      this.sendError(
        webSocket,
        "host_heartbeat_timeout",
        "The host stopped sending heartbeats and is no longer authoritative.",
      );
      webSocket.close(4002, "Host heartbeat timeout");
      return;
    }

    this.sendError(
      webSocket,
      "connection_heartbeat_timeout",
      "The connection stopped sending heartbeats and has expired.",
    );
    webSocket.close(4002, "Connection heartbeat timeout");
  }

  private async clearActiveHost(webSocket: WebSocket): Promise<void> {
    const attachment = this.getAttachment(webSocket);
    if (attachment?.role !== "host") {
      return;
    }
    const activeHostConnectionId =
      await this.state.storage.get<string>(
        ACTIVE_HOST_CONNECTION_KEY,
      );
    if (activeHostConnectionId === attachment.connectionId) {
      await this.state.storage.delete(ACTIVE_HOST_CONNECTION_KEY);
    }
  }

  private async isActiveHost(
    attachment: SocketAttachment,
  ): Promise<boolean> {
    const activeHostConnectionId =
      await this.state.storage.get<string>(
        ACTIVE_HOST_CONNECTION_KEY,
      );
    return activeHostConnectionId === attachment.connectionId;
  }

  private countRole(sockets: WebSocket[], role: Role): number {
    return sockets.filter(
      (socket: WebSocket) => this.getAttachment(socket)?.role === role,
    ).length;
  }

  private getAttachment(
    webSocket: WebSocket,
  ): SocketAttachment | undefined {
    return webSocket.deserializeAttachment() as
      | SocketAttachment
      | undefined;
  }

  private async broadcastPresence(now = Date.now()): Promise<void> {
    if (this.deleting) {
      return;
    }
    const activeHostConnectionId =
      await this.state.storage.get<string>(
        ACTIVE_HOST_CONNECTION_KEY,
      );
    const connections = this.state
      .getWebSockets()
      .map((socket: WebSocket) => this.getAttachment(socket))
      .filter(
        (
          attachment: SocketAttachment | undefined,
        ): attachment is SocketAttachment => attachment !== undefined,
      )
      .filter((attachment: SocketAttachment) => {
        if (!this.isRecentlyAlive(attachment, now)) {
          return false;
        }
        return (
          attachment.role !== "host" ||
          attachment.connectionId === activeHostConnectionId
        );
      })
      .map((attachment: SocketAttachment) => ({
        connectionId: attachment.connectionId,
        role: attachment.role,
        connectedAt: new Date(attachment.connectedAt).toISOString(),
        deviceToken: attachment.deviceToken,
      }));

    const counts: Record<Role, number> = {
      host: 0,
      controller: 0,
      participant: 0,
      display: 0,
    };
    for (const connection of connections) {
      counts[connection.role] += 1;
    }

    for (const recipient of this.state.getWebSockets()) {
      const recipientAttachment = this.getAttachment(recipient);
      if (
        recipientAttachment === undefined ||
        !this.isRecentlyAlive(recipientAttachment, now)
      ) {
        continue;
      }
      const isActiveHost =
        recipientAttachment.role === "host" &&
        recipientAttachment.connectionId === activeHostConnectionId;
      this.sendJson(recipient, {
        type: "presence",
        hostConnected: counts.host > 0,
        connections: connections.map((connection) => ({
          connectionId: connection.connectionId,
          role: connection.role,
          connectedAt: connection.connectedAt,
          ...(isActiveHost && connection.deviceToken !== undefined
            ? { deviceToken: connection.deviceToken }
            : {}),
        })),
        counts,
      });
    }
  }

  private isRecentlyAlive(
    attachment: SocketAttachment,
    now: number,
  ): boolean {
    if (attachment.heartbeatExpired === true) {
      return false;
    }
    const lastSeenAt = attachment.lastSeenAt ?? attachment.connectedAt;
    return now - lastSeenAt <= CONNECTION_HEARTBEAT_TIMEOUT_MS;
  }

  private broadcastJson(value: unknown): void {
    const encoded = JSON.stringify(value);
    const now = Date.now();
    for (const webSocket of this.state.getWebSockets()) {
      const attachment = this.getAttachment(webSocket);
      if (
        attachment === undefined ||
        !this.isRecentlyAlive(attachment, now)
      ) {
        continue;
      }
      try {
        webSocket.send(encoded);
      } catch {
        // A later close/error event removes stale presence.
      }
    }
  }

  private sendJson(webSocket: WebSocket, value: unknown): void {
    try {
      webSocket.send(JSON.stringify(value));
    } catch {
      // The connection is already closing.
    }
  }

  private sendError(
    webSocket: WebSocket,
    code: string,
    message: string,
  ): void {
    this.sendJson(webSocket, {
      type: "error",
      code,
      message,
    });
  }

  private async deleteRoom(reason: "ended" | "expired"): Promise<void> {
    if (this.deleting) {
      return;
    }
    this.deleting = true;
    for (const socket of this.state.getWebSockets()) {
      this.sendJson(socket, {
        type: "room_closed",
        reason,
      });
      socket.close(1000, `Room ${reason}`);
    }
    await this.state.storage.deleteAlarm();
    await this.state.storage.deleteAll();
  }
}
