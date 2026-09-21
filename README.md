# RiviumSync iOS SDK

Realtime database SDK for iOS with offline-first sync powered by pn-protocol.

[![Swift 5.7+](https://img.shields.io/badge/Swift-5.7+-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2013+%20|%20macOS%2012+-blue.svg)](https://developer.apple.com)
[![CocoaPods](https://img.shields.io/cocoapods/v/RiviumSync.svg)](https://cocoapods.org/pods/RiviumSync)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Installation

### Swift Package Manager (Xcode)

1. In Xcode, go to **File → Add Package Dependencies**
2. Enter the repository URL:
   ```
   https://github.com/Rivium-co/rivium-sync-ios-sdk
   ```
3. Select version **0.2.0**
4. Add **RiviumSync** library to your target

### Swift Package Manager (Package.swift)

```swift
dependencies: [
    .package(url: "https://github.com/Rivium-co/rivium-sync-ios-sdk", from: "0.2.0"),
]
```

Then add `"RiviumSync"` to your target's dependencies:

```swift
.target(
    name: "YourApp",
    dependencies: ["RiviumSync"]
)
```

### CocoaPods

Add to your `Podfile`:

```ruby
pod 'RiviumSync', '~> 0.2'
```

Then run:

```bash
pod install
```

## Verified user identity

Security Rules check `auth.uid`. The API key ships inside your app, so the app
cannot be trusted to say who the user is - only your own server can. Have your
backend mint a short-lived user token and give the SDK a provider:

```swift
let sync = RiviumSync.initialize(config: RiviumSyncConfigBuilder(apiKey: "rv_live_your_api_key").build())
sync.userTokens.provider = {
    try await MyBackend.fetchSyncToken()
}
```

The SDK asks for a token when it needs one and again before the old one
expires. Your backend mints it with your project's server secret, which must
stay on your server and never ship in an app.

If your project has **Require signed user tokens** turned on in the Console, a
token is required; without it, requests are refused.

## Documentation

- [Rivium Cloud](https://rivium.co/cloud)
- [Rivium Console](https://console.rivium.co)

## License

MIT
