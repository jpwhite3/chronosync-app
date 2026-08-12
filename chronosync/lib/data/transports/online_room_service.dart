import 'dart:async';
import 'dart:convert';

import 'package:chronosync/data/transports/session_crypto.dart';
import 'package:chronosync/domain/session/live_session.dart';
import 'package:chronosync/domain/session/session_protocol.dart';
import 'package:http/http.dart' as http;

const String defaultRelayUrl = String.fromEnvironment('CHRONOSYNC_RELAY_URL');
const String defaultWebUrl = String.fromEnvironment('CHRONOSYNC_WEB_URL');

final class OnlineRoom {
  const OnlineRoom({
    required this.roomId,
    required this.websocketEndpoint,
    required this.joinUri,
    required this.expiresAt,
    required this.sessionSecret,
    required this.hostCapability,
    required this.controllerCapability,
    required this.participantCapability,
    required this.displayCapability,
  });

  final String roomId;
  final Uri websocketEndpoint;
  final Uri joinUri;
  final DateTime expiresAt;
  final String sessionSecret;
  final String hostCapability;
  final String controllerCapability;
  final String participantCapability;
  final String displayCapability;

  Invitation hostInvitation() {
    return Invitation(
      sessionId: roomId,
      transport: SessionTransportKind.onlineRelay,
      endpoint: websocketEndpoint,
      joinUri: joinUri,
      capability: hostCapability,
      sessionSecret: sessionSecret,
      // Host authority is selected by OnlineRelayTransport.host; invitations
      // remain limited to roles that may safely appear in a QR payload.
      requestedRole: SessionRole.participant,
      expiresAt: expiresAt,
    );
  }

  Invitation participantInvitation() {
    return _invitation(
      capability: participantCapability,
      role: SessionRole.participant,
    );
  }

  Invitation displayInvitation() {
    return _invitation(
      capability: displayCapability,
      role: SessionRole.display,
    );
  }

  Invitation _invitation({
    required String capability,
    required SessionRole role,
  }) {
    return Invitation(
      sessionId: roomId,
      transport: SessionTransportKind.onlineRelay,
      endpoint: websocketEndpoint,
      joinUri: joinUri,
      capability: capability,
      sessionSecret: sessionSecret,
      requestedRole: role,
      expiresAt: expiresAt,
    );
  }
}

final class OnlineRoomService {
  OnlineRoomService({
    required Uri relayBaseUri,
    required Uri joinBaseUri,
    http.Client? client,
    Duration requestTimeout = const Duration(seconds: 15),
  }) : _relayBaseUri = relayBaseUri,
       _joinBaseUri = _withoutQueryOrFragment(joinBaseUri),
       _client = client ?? http.Client(),
       _requestTimeout = requestTimeout {
    if (requestTimeout <= Duration.zero) {
      throw ArgumentError.value(
        requestTimeout,
        'requestTimeout',
        'Must be positive.',
      );
    }
  }

  final Uri _relayBaseUri;
  final Uri _joinBaseUri;
  final http.Client _client;
  final Duration _requestTimeout;

  Future<OnlineRoom> createRoom() async {
    final SessionSecrets secrets = await SessionSecrets.generate();
    final Uri createEndpoint = Uri(
      scheme: _relayBaseUri.scheme,
      userInfo: _relayBaseUri.userInfo,
      host: _relayBaseUri.host,
      port: _relayBaseUri.hasPort ? _relayBaseUri.port : null,
      pathSegments: <String>[
        ..._relayBaseUri.pathSegments.where(
          (String segment) => segment.isNotEmpty,
        ),
        'v1',
        'rooms',
      ],
    );
    final http.Response response = await _client
        .post(
          createEndpoint,
          headers: const <String, String>{'Content-Type': 'application/json'},
          body: '{}',
        )
        .timeout(
          _requestTimeout,
          onTimeout: () => throw TimeoutException(
            'The online room service did not respond in time.',
            _requestTimeout,
          ),
        );
    if (response.statusCode != 201) {
      throw StateError(
        'The online room could not be created (${response.statusCode}).',
      );
    }
    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map<Object?, Object?>) {
      throw const FormatException('The relay returned an invalid room.');
    }
    final Map<String, Object?> json = Map<String, Object?>.from(decoded);
    if (json['protocolVersion'] != sessionProtocolVersion) {
      throw const FormatException(
        'The relay uses an unsupported protocol version.',
      );
    }
    final String roomId = _requiredString(json, 'roomId');
    final String websocketPath = _requiredString(json, 'websocketPath');
    final Uri websocketEndpoint = _validatedWebsocketEndpoint(
      roomId: roomId,
      websocketPath: websocketPath,
    );
    final DateTime expiresAt = _requiredUtcTimestamp(json, 'expiresAt');
    final Object? capabilitiesValue = json['capabilities'];
    if (capabilitiesValue is! Map<Object?, Object?>) {
      throw const FormatException('The relay room response is incomplete.');
    }
    final Map<String, Object?> capabilities = Map<String, Object?>.from(
      capabilitiesValue,
    );
    final List<String> roleCapabilities = <String>[
      _requiredRoomToken(capabilities, 'host'),
      _requiredRoomToken(capabilities, 'controller'),
      _requiredRoomToken(capabilities, 'participant'),
      _requiredRoomToken(capabilities, 'display'),
    ];
    if (roleCapabilities.toSet().length != roleCapabilities.length) {
      throw const FormatException(
        'The relay returned reused role capabilities.',
      );
    }
    return OnlineRoom(
      roomId: roomId,
      websocketEndpoint: websocketEndpoint,
      joinUri: _joinBaseUri,
      expiresAt: expiresAt,
      sessionSecret: secrets.sessionSecret,
      hostCapability: roleCapabilities[0],
      controllerCapability: roleCapabilities[1],
      participantCapability: roleCapabilities[2],
      displayCapability: roleCapabilities[3],
    );
  }

  void close() {
    _client.close();
  }

  String _requiredString(Map<String, Object?> json, String key) {
    final Object? value = json[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('The relay response is missing $key.');
    }
    return value;
  }

  String _requiredRoomToken(Map<String, Object?> json, String key) {
    final String token = _requiredString(json, key);
    if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(token)) {
      throw FormatException('The relay returned an invalid $key token.');
    }
    try {
      final List<int> decoded = base64Url.decode(base64Url.normalize(token));
      final String canonical = base64UrlEncode(decoded).replaceAll('=', '');
      if (decoded.length != 32 || canonical != token) {
        throw FormatException('The relay returned an invalid $key token.');
      }
    } on FormatException {
      rethrow;
    } on Object {
      throw FormatException('The relay returned an invalid $key token.');
    }
    return token;
  }

  DateTime _requiredUtcTimestamp(Map<String, Object?> json, String key) {
    final String value = _requiredString(json, key);
    if (!RegExp(r'(?:[zZ]|[+-]\d{2}:\d{2})$').hasMatch(value)) {
      throw FormatException('The relay returned an invalid $key timestamp.');
    }
    final DateTime? timestamp = DateTime.tryParse(value);
    if (timestamp == null) {
      throw FormatException('The relay returned an invalid $key timestamp.');
    }
    return timestamp.toUtc();
  }

  Uri _validatedWebsocketEndpoint({
    required String roomId,
    required String websocketPath,
  }) {
    final Uri path;
    try {
      path = Uri.parse(websocketPath);
    } on FormatException {
      throw const FormatException(
        'The relay returned an invalid WebSocket path.',
      );
    }
    final String expectedPath = '/v1/rooms/$roomId/connect';
    if (path.hasScheme ||
        path.hasAuthority ||
        path.path != expectedPath ||
        path.hasQuery ||
        path.hasFragment) {
      throw const FormatException(
        'The relay returned an untrusted WebSocket path.',
      );
    }
    final Uri endpoint = _relayBaseUri.resolveUri(path);
    if (endpoint.scheme != _relayBaseUri.scheme ||
        endpoint.host != _relayBaseUri.host ||
        endpoint.port != _relayBaseUri.port) {
      throw const FormatException(
        'The relay WebSocket endpoint changed origin.',
      );
    }
    return endpoint;
  }
}

Uri _withoutQueryOrFragment(Uri uri) {
  return Uri(
    scheme: uri.scheme,
    userInfo: uri.userInfo,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: uri.path,
  );
}
