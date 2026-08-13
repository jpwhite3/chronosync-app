import 'package:chronosync/data/database/app_database.dart';
import 'package:chronosync/data/repositories/device_identity_repository.dart';
import 'package:chronosync/presentation/screens/identity_settings_screen.dart';
import 'package:chronosync/presentation/theme/theme.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('explains that the account-free name persists on this device', (
    WidgetTester tester,
  ) async {
    final AppDatabase database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    await _pumpSettings(tester, DeviceIdentityRepository(database));

    expect(find.textContaining('No account is required'), findsOneWidget);
    expect(find.textContaining('saved on this device'), findsOneWidget);
    expect(find.textContaining('temporary name'), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).decoration?.hintText,
      'Alex Rivera',
    );
  });

  testWidgets('save failures do not expose internal details', (
    WidgetTester tester,
  ) async {
    await _pumpSettings(tester, const _ThrowingIdentityRepository());
    await tester.enterText(
      find.widgetWithText(TextField, 'Display name'),
      'Jordan Lee',
    );
    await tester.tap(find.text('Save name'));
    await tester.pumpAndSettle();

    expect(
      find.text('Could not save the display name. Try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('private/device.sqlite'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpSettings(
  WidgetTester tester,
  DeviceIdentitySettingsRepository repository,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ChronoTheme.light(),
      home: Scaffold(
        body: IdentitySettingsScreen(
          repository: repository,
          initialIdentity: const DeviceIdentity(
            deviceId: 'device-1',
            displayName: 'This device',
          ),
          onIdentityChanged: (DeviceIdentity _) {},
        ),
      ),
    ),
  );
  await tester.pump();
}

final class _ThrowingIdentityRepository
    implements DeviceIdentitySettingsRepository {
  const _ThrowingIdentityRepository();

  @override
  Future<DeviceIdentity> updateDisplayName(String displayName) {
    throw StateError('database path=/private/device.sqlite token=secret');
  }
}
