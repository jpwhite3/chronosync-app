import 'package:chronosync/domain/session/live_session.dart';
import 'package:chronosync/domain/session/session_protocol.dart';
import 'package:chronosync/presentation/screens/join_session_dialog.dart';
import 'package:chronosync/presentation/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('returns a valid pasted invitation', (WidgetTester tester) async {
    final Invitation invitation = _invitation();
    Invitation? result;

    await tester.pumpWidget(
      _DialogHarness(onResult: (Invitation? invitation) => result = invitation),
    );
    await tester.tap(find.text('Open join dialog'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), invitation.toQrPayload());
    await tester.tap(find.text('Join session'));
    await tester.pumpAndSettle();

    expect(result, invitation);
    expect(find.byType(JoinSessionDialog), findsNothing);
  });

  testWidgets('keeps the dialog open for a malformed invitation', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const _DialogHarness());
    await tester.tap(find.text('Open join dialog'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'https://example.com/join');
    await tester.tap(find.text('Join session'));
    await tester.pump();

    expect(find.byType(JoinSessionDialog), findsOneWidget);
    expect(
      find.text(
        'That invitation link is not valid. Ask the host to share it again.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('can paste an invitation from the clipboard', (
    WidgetTester tester,
  ) async {
    final String payload = _invitation().toQrPayload();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'Clipboard.getData') {
          return <String, Object>{'text': payload};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(const _DialogHarness());
    await tester.tap(find.text('Open join dialog'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paste from clipboard'));
    await tester.pump();

    final TextField field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, payload);
  });

  testWidgets('dialog stays usable on a compact screen at 200 percent', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const _DialogHarness(textScale: 2));
    await tester.tap(find.text('Open join dialog'));
    await tester.pumpAndSettle();

    expect(find.text('Join session'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _DialogHarness extends StatelessWidget {
  const _DialogHarness({this.onResult, this.textScale = 1});

  final ValueChanged<Invitation?>? onResult;
  final double textScale;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ChronoTheme.light(),
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Builder(
        builder: (BuildContext context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () async {
                final Invitation? result = await showJoinSessionDialog(context);
                onResult?.call(result);
              },
              child: const Text('Open join dialog'),
            ),
          ),
        ),
      ),
    );
  }
}

Invitation _invitation() {
  return Invitation(
    sessionId: 'session-1',
    transport: SessionTransportKind.nearbyLan,
    endpoint: Uri.parse('http://192.168.1.20:8787'),
    joinUri: Uri.parse('http://192.168.1.20:8787/join'),
    capability: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    sessionSecret: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    requestedRole: SessionRole.participant,
    expiresAt: DateTime.utc(2035),
  );
}
