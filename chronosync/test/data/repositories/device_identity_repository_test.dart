import 'dart:convert';
import 'dart:io';

import 'package:chronosync/data/database/app_database.dart';
import 'package:chronosync/data/repositories/device_identity_repository.dart';
import 'package:chronosync/domain/session/live_session.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'chronosync_identity_test_',
    );
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
  });

  test(
    'reuses a session credential after repository and database reload',
    () async {
      final File databaseFile = File(
        '${temporaryDirectory.path}/identity.sqlite',
      );
      final AppDatabase firstDatabase = AppDatabase(
        NativeDatabase(databaseFile),
      );
      final String firstSecret;
      try {
        firstSecret = await DeviceIdentityRepository(
          firstDatabase,
        ).loadOrCreateSessionAuthenticationSecret('session-one');
      } finally {
        await firstDatabase.close();
      }

      final AppDatabase reopenedDatabase = AppDatabase(
        NativeDatabase(databaseFile),
      );
      final String reloadedSecret;
      try {
        reloadedSecret = await DeviceIdentityRepository(
          reopenedDatabase,
        ).loadOrCreateSessionAuthenticationSecret('session-one');
      } finally {
        await reopenedDatabase.close();
      }

      expect(reloadedSecret, firstSecret);
      expect(firstSecret, matches(RegExp(r'^[A-Za-z0-9_-]{32,128}$')));
      expect(base64Url.decode(base64Url.normalize(firstSecret)), hasLength(32));
    },
  );

  test('uses independent credentials for different sessions', () async {
    final AppDatabase database = AppDatabase(NativeDatabase.memory());
    try {
      final DeviceIdentityRepository repository = DeviceIdentityRepository(
        database,
      );

      final String firstSecret = await repository
          .loadOrCreateSessionAuthenticationSecret('session-one');
      final String secondSecret = await repository
          .loadOrCreateSessionAuthenticationSecret('session-two');

      expect(secondSecret, isNot(firstSecret));
      expect(
        await DeviceIdentityRepository(
          database,
        ).loadOrCreateSessionAuthenticationSecret('session-one'),
        firstSecret,
      );
      expect(
        await DeviceIdentityRepository(
          database,
        ).loadOrCreateSessionAuthenticationSecret('session-two'),
        secondSecret,
      );
    } finally {
      await database.close();
    }
  });

  test('rejects a display name that cannot join a live session', () async {
    final AppDatabase database = AppDatabase(NativeDatabase.memory());
    try {
      final DeviceIdentityRepository repository = DeviceIdentityRepository(
        database,
      );
      final String oversized = List<String>.filled(
        maxParticipantDisplayNameLength + 1,
        'N',
      ).join();

      await expectLater(
        repository.updateDisplayName(oversized),
        throwsFormatException,
      );
    } finally {
      await database.close();
    }
  });
}
