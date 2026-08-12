import 'dart:convert';
import 'dart:math';

import 'package:chronosync/data/database/app_database.dart';
import 'package:chronosync/domain/session/live_session.dart';
import 'package:uuid/uuid.dart';

final class DeviceIdentity {
  const DeviceIdentity({required this.deviceId, required this.displayName});

  final String deviceId;
  final String displayName;
}

/// Narrow persistence boundary used by the device-name settings UI.
abstract interface class DeviceIdentitySettingsRepository {
  Future<DeviceIdentity> updateDisplayName(String displayName);
}

final class DeviceIdentityRepository
    implements DeviceIdentitySettingsRepository {
  DeviceIdentityRepository(this._database, {Uuid? uuid, Random? secureRandom})
    : _uuid = uuid ?? const Uuid(),
      _secureRandom = secureRandom ?? Random.secure();

  static const String _deviceIdKey = 'device_id';
  static const String _displayNameKey = 'display_name';
  static const String _sessionAuthenticationKeyPrefix =
      'session_authentication_secret:';
  static final RegExp _sessionAuthenticationSecretPattern = RegExp(
    r'^[A-Za-z0-9_-]{32,128}$',
  );

  final AppDatabase _database;
  final Uuid _uuid;
  final Random _secureRandom;

  Future<DeviceIdentity> load() async {
    String? deviceId = await _read(_deviceIdKey);
    if (deviceId == null ||
        deviceId.trim().isEmpty ||
        deviceId.trim().length > maxSessionDeviceIdLength) {
      deviceId = _uuid.v4();
      await _write(_deviceIdKey, deviceId);
    } else {
      deviceId = deviceId.trim();
    }
    final String? storedDisplayName = await _read(_displayNameKey);
    final String? normalizedDisplayName = storedDisplayName?.trim();
    final String displayName =
        normalizedDisplayName?.isNotEmpty == true &&
            normalizedDisplayName!.length <= maxParticipantDisplayNameLength
        ? normalizedDisplayName
        : 'This device';
    return DeviceIdentity(deviceId: deviceId, displayName: displayName);
  }

  @override
  Future<DeviceIdentity> updateDisplayName(String displayName) async {
    final String normalized = displayName.trim();
    if (normalized.isEmpty ||
        normalized.length > maxParticipantDisplayNameLength) {
      throw const FormatException(
        'Display name must be between 1 and '
        '$maxParticipantDisplayNameLength characters.',
      );
    }
    await _write(_displayNameKey, normalized);
    final DeviceIdentity identity = await load();
    return DeviceIdentity(deviceId: identity.deviceId, displayName: normalized);
  }

  /// Returns the stable, device-local credential used to rejoin [sessionId].
  ///
  /// The value lives only in private application metadata. It is deliberately
  /// not part of plans, session history, or portable ChronoSync archives.
  Future<String> loadOrCreateSessionAuthenticationSecret(
    String sessionId,
  ) async {
    final String normalizedSessionId = sessionId.trim();
    if (normalizedSessionId.isEmpty) {
      throw const FormatException('A session ID is required.');
    }
    final String key =
        '$_sessionAuthenticationKeyPrefix'
        '${_unpaddedBase64Url(utf8.encode(normalizedSessionId))}';
    return _database.transaction<String>(() async {
      final String? stored = await _read(key);
      if (stored != null &&
          _sessionAuthenticationSecretPattern.hasMatch(stored)) {
        return stored;
      }
      final List<int> bytes = List<int>.generate(
        32,
        (int _) => _secureRandom.nextInt(256),
        growable: false,
      );
      final String generated = _unpaddedBase64Url(bytes);
      await _write(key, generated);
      return generated;
    });
  }

  Future<String?> _read(String key) async {
    final AppMetadataRecord? record =
        await (_database.select(
              _database.appMetadataRecords,
            )..where(($AppMetadataRecordsTable table) => table.key.equals(key)))
            .getSingleOrNull();
    return record?.value;
  }

  Future<void> _write(String key, String value) {
    return _database
        .into(_database.appMetadataRecords)
        .insertOnConflictUpdate(
          AppMetadataRecordsCompanion.insert(key: key, value: value),
        );
  }
}

String _unpaddedBase64Url(List<int> bytes) {
  return base64UrlEncode(bytes).replaceAll('=', '');
}
