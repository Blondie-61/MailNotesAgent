# MailNotes TLS compatibility patch

The patched IdSecOpenSSL unit takes precedence over the existing IndySecOpenSSL installation. The remaining units and headers still come from that installation. This avoids modifying the globally installed library.

The original server used one shared fIOHandler in Accept and registered each accepted handler for TComponent.FreeNotification on the shared server. Concurrent connection teardown can corrupt the unsynchronized component notification list; two listener threads also overwrite the shared pending handler.

The patch uses a local pending handler, binds socket callbacks to that handler, removes the cross-thread notifications and frees an unaccepted handler on listener termination. The server context has no single active socket; its GetSSLSocket returns nil. Existing TLS versions, certificate checks and callback events are retained.

Base unit SHA-1: 9555608a7b602339350e9387726e23b22a091989 (UTF-8 source as read on macOS). Original license notice remains in the source.

Mac reproduction before the patch: 30,510 successful HTTPS requests, then an access violation in TComponent.RemoveFreeNotifications while stopping the HTTP server. The reminder scheduler had already stopped cleanly. The original overnight crash has not yet been conclusively linked to this reproduction. An overnight regression run is required.
