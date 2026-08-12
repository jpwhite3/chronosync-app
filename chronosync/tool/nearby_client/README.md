# Nearby browser client

This entry point compiles to the small, session-only browser client served by
an iPhone during a nearby session. It intentionally reuses the production
invitation, encryption, session, and command contracts.

After changing `main.dart`, `session_presentation.dart`, or a referenced
protocol model, regenerate the checked-in Flutter asset from the repository
root. The recipe disables source maps and removes compiler metadata:

```sh
make nearby-client
```

Do not edit `assets/nearby_client/client.js` by hand.
