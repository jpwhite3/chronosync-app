import 'package:chronosync/data/models/event.dart';
import 'package:chronosync/data/models/global_notification_settings.dart';
import 'package:chronosync/data/repositories/notification_settings_repository.dart';
import 'package:chronosync/data/services/notification_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

final class _StubSettingsRepository extends NotificationSettingsRepository {
  @override
  Future<GlobalNotificationSettings> getGlobalSettings() async {
    return const GlobalNotificationSettings(
      notificationsEnabled: true,
      hapticEnabled: false,
      soundEnabled: false,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel notificationsChannel = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  final List<MethodCall> calls = <MethodCall>[];

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationsChannel, (
          MethodCall call,
        ) async {
          calls.add(call);
          return call.method == 'initialize';
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationsChannel, null);
    debugDefaultTargetPlatformOverride = null;
    calls.clear();
  });

  test('initializes and shows an interval completion notification', () async {
    final NotificationService service = NotificationService(
      settingsRepository: _StubSettingsRepository(),
    );

    await service.init();
    await service.onEventComplete(
      Event(title: 'Closing remarks', durationInSeconds: 60),
    );

    expect(calls.map((MethodCall call) => call.method), <String>[
      'initialize',
      'show',
    ]);
    expect(
      calls.first.arguments,
      containsPair('defaultIcon', '@mipmap/ic_launcher'),
    );
    expect(calls.last.arguments, containsPair('title', 'Interval complete'));
    expect(
      calls.last.arguments,
      containsPair('body', 'Closing remarks has finished'),
    );
    expect(calls.last.arguments, containsPair('id', 0));
  });
}
