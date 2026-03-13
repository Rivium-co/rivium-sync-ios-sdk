# RiviumSync iOS SDK

Realtime database SDK for iOS with offline-first sync powered by pn-protocol.

[![Swift 5.7+](https://img.shields.io/badge/Swift-5.7+-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2013+%20|%20macOS%2012+-blue.svg)](https://developer.apple.com)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Installation

### Swift Package Manager (Xcode)

1. In Xcode, go to **File → Add Package Dependencies**
2. Enter the repository URL:
   ```
   https://github.com/Rivium-co/rivium-sync-ios-sdk
   ```
3. Select version **0.1.0**
4. Add **RiviumSync** library to your target

### Swift Package Manager (Package.swift)

```swift
dependencies: [
    .package(url: "https://github.com/Rivium-co/rivium-sync-ios-sdk", from: "0.1.0"),
]
```

Then add `"RiviumSync"` to your target's dependencies:

```swift
.target(
    name: "YourApp",
    dependencies: ["RiviumSync"]
)
```

## Documentation

- [Rivium Cloud](https://rivium.co/cloud)
- [Rivium Console](https://console.rivium.co)

## License

MIT
