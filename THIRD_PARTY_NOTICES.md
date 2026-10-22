# Third-Party Notices

`RiviumSync` (iOS) uses the following third-party components.
None of them is vendored: CocoaPods or Swift Package Manager pulls them into
your build. See each upstream repository for the full license text.

---

## CocoaMQTT (via `PNProtocol`)

Used for the realtime connection (live listeners). Rivium's `PNProtocol`
library depends on it.

- Homepage: https://github.com/emqx/CocoaMQTT
- Version: 2.1.6 or later 2.x (2.4.1 at the time of this release)
- License: Eclipse Public License 1.0 / Eclipse Distribution License 1.0 (dual)

---

## MqttCocoaAsyncSocket (via CocoaMQTT)

TCP and TLS sockets under CocoaMQTT.

- Homepage: https://github.com/leeway1208/MqttCocoaAsyncSocket
- Version: 1.0.8
- License: Public Domain, or BSD License (Copyright (c) 2017, Deusty, LLC), at your choice

---

## Starscream (via CocoaMQTT, Swift Package Manager only)

WebSocket support that Swift Package Manager resolves with CocoaMQTT. The SDK
connects over MQTT/TCP and does not use it; CocoaPods does not install it.

- Homepage: https://github.com/daltoniam/Starscream
- Version: 4.0.8
- License: Apache License 2.0
