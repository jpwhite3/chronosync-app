import 'dart:async';
import 'dart:io';

import 'package:chronosync/data/database/app_database.dart';
import 'package:chronosync/domain/session/session_protocol.dart';
import 'package:chronosync/main.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  test('malformed invite fragments are scrubbed before parsing', () {
    Uri? scrubbedUri;

    final Invitation? invitation = invitationFromUri(
      Uri.parse('https://example.test/app?source=qr#invite=not-valid'),
      onInviteFragmentDetected: (Uri uri) => scrubbedUri = uri,
    );

    expect(invitation, isNull);
    expect(scrubbedUri, Uri.parse('https://example.test/app?source=qr'));
  });

  test('unrelated fragments containing invite text are preserved', () {
    bool scrubbed = false;

    final Invitation? invitation = invitationFromUri(
      Uri.parse('https://example.test/app#not-an-invite=keep-me'),
      onInviteFragmentDetected: (_) => scrubbed = true,
    );

    expect(invitation, isNull);
    expect(scrubbed, isFalse);
  });

  testWidgets('bootstrap remains usable at 300% text on a short screen', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(320, 300);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 3;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    final Completer<AppDependencies> pending = Completer<AppDependencies>();

    await tester.pumpWidget(
      ChronoSyncBootstrap(
        dependencyInitializer: ({ValueChanged<String>? onProgress}) {
          onProgress?.call('Opening local storage…');
          return pending.future;
        },
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(Scrollable), findsOneWidget);
    expect(find.text('ChronoSync'), findsOneWidget);
    expect(find.text('Opening local storage…'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.text('Opening local storage…'))
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );
    semantics.dispose();
  });

  testWidgets('bootstrap hides internal errors and retries initialization', (
    WidgetTester tester,
  ) async {
    int attempts = 0;
    final Completer<AppDependencies> retry = Completer<AppDependencies>();

    Future<AppDependencies> initialize({ValueChanged<String>? onProgress}) {
      attempts += 1;
      if (attempts == 1) {
        return Future<AppDependencies>.error(
          StateError('sensitive database path and implementation details'),
        );
      }
      onProgress?.call('Trying local storage again…');
      return retry.future;
    }

    await tester.pumpWidget(
      ChronoSyncBootstrap(dependencyInitializer: initialize),
    );
    await tester.pump();

    expect(attempts, 1);
    expect(
      find.text('ChronoSync could not open local storage.'),
      findsOneWidget,
    );
    expect(find.textContaining('sensitive database path'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();

    expect(attempts, 2);
    expect(find.text('Trying local storage again…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  test(
    'failed dependency setup closes partial resources before retry',
    () async {
      final Directory hiveDirectory = await Directory.systemTemp.createTemp(
        'chronosync-bootstrap-test-',
      );
      addTearDown(() async {
        await Hive.close();
        if (hiveDirectory.existsSync()) {
          await hiveDirectory.delete(recursive: true);
        }
      });
      int hiveCloseCount = 0;
      bool failAfterDatabaseCreation = true;
      AppDatabase? failedDatabase;
      final AppDependenciesInitializationOverrides overrides =
          AppDependenciesInitializationOverrides(
            initializeHive: () async => Hive.init(hiveDirectory.path),
            createDatabase: () {
              final AppDatabase database = AppDatabase(NativeDatabase.memory());
              if (failAfterDatabaseCreation) {
                failedDatabase = database;
              }
              return database;
            },
            afterDatabaseCreated: (AppDatabase database) async {
              if (failAfterDatabaseCreation) {
                await database.customSelect('SELECT 1').get();
                throw StateError('injected setup failure');
              }
            },
            closeHive: () async {
              hiveCloseCount += 1;
              await Hive.close();
            },
          );

      await expectLater(
        AppDependencies.initialize(initializationOverrides: overrides),
        throwsStateError,
      );
      expect(hiveCloseCount, 1);
      await expectLater(
        failedDatabase!.customSelect('SELECT 1').get(),
        throwsA(anything),
      );

      failAfterDatabaseCreation = false;
      final AppDependencies dependencies = await AppDependencies.initialize(
        initializationOverrides: overrides,
      );
      expect(dependencies.identity.deviceId, isNotEmpty);
      await dependencies.dispose();
    },
  );
}
