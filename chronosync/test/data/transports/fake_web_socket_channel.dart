import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

final class FakeWebSocketChannel implements WebSocketChannel {
  FakeWebSocketChannel({Future<void>? ready})
    : _ready = ready ?? Future<void>.value();

  final StreamController<Object?> _incoming = StreamController<Object?>();
  final StreamController<Object?> _outgoing =
      StreamController<Object?>.broadcast();

  int? _closeCode;
  String? _closeReason;
  final Future<void> _ready;

  @override
  int? get closeCode => _closeCode;

  @override
  String? get closeReason => _closeReason;

  @override
  String? get protocol => 'chronosync.v1';

  @override
  Future<void> get ready => _ready;

  @override
  WebSocketSink get sink => _FakeWebSocketSink(_outgoing);

  @override
  Stream<Object?> get stream => _incoming.stream;

  Stream<Object?> get outgoing => _outgoing.stream;

  void addIncoming(Object? value) => _incoming.add(value);

  @override
  Never noSuchMethod(Invocation invocation) {
    throw UnsupportedError(
      'This fake supports stream and sink operations only.',
    );
  }

  Future<void> closeRemotely(int code, String reason) async {
    _closeCode = code;
    _closeReason = reason;
    await _incoming.close();
  }

  Future<void> dispose() async {
    if (!_incoming.isClosed) {
      final bool hasIncomingListener = _incoming.hasListener;
      final Future<void> closed = _incoming.close();
      if (hasIncomingListener) {
        await closed;
      }
    }
    if (!_outgoing.isClosed) {
      await _outgoing.close();
    }
  }
}

final class _FakeWebSocketSink implements WebSocketSink {
  const _FakeWebSocketSink(this._controller);

  final StreamController<Object?> _controller;

  @override
  void add(Object? event) => _controller.add(event);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    _controller.addError(error, stackTrace);
  }

  @override
  Future<void> addStream(Stream<Object?> stream) {
    return _controller.addStream(stream);
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) {
    return _controller.close();
  }

  @override
  Future<void> get done => _controller.done;
}
