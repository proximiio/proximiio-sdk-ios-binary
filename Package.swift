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
        // that re-exports the precompiled binary — one line, no dependencies.
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
    // NO DEPENDENCIES, ON PURPOSE. The framework is self-contained: GRDB is
    // compiled INTO `ProximiioBinary.xcframework` (≈4 990 exported GRDB
    // symbols, ZERO undefined ones), and the SQLite it talks to is the
    // system's `/usr/lib/libsqlite3.dylib`. So nothing here has to supply
    // GRDB, and declaring it did active harm: SwiftPM links source targets
    // statically, so every consumer — the customer's app AND
    // proximiio-ios-map-v6, which depends on these products — compiled and
    // absorbed a SECOND and THIRD copy of GRDB that no code could ever reach.
    // The symptom a customer saw was 104 `objc[…]: Class _TtC4GRDB… is
    // implemented in both` lines at launch (52 GRDB classes × two redundant
    // registrations) plus ~600 KB of dead bytes per consuming binary.
    //
    // Nor is GRDB part of the published surface: the shipped
    // `.swiftinterface` does not name it — it must not, or a consumer whose
    // toolchain rebuilds that interface without explicit Clang modules fails
    // with `missing required module 'GRDBSQLite'`, because SwiftPM cannot put
    // GRDB's system-library module map on the search path the interface
    // sub-invocation inherits. `import GRDB` is `package import` in the
    // sources for exactly that reason.
    //
    // Do not re-add it. scripts/verify-binary-release.sh asserts BOTH halves
    // on the shipped bytes — the binary must export GRDB and import none, and
    // this manifest must declare none — and fails the release either way.
    dependencies: [],
    targets: [
        .binaryTarget(
            name: "ProximiioBinary",
            url: "https://github.com/proximiio/proximiio-sdk-ios-binary/releases/download/6.0.0-beta.42/ProximiioBinary.xcframework.zip",
            checksum: "afc59fa1328ab7a68df71bd489570412b7ff79a707655bd49eaa6f7879c7dfbc"
        ),
        .target(
            name: "Proximiio",
            dependencies: ["ProximiioBinary"]
        ),
        // Shim. Same one-line body as `Proximiio` above — it re-exports the
        // same flattened binary, and like `Proximiio` it needs nothing but the
        // binary target itself.
        .target(
            name: "ProximiioCore",
            dependencies: ["ProximiioBinary"]
        ),
    ]
)
