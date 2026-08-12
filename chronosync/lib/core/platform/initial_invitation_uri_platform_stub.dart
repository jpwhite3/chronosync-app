import 'package:chronosync/core/platform/initial_invitation_uri.dart';

PendingInvitationUrlStore createPendingInvitationUrlStore() {
  return const _EmptyPendingInvitationUrlStore();
}

final class _EmptyPendingInvitationUrlStore
    implements PendingInvitationUrlStore {
  const _EmptyPendingInvitationUrlStore();

  @override
  String? read() => null;

  @override
  void remove() {}
}
