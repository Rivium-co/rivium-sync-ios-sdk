# Changelog

## 0.3.0

- **Breaking:** `set()` now replaces the document: fields you leave out are
  removed (before, `set()` merged). To keep the old behaviour, pass
  `merge: true`: `collection.set(documentId: id, data: data, merge: true)`.
  The same applies to `WriteBatch.set(_:documentId:data:merge:)`. Writes
  queued offline keep the meaning they were made with.
- With offline persistence on, the cache now stands in only when the server
  cannot be reached (no network, timeouts, 5xx). When the
  server refuses a request (your security rules, invalid data), the error is
  thrown: `getAll()` and `get(documentId:)` no longer answer from the cache,
  and `add`, `set`, `update` and `delete` no longer queue the write to retry
  later. Deleting a document that is already gone succeeds.
- A write made offline that the server refuses when it is sent is dropped,
  and the local copy goes back to the server's (a refused new document
  disappears) instead of staying on the device and being returned by reads.
  `SyncEngine.SyncListener.onDocumentRejected(documentId:operation:error:)`
  reports it (optional, with an empty default).
- After `disconnect()`, writes are queued at once, and
  `RiviumSyncDelegate.riviumSync(_:didDisconnectWithError:)` is called at
  once. Before, a write made right after `disconnect()` could still go to the
  server, and the delegate was not told, so apps kept showing "connected".
- `RiviumSyncError.statusCode`: the HTTP status the server answered with (for
  example 403 when your security rules refused the request), nil when it
  could not be reached. Also set for a refused `WriteBatch.commit()`:
  `batchWriteError` now carries the server's answer as a second value
  (optional, so existing code compiles).
- Listeners are now checked by your security rules like a read or a query,
  and only receive the changes the signed-in user may read. They follow the
  user: after sign-in, sign-out or a switch to another user they start again
  for that user. Requires the current Sync API; with an older one the SDK
  listens as before.
- New listener variants with an error callback:
  `listen(callback:onError:)`, `listenDocument(documentId:callback:onError:)`
  and `SyncQuery.listen(callback:onError:)`.
- New typed errors: `RiviumSyncError.queryNotAllowed(message, fields:)`
  (code `query_not_allowed`) when the security rules do not allow a query or
  query listener - add a filter on the fields named in `fields` - and
  `RiviumSyncError.listenerRevoked` (code `listener_revoked`) when a listener
  is stopped because the rules no longer allow it. `RiviumSyncError` has new
  `code` and `fields` properties. If you `switch` over `RiviumSyncError`
  without a `default`, add the two new cases.
- `listenDocument` now receives only its own document's changes, not every
  change in the collection.
- A `set()` made offline for a new document keeps its id when it is sent.
- Realtime came back after a dropped connection only while its connection
  token was valid (24 hours): later, every reconnect was refused and realtime
  stayed down until the app restarted. A refused login now fetches a fresh
  token and connects again.
- A write made offline that could not be sent (no network, server error) is
  retried until it goes through. Before, it was given up after
  3 attempts and stayed on the device unsent, and a queued delete that failed
  this way was later sent as an update, so the document was not deleted.
- `maxSyncRetries(_:)` is deprecated and has no effect: writes are retried until they go through, and refused ones are
  rolled back.

## 0.2.6

- With offline persistence on, `get()` returns nil only when the document
  does not exist. If the server can't be reached (or refuses) and the
  document is not cached, it now throws the error instead of returning nil,
  so your app can tell "not found" from "couldn't load".

## 0.2.5

- Realtime is always encrypted, and the SDK always uses Rivium's endpoints.
  Removed `apiUrl`, `mqttHost`, `mqttPort` and `mqttUseTls` from
  `RiviumSyncConfig` and `RiviumSyncConfigBuilder`: remove them from your
  code if you set them. If the Sync API's answer is missing or not an
  encrypted rivium.co endpoint, the SDK uses its built-in encrypted endpoint;
  it never connects unencrypted.

## 0.2.4

- Realtime connects where the Sync API tells it (host, port and whether the
  connection is encrypted), so your project can move to encrypted realtime
  (`mqtts`, port 8885) without an app update. Only a rivium.co endpoint is
  accepted, otherwise the SDK uses its built-in one; it never falls back from
  an encrypted connection to a plain one.
- An app that sets `mqttHost`, `mqttPort` or `mqttUseTls` itself keeps its own
  endpoint. `RiviumSyncConfigBuilder.mqttUseTls(_:)` is now optional.
- Added `THIRD_PARTY_NOTICES.md`.

## 0.2.3

- Every request to the Sync API now carries `X-Rivium-SDK: ios/<version>`,
  so the Console can show which SDK and version a project uses. Realtime
  (MQTT) is unchanged.
- New optional `wrapperSdkName` / `wrapperSdkVersion` on `RiviumSyncConfig`
  (and `RiviumSyncConfigBuilder.wrapperSdk(name:version:)`) for Rivium's
  Flutter and React Native wrappers: the header then reads
  `flutter/<version> ios/<version>`. Apps don't need them.

## 0.2.2

- With offline persistence on, writes made before the realtime connection is up
  (or without calling `connect()`) now go to the server instead of waiting in
  the local queue. They are queued only when the device is known to be offline.

## 0.2.1

- `connect()` can be called before sign-in when user tokens are required: the
  SDK waits for a token and then connects.
- Setting a token for a different user reconnects as that user.
- Added `refreshUserToken()`, `isAwaitingUserToken` and `onAwaitingUserToken`.
- Listeners added before the SDK is connected now receive updates.

## 0.2.0

- Added `userTokens` (a token or a `provider`) so Security Rules can trust
  `auth.uid`. Your backend mints a short-lived token; the SDK sends it and
  refreshes it before it expires.
- Fixed `getAll()` stopping at the first 100 documents.
- Fixed documents deleted on the server reappearing while offline.
- Reads at app start now come from the server instead of a stale local copy.
- Fixed an app started offline never connecting once the network returned.
- Debug logs no longer include tokens or response bodies.

## 0.1.0

- First release.
