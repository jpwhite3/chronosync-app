import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Holds a macOS ProcessInfo activity while a live session needs timely work.
final class MacLiveActivityLease {
  static const MethodChannel _channel = MethodChannel(
    'com.chronosync/live_activity',
  );

  String? _token;
  Future<void>? _pendingBegin;
  bool _releaseAfterBegin = false;

  Future<void> acquire({
    required String reason,
    bool keepDisplayAwake = false,
  }) async {
    if (!isSupported || _token != null || _pendingBegin != null) {
      return;
    }
    _releaseAfterBegin = false;
    final Future<void> pendingBegin = _begin(
      reason: reason,
      keepDisplayAwake: keepDisplayAwake,
    );
    _pendingBegin = pendingBegin;
    await pendingBegin;
    _pendingBegin = null;
    if (_releaseAfterBegin) {
      _releaseAfterBegin = false;
      await _endToken();
    }
  }

  Future<void> release() async {
    if (_pendingBegin != null) {
      _releaseAfterBegin = true;
      return;
    }
    await _endToken();
  }

  Future<void> _begin({
    required String reason,
    required bool keepDisplayAwake,
  }) async {
    try {
      _token = await _channel.invokeMethod<String>('begin', <String, Object>{
        'reason': reason,
        'keepDisplayAwake': keepDisplayAwake,
      });
    } on Object {
      _token = null;
    }
  }

  Future<void> _endToken() async {
    final String? token = _token;
    _token = null;
    if (!isSupported || token == null) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('end', <String, Object>{
        'token': token,
      });
    } on Object {
      // The operating system also ends activities when the process exits.
    }
  }

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
}
