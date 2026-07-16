// swift-tools-version:6.0
// Proximi.io iOS SDK — BINARY distribution package.
// This file is regenerated per release by scripts/publish-binary-release.sh;
// the __PLACEHOLDER__ tokens below are rewritten to the published release
// asset URL and its checksum. Do not hand-edit the binaryTarget block.
import PackageDescription

let package = Package(
    name: "Proximiio",
    platforms: [
        .iOS(.v15),
    ],
    products: [
        // Customers import the `Proximiio` umbrella. It is a thin SOURCE wrapper
        // that re-exports the precompiled binary and links GRDB from source.
        .library(name: "Proximiio", targets: ["Proximiio"]),
    ],
    dependencies: [
        // GRDB is open source and carries no Proximi.io IP; it is compiled from
        // source in the customer's build and satisfies the binary's storage
        // symbols at link time.
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .binaryTarget(
            name: "ProximiioBinary",
            url: "https://github.com/proximiio/proximiio-sdk-ios-binary/releases/download/6.0.0-beta.27/ProximiioBinary.xcframework.zip",
            checksum: "2f4e2654ceedab4363efdb2c0bd3c2b98bdfcf012924fc23ce7fb4a432d0cd28"
        ),
        .target(
            name: "Proximiio",
            dependencies: [
                "ProximiioBinary",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
    ]
)
