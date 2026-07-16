# Proximi.io iOS SDK

Precompiled binary distribution of the Proximi.io iOS SDK (indoor positioning,
PDR, geofencing, route snapping, wayfinding, offline venue packages).

> This repository ships the SDK as a signed **xcframework** via Swift Package
> Manager. The source is proprietary and not published here.

## Requirements

- iOS 15.0+
- Xcode 16+ / Swift 6

## Integration (Swift Package Manager)

Add the package in Xcode (**File ▸ Add Package Dependencies…**) using this
repository's URL, or add it to your own `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/proximiio/proximiio-sdk-ios-binary.git", from: "6.0.0"),
],
targets: [
    .target(name: "YourApp", dependencies: [
        .product(name: "Proximiio", package: "proximiio-sdk-ios-binary"),
    ]),
]
```

Then use it:

```swift
import Proximiio

let config = ProximiioConfiguration.default(token: "YOUR_API_TOKEN")
let sdk = Proximiio(configuration: config)
try await sdk.authenticate()
try await sdk.start()
for await position in sdk.positions() { /* … */ }
```

## Checksum verification

Each release pins the xcframework by SHA-256 **checksum** inside `Package.swift`
(`.binaryTarget(url:checksum:)`). SwiftPM refuses to use a downloaded archive
whose checksum does not match, so a tampered or truncated download fails the
build automatically — you do not need to verify by hand. To confirm a local
archive independently:

```sh
swift package compute-checksum ProximiioBinary.xcframework.zip
```

## License

See [LICENSE](LICENSE).
