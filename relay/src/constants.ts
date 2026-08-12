export const PROTOCOL_VERSION = 1;

export const ROOM_TTL_MS = 24 * 60 * 60 * 1000;

// Guest devices per room. The single authoritative host is not counted.
export const MAX_CONNECTIONS = 50;
export const MAX_CONTROLLERS = 10;
export const MAX_RETAINED_DEVICES = 250;
export const MAX_ENCRYPTED_PAYLOAD_BYTES = 256 * 1024;
export const MAX_MESSAGE_BYTES = 320 * 1024;
export const MAX_CREATE_BODY_BYTES = 1024;

export const RATE_LIMIT_WINDOW_MS = 10_000;
export const RATE_LIMIT_MESSAGES = 120;

// Browser WebSockets do not expose control-frame pings. Every socket proves
// that it is alive by sending a valid application frame within this window;
// production clients send protocol `ping` frames every 10 seconds.
export const CONNECTION_HEARTBEAT_TIMEOUT_MS = 30_000;

export const ROLE_VALUES = [
  "host",
  "controller",
  "participant",
  "display",
] as const;

export type Role = (typeof ROLE_VALUES)[number];
