# Changelog

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
