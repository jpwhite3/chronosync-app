import 'package:chronosync/core/platform/initial_invitation_uri_platform_stub.dart'
    if (dart.library.js_interop) 'package:chronosync/core/platform/initial_invitation_uri_platform_web.dart'
    as platform;

abstract interface class PendingInvitationUrlStore {
  String? read();

  void remove();
}

/// Returns an invitation URL hidden by the web bootstrap, if it belongs to
/// the page currently loading. Native platforms simply return [currentUri].
///
/// The value is consumed before it is parsed so malformed or stale secrets do
/// not survive another launch.
Uri initialInvitationUri(Uri currentUri, {PendingInvitationUrlStore? store}) {
  final PendingInvitationUrlStore resolvedStore =
      store ?? platform.createPendingInvitationUrlStore();
  final String? pending;
  try {
    pending = resolvedStore.read();
  } on Object {
    return currentUri;
  }
  if (pending == null) {
    return currentUri;
  }
  try {
    resolvedStore.remove();
  } on Object {
    // Parsing can continue from the in-memory copy. The browser bootstrap
    // will replace the same key if another invitation is opened later.
  }

  final Uri? candidate = Uri.tryParse(pending);
  if (candidate == null ||
      !candidate.hasScheme ||
      candidate.host.isEmpty ||
      !_samePage(candidate, currentUri)) {
    return currentUri;
  }
  try {
    final String? invitation = Uri.splitQueryString(
      candidate.fragment,
    )['invite'];
    return invitation == null || invitation.isEmpty ? currentUri : candidate;
  } on FormatException {
    return currentUri;
  }
}

bool _samePage(Uri candidate, Uri current) {
  return candidate.scheme == current.scheme &&
      candidate.userInfo == current.userInfo &&
      candidate.host == current.host &&
      candidate.port == current.port &&
      candidate.path == current.path &&
      candidate.query == current.query;
}
