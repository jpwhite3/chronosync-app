import 'dart:async';
import 'dart:convert';

import 'package:chronosync/data/transports/online_room_service.dart';
import 'package:chronosync/domain/session/session_protocol.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';

const String _hostCapability = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const String _controllerCapability =
    'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE';
const String _participantCapability =
    'AgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgI';
const String _displayCapability = 'AwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwM';

void main() {
  test('room invitations open the PWA but retain the relay endpoint', () async {
    final MockClient client = MockClient((http.Request request) async {
      expect(request.method, 'POST');
      expect(request.url, Uri.parse('https://relay.example.com/api/v1/rooms'));
      return http.Response(
        jsonEncode(<String, Object>{
          'protocolVersion': sessionProtocolVersion,
          'roomId': 'room-1',
          'websocketPath': '/v1/rooms/room-1/connect',
          'expiresAt': '2099-01-01T00:00:00.000Z',
          'capabilities': <String, String>{
            'host': _hostCapability,
            'controller': _controllerCapability,
            'participant': _participantCapability,
            'display': _displayCapability,
          },
        }),
        201,
      );
    });
    final OnlineRoomService service = OnlineRoomService(
      relayBaseUri: Uri.parse('https://relay.example.com/api'),
      joinBaseUri: Uri.parse(
        'https://app.example.com/chronosync/?campaign=launch#old',
      ),
      client: client,
    );
    addTearDown(service.close);

    final OnlineRoom room = await service.createRoom();
    final Invitation invitation = room.participantInvitation();
    final Uri qrUri = Uri.parse(invitation.toQrPayload());

    expect(room.joinUri, Uri.parse('https://app.example.com/chronosync/'));
    expect(
      invitation.endpoint,
      Uri.parse('https://relay.example.com/v1/rooms/room-1/connect'),
    );
    expect(invitation.joinUri, room.joinUri);
    expect(qrUri.host, 'app.example.com');
    expect(qrUri.path, '/chronosync/');
    expect(qrUri.fragment, startsWith('invite='));
  });

  for (final String maliciousPath in <String>[
    'https://attacker.example/v1/rooms/room-1/connect',
    '//attacker.example/v1/rooms/room-1/connect',
    '/v1/rooms/different-room/connect',
    '/v1/rooms/room-1/connect?token=unexpected',
  ]) {
    test('rejects untrusted relay WebSocket path $maliciousPath', () async {
      final MockClient client = MockClient((http.Request request) async {
        return http.Response(
          jsonEncode(<String, Object>{
            'protocolVersion': sessionProtocolVersion,
            'roomId': 'room-1',
            'websocketPath': maliciousPath,
            'expiresAt': '2099-01-01T00:00:00.000Z',
            'capabilities': <String, String>{
              'host': _hostCapability,
              'controller': _controllerCapability,
              'participant': _participantCapability,
              'display': _displayCapability,
            },
          }),
          201,
        );
      });
      final OnlineRoomService service = OnlineRoomService(
        relayBaseUri: Uri.parse('https://relay.example.com/api'),
        joinBaseUri: Uri.parse('https://app.example.com/chronosync/'),
        client: client,
      );
      addTearDown(service.close);

      await expectLater(service.createRoom(), throwsFormatException);
    });
  }

  test('rejects incompatible relay protocol versions', () async {
    final MockClient client = MockClient((http.Request request) async {
      return http.Response(
        jsonEncode(<String, Object>{
          'protocolVersion': sessionProtocolVersion + 1,
          'roomId': 'room-1',
          'websocketPath': '/v1/rooms/room-1/connect',
          'expiresAt': '2099-01-01T00:00:00.000Z',
          'capabilities': <String, String>{
            'host': _hostCapability,
            'controller': _controllerCapability,
            'participant': _participantCapability,
            'display': _displayCapability,
          },
        }),
        201,
      );
    });
    final OnlineRoomService service = OnlineRoomService(
      relayBaseUri: Uri.parse('https://relay.example.com/api'),
      joinBaseUri: Uri.parse('https://app.example.com/chronosync/'),
      client: client,
    );
    addTearDown(service.close);

    await expectLater(service.createRoom(), throwsFormatException);
  });

  test('times out when the relay never answers room creation', () async {
    final Completer<http.Response> response = Completer<http.Response>();
    final MockClient client = MockClient(
      (http.Request request) => response.future,
    );
    final OnlineRoomService service = OnlineRoomService(
      relayBaseUri: Uri.parse('https://relay.example.com'),
      joinBaseUri: Uri.parse('https://app.example.com/'),
      client: client,
      requestTimeout: const Duration(milliseconds: 1),
    );
    addTearDown(service.close);

    await expectLater(service.createRoom(), throwsA(isA<TimeoutException>()));
    response.complete(http.Response('', 503));
  });

  test('rejects a relay expiry without an explicit time zone', () async {
    final MockClient client = MockClient((http.Request request) async {
      return http.Response(
        jsonEncode(<String, Object>{
          'protocolVersion': sessionProtocolVersion,
          'roomId': 'room-1',
          'websocketPath': '/v1/rooms/room-1/connect',
          'expiresAt': '2099-01-01T00:00:00.000',
          'capabilities': <String, String>{
            'host': _hostCapability,
            'controller': _controllerCapability,
            'participant': _participantCapability,
            'display': _displayCapability,
          },
        }),
        201,
      );
    });
    final OnlineRoomService service = OnlineRoomService(
      relayBaseUri: Uri.parse('https://relay.example.com'),
      joinBaseUri: Uri.parse('https://app.example.com/'),
      client: client,
    );
    addTearDown(service.close);

    await expectLater(service.createRoom(), throwsFormatException);
  });

  test('rejects malformed or reused role capabilities', () async {
    for (final Map<String, String> capabilities in <Map<String, String>>[
      <String, String>{
        'host': 'too-short',
        'controller': _controllerCapability,
        'participant': _participantCapability,
        'display': _displayCapability,
      },
      <String, String>{
        'host': _hostCapability,
        'controller': _controllerCapability,
        'participant': _participantCapability,
        'display': _participantCapability,
      },
      <String, String>{
        'host': '${'A' * 42}B',
        'controller': _controllerCapability,
        'participant': _participantCapability,
        'display': _displayCapability,
      },
    ]) {
      final MockClient client = MockClient((http.Request request) async {
        return http.Response(
          jsonEncode(<String, Object>{
            'protocolVersion': sessionProtocolVersion,
            'roomId': 'room-1',
            'websocketPath': '/v1/rooms/room-1/connect',
            'expiresAt': '2099-01-01T00:00:00.000Z',
            'capabilities': capabilities,
          }),
          201,
        );
      });
      final OnlineRoomService service = OnlineRoomService(
        relayBaseUri: Uri.parse('https://relay.example.com/api'),
        joinBaseUri: Uri.parse('https://app.example.com/chronosync/'),
        client: client,
      );
      addTearDown(service.close);

      await expectLater(service.createRoom(), throwsFormatException);
    }
  });
}
