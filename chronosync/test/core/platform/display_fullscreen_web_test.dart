@TestOn('browser')
library;

import 'dart:async';

import 'package:chronosync/core/platform/display_fullscreen_web.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reports browser fullscreen support', () {
    final FakeWebFullscreenDocument document = FakeWebFullscreenDocument(
      supported: true,
    );

    expect(WebDisplayFullscreenDriver(document).isSupported, isTrue);
    document.supported = false;
    expect(WebDisplayFullscreenDriver(document).isSupported, isFalse);
  });

  test('enters, toggles, exits, and relays browser state changes', () async {
    final FakeWebFullscreenDocument document = FakeWebFullscreenDocument(
      supported: true,
    );
    final WebDisplayFullscreenDriver driver = WebDisplayFullscreenDriver(
      document,
    );
    final List<bool> changes = <bool>[];
    final StreamSubscription<bool> subscription = driver.changes.listen(
      changes.add,
    );
    addTearDown(subscription.cancel);

    expect(await driver.enter(), isTrue);
    expect(await driver.toggle(), isFalse);
    expect(await driver.toggle(), isTrue);
    expect(await driver.exit(), isFalse);
    document.setActiveExternally(true);
    await pumpEventQueue();

    expect(document.requestCount, 2);
    expect(document.exitCount, 2);
    expect(changes, <bool>[true, false, true, false, true]);
  });

  test(
    'returns the current state when the browser rejects a request',
    () async {
      final FakeWebFullscreenDocument document = FakeWebFullscreenDocument(
        supported: true,
        rejectRequests: true,
      );
      final WebDisplayFullscreenDriver driver = WebDisplayFullscreenDriver(
        document,
      );

      expect(await driver.enter(), isFalse);
      expect(await driver.exit(), isFalse);
    },
  );
}

final class FakeWebFullscreenDocument implements WebFullscreenDocument {
  FakeWebFullscreenDocument({
    required this.supported,
    this.rejectRequests = false,
  });

  @override
  bool supported;
  final bool rejectRequests;
  final StreamController<bool> _changes = StreamController<bool>.broadcast();
  bool _active = false;
  int requestCount = 0;
  int exitCount = 0;

  @override
  bool get active => _active;

  @override
  Stream<bool> get changes => _changes.stream;

  @override
  Future<void> requestFullscreen() async {
    requestCount += 1;
    if (rejectRequests) {
      throw StateError('Browser rejected fullscreen.');
    }
    _active = true;
    _changes.add(true);
  }

  @override
  Future<void> exitFullscreen() async {
    exitCount += 1;
    if (rejectRequests) {
      throw StateError('Browser rejected fullscreen.');
    }
    _active = false;
    _changes.add(false);
  }

  void setActiveExternally(bool value) {
    _active = value;
    _changes.add(value);
  }
}
