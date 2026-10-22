# Changelog

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
