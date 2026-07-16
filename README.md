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

## Integration (CocoaPods)

Each release also commits a tagged `Proximiio.podspec` to this repo. Reference it
directly by URL — no CocoaPods trunk push is required:

```ruby
# Podfile
platform :ios, '15.0'

target 'YourApp' do
  use_frameworks!
  pod 'Proximiio', :podspec => 'https://raw.githubusercontent.com/proximiio/proximiio-sdk-ios-binary/<tag>/Proximiio.podspec'
end
```

Replace `<tag>` with the release you want (e.g. `6.0.0-rc.1`). Then
`pod install`. The podspec downloads the `ProximiioBinary.xcframework` Release
asset (SHA-256 verified via `:sha256`), links **GRDB.swift ~> 7** from source,
and exposes the SDK under `import Proximiio` — identical to the SPM package.

> **Required: GRDB 7 source override.** The SDK binary is built against GRDB 7,
> but GRDB has **not** published its 7.x line to the CocoaPods trunk CDN (trunk
> stops at 6.24.1). GRDB does ship a valid `.podspec` in its repo at every 7.x
> tag, so add this one line to your `Podfile` to make GRDB 7 resolvable — it is
> what satisfies `pod 'Proximiio'`’s `GRDB.swift ~> 7` dependency:
>
> ```ruby
> pod 'GRDB.swift', :git => 'https://github.com/groue/GRDB.swift.git', :tag => 'v7.11.1'
> ```
>
> Pick any `v7.x` tag `>= 7.0`. When GRDB resumes publishing 7.x to trunk this
> line becomes unnecessary. (SwiftPM consumers are unaffected — SPM resolves
> GRDB 7 directly from the git repo.)

### React Native

The pod works with React Native autolinking through your app's `Podfile`. If you
wrap the SDK in a native module, add the pod alongside your module's other
dependencies:

```ruby
# ios/Podfile — inside your app target
pod 'Proximiio', :podspec => 'https://raw.githubusercontent.com/proximiio/proximiio-sdk-ios-binary/<tag>/Proximiio.podspec'
pod 'GRDB.swift', :git => 'https://github.com/groue/GRDB.swift.git', :tag => 'v7.11.1'  # see GRDB 7 note above
```

```jsonc
// package.json — pin the JS wrapper (if you ship one) to the same SDK line
{
  "dependencies": {
    "react-native-proximiio": "^6.0.0"
  }
}
```

In your Swift/Obj-C bridge, `import Proximiio` and call the SDK as usual.

### Private spec repo (optional, future)

For teams that prefer a curated source, the podspec can instead be pushed to a
private CocoaPods spec repo:

```sh
pod repo add proximiio-specs git@github.com:proximiio/proximiio-podspecs.git
pod repo push proximiio-specs Proximiio.podspec --allow-warnings
```

Consumers then add `source 'https://github.com/proximiio/proximiio-podspecs.git'`
at the top of their `Podfile` and write `pod 'Proximiio', '~> 6.0'`. This repo
is **not** created today; the direct `:podspec => <url>` path above is the
supported flow.

## Checksum verification

Each release pins the xcframework by SHA-256 **checksum** inside `Package.swift`
(`.binaryTarget(url:checksum:)`) **and** inside `Proximiio.podspec` (`:sha256`)
— the same digest for both toolchains. SwiftPM and CocoaPods both refuse a
downloaded archive whose checksum does not match, so a tampered or truncated
download fails the build automatically — you do not need to verify by hand. To
confirm a local archive independently:

```sh
swift package compute-checksum ProximiioBinary.xcframework.zip
```

## License

See [LICENSE](LICENSE).
