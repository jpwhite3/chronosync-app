import {
  MAX_CREATE_BODY_BYTES,
  PROTOCOL_VERSION,
  ROOM_TTL_MS,
} from "./constants";
import {
  errorResponse,
  isRoomId,
  jsonResponse,
  randomToken,
  type Env,
} from "./protocol";
import { Room } from "./room";

export { Room };

const ROOM_ROUTE = /^\/v1\/rooms\/([^/]+)\/connect$/;

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "GET" && url.pathname === "/health") {
      return jsonResponse({
        status: "ok",
        service: "chronosync-relay",
        protocolVersion: PROTOCOL_VERSION,
      });
    }

    if (request.method === "OPTIONS") {
      return handlePreflight(request, env);
    }

    if (request.method === "POST" && url.pathname === "/v1/rooms") {
      const corsHeaders = corsHeadersFor(request, env);
      if (request.headers.has("Origin") && corsHeaders === undefined) {
        return errorResponse(
          "origin_not_allowed",
          "This origin is not allowed to create relay rooms.",
          403,
        );
      }

      if (await requestBodyExceedsLimit(request, MAX_CREATE_BODY_BYTES)) {
        return errorResponse(
          "request_too_large",
          `Room creation bodies cannot exceed ${MAX_CREATE_BODY_BYTES} bytes.`,
          413,
          corsHeaders,
        );
      }

      const roomId = randomToken(18);
      const durableObjectId = env.ROOMS.idFromName(roomId);
      const room = env.ROOMS.get(durableObjectId);
      const response = await room.fetch(
        new Request("https://room.internal/create", {
          method: "POST",
          headers: {
            "X-ChronoSync-Room-Id": roomId,
          },
        }),
      );
      return copyResponse(response, corsHeaders);
    }

    const match = ROOM_ROUTE.exec(url.pathname);
    if (request.method === "GET" && match !== null) {
      const roomId = match[1];
      if (roomId === undefined || !isRoomId(roomId)) {
        return errorResponse(
          "invalid_room",
          "The room identifier is invalid.",
          400,
        );
      }
      if (!isOriginAllowed(request, env)) {
        return errorResponse(
          "origin_not_allowed",
          "This origin is not allowed to join relay rooms.",
          403,
        );
      }

      const durableObjectId = env.ROOMS.idFromName(roomId);
      const room = env.ROOMS.get(durableObjectId);
      return room.fetch(
        new Request("https://room.internal/connect", request),
      );
    }

    return errorResponse("not_found", "Route not found.", 404);
  },
} satisfies ExportedHandler<Env>;

async function requestBodyExceedsLimit(
  request: Request,
  limit: number,
): Promise<boolean> {
  const contentLengthHeader = request.headers.get("Content-Length");
  if (contentLengthHeader !== null) {
    const contentLength = Number(contentLengthHeader);
    if (
      !Number.isFinite(contentLength) ||
      contentLength < 0 ||
      contentLength > limit
    ) {
      return true;
    }
  }
  if (request.body === null) {
    return false;
  }

  const reader = request.body.getReader();
  let bytesRead = 0;
  while (true) {
    const chunk = await reader.read();
    if (chunk.done) {
      return false;
    }
    bytesRead += chunk.value.byteLength;
    if (bytesRead > limit) {
      await reader.cancel().catch(() => undefined);
      return true;
    }
  }
}

function handlePreflight(request: Request, env: Env): Response {
  const headers = corsHeadersFor(request, env);
  if (headers === undefined) {
    return errorResponse(
      "origin_not_allowed",
      "This origin is not allowed.",
      403,
    );
  }
  headers.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  headers.set("Access-Control-Allow-Headers", "Content-Type");
  headers.set("Access-Control-Max-Age", "86400");
  return new Response(null, {
    status: 204,
    headers,
  });
}

function corsHeadersFor(
  request: Request,
  env: Env,
): Headers | undefined {
  const origin = request.headers.get("Origin");
  if (origin === null) {
    return new Headers();
  }
  if (!isOriginAllowed(request, env)) {
    return undefined;
  }

  const headers = new Headers();
  headers.set("Access-Control-Allow-Origin", origin);
  headers.set("Vary", "Origin");
  return headers;
}

function isOriginAllowed(request: Request, env: Env): boolean {
  const origin = request.headers.get("Origin");
  if (origin === null) {
    return true;
  }

  const allowedOrigins = (env.ALLOWED_ORIGINS ?? "")
    .split(",")
    .map((value: string) => value.trim())
    .filter((value: string) => value.length > 0);
  return (
    allowedOrigins.includes("*") || allowedOrigins.includes(origin)
  );
}

function copyResponse(
  response: Response,
  extraHeaders?: Headers,
): Response {
  const headers = new Headers(response.headers);
  if (extraHeaders !== undefined) {
    extraHeaders.forEach((value: string, key: string) => {
      headers.set(key, value);
    });
  }
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

export const relayMetadata = {
  protocolVersion: PROTOCOL_VERSION,
  roomTtlMs: ROOM_TTL_MS,
} as const;
