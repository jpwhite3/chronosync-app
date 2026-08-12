import 'dart:async';

import 'package:chronosync/core/platform/mac_live_activity.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('com.chronosync/live_activity');

  test('release during acquire ends the eventual native activity', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final Completer<String> beginResult = Completer<String>();
    final List<MethodCall> calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          calls.add(call);
          if (call.method == 'begin') {
            return beginResult.future;
          }
          return null;
        });
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final MacLiveActivityLease lease = MacLiveActivityLease();
    final Future<void> acquire = lease.acquire(reason: 'Test session');
    await Future<void>.delayed(Duration.zero);

    await lease.release();
    beginResult.complete('activity-token');
    await acquire;

    expect(calls.map<String>((MethodCall call) => call.method), <String>[
      'begin',
      'end',
    ]);
    expect(calls.last.arguments, <String, Object>{'token': 'activity-token'});
  });
}
