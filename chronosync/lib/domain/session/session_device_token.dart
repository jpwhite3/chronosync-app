import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// Derives the opaque transport identity bound to one device and live room.
abstract final class SessionDeviceToken {
  static const String _domain = 'chronosync.transport-device.v1\u0000';

  static Future<String> derive({
    required String deviceId,
    required String sessionSecret,
  }) async {
    final String normalizedDeviceId = deviceId.trim();
    if (normalizedDeviceId.isEmpty) {
      throw ArgumentError.value(
        deviceId,
        'deviceId',
        'A device ID cannot be empty.',
      );
    }
    final SecretKey secretKey = SecretKey(
      base64Url.decode(base64Url.normalize(sessionSecret)),
    );
    final Mac mac = await Hmac.sha256().calculateMac(
      utf8.encode('$_domain$normalizedDeviceId'),
      secretKey: secretKey,
    );
    return base64UrlEncode(mac.bytes).replaceAll('=', '');
  }
}
