import 'dart:js_interop';

import 'package:chronosync/core/platform/initial_invitation_uri.dart';

@JS('__chronosyncTakeInitialInvitationUrl')
external JSString? _takeInitialInvitationUrl();

PendingInvitationUrlStore createPendingInvitationUrlStore() {
  return const _BrowserPendingInvitationUrlStore();
}

final class _BrowserPendingInvitationUrlStore
    implements PendingInvitationUrlStore {
  const _BrowserPendingInvitationUrlStore();

  @override
  String? read() {
    return _takeInitialInvitationUrl()?.toDart;
  }

  @override
  void remove() {}
}
