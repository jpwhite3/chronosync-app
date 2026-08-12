import {
  MAX_ENCRYPTED_PAYLOAD_BYTES,
  MAX_MESSAGE_BYTES,
  PROTOCOL_VERSION,
  ROLE_VALUES,
  type Role,
} from "./constants";

// Dart's base64UrlEncode emits RFC 4648 padding when the encoded byte length
// requires it. Accept that optional terminal padding while still rejecting
// standard-base64 characters and padding embedded in the payload.
const BASE64_URL_PATTERN = /^[A-Za-z0-9_-]+={0,2}$/;
const IDENTIFIER_PATTERN = /^[A-Za-z0-9_-]+$/;

export interface Env {
  ROOMS: DurableObjectNamespace;
  ALLOWED_ORIGINS?: string;
}

export interface RoomConfig {
  protocolVersion: number;
  roomId: string;
  createdAt: number;
  /**
   * Fixed deadline after which bearer capabilities cannot open new sockets.
   * Optional only so Durable Objects created before this field was introduced
   * can fall back to `createdAt + ROOM_TTL_MS`.
   */
  expiresAt?: number;
  capabilityHashes: Record<Role, string>;
}

export interface SocketAttachment {
  connectionId: string;
  role: Role;
  /// Opaque room-scoped HMAC; optional only for pre-upgrade attachments.
  deviceToken?: string;
  connectedAt: number;
  /// Optional for attachments serialized before host heartbeat tracking.
  lastSeenAt?: number;
  heartbeatExpired?: boolean;
  recentMessageIds: string[];
  rateWindowStartedAt: number;
  rateCount: number;
}

interface EncryptedFields {
  messageId: string;
  sentAt: string;
  nonce: string;
  ciphertext: string;
}

export interface SnapshotMessage extends EncryptedFields {
  type: "snapshot";
  revision: number;
}

export interface CommandMessage extends EncryptedFields {
  type: "command";
  baseRevision: number;
}

export interface PingMessage {
  type: "ping";
}

export interface EndRoomMessage {
  type: "end_room";
}

export interface DisconnectPeerMessage {
  type: "disconnect_peer";
  requestId: string;
  deviceToken: string;
}

export interface DisconnectConnectionMessage {
  type: "disconnect_connection";
  requestId: string;
  connectionId: string;
}

export interface SetPeerRoleMessage {
  type: "set_peer_role";
  requestId: string;
  deviceToken: string;
  role: Exclude<Role, "host">;
}

export type ClientMessage =
  | SnapshotMessage
  | CommandMessage
  | PingMessage
  | DisconnectPeerMessage
  | DisconnectConnectionMessage
  | SetPeerRoleMessage
  | EndRoomMessage;

export interface StoredSnapshot extends SnapshotMessage {}

export function jsonResponse(
  body: unknown,
  status = 200,
  extraHeaders?: HeadersInit,
): Response {
  const headers = new Headers(extraHeaders);
  headers.set("Content-Type", "application/json; charset=utf-8");
  headers.set("Cache-Control", "no-store");
  headers.set("X-Content-Type-Options", "nosniff");
  return new Response(JSON.stringify(body), { status, headers });
}

export function errorResponse(
  code: string,
  message: string,
  status: number,
  extraHeaders?: HeadersInit,
): Response {
  return jsonResponse(
    {
      error: {
        code,
        message,
      },
    },
    status,
    extraHeaders,
  );
}

export function encodedByteLength(value: string | ArrayBuffer): number {
  if (typeof value === "string") {
    return new TextEncoder().encode(value).byteLength;
  }
  return value.byteLength;
}

export function decodeWebSocketMessage(
  value: string | ArrayBuffer,
): string | undefined {
  if (encodedByteLength(value) > MAX_MESSAGE_BYTES) {
    return undefined;
  }
  if (typeof value === "string") {
    return value;
  }
  try {
    return new TextDecoder("utf-8", {
      fatal: true,
      ignoreBOM: false,
    }).decode(value);
  } catch {
    return undefined;
  }
}

export function parseClientMessage(value: string): ClientMessage | undefined {
  let parsed: unknown;
  try {
    parsed = JSON.parse(value);
  } catch {
    return undefined;
  }

  if (!isRecord(parsed) || typeof parsed.type !== "string") {
    return undefined;
  }

  switch (parsed.type) {
    case "snapshot": {
      if (!isEncryptedFields(parsed) || !isRevision(parsed.revision)) {
        return undefined;
      }
      return {
        type: "snapshot",
        messageId: parsed.messageId,
        revision: parsed.revision,
        sentAt: parsed.sentAt,
        nonce: parsed.nonce,
        ciphertext: parsed.ciphertext,
      };
    }
    case "command": {
      if (!isEncryptedFields(parsed) || !isRevision(parsed.baseRevision)) {
        return undefined;
      }
      return {
        type: "command",
        messageId: parsed.messageId,
        baseRevision: parsed.baseRevision,
        sentAt: parsed.sentAt,
        nonce: parsed.nonce,
        ciphertext: parsed.ciphertext,
      };
    }
    case "ping":
      return { type: "ping" };
    case "disconnect_peer":
      if (
        !isIdentifier(parsed.requestId, 8, 64) ||
        !isBase64Url(parsed.deviceToken, 43, 43)
      ) {
        return undefined;
      }
      return {
        type: "disconnect_peer",
        requestId: parsed.requestId,
        deviceToken: parsed.deviceToken,
      };
    case "disconnect_connection":
      if (
        !isIdentifier(parsed.requestId, 8, 64) ||
        !isIdentifier(parsed.connectionId, 1, 128)
      ) {
        return undefined;
      }
      return {
        type: "disconnect_connection",
        requestId: parsed.requestId,
        connectionId: parsed.connectionId,
      };
    case "set_peer_role":
      if (
        !isIdentifier(parsed.requestId, 8, 64) ||
        !isBase64Url(parsed.deviceToken, 43, 43) ||
        !isPeerRole(parsed.role)
      ) {
        return undefined;
      }
      return {
        type: "set_peer_role",
        requestId: parsed.requestId,
        deviceToken: parsed.deviceToken,
        role: parsed.role,
      };
    case "end_room":
      return { type: "end_room" };
    default:
      return undefined;
  }
}

export function parseWebSocketCredentials(
  header: string | null,
): { role: Role; token: string; deviceToken: string } | undefined {
  if (header === null) {
    return undefined;
  }

  const protocols = header
    .split(",")
    .map((protocol: string) => protocol.trim())
    .filter((protocol: string) => protocol.length > 0);

  if (!protocols.includes(`chronosync.v${PROTOCOL_VERSION}`)) {
    return undefined;
  }

  const roleProtocol = protocols.find((protocol: string) =>
    protocol.startsWith("role."),
  );
  const capabilityProtocol = protocols.find((protocol: string) =>
    protocol.startsWith("cap."),
  );
  const deviceProtocol = protocols.find((protocol: string) =>
    protocol.startsWith("device."),
  );
  if (
    roleProtocol === undefined ||
    capabilityProtocol === undefined ||
    deviceProtocol === undefined
  ) {
    return undefined;
  }

  const roleValue = roleProtocol.slice("role.".length);
  const token = capabilityProtocol.slice("cap.".length);
  const deviceToken = deviceProtocol.slice("device.".length);
  if (
    !isRole(roleValue) ||
    !isBase64Url(token, 43, 43) ||
    !isBase64Url(deviceToken, 43, 43)
  ) {
    return undefined;
  }

  return { role: roleValue, token, deviceToken };
}

export function isRoomId(value: string): boolean {
  return (
    value.length >= 20 &&
    value.length <= 64 &&
    IDENTIFIER_PATTERN.test(value)
  );
}

export function isRole(value: string): value is Role {
  return (ROLE_VALUES as readonly string[]).includes(value);
}

export function randomToken(byteLength = 32): string {
  const bytes = crypto.getRandomValues(new Uint8Array(byteLength));
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary)
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replace(/=+$/, "");
}

export async function hashToken(token: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(token),
  );
  return Array.from(new Uint8Array(digest))
    .map((byte: number) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isEncryptedFields(
  value: Record<string, unknown>,
): value is Record<string, unknown> & EncryptedFields {
  return (
    isIdentifier(value.messageId, 8, 64) &&
    typeof value.sentAt === "string" &&
    value.sentAt.length <= 64 &&
    /(?:[zZ]|[+-]\d{2}:\d{2})$/.test(value.sentAt) &&
    Number.isFinite(Date.parse(value.sentAt)) &&
    isBase64Url(value.nonce, 12, 128) &&
    isBase64Url(value.ciphertext, 1, MAX_ENCRYPTED_PAYLOAD_BYTES)
  );
}

function isPeerRole(value: unknown): value is Exclude<Role, "host"> {
  return value === "participant" || value === "controller" || value === "display";
}

function isIdentifier(
  value: unknown,
  minLength: number,
  maxLength: number,
): value is string {
  return (
    typeof value === "string" &&
    value.length >= minLength &&
    value.length <= maxLength &&
    IDENTIFIER_PATTERN.test(value)
  );
}

function isBase64Url(
  value: unknown,
  minLength: number,
  maxLength: number,
): value is string {
  return (
    typeof value === "string" &&
    value.length >= minLength &&
    value.length <= maxLength &&
    BASE64_URL_PATTERN.test(value)
  );
}

function isRevision(value: unknown): value is number {
  return (
    typeof value === "number" &&
    Number.isSafeInteger(value) &&
    value >= 0
  );
}
