import 'dart:async';

import 'package:chronosync/core/platform/display_fullscreen_driver.dart';
import 'package:chronosync/core/platform/display_fullscreen_web_stub.dart'
    if (dart.library.js_interop) 'package:chronosync/core/platform/display_fullscreen_web.dart'
    as web_fullscreen;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Controls fullscreen mode for the read-only Display role on web and macOS.
abstract final class DisplayFullscreen {
  static const MethodChannel _channel = MethodChannel(
    'com.chronosync/display_fullscreen',
  );
  static final StreamController<bool> _changes =
      StreamController<bool>.broadcast();
  static bool _handlerRegistered = false;
  static final DisplayFullscreenDriver _webDriver = web_fullscreen
      .createWebDisplayFullscreenDriver();

  static bool get isSupported => kIsWeb
      ? _webDriver.isSupported
      : defaultTargetPlatform == TargetPlatform.macOS;

  static Stream<bool> get changes {
    if (kIsWeb) {
      return _webDriver.changes;
    }
    _registerHandler();
    return _changes.stream;
  }

  static Future<bool> enter() =>
      kIsWeb ? _webDriver.enter() : _setEnabled(true);

  static Future<bool> exit() => kIsWeb ? _webDriver.exit() : _setEnabled(false);

  static Future<bool> toggle() async {
    if (kIsWeb) {
      return _webDriver.toggle();
    }
    if (!isSupported) {
      return false;
    }
    _registerHandler();
    try {
      return await _channel.invokeMethod<bool>('toggle') ?? false;
    } on Object {
      return false;
    }
  }

  static Future<bool> _setEnabled(bool enabled) async {
    if (!isSupported) {
      return false;
    }
    _registerHandler();
    try {
      return await _channel.invokeMethod<bool>(enabled ? 'enter' : 'exit') ??
          false;
    } on Object {
      return false;
    }
  }

  static void _registerHandler() {
    if (!isSupported || _handlerRegistered) {
      return;
    }
    _handlerRegistered = true;
    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'stateChanged' && call.arguments is bool) {
        _changes.add(call.arguments as bool);
      }
    });
  }
}
