import 'dart:async';
import 'dart:js_interop';

import 'package:chronosync/core/platform/display_fullscreen_driver.dart';
import 'package:web/web.dart' as web;

abstract interface class WebFullscreenDocument {
  bool get supported;

  bool get active;

  Stream<bool> get changes;

  Future<void> requestFullscreen();

  Future<void> exitFullscreen();
}

final class WebDisplayFullscreenDriver implements DisplayFullscreenDriver {
  const WebDisplayFullscreenDriver(this._document);

  final WebFullscreenDocument _document;

  @override
  bool get isSupported => _document.supported;

  @override
  Stream<bool> get changes => _document.changes;

  @override
  Future<bool> enter() => _setEnabled(true);

  @override
  Future<bool> exit() => _setEnabled(false);

  @override
  Future<bool> toggle() => _setEnabled(!_document.active);

  Future<bool> _setEnabled(bool enabled) async {
    if (!isSupported) {
      return _document.active;
    }
    try {
      if (enabled) {
        await _document.requestFullscreen();
      } else if (_document.active) {
        await _document.exitFullscreen();
      }
    } on Object {
      // Browsers can reject fullscreen outside a current user gesture.
    }
    return _document.active;
  }
}

DisplayFullscreenDriver createWebDisplayFullscreenDriver() {
  return WebDisplayFullscreenDriver(BrowserWebFullscreenDocument());
}

final class BrowserWebFullscreenDocument implements WebFullscreenDocument {
  BrowserWebFullscreenDocument() {
    _fullscreenListener = ((web.Event _) {
      if (!_changes.isClosed) {
        _changes.add(active);
      }
    }).toJS;
    web.document.addEventListener('fullscreenchange', _fullscreenListener);
  }

  final StreamController<bool> _changes = StreamController<bool>.broadcast();
  late final web.EventListener _fullscreenListener;

  @override
  bool get supported => web.document.fullscreenEnabled;

  @override
  bool get active => web.document.fullscreenElement != null;

  @override
  Stream<bool> get changes => _changes.stream;

  @override
  Future<void> requestFullscreen() async {
    final web.Element? root = web.document.documentElement;
    if (root == null) {
      throw StateError('The browser document has no root element.');
    }
    await root.requestFullscreen().toDart;
  }

  @override
  Future<void> exitFullscreen() async {
    if (active) {
      await web.document.exitFullscreen().toDart;
    }
  }
}
