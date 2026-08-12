abstract interface class DisplayFullscreenDriver {
  bool get isSupported;

  Stream<bool> get changes;

  Future<bool> enter();

  Future<bool> exit();

  Future<bool> toggle();
}

final class UnsupportedDisplayFullscreenDriver
    implements DisplayFullscreenDriver {
  const UnsupportedDisplayFullscreenDriver();

  @override
  bool get isSupported => false;

  @override
  Stream<bool> get changes => const Stream<bool>.empty();

  @override
  Future<bool> enter() async => false;

  @override
  Future<bool> exit() async => false;

  @override
  Future<bool> toggle() async => false;
}
