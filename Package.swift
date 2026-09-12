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

        // ── shim products ────────────────────────────────────────────────
        // READ THIS BEFORE ADDING ONE. A shim buys the NAME, not the
        // ISOLATION.
        //
        // The binary is ONE module. `ProximiioBinary.xcframework` contains a
        // single flattened `ProximiioBinary` built from every library module
        // in the source package, and each shim below is one line of
        // `@_exported import ProximiioBinary`. So a target that depends on
        // `ProximiioCore` and writes `import ProximiioCore` still sees the
        // whole SDK surface — `ProximiioConfiguration`, the positioning
        // stack, all of it — and still links the whole dylib. Nothing here
        // narrows what is visible or what is linked. Do not read these
        // product names as module boundaries; they are aliases for one
        // module.
        //
        // Real isolation would need one xcframework per module, which is the
        // split we measured and decided against — every boundary becomes a
        // hard optimisation barrier under BUILD_LIBRARY_FOR_DISTRIBUTION=YES
        // and the sources carry no @inlinable/@frozen to cross it. See
        // docs/binary-distribution-analysis.md.
        //
        // What a shim IS for: letting a downstream SwiftPM package name a
        // dependency that matches its own structure, so it can be
        // version-tagged instead of pinned to `branch: "master"`. Vend a name
        // only when a real consumer names it — one per source module would
        // read as thirteen boundaries that do not exist.
        //
        // `ProximiioCore` — proximiio-ios-map-v6's `ProximiioMapCore` target
        // depends on `.product(name: "ProximiioCore", …)` to express that it
        // uses the models/geometry vocabulary and not the positioning stack.
        // It is the only SDK product name any downstream package asks for
        // besides `Proximiio`, which is why it is the only shim here.
        .library(name: "ProximiioCore", targets: ["ProximiioCore"]),
    ],
    dependencies: [
        // GRDB is open source and carries no Proximi.io IP. It is compiled from
        // source in the customer's build, and the minimum is rendered at publish
        // time from the exact version the binary was compiled against, so a
        // consumer cannot resolve an older GRDB than the SDK was built with.
        //
        // It does NOT satisfy the framework's storage symbols: the shipped
        // dylib already contains the GRDB it was compiled against (zero
        // undefined GRDB symbols; SQLite comes from /usr/lib/libsqlite3.dylib).
        // The public `.swiftinterface` does not reference GRDB either — it must
        // not, or a consumer whose toolchain rebuilds that interface without
        // explicit Clang modules fails with `missing required module
        // 'GRDBSQLite'`, because SwiftPM cannot put GRDB's system-library module
        // map on the search path the interface sub-invocation inherits.
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.1"),
    ],
    targets: [
        .binaryTarget(
            name: "ProximiioBinary",
            url: "https://github.com/proximiio/proximiio-sdk-ios-binary/releases/download/6.0.0-beta.32/ProximiioBinary.xcframework.zip",
            checksum: "d13488e09575455589a002f30e874d978339d092675b581ede7e28197f322e67"
        ),
        .target(
            name: "Proximiio",
            dependencies: [
                "ProximiioBinary",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        // Shim. Same one-line body and the same dependencies as `Proximiio`
        // above — it re-exports the same flattened binary. The GRDB dependency
        // is not optional here either: a binaryTarget cannot declare it, so
        // every source target that re-exports the binary has to carry it or
        // the consumer's link is short the storage symbols.
        .target(
            name: "ProximiioCore",
            dependencies: [
                "ProximiioBinary",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
    ]
)
