import { describe, expect, it } from "vitest";
import {
  MAX_ENCRYPTED_PAYLOAD_BYTES,
  MAX_MESSAGE_BYTES,
} from "../src/constants";
import {
  decodeWebSocketMessage,
  parseClientMessage,
  parseWebSocketCredentials,
} from "../src/protocol";

describe("relay protocol parsing", () => {
  it("accepts total frames through 320 KiB and rejects larger frames", () => {
    const maximumFrame = "a".repeat(320 * 1024);

    expect(MAX_MESSAGE_BYTES).toBe(320 * 1024);
    expect(decodeWebSocketMessage(maximumFrame)).toBe(maximumFrame);
    expect(
      decodeWebSocketMessage(`${maximumFrame}a`),
    ).toBeUndefined();
  });

  it("keeps encrypted payloads bounded below the total frame limit", () => {
    const message = (ciphertext: string): string =>
      JSON.stringify({
        type: "snapshot",
        messageId: "message_payload_limit",
        revision: 0,
        sentAt: "2026-07-28T12:00:00.000Z",
        nonce: "abcdefghijklmnop",
        ciphertext,
      });

    expect(MAX_ENCRYPTED_PAYLOAD_BYTES).toBe(256 * 1024);
    expect(
      parseClientMessage(message("a".repeat(MAX_ENCRYPTED_PAYLOAD_BYTES))),
    ).toBeDefined();
    expect(
      parseClientMessage(
        message("a".repeat(MAX_ENCRYPTED_PAYLOAD_BYTES + 1)),
      ),
    ).toBeUndefined();
  });

  it("accepts valid browser WebSocket credentials", () => {
    const token = "a".repeat(43);

    expect(
      parseWebSocketCredentials(
        `chronosync.v1, role.participant, cap.${token}, device.${"b".repeat(43)}`,
      ),
    ).toEqual({
      role: "participant",
      token,
      deviceToken: "b".repeat(43),
    });
  });

  it("rejects credentials without a supported protocol", () => {
    expect(
      parseWebSocketCredentials(
        `chronosync.v2, role.host, cap.${"a".repeat(43)}, device.${"b".repeat(43)}`,
      ),
    ).toBeUndefined();
  });

  it("rejects credentials without an opaque device token", () => {
    expect(
      parseWebSocketCredentials(
        `chronosync.v1, role.participant, cap.${"a".repeat(43)}`,
      ),
    ).toBeUndefined();
    expect(
      parseWebSocketCredentials(
        `chronosync.v1, role.participant, cap.${"a".repeat(43)}, device.raw-device-id`,
      ),
    ).toBeUndefined();
  });

  it("requires 256-bit role capabilities", () => {
    for (const token of ["a".repeat(42), "a".repeat(44)]) {
      expect(
        parseWebSocketCredentials(
          `chronosync.v1, role.participant, cap.${token}, device.${"b".repeat(43)}`,
        ),
      ).toBeUndefined();
    }
  });

  it("accepts an encrypted snapshot and strips unknown plaintext", () => {
    expect(
      parseClientMessage(
        JSON.stringify({
          type: "snapshot",
          messageId: "message_001",
          revision: 0,
          sentAt: "2026-07-28T12:00:00.000Z",
          nonce: "abcdefghijklmnop",
          ciphertext: "opaque_ciphertext",
          planTitle: "Never retain or forward this",
        }),
      ),
    ).toEqual({
      type: "snapshot",
      messageId: "message_001",
      revision: 0,
      sentAt: "2026-07-28T12:00:00.000Z",
      nonce: "abcdefghijklmnop",
      ciphertext: "opaque_ciphertext",
    });
  });

  it("accepts terminal padding emitted by Dart base64url encoding", () => {
    expect(
      parseClientMessage(
        JSON.stringify({
          type: "snapshot",
          messageId: "message_002",
          revision: 1,
          sentAt: "2026-07-28T12:00:01.000Z",
          nonce: "abcdefghijklmnop",
          ciphertext: "YWJjZA==",
        }),
      ),
    ).toMatchObject({
      type: "snapshot",
      messageId: "message_002",
      ciphertext: "YWJjZA==",
    });
  });

  it("requires an explicit timezone on encrypted envelope timestamps", () => {
    const message = (sentAt: string): string =>
      JSON.stringify({
        type: "snapshot",
        messageId: "timezone_message_001",
        revision: 0,
        sentAt,
        nonce: "abcdefghijklmnop",
        ciphertext: "opaque_ciphertext",
      });

    expect(
      parseClientMessage(message("2026-07-28T12:00:00.000Z")),
    ).toBeDefined();
    expect(
      parseClientMessage(message("2026-07-28T12:00:00.000-04:00")),
    ).toBeDefined();
    expect(
      parseClientMessage(message("2026-07-28T12:00:00.000")),
    ).toBeUndefined();
  });

  it("accepts a host request to update one device role", () => {
    expect(
      parseClientMessage(
        JSON.stringify({
          type: "set_peer_role",
          requestId: "role_request_123",
          deviceToken: "t".repeat(43),
          role: "controller",
          ignored: "not forwarded",
        }),
      ),
    ).toEqual({
      type: "set_peer_role",
      requestId: "role_request_123",
      deviceToken: "t".repeat(43),
      role: "controller",
    });
  });

  it("rejects host role grants and malformed peer-role requests", () => {
    for (const role of ["host", "unknown"]) {
      expect(
        parseClientMessage(
          JSON.stringify({
            type: "set_peer_role",
            requestId: "role_request_123",
            deviceToken: "t".repeat(43),
            role,
          }),
        ),
      ).toBeUndefined();
    }
    expect(
      parseClientMessage(
        JSON.stringify({
          type: "set_peer_role",
          requestId: "role_request_123",
          deviceToken: "not-a-token",
          role: "participant",
        }),
      ),
    ).toBeUndefined();
  });

  it("accepts a correlated host request to disconnect one opaque device", () => {
    expect(
      parseClientMessage(
        JSON.stringify({
          type: "disconnect_peer",
          requestId: "disconnect_request_123",
          deviceToken: "t".repeat(43),
          ignored: "not forwarded",
        }),
      ),
    ).toEqual({
      type: "disconnect_peer",
      requestId: "disconnect_request_123",
      deviceToken: "t".repeat(43),
    });
  });

  it("rejects uncorrelated or malformed disconnect requests", () => {
    expect(
      parseClientMessage(
        JSON.stringify({
          type: "disconnect_peer",
          deviceToken: "t".repeat(43),
        }),
      ),
    ).toBeUndefined();
    expect(
      parseClientMessage(
        JSON.stringify({
          type: "disconnect_peer",
          requestId: "disconnect_request_123",
          deviceToken: "not-a-token",
        }),
      ),
    ).toBeUndefined();
  });

  it("accepts a correlated connection-only disconnect request", () => {
    expect(
      parseClientMessage(
        JSON.stringify({
          type: "disconnect_connection",
          requestId: "disconnect_connection_123",
          connectionId: "connection_123",
          ignored: "not forwarded",
        }),
      ),
    ).toEqual({
      type: "disconnect_connection",
      requestId: "disconnect_connection_123",
      connectionId: "connection_123",
    });
  });

  it("rejects plaintext or malformed encrypted envelopes", () => {
    expect(
      parseClientMessage(
        JSON.stringify({
          type: "snapshot",
          messageId: "message_001",
          revision: 0,
          sentAt: "2026-07-28T12:00:00.000Z",
          nonce: "abcdefghijklmnop",
          plaintext: {
            planTitle: "Do not relay this",
          },
        }),
      ),
    ).toBeUndefined();
  });
});
