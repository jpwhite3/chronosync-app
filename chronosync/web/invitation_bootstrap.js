(() => {
  const bridgeName = '__chronosyncTakeInitialInvitationUrl';
  try {
    const params = new URLSearchParams(window.location.hash.slice(1));
    if (!params.has('invite')) {
      return;
    }
    let pendingInvitationUrl = window.location.href;
    Object.defineProperty(window, bridgeName, {
      configurable: true,
      enumerable: false,
      value: () => {
        const value = pendingInvitationUrl;
        pendingInvitationUrl = null;
        delete window[bridgeName];
        return value;
      },
    });
    window.history.replaceState(
      window.history.state,
      '',
      `${window.location.pathname}${window.location.search}`,
    );
  } catch (_) {
    // Flutter consumes and scrubs the original fragment through its normal
    // startup path if this early privacy step is unavailable.
  }
})();
