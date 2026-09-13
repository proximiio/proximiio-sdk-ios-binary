# Changelog

All notable changes to the Proximi.io iOS SDK are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [6.0.0-beta.36] — 2026-09-13

### Changed

- **The diagnostics recording no longer needs a `Proximiio` instance.** The three
  cases support sees most — "the SDK never started", "authentication failed",
  "I passed the wrong token" — are the ones where there is either no instance at
  all (`init(configuration:)` throws) or one that never got past
  `authenticate()`. An export reachable only through a successfully-constructed
  facade could not describe any of them, which made the single most valuable
  report the one it could not produce.

  `startDiagnosticsRecording(_:)`, `stopDiagnosticsRecording()`,
  `isRecordingDiagnostics`, `recordDiagnosticsEvent(_:_:at:)`,
  `attachDiagnosticsReportSection(_:_:)`, `addDiagnosticsSecret(_:)` and
  `prepareDiagnosticsReport()` now exist on `Proximiio` **the type** as well as
  on an instance. Start the recording on the first line of
  `didFinishLaunchingWithOptions`; the first instance to call `authenticate()`
  or `start()` is adopted into it automatically, and its streams join the same
  file below what is already there — nothing to hold, nothing to hand over.

  There is one recording per process, stated plainly, because there is one
  `proximiio-diagnostics.log` per container. That was already true (two facades
  recording at once already interleaved into one file); this makes it explicit
  and lock-safe. The alternatives were considered and rejected: a recorder
  object the host creates adds a step and a stored property to a five-step
  drop-in and does not actually remove the global, and recording implicitly
  writes a file into a customer's container uninvited.

  A report taken with no instance omits the manifest's `diagnostics`,
  `configuration` and `inputs` sections rather than zero-filling them — an
  absent section is a finding, a fabricated one is a wrong answer — and the
  README's verdict says the SDK was never running.

- **`recordDiagnosticsEvent(_:_:at:)` is no longer `async`.** It was `async` into
  an actor, so a host with a synchronous logger — every host — either chained the
  calls itself or watched consecutive lines land in the file in whatever order
  the runtime resumed them. Events are now queued synchronously under a lock, so
  file order is call order from any thread, and the recorder drains that queue
  before a flush, a stop and an export. Ordering is the SDK's problem, which is
  where it belongs. Existing `await` call sites keep compiling (with a
  "no 'async' operations occur" warning).

- **`ProximiioDiagnosticsEventKind` is a `RawRepresentable` struct rather than an
  enum, and hosts can name their own column.** Three kinds is not a taxonomy: an
  app with ten had to smuggle its own into the message text as a `[MAP]` prefix,
  which puts it in the one column nothing indexes. `.custom(_:)` writes `MAP`,
  `ROUTE`, `NAV` into the kind column instead.

  The column stays a contract: `[A-Z]`, at most `maximumLength` (12) characters —
  the intersection of what `DiagnosticsLogDecoder` can tokenise and what
  `tools/accuracy/evaluate.py`'s `[A-Z]+\b` can count. Both readers drop a column
  they cannot parse *silently*, so `.custom(_:)` normalises rather than refuses
  (`"route-2"` → `ROUTE`) and falls back to `.info` for a name that survives
  nothing or that claims a kind the SDK writes itself — a hand-written `FIX`
  would inject a phantom position into a replay. `init?(rawValue:)` refuses
  anything the format cannot carry. The static members (`.fix`, `.state`, …),
  `rawValue`, `init?(rawValue:)` and `Codable` are unchanged; an exhaustive
  `switch` over the kind no longer compiles, which is the only realistic break
  and only for code written against `6.0.0-beta.35`.

### Added

- **`addDiagnosticsSecret(_:)`, which scrubs backwards as well as forwards.**
  `ProximiioDiagnosticsRecordingOptions.additionalSecrets` freezes when recording
  starts, which is fine for a value compiled in and useless for the ones that
  matter: a relay bearer and an engine password are typed into a settings screen
  an hour into a session. Redaction that depends on the host getting the ordering
  right is redaction that will fail.

  Registering a secret mid-session now removes it from the material **already
  written** — the current log, the retained previous generation, the unflushed
  buffer and the manifest sections already attached — not only from future
  writes. The line most likely to contain the value is the one the host wrote the
  instant the user typed it, and that line is on disk before anyone can call
  this. Adoption of an instance registers its application token the same way, so
  a token logged before the SDK existed is scrubbed retroactively too.

  It returns `false`, and writes a line saying so (never the value), when the
  value is under eight characters — below which scrubbing destroys the log rather
  than the credential — or is already known.

- Host-owned manifest sections are now redacted on the way in, keys included,
  rather than only caught by the L3 audit refusing the whole export.

## [6.0.0-beta.35] — 2026-09-13

### Fixed

- **The bearer token was being written to disk by `URLCache`, and every release
  before this one is affected.** Finding M14 moved the credential out of URLs
  and into an `Authorization` header, which was right — but `URLCache` persists
  request headers alongside responses, so the token moved from one on-disk
  artefact to another. It was found by pulling a container off a physical
  device and scanning the bytes: 34 `Authorization: Bearer` headers in
  `Library/Caches/<bundle>/Cache.db-wal`. Cached bodies included venue data.

  The SDK's own sessions were `.ephemeral` and therefore safe — but only by
  accident, because that configuration's built-in cache happens to have zero
  disk capacity. The live hole was the public `init(session:)` seams on the
  relay and Blueiot transports: hand them `URLSession.shared`, which is the
  natural thing to pass, and the credential lands on disk.

  A session that would write to disk is now rebuilt without its cache; its
  timeouts, headers, proxy settings and protocol classes survive. One-time
  cleanup clears what earlier versions already wrote, gated on a marker so it
  runs once rather than on every launch.

  Worth knowing if you are hardening your own networking: neither
  `.reloadIgnoringLocalCacheData` nor `willCacheResponse` returning `nil`
  prevents the write — the first governs reads, the second is not honoured on
  every request method. Clearing the cache is the only control that holds. And
  there is no way to keep the response body while dropping the credential:
  `URLCache` keys one entry by its request and stores both halves together.

  **Cost:** no HTTP response caching on API traffic. Sync is watermark-based,
  so the practical loss is 304 revalidation on repeated identical GETs.

### Added

- **A support report is now one call, and the SDK writes it.** Recording a
  session and preparing the bundle replaces the checklist an integrator used to
  work through by hand — capture `diagnostics().summary` while the problem is
  live, install a log sink, print the venue-configuration checks, remember the
  SDK and iOS versions — and produces a single `.zip` to attach to a ticket.

  ```swift
  // Once, at launch. Before start(), so "the SDK never started" is recordable.
  try await proximiio.startDiagnosticsRecording()

  // … reproduce the problem …

  let report = try await proximiio.prepareDiagnosticsReport()
  share(report.archiveURL)      // proximiio-report-20260913-101422.zip
  ```

  Inside `proximiio-report-<yyyyMMdd-HHmmss>.zip`: a generated `README.txt`
  written in plain English for whoever opens it — what this is, the session
  (app, SDK, device, when it started, how many positions), a **Verdict** line,
  what to do about it, and what each other file holds; `proximiio-diagnostics.log`
  in the established `<ISO8601 fractional><SP><SP><KIND><TAB><message>` format,
  with the rotated `proximiio-diagnostics-previous.log` beside it when one
  exists; a pretty-printed, sorted-key `proximiio-session-manifest.json`
  carrying `schemaVersion`, `sdk`, `app`, `device`, `session`, `diagnostics`,
  `configuration`, `inputs` and any host-attached `extensions`; and
  `proximiio-inputs-layout.json` when the venue has positioned inputs.

  The log gains a `DIAG` kind written on every diagnostics transition —
  `noPositionReason` changing, a provider's connection flipping, the last fix
  crossing a staleness band — plus a heartbeat forced every 60 s even when
  nothing changed. That heartbeat is the point: two consecutive lines with the
  same fix count and a growing age say the stream went quiet, while a climbing
  fix count and an age under a second say positions are arriving and a dot that
  will not move is a geometry problem. A frozen position and a dead stream look
  identical in the app and want completely different fixes.

  **The bundle carries no credentials, and that is enforced rather than
  asserted.** Three layers: the manifest records `tokenConfigured: Bool` and
  never a token, every log line and manifest string is scrubbed at write, and
  the finished bytes are audited — if anything credential-shaped survived,
  `prepareDiagnosticsReport()` throws
  `ProximiioDiagnosticsReportError.redactionAudit(_:)` and **produces no file at
  all**, so there is nothing left on disk to share by accident. Each finding
  names the file, the line and the rule. This belongs in the SDK because the SDK
  is the component that *holds* the application token and can scrub it without
  being told; an app-level redactor must be told its secrets and will be told
  them incompletely. Pass any others your app configured through
  `ProximiioDiagnosticsRecordingOptions.additionalSecrets`.

  Coordinates, beacon short keys, anchor names, tag ids, hostnames and geofence
  names are deliberately **not** redacted. They are the content, they are
  already visible to anyone holding the venue configuration, and an export
  nobody can read is a screenshot with extra steps.

  **What you have to do: nothing.** Recording is opt-in and off until you call
  `startDiagnosticsRecording(_:)`, which is deliberate — it writes a file in your
  container and subscribes to streams, and an SDK should not do either uninvited.
  Calling it twice is a no-op rather than an error, so a launch call and a
  settings toggle need not coordinate, and `prepareDiagnosticsReport()` works
  whether or not a recording is running: with no recorder it reopens the same
  on-disk log, so an export after a crash and relaunch still carries the session
  that crashed. An empty log is itself a finding — the SDK never started, the
  token was never accepted, permission was denied — so the export never refuses
  the cases that most need one.

  Your own lines go in the same timeline via
  `recordDiagnosticsEvent(_:_:at:)`, and the things only the host knows via
  `attachDiagnosticsReportSection(_:_:)`. Knobs on
  `ProximiioDiagnosticsRecordingOptions`: `directory`, `diagnosticsInterval`
  (1 s), `heartbeatInterval` (60 s), `rotationThresholdBytes` (2 MB),
  `maximumBundleBytes` (10 MB), `recordsBeacons` (`true`), `capturesSDKLog`
  (`false`) and `additionalSecrets`.

  Nothing about the bundle is a private format. Unzip it and point the tools
  that already existed at the files inside:

  ```
  python3 tools/accuracy/evaluate.py run1/proximiio-diagnostics.log \
      --layout run1/proximiio-inputs-layout.json --out report1

  python3 scripts/anonymize-diagnostics-log.py run1/proximiio-diagnostics.log fixture.log \
      --layout run1/proximiio-inputs-layout.json fixture-layout.json
  ```

  **Known limitation:** diagnostics are polled at 1 Hz rather than streamed, so
  a transition that opens and closes inside one interval is missed — a provider
  that drops and reconnects within the same second leaves no `DIAG` line. The
  forced heartbeat bounds how long any state can go unrecorded; it does not make
  the record continuous. A real change stream is follow-up work.

- **`ProximiioPackage.version` — the SDK can now say which release it is.** It
  could not before, which meant a support bundle, a crash report or an integrity
  dump could describe a misbehaving SDK without identifying it, and four betas
  can ship in a week. "The current version" is not a usable answer to "which
  build produced this".

  ```swift
  ProximiioPackage.version      // "6.0.0-beta.34" — the most recent released tag
  ProximiioPackage.generation   // "6" — what other packages pin against
  ```

  Both are plain constants. Nothing is derived at build time: a build revision
  or a build date would look authoritative in a report while being unverifiable
  against anything. `scripts/release.sh` is the only thing that moves `version`,
  rewriting it in the same commit that stamps this file, and a test fails the
  moment the constant and the newest stamped heading disagree. A build made
  between two releases reports the release it descends from — an unpublished
  build has no other honest answer. The report export stamps it into every
  manifest.

### Changed

- **`ProximiioDiagnostics.ConfigurationSummary` is now `Encodable`, so you can
  stop hand-mirroring it.** Serialising a diagnostics snapshot into your own
  telemetry or support payload meant writing out roughly forty knobs by hand,
  and a knob added here silently went missing from your report until someone
  noticed. `NoPositionReason`, `VisitorReportingState` and
  `CustomPositionProviderConnection` gained the same conformance, which is what
  makes the summary encodable as a whole.

  ```swift
  let json = try JSONEncoder().encode(await proximiio.diagnostics().configuration)
  ```

  **What you have to do: nothing** — this is additive, and the mirroring code
  you already have keeps working. Delete it when convenient.

  **`Encodable`, not `Codable`, on purpose.** These are snapshots of live SDK
  state, produced by the SDK and read by a human or a tool. Decoding one would
  imply a value you can construct and hand back, which is not a thing the SDK
  accepts, and it would freeze every field name into a format we have to keep
  decoding after the diagnostics themselves move on. Write-only keeps the
  summary free to grow.

## [6.0.0-beta.34] — 2026-09-12

### Removed

- **The binary distribution no longer declares a GRDB dependency.** Neither the
  SwiftPM `Package.swift` nor the CocoaPods podspec asks for `GRDB.swift` any
  more.

  GRDB is compiled *into* `ProximiioBinary.xcframework` — 4 990 exported GRDB
  symbols per slice, **zero** undefined, with SQLite coming from
  `/usr/lib/libsqlite3.dylib`. The framework has never needed an external copy,
  and its public `.swiftinterface` never named a GRDB type. But SwiftPM and
  CocoaPods link source dependencies *statically*, so declaring GRDB made every
  consumer compile and absorb a second one that no code could reach — the
  customer's app, and `proximiio-ios-map-v6` on the way through.

  What a customer saw: 104 `objc[…]: Class _TtC4GRDB… is implemented in both …`
  lines at launch — 52 GRDB classes, registered three times over — and
  **601 873 bytes** of dead GRDB in the map framework alone (23 % of its
  symbol-covered `ios-arm64` bytes; the same 601 991 bytes are the one copy the
  SDK legitimately carries). Nothing misbehaved: there is exactly one SDK in the
  process, the extra GRDB copies were never entered, and no state was
  duplicated. It was noise and dead weight, and it is gone.

  **What you have to do: nothing**, beyond re-resolving on the next tag.
  CocoaPods integrators get a line *back*: the Podfile no longer needs
  `pod 'GRDB.swift', :git => …, :tag => 'v7.11.1'` — the workaround for GRDB's
  7.x line being absent from the CocoaPods CDN — and keeping it re-creates the
  duplicate. Delete it.

  **The one way this can break you:** if your own code writes `import GRDB` and
  reached GRDB transitively through us, it no longer resolves. That was never a
  documented or supported part of this SDK's surface — no public API exposes a
  GRDB type and the shipped interface never re-exported it — so declare GRDB
  yourself:

  ```swift
  .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.1"),
  ```

  `manifest.json` still records `grdbVersion` as build provenance (which GRDB is
  inside these bytes — the MIT notice obligation is unchanged, since the
  framework still redistributes GRDB). It is no longer rendered into any
  manifest.

  `verify-binary-release.sh` replaces the old "advertised GRDB minimum is not
  below the compiled-against version" check — which, with nothing left to grep
  for, had silently degraded from a hard failure to a warning — with the
  inverse invariant asserted on the shipped bytes, in both directions and both
  fatal: every slice must **export** GRDB symbols and **import** none, and the
  manifest a customer resolves must **declare** none. Three negative controls
  prove the gate can fail: a binary with no GRDB in it, a binary that leaves a
  GRDB symbol undefined, and a manifest that declares GRDB as a package
  dependency and as a target product.

## [6.0.0-beta.33] — 2026-09-12

### Fixed
- **The published xcframeworks carried invalid code signatures, and every
  release before this one is affected (`6.0.0-beta.27` through
  `6.0.0-beta.32`).** An app embedding them dies at launch with
  `SIGKILL (Code Signature Invalid)` before its test host bootstraps, and the
  error names nothing useful. SwiftPM's SHA-256 check passes throughout,
  because a checksum proves the bytes arrived intact, not that they are signed.

  Two separate defects produced the one symptom. Simulator slices are ad-hoc
  signed by `ld`, and `strip -x -S` then shortened the Mach-O while leaving
  `LC_CODE_SIGNATURE` untouched, so `codeLimit` described a longer file than
  existed — `strip` warns about exactly this on stderr, and the build script
  was discarding that output. The device slice was never signed at all:
  `xcodebuild archive` emits `ios-arm64` without a signature, and `ld`'s
  ad-hoc signing does not cover iOS device.

  Frameworks are now signed per bundle immediately after `strip`, the last
  step that mutates them. The signature is ad-hoc deliberately: dyld checks
  integrity rather than identity, Xcode re-signs embedded frameworks with the
  customer's own identity, and ad-hoc signing is byte-deterministic so the
  "same tag rebuilds to the same checksum" property survives.

  `verify-binary-release.sh` now checks `codesign -v --strict` per slice **and
  per architecture** — a fat slice valid for one arch and broken for another
  passes a whole-file check — with negative controls reproducing both verdicts
  seen in the field.

  **If you are on any earlier release, upgrade.** The older artefacts are not
  usable in an app that runs tests.

## [6.0.0-beta.32] — 2026-09-12

### Added
- **Four public additions the map package needed, so it does not re-implement
  SDK plumbing.** Each removes a duplicate that already exists in both
  first-party apps; all four are additive and the api-baseline diff carries
  nothing else.
  - `Proximiio.features() -> [ProximiioFeature]` — the venue's map features
    (rooms, POIs, level changers, paths) read synchronously from the local
    cache, next to `places()` and `floors()`. The cache is the one
    `loadRouteNetwork()` already fills, so a renderer gets every feature from
    the download the router was doing anyway instead of paging
    `GET /v7/geo/features` a second time. Empty until that has succeeded once.
  - `Proximiio.mapStyle() async throws -> Data` — the organization's MapLibre
    style document, returned verbatim. The SDK now owns the endpoint, which is
    the point: both apps built `GET /v7/geo/style` by hand, and that is how a
    token once ended up in a query string. Here it travels in the
    `Authorization` header.
  - `Proximiio.amenities() async throws -> [ProximiioAmenity]` — the
    icon-and-title taxonomy a feature's `properties.amenity` refers to, paged to
    completion. A network read rather than a cache read, deliberately: amenities
    are not in the resource set the sync pipeline fills, so a synchronous
    accessor beside `places()` would return an empty array forever.
  - `GeoMath.destination(from:distanceMeters:bearingDegrees:)` — the coordinate
    reached by walking a distance along a bearing, on the public
    `meanEarthRadiusMeters` sphere. It closes the loop with `haversineDistance`
    and `bearing`, which is what an accuracy ring and a heading wedge need.
    This is a **new** function, not the Turf-parity `destination` made public:
    that one is bound to `turfEarthRadiusMeters` and would not round-trip with
    the public distance function, so it stays `package`. See
    `docs/DECISIONS.md`.

## [6.0.0-beta.31] — 2026-09-11

### Fixed
- **A geofence drawn in the management app is now monitored where it was
  drawn, instead of never firing at all.** `/core/geofences` stores `area` as
  an untyped object, and our own clients write two different shapes into it:
  post a `polygon` ring and the API derives `area` as a `{lat, lng}` centroid
  plus a `radius` (the shape this SDK was modelled on), while the management
  app writes a GeoJSON geometry *object* into `area` and a circle's centre into
  `location`. Handing that geometry object to a `{lat, lng}` decoder that fills
  each missing member with `0` produced a geofence at `(0, 0)`: the record
  decoded, `hasArea` was `true`, `radius` was `0`, and the engine's
  zeroed-centre guard then made it permanently inert — monitored, evaluated on
  every position update, never matching, and never logged. A circle authored
  the same way lost its centre outright and was equally silent. This was not a
  rendering bug: geofences are decoded for **monitoring**, so an affected
  region never fired in a visitor's app and never appeared in analytics.

  `ProximiioGeofence` and `ProximiioPrivacyZone` now read `area` deliberately
  rather than assuming one shape. A `{lat, lng}` centre still decodes exactly
  as before, including its historical tolerance for numeric strings and a
  half-written pair. A GeoJSON `Polygon`, `MultiPolygon`, `Point` or `Feature`
  is understood, with a ring read into `polygon` in the `[longitude, latitude]`
  order that field already uses. A centre in `location` is read when nothing
  else described a shape. An explicit `polygon` member still wins over
  everything, so records the API derived are untouched.

  Tolerant reading, strict writing: encoding is unchanged, and `location` is
  read but never written.

- **An `area` the SDK cannot recognise is now reported instead of guessed.**
  New `ProximiioGeofence.geometryIssue` / `ProximiioPrivacyZone.geometryIssue`
  (`ProximiioGeometryIssue`) say when `area` held something that is neither a
  centre nor a usable outline (`.unreadableArea`), or an outline of fewer than
  three distinct positions (`.degenerateOutline`). Both leave `area` and
  `polygon` `nil` rather than inventing a coordinate — the invented `(0, 0)` is
  precisely what kept the original defect invisible. The diagnostic describes a
  decode, not a geofence, so it takes no part in equality and is never encoded;
  `==` is now written out on both types for that reason.

### Changed
- **The binary distribution no longer ships `ProximiioQuuppa`.** The
  xcframework build sweeps every `.swift` under `Sources/` into one flattened
  `ProximiioBinary`, which opted a new module **in** by default — so the
  experimental Quuppa QPE client, its configuration type and its test doubles
  (`QuuppaFakeQPE`, `QuuppaFakePayloads`, `QuuppaScriptedSleeper`) sat in every
  binary customer's autocomplete, undoing the effort spent hiding them from the
  documentation. `scripts/build-xcframeworks.sh` now carries an explicit
  `EXCLUDED_MODULES` list, one entry with its reason, and both it and
  `scripts/verify-binary-release.sh` assert on the shipped `.swiftinterface`
  that the withheld symbols are gone **and** that `ProximiioBlueiot` and
  `ProximiioLiveView` are still present — those two stay in the binary, because
  the Blueiot cloud relay client is in a live customer's shipping product.

  Source consumers are unaffected: `Package.swift` still vends
  `ProximiioQuuppa` as a product, and `api-baseline/` — which records the
  **source** package's surface, not the binary's — is unchanged.
  `import Proximiio` is untouched for everyone.

### Added
- **Shim products in the binary distribution package.**
  `distribution/Package.swift.template` now also vends `ProximiioCore`
  alongside `Proximiio`, so `proximiio-ios-map-v6` can write
  `.product(name: "ProximiioCore", …)` and become a version-tagged package
  instead of pinning `branch: "master"` on the SDK source. A shim buys the
  **name, not isolation**: the binary is one flattened module, so a target
  importing `ProximiioCore` still sees the whole SDK surface and still links
  the whole dylib. Real isolation would need one xcframework per module — see
  `docs/binary-distribution-analysis.md` for why that was measured and
  rejected. `verify-binary-release.sh` now builds one smoke target per vended
  product, each importing only its own, so a broken shim cannot ship green.
- **`RelayPositionProvider` reports its connection**, so an app fed only by the
  RTLS relay can finally reach `NoPositionReason.positioningSourceOffline`. The
  reason shipped with only `BlueiotCloudRelayClient` answering `connection`,
  which left the vendor-neutral client — the one the case was written for —
  inheriting the protocol default `.unknown` and unable to raise it. The state
  lives on `RelayClient.connection` (new, `public`) and the provider forwards it:
  - `.online` from the first position the run loop accepts, on **either**
    transport. An app whose SSE was eaten by a proxy is polling, is receiving the
    venue's fixes, and is not lost — it reads online. `transportMode()` remains
    the way to ask which path won.
  - `.offline` once consecutive failures on the path in use reach
    `streamFailuresBeforePollFallback` — the client's own tolerance, the count at
    which it stops believing SSE and changes strategy. Below it the answer does
    not move: one `text/event-stream` connection ending and being re-established
    is the ordinary lifecycle of a long stream, and reporting it would blink a
    "venue lost" banner at the reconnect cadence. It clears on the next accepted
    position, not on a counter reset.
  - `.unknown` while a freshly started client has neither accepted a position nor
    failed that many times, and again after `resume()` — the network the phone
    came back to has not been tried yet. A warming-up app reads
    `awaitingFirstFix` rather than "the venue is gone", because the reason
    ignores `.unknown` on both sides.
  - `.offline` while stopped or paused, when the client holds nothing open. That
    is the literal truth and not a venue outage; the facade already keeps the two
    apart by weighing only providers it is actually consuming.
  - The geofence loop is deliberately outside this signal: it is an independent
    subscription a host may never open, it carries transitions rather than
    positions, and it has its own readers.
- **The vendor-neutral RTLS relay client is its own module, `ProximiioRelay`.**
  `RelayClient`, `RelayPositionProvider`, `RelayConfiguration`, `RelayPosition`,
  `RelayGeofenceEvent`, `RelayError`, `RelayURLSessionTransport` and the
  `RelayFakeServer` simulation harness lived inside `ProximiioQuuppa` — a module
  we deliberately keep out of an integrator's sight because it is experimental
  and named after somebody else's RTLS. That mismatch had started to cost real
  things: the client permissions document could only describe the neutral seam
  instead of the shipping relay client, and the README's Quuppa row turned out
  to be the only place naming the relay's home. Now it is a library product of
  its own, **re-exported by the umbrella** — so `import Proximiio` sees the
  relay API with no second import, and `ProximiioQuuppa` is once again only what
  its name says.
  - Two relay-only types were renamed with the move: `QuuppaStreamingTransport`
    → `RelayStreamingTransport`, `QuuppaStreamingResponse` →
    `RelayStreamingResponse`. Only a custom SSE transport touches them.
  - The module owns its own request/response and time seams —
    `RelayHTTPTransport`, `RelayHTTPResponse`, `RelayClock`, `RelaySystemClock`,
    `RelaySleeping`, `relaySystemSleeper`, `RelayManualClock`,
    `RelayScriptedSleeper` — exact renames of the `Quuppa…` ones it used to
    borrow, so that neither module depends on the other in either direction. A
    custom transport now conforms to `RelayHTTPTransport`.
  - `ProximiioQuuppa` is unchanged apart from losing the relay half: same
    types, same behaviour, same tests. See the 2026-09-11 amendment under
    *Umbrella-only distribution* in `docs/DECISIONS.md` for why this module is
    re-exported where the two vendor clients are not.
- **`ProximiioOffline` is now an SPM library product.** It was a build target
  re-exported through the umbrella, which meant another *package* could not link
  it at all — SwiftPM can only depend on products. The map-rendering package
  being built on this SDK has to resolve an offline venue's tiles, style and
  GeoJSON from the offline store, so the product now exists. Nothing changes for
  existing integrators: the umbrella still `@_exported`s it, so `import
  Proximiio` sees exactly the same types as before, and the module's public
  surface is unchanged. Unlike `ProximiioQuuppa` and `ProximiioBlueiot` — which
  are products *and* excluded from the umbrella so a third-party RTLS vendor's
  vocabulary stays out of every app — this is a linking exception, like
  `ProximiioDevices`. See the 2026-09-10 amendment under *Umbrella-only
  distribution* in `docs/DECISIONS.md`.
- **`GeoMath` is public**, in part. The coordinate math that goes with the
  already-public `ProximiioCoordinate` was package-internal, so clients and our
  own apps could not reach it — which did not stop anyone, it just produced
  about eight hand-rolled re-derivations of haversine, bearing and
  metres-per-degree across the two first-party apps, each free to get the
  bearing convention or GeoJSON's `[longitude, latitude]` ring order wrong on
  its own. Now public, all documented with units, argument order and convention:
  - `GeoMath.meanEarthRadiusMeters` — `6 371 000 m`, the single radius behind
    every public function here, exposed so a caller can reproduce our numbers.
  - `GeoMath.metersPerDegreeLatitude` — `111 194.93 m`, constant everywhere.
  - `GeoMath.metersPerDegreeLongitude(atLatitude:)` — the same figure scaled by
    `cos(latitude)`, because longitude degrees shrink towards the poles.
  - `GeoMath.haversineDistance(from:to:)` — great-circle metres, ignoring floor.
  - `GeoMath.bearing(from:to:)` — compass degrees in `(-180, 180]`: `0` is true
    north, `+90` east, clockwise. Argument order reverses the heading.
  - `GeoMath.angularDifferenceDegrees(_:_:)` — wrap-safe difference in
    `[0, 180]`.
  - `GeoMath.isPointInPolygon(_:polygon:)` — ray casting against a GeoJSON ring
    of `[longitude, latitude]` pairs.

  The rest of the type stays `package` deliberately, because it is the *how*
  rather than the *what* and we may want to change it: the MapLibre Turf-parity
  snapping family (`distance`, `destination`, `nearestPointOnLine`,
  `lineIntersects`, `NearestPointResult`), `distanceToPolygonBoundary` (a
  local-planar approximation tuned to the geofence scale), and the `BoundingBox`
  / `isDefinitelyOutside` prefilter (whose conversion constant is deliberately
  wrong in the safe direction).

  `GeoMath` holds **two** Earth radii and they are still not unified:
  `6 371 000` for the haversine/geofencing family (Android `GeofenceManager.kt`
  parity) and `6 373 000` for the Turf snapping family (`PxRoutableSnapping`
  parity). Unifying them would move every snapped position by 0.031 % — 3.1 cm
  per 100 m, 31 cm per km — and break the cross-platform parity those ports
  exist for. Only the first is published, so the public contract holds exactly
  one radius and one distance function; the constants were renamed to
  `meanEarthRadiusMeters` and `turfEarthRadiusMeters` (was `earthRadius` and
  `earthRadiusMeters`, which were indistinguishable at a call site).
- **`ProximiioConfiguration.relayOnly(token:runsInBackground:)`** — preset for apps whose
  positions come from an attached relay provider (a Blueiot wristband, a Quuppa
  badge: the venue's anchors locate the tag and the phone only receives the
  answer). Switches off Eddystone/iBeacon scanning, UWB and the native location
  source, so `start()` builds no `BLEScanner` and shows no Bluetooth or location
  prompt. Everything else is `.default(token:)`, and the result is a plain value
  the host keeps adjusting. The trade is the beacon fallback that would take
  over the blue dot while such an app is backgrounded — correct to lose when the
  tracked thing is a band rather than the phone. Documented in the permissions
  guide's "Apps that never scan".
  The `runsInBackground` parameter (default `false`, so the shipped behaviour is
  unchanged) additionally sets `allowsBackgroundLocationUpdates` and nothing
  else. That one flag starts the native source purely as a keep-alive —
  `nativeLocationEnabled` stays `false`, so none of its fixes reach the engine —
  because iOS suspends a backgrounded app unless an active location session
  entitles it to keep executing, and a suspended app's relay socket is a dead
  socket. It needs `location` in `UIBackgroundModes`, a When-in-use
  authorization the host asks for itself, and the relay provider created with
  `runsInBackground: true` as well; Always is only for surviving termination.
- **`BlueiotCloudRelayConfiguration.runsInBackground`** (default `false`) — the
  cloud relay provider now reports the configured value instead of a hardcoded
  `false`, so an app that has arranged background execution can keep being
  positioned by the relay while backgrounded. Left `false` the facade still
  pauses the socket on `didEnterBackground` and resumes it on foreground, which
  is the right trade for a phone in a pocket. Setting it `true` alone changes
  nothing: it stops the SDK pausing the source, it does not grant the process
  time to run — pair it with `relayOnly(token:runsInBackground: true)`.
- **`BlueiotCloudRelayClient.Diagnostics.latestRelayReceivedAt`** and
  `latestProducerReceivedAt` — the two receipt stamps the relay carries on
  every fix, as `Date`s. Against `latestSampleAt` (the phone's arrival clock)
  the relay stamp gives an app its transport latency; the producer stamp rides
  along because one producer has been seen minutes ahead of its relay, and the
  gap between the two is the clock audit an integrator needs before believing
  either.
- **`BlueiotCloudRelayMessage.Relative.positioningIndicator`** and three new
  `BlueiotCloudRelayClient.Diagnostics` fields — `latestConfidence`,
  `latestPositioningIndicator`, `latestEngineFloor`. The relay carries two
  uncertainty signals from the engine on every fix; the decoder dropped one
  silently (it was missing from the CodingKeys) and never read the other, which
  is why every app on this path draws a constant accuracy ring. They are now
  decoded and exposed **raw** — the live relay shows `confidence 0` and
  `positioningIndicator 34` for a well-grounded tag, and neither has a published
  meaning in metres — so a venue walk can record their distribution before
  anyone maps them to an accuracy. The engine floor number rides along for the
  ground-floor-knob check.
- **`BlueiotCloudRelayPositionProvider` (module `ProximiioBlueiot`)** — a third
  way to be positioned by a Blueiot venue, next to the direct engine socket and
  the LAN `RelayPositionProvider`. A Proximi.io cloud relay
  (`blueiot-cloud-relay`, protocol `blueiot-coordinates-v1`) sits beside the
  LocalSense engine, grounds its local metres onto WGS-84 and republishes every
  tag as JSON over the internet; the provider opens `wss://host/stream` with the
  relay's `STREAM_TOKEN`, follows one tag, and hands its grounded fixes to the
  SDK as custom samples stamped with the phone's clock (the engine's was seen
  six minutes off). One WebSocket with backoff, a snapshot-poll fallback after
  three dead connections, de-duplication on `wgs.timestamp`, and diagnostics
  that say "relay refused the token" rather than a bare 401 and list every tag
  the relay currently holds. Shipped with `BlueiotCloudRelayConfiguration`,
  `BlueiotCloudRelayEndpoint` (a bare host becomes `https://`),
  `BlueiotCloudRelayClient`, `BlueiotCloudRelayMessage` and
  `BlueiotCloudRelaySampleMapping`; the wire format is pinned by fixtures
  captured from the live relay. Moved here from the Blueiot demo app so the
  management app can share it.
- **`Proximiio.setWayfindingJoinTolerance(meters:)`** and
  `WayfindingRouter.joinToleranceMeters`. On-device routing stitched path ends
  only within 0.75 m; venues traced with 1–3 m gaps at junctions fell apart into
  islands and every route came back `.disconnected` although the corridors
  visibly meet. The tolerance is now a runtime knob that rebuilds the graphs from
  the installed network at once.
- **`ProximiioLiveView` — an opt-in forwarder of positions to a customer-hosted
  LiveView map.** Link the product and a browser can watch a device move around
  the venue in real time; do not link it and the app makes no requests. There is
  no default base URL, no default token and no derived device identifier: these
  are live positions of a real person, and each of the three is a decision a host
  states out loud.

  It is latest-wins rather than accumulate — the map draws the current dot, so
  the uploader coalesces to at most one upload a second and always sends the
  newest fix. The bounded queue is for the other case, the network being away,
  and it drops the *oldest*: after a gap the newest fix is the one worth having.

  The response semantics are the part worth reading. A partially valid batch
  still returns `200` — the server keeps the good samples and reports the bad
  ones — so `accepted > 0` is success and `rejected > 0` is logged, never
  retried; re-sending would loop one permanently malformed sample forever. `400`
  is dropped, `401` stops uploading rather than hammering someone else's server,
  and `5xx` retries with jittered backoff, because a venue full of phones that
  lost the same server must not come back as a thundering herd.

  It reuses the package's `APIClient` rather than wrapping `URLSession` again,
  which means the deliberate refusal to send a bearer token to a cleartext
  non-loopback host applies here too: test against the Simulator, whose
  `localhost` is the Mac's, or terminate TLS in front of the server.

  `ProximiioCore`'s bounded, cadence-gated report queue is now generic
  (`PositionReportBuffer`) so both visitor reporting and this uploader share one
  implementation. `VisitorReportBuffer` remains as a typealias.

- **The SDK can now say the venue connection was lost.** A relay-fed app whose
  network drops had no supported way to tell its user: the position stream just
  goes quiet (it never finishes, nothing is buffered or replayed), the last fix
  ages out of `customPositionDuration`, and on a `.relayOnly` configuration
  nothing takes over. `ProximiioDiagnostics.noPositionReason` could not describe
  it either — it reads `nil` for ever once any fix has been produced. Three
  additions, at the two levels the answer actually lives at:
  - **`CustomPositionProviderConnection`** (`online` / `offline` / `unknown`) and
    `CustomPositionProviding.connection`, a protocol requirement with an
    `unknown` default. A source that has not been taught to answer is never
    reported as healthy *or* as lost.
  - **`Proximiio.positionProviderConnections()`** — the link report for every
    attached provider, the counterpart to `positionProviderStates()`: that one
    says what the SDK is doing with a source, this one says what the source can
    see. Also carried on `ProximiioDiagnostics.positionProviderConnections` and
    named in the pasteable `summary`.
  - **New enum case `NoPositionReason.positioningSourceOffline`** — every source
    the SDK is *consuming* reports itself offline **and** the last fix has aged
    past `customPositionDuration`. A dropped socket alone does not raise it (the
    dot is still right, and reconnects are constant); a fresh position from any
    source clears it, so a hybrid venue whose beacons keep solving never sees it
    while a venue-fed app does. A provider the facade paused for the background
    gets no vote — that silence is the SDK's own doing.

  `BlueiotCloudRelayClient.connection` implements it for the cloud relay:
  `online` from the first message of a connection until it ends, `offline` while
  stopped, in reconnect backoff, or with a failing snapshot poll.

### Fixed
- **The binary distribution can be consumed without explicit Clang modules.**
  The shipped `ProximiioBinary.swiftinterface` carried `import GRDB`, so any
  toolchain that rebuilds that textual interface had to load GRDB's binary
  `.swiftmodule`, which in turn requires GRDB's system-library Clang module
  `GRDBSQLite`. SwiftPM passes that module map as a `-Xcc -fmodule-map-file=`
  extra argument, and extra Clang arguments are not inherited by the
  interface-rebuild sub-invocation — only Swift import search paths are — so
  consumption failed with:

  ```
  ProximiioBinary.swiftmodule/arm64-apple-ios-simulator.swiftinterface:14:8:
    error: missing required module 'GRDBSQLite'
  ```

  A package manifest cannot fix this: a dependency package may not use
  `unsafeFlags`, and declaring GRDB's `GRDBSQLite` product explicitly changes
  nothing. Xcode only survived it because explicit module builds (its default
  since Xcode 16) precompile `GRDBSQLite` and hand it in; the same Xcode build
  with `SWIFT_ENABLE_EXPLICIT_MODULES=NO` failed identically to the SwiftPM CLI.

  The interface now does not mention GRDB at all. `SyncStore`'s GRDB-typed
  initializer — a test-injection hook — is the only public declaration that
  exposed a GRDB type, and it is the reason the import was printed at all;
  `import GRDB` became `package import GRDB` inside `ProximiioCore`, which keeps
  GRDB out of both the public and the private interface.

### Changed
- **`SyncStore.init(databaseQueue:)` is `package`, not `public`.** It exists to
  let tests inject an in-memory `DatabaseQueue`; no integration can use it
  without also depending on GRDB, and making it `public` forced `import GRDB`
  into the shipped binary interface (see above). The two supported initializers,
  `init()` and `init(path:)`, are unchanged.

- **Relay samples are stamped with when the fix was measured, not when it
  arrived.** `BlueiotCloudRelaySampleMapping` stamped every sample `timestamp:
  now`, so after a reconnect a relay that replayed or re-served an old snapshot
  produced a fix the staleness guard could not recognise as old — a silent jump
  to a stale position, with only exact duplicates suppressed.

  A measurement time *is* on the wire; what is not on it is any relation between
  the venue's clocks and the phone's (the live capture has the engine six
  minutes ahead of its own relay). The new `BlueiotCloudRelayFixClock` recovers
  the fix's **age** instead of trusting an absolute stamp:
  - **Skew-free** whenever the message carries `serverTime`: that and the tag's
    `relayReceivedAt` are both the *relay's* clock, so their difference is an
    age with no phone clock in it. Every `coordinate_snapshot` carries it, and so
    does the whole polling path — exactly where an old snapshot comes from.
  - **Estimated** otherwise, by the NTP min-filter: the smallest phone-to-venue
    offset seen in the last two minutes is the best estimate of the true one, and
    a fix's age is its excess over that. Ages come out `≥ 0`, so a sample can
    never be stamped in the future, and a constant skew of any size cancels.
    Offsets are tracked per venue clock (they are minutes apart) and the minimum
    is kept over a sliding window, so a clock step is forgotten rather than
    poisoning every later age.

  Two guards follow from it. A tag is published only when its venue stamp moved
  **forward** since the last published fix (equality was never enough: a
  reconnect can hand back something *older* than what the app is drawing), and
  only when it is younger than the new
  `BlueiotCloudRelayConfiguration.staleAfter` — 10 s by default, matching
  `customPositionDuration`; `0` restores the old publish-everything behaviour.
  `BlueiotCloudRelayClient.Diagnostics` gains `latestFixAge`,
  `latestFixAgeIsSkewFree`, `staleFixesRejected` and `repeatedFixesSuppressed`;
  `latestSampleAt` is now the fix's measurement time rather than its arrival
  time, and `latestFixAge` is the skew-corrected latency that
  `latestRelayReceivedAt`/`latestProducerReceivedAt` only approximated.

  **Wire-format limitation, deliberately not faked.** A `tag_coordinates` update
  carries no `serverTime`, so the live-stream path falls back to the estimate.
  The relay should send `serverTime` (relay-clock milliseconds at send) on
  **every** message, not only on `coordinate_snapshot`; with that one field the
  skew-free path covers the stream too and the min-filter becomes a fallback for
  nothing.
- **`allowsBackgroundLocationUpdates` no longer crashes a host that has not
  declared the background mode.** CoreLocation treats setting that property in
  an app whose Info.plist omits `location` from `UIBackgroundModes` as a
  programmer error and raises an assertion — SIGABRT, from inside the SDK, on a
  flag the *host* sets. `CLLocationManagerLocationUpdater` now checks the
  Info.plist first (`CoreLocationSource.backgroundModesDeclareLocation(in:)`)
  and, when the mode is missing, leaves the manager at `false` and logs one
  warning naming the missing key. Hosts that do declare the mode see no change.
- **Relay SSE stream never delivered an event.** `RelayURLSessionTransport` split the
  stream with `URLSession.AsyncBytes.lines`, which drops empty lines — and the empty
  line is what terminates a Server-Sent Event. Against a real relay the client
  connected, received every `event:`/`data:` pair and dispatched nothing, with no
  error. The transport now splits the bytes itself and hands every line over, blank
  ones included (`SSELineSplitter`).
- **Blueiot socket errors name the handshake outcome.** `URLSessionWebSocketTask`
  reports every early death as POSIX 57 "Socket is not connected"; the error now
  also carries the handshake's HTTP status (101 = upgraded) and the close code, so
  a refused upgrade and an engine that hung up on the login frame read differently.
- **On-device routing nodes crossing paths.** Two routing paths that cross — or one
  that overshoots a junction by a metre or two instead of ending on it — shared no
  vertex, so the corridors were either disconnected or linked only through the
  overshooting end, which a route walked out and back: a 1–2 m spur the
  instructions read as a sharp left/right pair. `RouteGraphBuilder` now inserts a
  vertex at every segment crossing. On a real venue (91 ground-floor destinations)
  this took the default 0.75 m tolerance from 0 to 89 routable destinations with
  no spurs.

- **The Blueiot geofence enter/exit flag was inverted, and there are four states,
  not two.** The vendor's `LocalSense Client Communication Protocol (websocket)
  V1.6.6` and the three official SDKs reached us and were audited line by line
  against both our codecs (`docs/research/blueiot-protocol-verification.md`).
  Page 24 item 12 gives `0 = go in area`, `1 = go out area`, `2 = disappear in
  the area`, `3 = disappear in the area and appear again` — and the document's
  own worked example transmits `00` for *"Enter the area"*. This SDK read `1` as
  *entered*, so **every entry surfaced as an exit and every exit as an entry**,
  and both disappearance states were folded into "exit", inventing a departure
  for every tag that merely stopped reporting for a moment.
  ``BlueiotGeofenceEvent/entered`` now means *"is the tag inside the area as of
  this event"* and is correct; ``BlueiotGeofenceEvent/statusKind`` carries all
  four states. If you wrote code that compensated for the old sense — an inverted
  `!event.entered` — remove it.
- **Frame `0x81`'s timestamp is not an epoch.** It is *milliseconds since the
  engine's local 00:00:00* (p10 item 8). Running it through a magnitude heuristic
  returns `nil` for every real sample, so `BlueiotConfiguration.sample(from:now:)`
  refused every record as unreadable. Rebuilt from a calendar date via the new
  ``BlueiotFrameCodec/date(fromMillisecondsSinceLocalMidnight:now:timeZone:)``,
  including the next-day rollover the specification explicitly demands, against
  the new ``BlueiotConfiguration/engineTimeZone``. The asymmetry is the
  specification's and is deliberate: frame `0xB3`'s 8-byte timestamp *is*
  epoch-ms and is unchanged.
- **Frame `0xB4` no longer surfaces a `Z` coordinate.** Page 10 item 4 declares
  the field *invalid* when the coordinates are latitude and longitude, which is
  why the three official SDKs disagree about the divisor (C#/JS ÷1e7, C++ ÷100) —
  the value is junk. The two bytes are still read, because the 27-byte stride
  needs them; ``BlueiotTagRecord/z`` is now `Double?` and is `nil` there.
- **Map transitions are no longer delivered as geofence events.** A `0xB3` whose
  `AreaId` equals its `MapId` is a floor/map change (p24), not a zone somebody
  drew. They now arrive on ``BlueiotEngineClient/mapTransitions()``.
- **The engine's repeat pushes are deduplicated.** Each real transition is pushed
  about once a second for five seconds with a frozen timestamp (p25), so one walk
  through a door was delivered five times. Filtered on the exact
  `(tag, area, status, timestamp)` tuple; the drops are counted in
  ``BlueiotEngineClient/duplicateEventCount()``.

### Added
- **``BlueiotTagRecord/positioningTechnology`` and
  ``BlueiotTagRecord/solvedDimensions``** — the trailing `Indicator` byte,
  decoded at last (p11 item 10). The high nibble says whether the engine solved
  that fix by **AoA** or fell back to plain beacon/RSSI; the low nibble says
  whether it is a real 2-D/3-D fix or a degenerate 0-D one. A per-sample quality
  gate the SDK had been carrying and discarding — and the cheapest confirmation
  that ``BlueiotTagEmulator``'s broadcast is being solved the way it should be.
- **``BlueiotError/engine(number:message:)``** — frame `0x99`, which carries an
  error number and the engine's own message and which no client other than the
  vendor's JavaScript SDK ever read. A rejected login used to reach this SDK as
  ``BlueiotError/socketClosed(_:)``, exactly what a phone leaving Wi-Fi produces.
  Counted in ``BlueiotEngineClient/errorFrameCount()``: non-zero means check the
  credentials, not the network.
- **``RelayGeofenceEvent/status``** (module `ProximiioQuuppa`) — the same four
  states, from a relay running 0.3.1 or later. Optional and additive: a phone
  reading only ``RelayGeofenceEvent/entered`` keeps working, and against a 0.3.1
  relay starts reading *correct* booleans without an SDK release.
- ``BlueiotFrameCodec/publishedSalt`` — the salt is a documented constant
  (`abcdefghijklmnopqrstuvwxyz20191107salt`), not a per-deployment secret,
  verified against the specification's own example digest. Not applied by
  default, because a venue that authenticates without one today would break.
- ``BlueiotFrameCodec/frameTypeName(_:)`` plus constants for the recommended
  new-generation `0xC1`/`0xC4`/`0xC5` position frames and the rest of the
  inventory, so ``BlueiotEngineClient/unknownFrameCount()`` is attributable — an
  unmodelled frame is now logged by name, not just by byte. Decoding them is
  deferred and documented in <doc:DirectBlueiotConnection>.
- ``BlueiotFakeEngine`` reproduces the behaviours these fixes are about — the
  documented `Status` values, map transitions, `0x99`, local-midnight timestamps
  and a real `Indicator` byte — so a Simulator demo stays truthful.

### Changed
- ``BlueiotTagRecord/timestamp`` is now
  ``BlueiotTagRecord/timestamp(now:timeZone:)``. A time of day cannot become an
  instant without a date, and a property that read the wall clock to get one
  would have broken this module's "nothing here reads `Date()`" rule.
- ``BlueiotFakeEngine/geofenceFrame(tagID:tagName:areaID:areaName:mapID:mapName:status:timestamp:options:)``
  takes the vendor's `status` byte instead of an `entered` boolean — a fake that
  spoke in our booleans could only ever agree with our decoder.
- Documentation across `ProximiioBlueiot`, `ProximiioQuuppa` and
  `docs/research/blueiot-aoa-research.md` now cites the vendor specification
  rather than the third-party reference. `vvvv/VL.BlueIOT`, which our codec was
  transcribed from, turns out to be a near-line-for-line derivative of the
  vendor's own C# SDK — which is why our codec was as accurate as it was, and
  why it inherited exactly that SDK's bugs and none of its own.

- Docs: `NSNearbyInteractionUsageDescription` and `NSCameraUsageDescription` are now listed as **always required** Info.plist keys in README/MIGRATION — App Store validation checks referenced APIs (NearbyInteraction, ARKit via UWB support), not runtime use (ITMS-90683 seen on a host app without them).

### Added
- **`ProximiioBlueiot` can make the phone itself a Blueiot tag.**
  `BlueiotTagEmulator` advertises the vendor's app-tag protocol through
  `CBPeripheralManager`, so an installed Blueiot AoA system tracks the phone and
  `BlueiotPositionProvider` (or `RelayPositionProvider`) fetches that same id's
  position back — the loop that turns a venue full of anchors into a blue dot on
  iOS. Both protocol versions are supported: the general one (2-byte ids, one
  128-bit service UUID per channel, plus the three dummy UUIDs that push TX Power
  out of the packet) and the new one (server >= V2.1 and anchor firmware >= V4026:
  4-byte ids, a 26-byte payload carried as thirteen pre-swapped 16-bit UUIDs,
  with settable sleep and moving/still status bits). Every byte is transcribed
  from the vendor package — `BlueIOT_iOS Development Instructions V1.1.docx`
  §2.3 and the `BlueIOT_IOS_Demo` ObjC project — cited inline, and pinned by
  hand-laid fixtures including the vendor demo's own example
  (`tagId 12345`, ch37 -> `CB240898-BAD8-3353-9ED0-AC3039050975`). The payload
  builder `BlueiotTagBroadcast` is pure and CoreBluetooth-free; the radio sits
  behind the `BlueiotPeripheralAdvertising` seam with a public
  `BlueiotFakeAdvertiser` double. **Foreground only, deliberately**: iOS moves a
  backgrounded app's service UUIDs into the advertisement overflow area where
  passive AoA anchors cannot see them, so the SDK does not ask host apps to
  declare `bluetooth-peripheral` and does not pretend background tracking works.
  See the module's `Making the phone a Blueiot tag` article.

- **New opt-in product `ProximiioBlueiot`: a direct Blueiot engine client.**
  For venues that cannot host `proximiio-rtls-relay` and whose phones must reach
  the AoA engine themselves. `BlueiotFrameCodec` decodes the vendor's binary
  frames (`0x81` batched positions in centimetres, `0xB4` native WGS84, `0xB3`
  geofence transitions; head `0xcc5f`, CRC-16/MODBUS, tail `0xaabb`) and encodes
  the auth + subscribe handshake; `BlueiotEngineClient` owns the
  `localSensePush-protocol` WebSocket, the reconnect backoff and `pause`/`resume`;
  `BlueiotPositionProvider` maps a record onto `CustomPositionSample` through a
  per-`MapId` `BlueiotAffineTransform` (or WGS84 passthrough) and a `FloorNo`
  floor map, and feeds the existing `CustomPositionProviding` seam under the name
  `"blueiot"`. Not re-exported by the umbrella — add the product and
  `import ProximiioBlueiot`. Every byte offset is ported from the relay's
  `relay-ingest-blueiot`, itself read off the MIT-licensed `vvvv/VL.BlueIOT` at
  `ffca3ce`, with the citations kept inline and the relay's own hand-laid byte
  fixtures reused as tests. **The relay remains the recommended path**; the
  module's `Direct Blueiot connection` article lists what is `[UNVERIFIED]`
  (CRC on push frames, WGS84 axis order, geofence `Status` polarity, salted
  password mechanics, default port, coordinate units, tag-id width, TLS) and
  which knob fixes each. Ships `BlueiotFakeEngine`, a public scriptable engine
  double whose position chunks are stamped **at emission** (the moral equivalent
  of `RelayFakeServer`'s `{{ts}}`), so a scripted walk never ages past the
  engine's custom-position window while a Simulator demo is open.
- **Geofence events from the relay.** `RelayClient.geofenceEvents()` and
  `RelayPositionProvider.geofenceEvents()` stream `RelayGeofenceEvent`s — zone
  enter/leave transitions with a monotonically increasing `seq` — SSE-first via
  `/v1/stream?events=geofence`, falling back to polling
  `/v1/events?since=<seq>&limit=<n>` with a resume cursor. `since` is exclusive,
  so the fallback (and a background round trip) is lossless; a relay ring-buffer
  eviction shows up as a counted gap (`geofenceGapCount()`) rather than a
  silently incomplete history. `RelayClient.events(since:limit:)` reads one page
  directly. The stream is independent of the blue dot, and the SDK never acts on
  a transition. Only Blueiot venues produce them today.
- **External position providers now follow the app lifecycle.**
  `CustomPositionProviding` gains `runsInBackground` (default `false`), `pause()`
  and `resume()` — all three as **protocol extension defaults** (`false`,
  `stop()`, `start()`), so every existing conformer keeps compiling and inherits
  the safe behaviour. The facade pauses every provider that has not claimed the
  background on `didEnterBackground` and resumes it on `willEnterForeground`;
  a provider attached while backgrounded starts paused. New
  `Proximiio.positionProviderStates()` returns
  `[String: CustomPositionProviderState]` (`.running` / `.paused` / `.stopped`)
  so a host can render activity rather than just registration.
  `attachedPositionProviderNames()` is unchanged.
  `QuuppaPositionProvider` / `RelayPositionProvider` implement `pause()`/`resume()`
  natively — the loop is suspended and the SSE connection closed, while the
  configuration, last sample and `lastError()` survive, and a resume re-arms with
  a **fresh** backoff (and re-tries SSE after a fallback to polling). Opt out with
  the new `QuuppaConfiguration.runsInBackground` /
  `RelayConfiguration.runsInBackground` (default `false`); keeping one on needs a
  legitimate background mode in the host app and iOS still throttles what runs
  there — a test-tool affordance, not a promise. See `docs/DECISIONS.md`.
- **`PositionUpdate.background`.** Every update the engine emits now carries
  whether the host app was in the background when it was produced, stamped in the
  one place updates are broadcast, so it is correct for BLE, native, custom, UWB
  and PDR-fused fixes alike. The facade feeds the engine the same lifecycle
  transitions that drive provider pause/resume (`PositioningEngine.setBackgrounded(_:)`);
  it is `false` until told otherwise, and on any platform with no app lifecycle to
  observe. Purely additive — the initialiser parameter is defaulted.

### Changed
- **The background handover from an external position source to beacons is now
  immediate.** A `.custom` fix suppresses BLE/native solves for
  `customPositionDuration` (10 s) — correct while the source is live, wrong the
  moment it is not. Backgrounding an app whose AoA/UWB provider auto-pauses
  therefore froze the blue dot for the rest of the window before the iBeacon /
  Eddystone fallback could take over. The window now ends with the source: when
  pausing for the background, detaching, or stopping leaves **no** attached
  provider running, the facade revokes it and the next positioning tick solves
  from beacons. Deliberately narrow — a provider that keeps running
  (`runsInBackground: true`) still owns the dot, and a window the *host* opened
  with `setCustomPosition(_:accuracy:floor:)` (or a simulated walk) keeps the full
  duration it was promised. Nothing to configure, no public API added, and the
  reverse direction is unchanged: the first sample a resumed provider emits
  suppresses BLE again exactly as before. Venues previously advised to shorten
  `customPositionDuration` to paper over the freeze should return it to the
  default.
- **`RelayConfiguration.streamURL(tags:)` / `streamRequest(tags:)` take a
  defaulted `events:` filter**, and the initialiser takes defaulted
  `eventsPollInterval` (2 s) and `eventsPageLimit` (100). Source-compatible —
  omitting `events:` omits the query parameter, which the relay reads as "both
  kinds" — but the mangled symbols moved, so the recorded baseline shows three
  replacements. Deliberate pre-GA baseline change; see MIGRATION.
- **`RelayFakeServer` grows a geofence half**: `setEventResponses(_:loops:)` for
  `GET /v1/events`, `setGeofenceStreamAttempts(_:loops:pacing:)` and
  `scriptGeofenceStream(…)` for the filtered SSE path, plus a new
  `StreamChunk.idle` that holds a connection open instead of ending the script.
  Requests are routed by path and by `?events=`, so both loops can be driven
  against one fake.
- **`Proximiio.attachPositionProvider(_:)` returns `Bool`** (was `Void`), and is
  `@discardableResult`. `true` = armed and consuming; `false` = registered but
  idle, which means either the SDK is not running or the app is backgrounded and
  the provider does not run there. Never a failure to attach, and never a reason
  to retry. Deliberate pre-GA baseline change; see MIGRATION.
- **`QuuppaQPEClient.configuration` and `RelayClient.configuration` are
  `nonisolated`**, as is `Proximiio.configuration`. All three are immutable
  `Sendable` values; without the annotation every cross-module read cost an
  `await` and an actor hop for a value that cannot change. Reading them from a
  synchronous context now just works.
- **`RelayFakeServer.stream()` paces its script.** `scriptStreamWalk(…)` now
  emits one event every 0.5 s by default (through the fake's injected sleeper, so
  a test pays nothing), instead of dumping the whole script into the stream —
  which made an SSE Simulator demo render one teleport and then stand still. Pass
  `pacing: .immediate` for the old behaviour, or `.hz(_:)` / `.interval(_:)` to
  choose a cadence; hand-written scripts (`setStreamAttempts`, the initialiser)
  still default to `.immediate`. `{{ts}}` is substituted per chunk under pacing so
  a long walk does not age past `staleAfter` halfway through. `QuuppaFakeQPE` is
  unchanged: its script is served one response per request, so the cadence is
  already the client's poll interval.

- **A public seam for external positioning sources.** `CustomPositionProviding`
  (in `ProximiioPositioning`) plus `Proximiio.attachPositionProvider(_:)`,
  `detachPositionProvider(named:)`, `detachAllPositionProviders()` and
  `attachedPositionProviderNames()` promote the one-shot `setCustomPosition`
  push into a first-class *continuous* input: a provider yields
  `CustomPositionSample`s (coordinate, accuracy, an optional Proximi `floorID`,
  a source timestamp) and the SDK owns everything else — one consumer task per
  provider, floor-id resolution against the synced floors, a stale guard at
  `positioning.customPositionDuration`, stop on `stop()` and re-arm on `start()`
  while the registration survives the cycle. Samples arrive as
  `PositionSource.custom`, so they arbitrate exactly as a manual push does and
  drive route snapping, geofencing and wayfinding unchanged. This is the
  recorded post-6.0 roadmap item; see `docs/DECISIONS.md`.
- **`ProximiioQuuppa` — positions from a Quuppa Positioning Engine.** A new
  **opt-in** library product (deliberately *not* re-exported by the umbrella —
  add the product and `import ProximiioQuuppa`) that polls a QPE's REST
  `getTagData` for one tag and feeds it through the provider seam:
  `QuuppaConfiguration`, `QuuppaQPEClient` (actor; poll loop, error taxonomy,
  2x backoff to a 30 s ceiling, reset on success), `QuuppaPositionProvider`,
  `QuuppaTagRecord`/`QuuppaTagDataResponse` (tolerant decode of the verified
  fields), `QuuppaAffineTransform` (six-parameter local-XY -> WGS84, solvable
  from three surveyed points) and a `QuuppaHTTPTransport` seam. The poll
  interval is clamped at 5 Hz, per Quuppa's own guidance. Coordinates come from
  the record's WGS84 fields when the project is georeferenced, otherwise from
  the affine transform; `locationCoordSysId` maps to a Proximi floor id.
  Everything the public QPE documentation does not pin down — auth, the response
  envelope, the `locationTs` unit, query-parameter names, the output format
  name, the WGS84 field names — is configuration with a documented default, not
  a constant. `QuuppaFakeQPE` (public, with the real published payload and a
  scripted-walk generator) is the double the module was built against and the
  one a host app's Simulator demo should use. See
  <doc:FeedingPositionsFromQuuppa> and `docs/archive/quuppa-qpe-research.md`.
- **`ProximiioQuuppa` — a vendor-neutral client for the Proximi RTLS relay.** The
  same module now also consumes `proximiio-rtls-relay`, the daemon that speaks
  Quuppa's REST and Blueiot's binary WebSocket on one side and one normalised
  HTTP API on the other, so a single provider serves every vendor the relay
  supports and a new vendor is a relay release rather than an SDK release:
  `RelayConfiguration`, `RelayPosition` (the relay's `Position` contract,
  forward-tolerant, RFC 3339 `ts` with or without fractional seconds, optional
  `battery_pct` from relay v0.2.0), `RelayClient` (actor; `latest()` for
  `GET /v1/tags/{id}/position` with `404` → `.tagUnknown` and `410 Gone` →
  `.stale(lastSeen:)`, `snapshot()` for `GET /v1/positions`, and an SSE consumer
  for `GET /v1/stream`), `RelayPositionProvider` (`CustomPositionProviding`,
  registered as `"rtls-relay"`, with `latestRaw()` for the zones/battery/label a
  positioning sample deliberately does not carry) and `RelayError`. SSE is the
  default and keep-alive comments are ignored; a dropped stream reconnects with
  a 2x backoff to a 30 s ceiling, and three consecutive stream failures fall the
  client back to polling for the session rather than leaving the phone dark — a
  buffering proxy is a deployment, not a crash. Streaming needed a shape the Qu1
  request/response seam cannot express, so it is a **separate optional**
  protocol, `QuuppaStreamingTransport`, plus `RelayURLSessionTransport` (which
  conforms to both, with SSE-appropriate timeouts); a transport that only does
  request/response simply polls. Client-side `staleAfter` (default 10 s) applies
  to every position however it arrived, which matters most on SSE where nothing
  re-asks. `RelayFakeServer` (public, both seams, scriptable events with
  keep-alives and a mid-stream drop) is the double it was built against. See
  <doc:FeedingPositionsFromTheRelay> and
  `docs/research/blueiot-integration-feasibility.md` §Bu2.
- **`ProximiioDevices` — the second firmware line, ALOHA-TWR.** Proximi ships two
  firmwares for the same boards and the SDK now tells them apart:
  `PRXDeviceName.Line` (`.fira` / `.alohaTWR`), the `PRX-TWR-T<n>` /
  `PRX-TWR-A<n>` grammar (**decimal** id, canonicalised unpadded; `twrID`,
  `shortAddress` is `nil` there), `PRXServiceInventory.line(for:)` /
  `PRXDeviceIdentity.line` / `PRXDeviceSession.line` resolved from the service
  inventory first and the name second, and `PRXAdvertisement.line` as the scan's
  hypothesis. The `0x0201` stream, `0x0202`, `0x0204` and the whole DFU chain are
  byte-identical, so nothing there changed; what the line lacks is now gated
  rather than attempted — new `PRXDeviceFeature.provisioning` (the `0x0001`
  service) plus `stsKeyProvisioning` / `tokenForm` answering `false`, a DFU that
  no longer requires `0x0106` or `0x0203` to exist (an unverifiable version
  reports `.done(installed: nil)` instead of `.verifyFailed`), and
  `PRXTagTestRanging.init(twrTag:anchorIDs:…)`, whose `.allocateAndRange` fails
  as `.unsupported` because there is no session to allocate. **The `anchor_id` in
  a `0x0201` notification is a different namespace on each line** — a FiRa short
  address against a small provisioned `twr aid` — so read
  `PRXDeviceIdentity.anchorIDNamespace` (`PRXDeviceName.AnchorIDNamespace`)
  before keying a venue's anchor map. `QANIProtocol` rejects ALOHA-TWR names
  outright: that line has no Nearby Interaction, so the phone never ranges it.
  `PRXSimulatedDevice.alohaTWRTag(id:anchorIDs:…)` and
  `PRXSimulatedTagRanging.emitBlocks(_:anchorIDs:…)` are the fixtures.
- **`ProximiioDevices` — one central, one scan, and a clock a host can drive.**
  `PRXDeviceScanner.central` is public (`nonisolated`), so the transport behind
  the fleet list is the one an update and a session run on rather than a second
  `CBCentralManager` that CoreBluetooth treats as unrelated;
  `PRXDFUEngine.init(scanner:…)` reads it. The engine now suspends that scan
  itself — `PRXDeviceScanner.pause()` / `resume()` (list preserved, sweep
  suspended, `PRXScannerEvent.paused` / `.resumed`) around every run, given a
  `hostScanner`, and gives it back on `.done`, on a failure and on `cancel()`;
  a scanner the host paused itself stays paused. `PRXManualClock`,
  `PRXTickingClock` and `PRXScriptedSleeper` are public under `Simulation/`, so
  a host app writes the same wall-clock-free tests the SDK does.
- **`ProximiioDevices` — four edges the unit-detail screen asked for.**
  `PRXDeviceSession.supports(_:)` answers the role / firmware-version /
  capability gates the commands already applied — `PRXDeviceFeature` names the
  nine of them — so a screen can disable a control instead of learning about the
  refusal by sending the command; `clearStickyEvent()` and `identify()` now gate
  on it. `PRXSimulatedDevice.degradedAnchor()` is the unhappy-path board (amber
  health findings, red with `lastSaveFailed:`, a `0x0104` tail whose two rounds
  are inside the §7.11 clearance plus one that has never ranged, one free slot,
  firmware behind both version gates), and `PRXFakeConnectBehaviour.failWith(error:)`
  scripts a connect failure a caller has to branch on rather than print.
- **`ProximiioDevices` — test-ranging a tag at installation.** `PRXTagTestRanging`
  brings one tag's UWB session up on one anchor while an installer is connected
  and streams what happens: `protocol.md §7.11` phase discipline
  (`PRXPhasePlacement` / `PRXPhaseSampler` — five `0x0104` reads 1.5 s apart,
  per-session clustering, the start of the widest free arc with 55 ms
  clearance, sent as `aim_ms`), the 24-byte `0x0102` carrying the tag's own
  short address and STS key, the six-byte `0x0103` start, and verification
  against the tag's `0x0201` stream over a 30 s window with the 60 s
  acquisition grace and exactly one re-placement when the rate sits in the
  35–65 % collide band. `stop()` sends the `0x0103` stop **before** the
  caller's disconnect — a product anchor holds the slot across the link, so a
  plain disconnect orphans a ranging session for ~70 s. `.observeOnly` writes
  nothing at all, because adopting a running `session_id` stops it. New session
  writes on `PRXDeviceSession` (`writeSessionParameters`, `sessionControl`) read
  the in-band verdict back from `0x0104`, and the simulation gained a live OOB
  arbiter and tag ranging engine (`PRXSimulatedAnchorSessions`,
  `PRXSimulatedTagRanging`, `PRXFakePeripheral.setReadHandler`).
- **Four edges the management app asked for after wiring its Devices screen.**
  `ProximiioDiagnostics.ConfigurationSummary.uwbHealthPollSeconds` carries the
  per-anchor health-read cadence and `summary` prints it next to the other UWB
  knobs (`healthPoll: 30s`, or `off` — zero means the reads never happen, not
  that they happen instantly); `PRXDeviceScanner.peripheral(for:)` and
  `peripheral(identifier:)` hand back the **scanning** central's own link, which
  is the one to open a `PRXDeviceSession` on; `PRXDeviceScanner.snapshots()` and
  `events()` are `nonisolated`, so a view model subscribes from its initialiser
  with no `await` and no actor hop — registration is synchronous, so nothing is
  emitted into the gap, and a late subscriber opens on the list the scanner
  currently holds; and `PRXDeviceName.isProvisionedAnchor` / `isProvisionedTag`
  / `isProvisioned(as:)` do the by-role narrowing every caller of
  `isProvisioned` was doing by hand.
- **`ProximiioDevices` — firmware updates over BLE (SMP/mcumgr).** `PRXDFUEngine`
  walks a PRX anchor or tag through the whole update as an explicit state
  machine with an `AsyncStream<PRXDFUProgress>`: preflight on *this* connection
  (capability bit, installed version, tag battery), the idle gate — an anchor
  with live sessions is waited out, never overridden, because no stop-all
  exists by design — enter-DFU, finding the unit again by the **SMP service
  UUID at the same peripheral identifier** (never by name; the OS cache serves
  the product name of a unit already in recovery), a fresh GATT browse, frame
  sizing from `os mcumgr_params`, the upload, `os reset`, and confirmation that
  the product services came back with the expected `0x0106`. A dropped link
  costs only the packets in flight: the engine reconnects and continues from
  the offset the **device** holds, never from zero, and
  `resume(recoveryPeripheral:image:installed:)` is the same thing as an entry
  point for a unit already parked in recovery. Failures are named for what an
  operator can do about them (`PRXDFUFailure`), and a refusal at offset zero —
  in either SMP refusal form — is reported as "this build is older than the
  firmware on the device" with nothing erased. `SMPClient` is the mcumgr client
  underneath: notifications enabled before the first request, frames split to
  the link's write ceiling under `canSendWriteWithoutResponse` flow control,
  responses reassembled by the header's `len`, `seq` matching, and a per-request
  watchdog decided by the injected clock. `PRXFakeRecoveryPeripheral` answers
  real SMP for tests and Simulator demos, with scripted refusals, mid-transfer
  drops, a silent device and an `os reset` whose answer is lost. Nothing here
  can brick a unit — MCUboot validates at every boot and falls back to the
  resident recovery image — which the new "Updating firmware over BLE" DocC
  article spells out along with the bench numbers and the iOS caveats.
  `PRXFirmwareCatalogEntry` describes a release without its bytes (role,
  version, size, digest, optional URL) so "which release is this, and did we
  get the file we asked for" has one spelling until a catalogue endpoint
  exists; the SDK still never fetches, and takes `Data`.
- **`ProximiioDevices` — transport, scanner, device session, fake peripheral.**
  The layer that puts the codecs on air: a CoreBluetooth seam
  (`PRXPeripheralLinking`/`PRXCentralLinking` with `PRXCentralLink` and
  `PRXPeripheralLink` behind it, on this module's own foreground central),
  `PRXDeviceScanner` (one scan covering anchors, tags and units parked in
  recovery, deduped by peripheral identifier and aged out on an injected clock
  with a 3 s floor for the product build's advertising mux), and
  `PRXDeviceSession` (connect → fresh discovery → classification → identity;
  typed reads and notification streams; `provision(_:current:)` with the
  field-by-field Write Requests, `0x7F` commit, read-back verification and the
  one post-pairing retry; `enterDFU(tagToken:guardIdle:)` for both roles with
  the busy, token and warm-reset branches). `PRXFakePeripheral`,
  `PRXFakeCentral` and `PRXSimulatedDevice` ship **public** so hosts can run the
  same flows in a Simulator demo, and are what the 109 new tests exercise —
  no radio, no wall-clock sleeps.
- **UWB anchors report which firmware they run.** Once an anchor starts ranging,
  the SDK reads Proximi's `0x0106` firmware-version characteristic on the BLE
  link ranging already owns, so `UWBAnchorSnapshot` now carries
  `firmwareVersion: PRXFirmwareVersion?` and `build: UWBAnchorBuild?`
  (`.product` / `.debug` / `.legacyQANI` / `.unknown`). `ProximiioDiagnostics`
  counts the three in `uwbProductAnchorCount` / `uwbDebugAnchorCount` /
  `uwbLegacyAnchorCount` and prints them in `summary` — which is how a venue
  notices half its fleet is on debug images before a firmware rollout silently
  skips them. Stock Qorvo `DWM3001CDK` boards have no such characteristic; they
  answer once, are classified `.legacyQANI`, and are never asked again. Nothing
  here can fail a ranging session: a missing service, a refused read or an
  undecodable payload is a line in the anchor event log and a `nil` column.
- **Optional per-anchor health polling.** `TrilaterationConfiguration.uwbHealthPollSeconds`
  (default `0`, off) reads the anchor's 40-byte `0x0105` health payload on the
  ranging link at the given cadence and publishes it on
  `UWBAnchorSnapshot.health`: uptime, boot count and cause, freeze count,
  round-success rate, sticky fault, and `session_owner`. Pick **30 s or slower**
  — the firmware defers these reads to the thread that services the accessory
  handshake, and the counters behind them move on the order of seconds at best.
  Reads are only ever issued after `0x02 uwbDidStart`, never between `0x0A` and
  `0x01`, so the handshake is never in contention with one.
- **Public pause/resume of UWB ranging:** `Proximiio.uwbSuspend(anchor:)`,
  `uwbResume(anchor:)`, `uwbSuspendAll()`, `uwbResumeAll()`. A Proximi anchor
  accepts two BLE connections and a tag or a board in recovery accepts one, so
  an app that wants to provision, inspect or update a board is competing with
  the SDK's own ranging link for a slot on the very board it is servicing — and
  the phone's Nearby Interaction session is exclusive on an anchor, so while it
  runs every other UWB session on that board is evicted. Suspending sends
  `0x0C stop`, tears the session down and drops the link while **keeping the
  anchor's session slot**, and ignores its advertisements until you resume —
  which matters specifically because a Proximi anchor keeps advertising with a
  link open and would otherwise be reconnected within the second.
  `uwbSuspendAll()` also holds anchors discovered while it is in force.
  Suspension is visible on `UWBAnchorSnapshot.isSuspendedByHost` and
  `UWBAnchorStateChange.isSuspendedByHost`, and is cleared by `stop()`.
- **Proximi UWB anchors appear in Discovery as iBeacons.** Their factory-default
  proximity UUID `50524F58-494D-492D-5557-422D414E4348` joins the four bundled
  vendor defaults in `CommonBeaconUUIDs` — five of CoreLocation's twenty ranged
  UUIDs, with caller-supplied UUIDs still seeded first. Without it a powered
  anchor is invisible to a discovery session, because iOS strips Apple
  manufacturer data from a raw scan and an iBeacon can only be seen by a session
  that already ranges its UUID.
- **`ProximiioDevices` — the byte-level codec layer for Proximi's UWB anchor and
  tag firmware.** A new library target and product (re-exported through the
  umbrella, so `import Proximiio` still suffices) carrying the GATT UUID map,
  the provisioning TLV writer and 56-byte config record, the anchor OOB
  capabilities/parameters/control/state/health payloads, the tag
  measurement/control/status/features payloads, ATT-error mapping, and the
  SMP/mcumgr + MCUboot layer a firmware update runs on — including a minimal
  CBOR codec that decodes the indefinite-length maps the device actually sends.
  Pure value types with no CoreBluetooth import, so every layout is pinned by
  golden vectors on the macOS host.
- No behaviour change for existing integrators: nothing in the positioning path
  moved except `QANIProtocol`'s anchor-name canonicaliser, which now forwards to
  `PRXDeviceName` and answers byte-for-byte what it answered before.

### Fixed
- **`PRXConfigDraft` no longer normalises a `role` / `ranging_policy` byte it
  cannot name.** Both fields are now stored as the raw byte (`roleRaw`,
  `rangingPolicyRaw`) and `diff(against:)` compares raw against raw, so a unit
  running firmware newer than this SDK — one serving a value no `PRXDeviceRole` /
  `PRXRangingPolicy` case names — round-trips it untouched instead of being
  silently rewritten to `0xFF` / `0` by a save into an untouched form. Every
  field a diff reports costs a flash commit on the device, so a spurious one is
  not free. `role` and `rangingPolicy` stay source-compatible as non-optional
  enum views (an unknown byte still *displays* as `.unset` / `.manual`) and only
  move the storage when they are assigned; `PRXProvisioning.role(raw:)` /
  `rangingPolicy(raw:)` write an arbitrary byte. **Requires the paired Android
  SDK change** — until both ship, the two management clients disagree about what
  an untouched save writes.
- **The `ProximiioDevices` simulation now answers a commit the way the firmware
  does.** A simulated tag's `0x0204` is computed per read, so bit 2 follows a
  `0x0C` STS-key write and its clear instead of reporting the value the factory
  call was built with; and a commit that moves `device_id` or `ble_name_suffix`
  renames the fake unit to `PRX-A-<id>[-suffix]` and puts it back on air through
  `PRXFakeCentral`, so a running `PRXDeviceScanner` sees the new name against
  the same identifier — the live re-apply of protocol 1.3.0, no reboot.
- **An unresponsive UWB board is no longer retried every fifteen seconds.** A
  board whose Bluetooth stack answers while its UWB layer does not is parked
  until it is power-cycled, and any advertisement used to un-park it — sound on
  a Qorvo `DWM3001CDK`, which stops advertising while it holds a link, so an
  advertisement really was proof of the reboot. A Proximi anchor allows two
  links and keeps advertising with one open, so its advertisement proves only
  that the radio is alive: a deaf board was un-parked, reconnected, given two
  handshake timeouts and parked again, in a loop, against firmware that is
  documented to wedge under exactly that churn. The retry is kept — a board that
  really was power-cycled still rejoins on its own — but spaced by a doubling
  backoff measured from the verdict (30 s, 60 s, 120 s … capped at 10 minutes)
  that a successful ranging start resets.
- **Proximi's own UWB anchors are visible to the ranging layer.** The QANI
  accessory-name parser recognised only the stock Qorvo pattern
  (`DWM3001CDK (XXXXXXXX)`), so a production anchor running Proximi's firmware —
  which advertises the same QNIS service under `PRX-A-<6 hex>[-label]` — was
  parsed as "not an anchor" and dropped at the scan, on every board. Both
  patterns are now canonicalised: `PRX-A-00002a`, `PRX-A-00002A`,
  `prx-a-00002a` and `PRX-A-00002a-LOBBY` all resolve to `PRX-A-00002a` (the
  optional ≤ 8-character label is a human name an operator changes, so it is
  dropped — identity is the board's 24-bit `device_id`), the unprovisioned
  Zephyr default `PRX-A-0001` is accepted so a bench board can be ranged, and
  `PRX-T-…` (tag) and `PRX-DFU-…` (recovery) stay rejected. Legacy
  `DWM3001CDK-…` names are byte-for-byte unchanged, so no deployed venue is
  renumbered. `ProximiioInput.metadata`'s `uwb.accessoryName` accepts every one
  of those spellings. No public API change.
- **UWB links now report the ATT MTU they negotiated.** The PRX anchor firmware
  needs an ATT MTU ≥ 65 before it will carry QANI traffic, and iOS offers no way
  to demand one — so a short MTU used to present as a board that connects, is
  handed `0x0A`, and then never answers. The negotiated write ceilings are
  logged when a link becomes ready, and a write-without-response ceiling below
  62 bytes is logged as a warning (diagnostic only; ranging is not blocked).
- **Resources created after first launch now arrive even when the audit change
  log is empty.** Sync reconciles against the `/core/package` snapshot on any
  pass where the audit delta brought nothing, instead of trusting the one-shot
  bootstrap marker. An organization whose audit stream never receives its
  `/core/inputs` writes (a backend defect, fixed separately) left the store
  frozen at the moment of first launch: every tick truthfully logged
  `0 changes applied`, and a newly registered UWB anchor stayed invisible to
  positioning — reported as `anchorNotRegistered` — with no recovery short of
  `resetAndRefresh()`. The reconcile is additive (upserts only, never deletes),
  and skips the import entirely when the package is unchanged, so a steady venue
  costs one conditional GET per sync interval and no store writes.

### Changed
- **Sync logs what it could *not* apply.** Each pass emits a single line —
  `SYNC N changes applied`, extended to `…, M dropped (unknown-entity:X x1, …)`
  when records carried entity names this SDK cannot project into an engine, and
  annotated with `[snapshot reconcile: N upserts]` when the reconcile ran.
  Previously such records were counted as applied and silently filed in a bucket
  no reader queries. `ProximiioResourceType(auditEntity:)` is new public API: it
  resolves the spelling variants the backend emits (tenant aliases such as
  `Inputs` for `Input`, plural/lowercase forms, separators) so the engine
  projection step no longer skips a whole entity kind without a word.
- **Visitor reporting is now opt-in** (external audit H4): `visitorReportingEnabled`
  defaults to `false` — a deliberate deviation from Android, which reports by
  default. Indoor movement traces under a stable identifier are personal data;
  the host app now opts in explicitly, and a runtime consent hook
  `Proximiio.setVisitorReportingConsent(_:)` gates the reporting pipeline and
  discards buffered samples on withdrawal (before the stop-flush, so withdrawn
  data never uploads). Privacy zones and coordinate redaction are unchanged.
- **Adaptive RSSI learning hardened against self-poisoning** (audit H2): the
  learned per-beacon TX power now requires real calibration samples (or a much
  higher pseudo-sample bar, default 20) before it can override a beacon's
  advertised power, and is clamped to ±10 dB of the advertised value at use
  plus an absolute [-90, -30] dBm band at update. Imported model snapshots
  decay by age (7-day half-life) so stale learning must re-earn confidence;
  old persisted snapshots still decode.
- **Barometric floor detection no longer drifts with the weather** (audit H3):
  the pressure reference tracks ambient with a 5-minute time constant, so only
  fast changes (elevator/stairs) can trip the threshold, and floor commits
  require a confidence gate (relaxed under beacon/PDR corroboration via
  `noteVerticalActivity`). The new `positioning.floorDetection` section adds
  per-venue `pressurePerFloorPa`, so 4.5–6 m storeys stop over-counting floors
  traversed.

### Added
- **Immediate beacon anchor** (field feedback, occluded-beacon venues): opt-in
  `positioning.trilateration.immediateBeaconAnchorEnabled` pulls the fused
  position onto a beacon's configured coordinate whenever that beacon is ranged
  inside `immediateBeaconAnchorEngageDistance` (default 2 m) for
  `immediateBeaconAnchorDebounceTicks` consecutive BLE evaluations, and holds it
  there until the beacon recedes past `immediateBeaconAnchorReleaseDistance`
  (default 3.5 m; engage/release hysteresis). The pull is a tight EKF
  measurement (`immediateBeaconAnchorAccuracy`, default 1.2 m) rather than a
  teleport, converges within a tick or two, corrects accumulated PDR drift, and
  works even when the anchor beacon is the only one audible. A strictly closer
  qualifying beacon takes the anchor over without a release gap. Designed for
  venues whose beacons are mounted so occluded that hearing one at all implies
  standing next to it. In the engage→release hysteresis band the pull weakens
  quadratically with range, so a user walking away from the anchor is held, not
  dragged back (field feedback); stepping back inside the engage radius snaps
  tight again. The diagnostics `ConfigurationSummary` now reports
  `immediateBeaconAnchorEnabled`, the engage/release distances and the debounce
  tick count (its `init` gained defaulted parameters — source-compatible) so
  field exports show exactly which anchor tuning a walk ran with.
- **`Proximiio.resetVisitorId()`** rotates the Keychain-persisted anonymous
  visitor id and rebinds the reporter so the fresh id re-registers. Server-side
  deletion of already-uploaded traces remains a separate backend request.
- **`SyncEvent.storeRecreated(reason:)`** on `Proximiio.syncEvents()` — reports
  that the local sync cache was rebuilt after corruption (diagnostic only).
- **Adaptive-RSSI divergence telemetry**: diagnostics now report how many
  beacons' learned TX power drifted beyond a threshold from their seeded value,
  making venue-wide drift operator-visible.
- **`ProximiioOffline` privacy manifest** declaring its DiskSpace
  required-reason API use (reason E174.1) — the last target with a
  required-reason API that lacked one.

### Changed
- **The RANSAC-seeded hybrid solve is now gated on range dispersion**
  (`ransacHybridMinRangeDispersion`, coefficient of variation of the solve
  window's model ranges, default 0.40; `0` disables — no Android equivalent).
  On a flat range field (weak TX, path-loss n ≈ 0 venues) RANSAC's inlier vote
  selects on noise rather than geometry, so those solves fall back to the plain
  IRLS solve. Replay-validated on four field logs: 0.7–1.5 m RMSE improvement
  on flat-RSSI venues, and venues where the hybrid helps get slightly better
  (their occasional degenerate windows are suppressed too). Deliberately no
  hysteresis: both branches share the IRLS refine, and a measured hysteresis
  sweep only carried stale decisions into changed geometry.

### Fixed
- **Beacon discovery no longer reports a fake advertising interval for
  iBeacons.** Their sightings come from CoreLocation ranging, which delivers
  one batch per second regardless of the beacon's real setting, so the
  gap-median "interval" always read ~1000 ms (a field team tuned beacons to
  250 ms and saw a constant 1000). iBeacon rows now report no interval;
  service-data/Eddystone advertisers, which are measured from raw scan
  packets, are unaffected.
- **A corrupt `sync.sqlite` no longer bricks `Proximiio.init`** (audit H6):
  a corruption-classified open failure deletes the re-syncable cache and its
  `-wal`/`-shm` sidecars and recreates it; corruption detected mid-sync
  rebuilds the store in place and forces a cold resync, mirroring the existing
  410 path. Permission and disk-full failures still surface unchanged —
  previously the documented recovery (`resetAndRefresh()`) was unreachable
  exactly when init threw.
- **`ProximiioConfiguration.positioning`** — the positioning-engine tuning
  section is now reachable from the public initialiser. Roughly 68 documented
  knobs (the trilateration pipeline, EKF, emission gate, arbitration windows)
  were previously unreachable: the facade always built engine defaults, and only
  a test-only initialiser could inject a configured engine. We documented knobs
  a customer had no way to set. `bleEvaluationInterval`,
  `allowsSingleBeaconPositioning` and `pdrFusionEnabled` are now computed views
  onto the same storage, so the two spellings can never disagree, and their
  initialiser parameters became optional so a defaulted argument cannot silently
  reset a host-tuned section.
- **Unified error surface (`ProximiioFailure`).** The SDK threw seven unrelated
  error enums, only one of which was a `LocalizedError`, plus GRDB's
  `DatabaseError` as a bare dependency type. They now share a protocol carrying
  a stable domain/code, a `ProximiioFailureCategory`, retryability and recovery
  copy, and `ProximiioErrorReport(from:)` flattens any caught error — including
  GRDB's — into something a host can present or send to telemetry without
  importing our dependencies. Bridge cases (`ProximiioAPIError.transport`,
  `SnapshotBootstrapError.payloadEncodingFailed`,
  `OfflinePackageError.storageFailure`, `ProximiioError.storage`/`.underlying`)
  preserve system errors that were previously flattened away — one of them,
  a non-`URLError` in the API retry loop, used to escape untyped and skip
  host failover entirely.
- **Honest reported accuracy during dead reckoning** — four new
  `TrilaterationConfiguration` knobs: `ekfPdrDriftFraction` (`0.06`),
  `ekfUnanchoredDriftRate` (`0.02` m/s), `ekfMeasurementDecorrelationInterval`
  (`10` s) and `ekfSingleBeaconMeasurementIsNovel` (`false`). Field evidence
  (Dubai Hills Mall, 2026-07-28): across 2.8 minutes in which the SDK emitted
  129 `pdrFusion` positions and exactly **one** BLE fix, the reported accuracy
  *improved* from 10.8 m to 7.5 m. The log also holds 1437 beacon updates over
  that window, so ~69 BLE ticks did call `LocationEKF.updateMeasurement` behind
  the emission gate; consecutive solves shared 70–100 % of their beacon set, yet
  each was folded in as an independent white-noise measurement. The filter now
  (a) floors the position covariance at a drift budget that grows with the
  distance and time dead-reckoned since the last accepted absolute fix, and
  (b) lets an autocorrelated repeat correct the mean at full gain while refusing
  to shrink the covariance below what the last genuinely novel measurement
  justified. No Android equivalent — Android reports the raw covariance and has
  the same optimism. Set the fraction/interval to `0` for the previous
  behaviour. Additive only; no existing declaration changed.
- **Bounded EKF heading variance** — new `TrilaterationConfiguration`
  knob `ekfHeadingVarianceCeiling` (`(π/2)²` rad²). Making the covariance
  honest (above) exposed the opposite error in the same field stretch: with no
  beacons at all, 235 m of PDR took the reported accuracy from 10.0 m to
  42.5 m — ~18 % of distance travelled, three times the 5–8 % that real PDR
  drifts and that `ekfPdrDriftFraction` is calibrated on. `LocationEKF`
  *assigns* the heading from the PDR input on every predict, so heading is an
  exogenous input rather than an estimated state, but the filter kept adding
  heading process noise to `P[heading][heading]` anyway. That variance
  random-walked without bound and the motion Jacobian (`∂position/∂heading =
  ±L`) fed it back into position every step, so position variance grew as `N²`
  instead of `N` — double-counting the `(L·σ_θ)²` the per-step process noise
  already carries. The heading variance is now assigned from the step's own
  heading uncertainty (clamped by the new ceiling) and its stale
  cross-covariances are cleared. The 235 m stretch now reports 10.0 m →
  17.6 m, i.e. 6 % of distance. Additive only; no existing declaration changed.
- **`PositioningEngine.Configuration.ransacSeed`** — optional fixed seed for the
  RANSAC inlier search. Defaults to `nil`, which keeps seeding from the wall
  clock (Android parity); production hosts should leave it alone. The replay
  harness pins it so golden thresholds are stable.

### Changed
- **The positioning tick stopped allocating on the hot path.** It ran every
  2.5 s for the lifetime of the app, background included, and rebuilt a `Set` of
  registered beacon keys on each pass even though that set only changes in
  `setInputs(_:)`; the resolved-beacon array grew without a reserved capacity;
  and the RSSI median allocated three arrays *per beacon per tick* (`filter` +
  `map` + `sorted`) — roughly 90 allocations a tick in a 30-beacon venue. The
  key set is cached, the array is sized once, and the median is computed in a
  stack buffer. Behaviour is unchanged: the median still selects the upper
  middle element, which the replay harness' golden thresholds are calibrated
  against, and the bundled replay stays bit-identical.
- **The public API surface was audited and narrowed before GA (breaking for
  anyone using internal plumbing).** `VERSIONING.md` promises stability across
  the whole public surface, and 2125 non-SPI public declarations across 181
  types was far more than the ~155 the SDK means to support. 47 types that are
  internal plumbing — the networking/auth stack (`APIClient`, `AuthManager`,
  `TokenProviding`…), audit-sync and integrity checking, visitor analytics
  (`VisitorEvent`, `VisitorReportingClient`…), background-lifecycle platform
  glue, offline package sourcing, plus `FloorManager`, `GeofenceEngine` and
  `ProximiioDateParser` — are now `package`. Surface is 1874 declarations
  across 134 types.
  Most importantly, five entry points that let a host corrupt engine
  invariants are no longer reachable: `PositioningEngine.evaluateTick()`,
  `.reset()`, `.applyStillness()`, `.processExternalDisplacement(_:)` and
  `PositioningEngine.init` — a host-constructed engine is precisely the
  configuration in which the fusion invariants cannot hold.
  `ProximiioConfiguration.defaultAPIBaseURL` and `.defaultAnalyticsPathPrefix`
  were added (same values as before) so the facade initialiser stays public.
- **CI gates the public API against a recorded baseline**
  (`scripts/api-baseline.sh`, `api-baseline/*.txt`). Additions and removals both
  fail the check, because "we widened the contract without noticing" is half of
  what the gate is for. The baseline is a distilled, sorted list of public
  declarations rather than the raw multi-megabyte digester dump, so a contract
  change is a legible line in a diff — and `package`/internal declarations are
  excluded, so internal refactors do not trip it.
- **The binary artifact is reproducible and its dSYMs survive.** The xcframework
  zip is built with normalised timestamps and `-X`, so rebuilding the same tag
  produces the same bytes — previously a rebuild yielded a different checksum
  than the one SwiftPM pins. `manifest.json` honours `SOURCE_DATE_EPOCH`.
  `publish-binary-release.sh` now archives the dSYMs and attaches them to the
  **private source** repo's release: the shipped dylib is stripped, so they are
  the only way to symbolicate a production crash, and they previously lived only
  in a local build directory. The script refuses to upload them to the
  distribution repo, which becomes public at GA.
- **Local checks match CI.** `make check` runs lint, tests, the API baseline and
  the docs build with the same arguments CI uses; `make hooks` installs a
  pre-commit hook limited to the fast checks (a hook slow enough to annoy is a
  hook people bypass). CI also builds the docs site, whose link checker had
  never run anywhere automated.
- **Release tooling hardened for the RC cut.** `release.sh` now *fails* an
  RC/GA cut when the CI or Release GitHub workflow is disabled (override with
  `--allow-disabled-ci`) and identifies workflows by file path instead of
  opaque numeric ids. CI runs on `macos-15`, selects the newest installed
  Xcode ≥ 16 instead of a hardcoded `Xcode_16.2` path, and asserts the pinned
  SwiftLint/SwiftFormat versions instead of silently taking whatever `brew`
  installs. New `scripts/verify-binary-release.sh` smoke-tests a published
  binary release: asset reachable, checksum matches the tagged `Package.swift`,
  GRDB minimum consistent, and a scratch consumer compiles `import Proximiio`
  for the iOS 15 simulator.

### Added
- **Beacon discovery API (`BeaconDiscoverySession`).** A standalone,
  foreground-only survey/audit scanner, independent of the positioning pipeline,
  for inventorying an existing (often undocumented, third-party) beacon
  installation at a venue. It runs its own `CBCentralManager` scan with
  `withServices: nil` + allow-duplicates (catching *every* service-data
  advertiser, not just Eddystone) and a CoreLocation iBeacon ranging manager over
  a UUID union of bundled common vendors (`CommonBeaconUUIDs` — Kontakt.io,
  Estimote, Radius Networks, Minew/AirLocate), caller/portal-supplied UUIDs and
  user-entered UUIDs added at runtime via `addUUID(_:)` (iBeacons are invisible
  to a raw iOS scan, so only ranged UUIDs appear). Eddystone UID/TLM/URL parse
  through the existing `EddystoneFrameParser`; unknown-vendor service-data
  advertisers surface via a new `DiscoveredBeaconIdentity.serviceData(uuid:payloadPrefix:)`
  wrapper (the positioning-side `BeaconIdentifier` ABI is unchanged). The session
  feeds a dedicated `BeaconRegistry`, delegates `events()`/`tracked`, and adds
  per-identity `DiscoveryStats` (first-seen, session median RSSI, advertising
  interval estimate). CoreLocation `rssi == 0` ("uncomputable") samples are
  discarded. Both hardware seams (`BLECentralManaging`, new `BeaconRangingManaging`)
  are injectable for off-hardware unit tests. Convenience factory:
  `Proximiio.startBeaconDiscovery(extraUUIDs:)`, which wires the org's
  `customIBeaconUUIDs` into the union.
- **`RSSIKalmanFilter` is now public** so a discovery/finder UI can smooth live
  RSSI itself (promoted from `package`; no `package`-only types leak through its
  public signatures).

### Fixed
- **PDR dead-reckoned backwards whenever the phone leaned past upright.** The
  tilt-compensated compass azimuth is Android `getOrientation`'s definition —
  the bearing of the device y axis — which is degenerate once the device stands
  vertical: y points at the sky. Measured on a synthetic field, the reported
  bearing equalled the true heading up to 90.0° of pitch and equalled
  heading + 180° from 90.1° on, and it *stayed* inverted for as long as the
  posture held. A phone in a pocket, or read while walking, therefore displaced
  the user backwards for the whole walk. `headingFlipGuardEnabled` could not
  help — it compares step to step, and a constant offset never arms it, so what
  it suppressed were the symptoms of this at the moment the posture changed.
  The bearing is now read from the device axis best conditioned at the current
  tilt (Android's `remapCoordinateSystem` branch, which the original port left
  out), controlled by the new `PdrConfiguration.headingPitchRemapEnabled`
  (default `true`; disable to restore the previous behaviour exactly). The
  correction covers pitch to roughly 135°, which spans every carried posture;
  beyond that the device is tipping face-down, where which way "forward" points
  depends on how it is carried, so those postures keep today's behaviour rather
  than gaining a guess.
- **A host-raised `minimumBeaconsForPositioning` was silently ignored.**
  `PositioningEngine.init` unconditionally overwrote it with
  `allowsSingleBeaconPositioning ? 1 : 2`, so a host demanding four-beacon
  geometry got two. Clamping *down* stays (lowering the knob alone must not
  half-enable single-beacon positioning — the opt-in flag is the single source
  of truth), but a value above the floor now survives. Invisible until now
  because the knob was unreachable; with `positioning` exposed it would have
  been a user-visible defect.
- **Positioning was not reproducible run-to-run.** `PositioningEngine`'s
  resolved-beacon list came straight out of a dictionary walk, so its order
  varied between processes (Swift seeds hashing per launch). Most of the
  pipeline is order-insensitive, but the RANSAC-seeded IRLS hybrid draws
  minimal samples *by index*, so an unstable input order silently changed which
  consensus set won — two runs over byte-identical input differed by ~1 m RMSE
  (measured 5.77–6.52 m on the same log). The list is now sorted by beacon id.
  Field behaviour is unchanged in character, but a replay of the same log is
  now bit-identical, which is what makes golden regression thresholds possible.
- **The binary distribution could not be built.** `build-xcframeworks.sh`
  staged *every* `Sources/**/*.swift` into the flattened `ProximiioBinary`
  module, including the `proximiio-offline-fetch` executable target whose
  `main.swift` has top-level statements — illegal in a library module, so the
  archive aborted with "expressions are not allowed at the top level". The
  executable target is now excluded from staging (it still ships separately as
  the macOS CLI), and the stage step fails fast if it collects zero files.
- **Binary consumers could resolve a GRDB too old to link.** The distribution
  `Package.swift` advertised `from: "7.0.0"` and the podspec `~> 7.0`, while the
  binary is compiled against whatever `Package.resolved` pins (7.11.1 today) —
  a consumer resolving 7.0.x got undefined storage symbols at link time. The
  minimum is now recorded at build time (`grdbVersion` in `manifest.json`) and
  rendered into both manifests at publish time; rendering fails if any
  `__PLACEHOLDER__` survives.
- **Privacy manifests were merged from a hardcoded list.** A `PrivacyInfo.xcprivacy`
  added to a new module would have been silently dropped from the shipped
  binary (App Store review risk); they are now discovered under `Sources/`.
- **PDR heading ran opposite to the compass (mirrored tracks).**
  `CoreMotionIMUMapper` summed CoreMotion's `gravity` and `userAcceleration`,
  but Android's `TYPE_ACCELEROMETER` — the convention the whole ported heading
  pipeline assumes — measures the *reaction* force (flat face-up reads
  **+9.80665** on Z, while CoreMotion's gravity vector is (0, 0, −1) g). The
  sum negated the whole acceleration vector, which mirrored the
  tilt-compensated magnetic azimuth (east ↔ west), flipped the gyro yaw-rate
  sign, and swapped faceUp/faceDown placement. The mapping is now the negated
  sum `−(gravity + userAcceleration) · 9.80665`, matching Android exactly. (An
  intermediate `userAcceleration − gravity` form corrected the heading but
  inverted the *dynamic* term and halved the acceleration signal the
  step-detection pipeline was tuned on — a step-cadence regression; negating
  the whole vector restores |a| exactly while keeping the reaction convention.)
- **Stale "table"/"bag" placement during hand-held walking.** Device
  orientation only (re)classified when the acceleration magnitude was within
  2 m/s² of gravity — nearly never true mid-stride — so a placement captured
  at rest stayed latched. Sustained walking-level magnitude variance now
  re-classifies a stale flat `table` as a hand placement, which surfaces a
  `placementChanged` event and (when the host enables it) the auto motion-only
  policy — the mechanisms placement actually drives; step-detection thresholds
  are unchanged (`recommendedParameters()` has no production caller). Release
  is now symmetric (a brief quiet dip no longer disarms it), and a genuinely
  resting phone is unaffected.
- **Transient ~180° heading flips corrupted steps.** A new heading-flip guard
  holds the gyro-propagated heading when a step-to-step heading jump exceeds
  120° without matching integrated gyro rotation (field log: 5 flips in 90 s,
  each reverting within 1–3 steps). Genuine about-turns pass through. The guard
  is now robust across discontinuities: a >1 s IMU gap resets it (gyro rotation
  across the gap is dropped, so a genuine post-gap turn is no longer held);
  disabling PDR clears its state (a turn made while disabled is not held on
  re-enable); and while it is inactive (guard disabled or an external heading
  override active) its reference is no longer mutated, so it re-seeds fresh when
  it next becomes active instead of comparing across the inactive window.
- **BLE fixes claimed sub-metre accuracy from weak, biased ranges.** The IRLS
  residual RMS collapses when RSSI-model ranges are mutually consistent but
  all biased (venue log: +3…+11 m per-beacon path-loss residuals at
  −85…−91 dBm, claimed ±0.6–1.1 m) — the EKF then dragged the fused position
  backwards behind the lagging BLE estimate on every correction.
  `GeometryAwareMeasurement.residualAwareAccuracy` now floors reported
  accuracy at the range-residual dispersion — a *weighted* RMS over the
  solver's own Huber/RANSAC weights (`sqrt(Σ wᵢ·rᵢ² / Σ wᵢ)`, median RSSI
  inlier-filtered), so a correctly-rejected NLOS outlier does not falsely
  widen a good fix. Weak-RSSI distrust lives one layer deeper, in
  `AdaptiveRSSIModel`'s per-beacon range uncertainty (inflated by
  `1 + perDb·max(0, threshold − rssi)`, knobs `bleWeakRSSIThreshold` /
  `bleWeakRSSIAccuracyPerDb`), so weak beacons down-weight the *solve*
  itself rather than only widening the final number. The PDR calibrator's
  anchor trust gate receives the same inflated accuracy the EKF sees (was:
  raw pre-inflation solver accuracy), so overconfident high-dispersion
  solves no longer register as calibration anchors. Replay on the reporting
  venue log (≥6-rep averages): RMSE ~6.4 → ~5.0 m, jumpiness ~9.1 → ~6.0.
- **Indoor `native` GPS fixes no longer punch through fresh indoor fixes.**
  A ±15 m native fix could be emitted 12 s after a ±0.7 m PDR-fusion fix,
  yanking the position 3.5 m backwards. Native fixes are now suppressed while
  a recent *absolute* indoor fix (BLE trilateration, default < 30 s) is at
  least 3× tighter (both configurable). Dead-reckoned `pdrFusion` emissions do
  NOT re-arm the window, so out of BLE coverage the fail-open genuinely
  expires 30 s after the last BLE fix — pure-PDR drift cannot hold corrective
  GPS out indefinitely. The anchor is stored atomically
  (`lastIndoorFix: (at:accuracy:)` via one `recordIndoorFix` helper), and it
  arms when a BLE solve updates the EKF — not only when the DistanceFilter
  emits it — so a stationary user's coalesced BLE ticks (field: build 11,
  1 emitted BLE fix in 80 s with 9 beacons visible) no longer let ±15 m
  native fixes punch through while healthy corrections flow every 2.5 s.

## [6.0.0-beta.30] — 2026-07-17

### Added
- **Fully-offline first launch for geofencing (offline seed → SyncStore).** The
  bundled offline seed can now populate the runtime `SyncStore` on first launch,
  so geofences, privacy zones, inputs, places, floors and departments work with
  **no network at all** — previously they waited for the first online audit sync.
  - `proximiio-offline-fetch` now also writes a `sync-snapshot.json` next to
    `manifest.json` — a point-in-time export of the synced models fetched from
    the SDK's own full-package endpoint (`/core/package`, the same one the online
    cold sync bootstraps from). Pass `--no-snapshot` to ship map data only.
  - `installBundledOfflineSeedIfNeeded(...)` (and `installOfflineSeed(...)`)
    detect a bundled `sync-snapshot.json` and import it into the `SyncStore`
    **atomically** before the online sync runs. The import is idempotent
    (gated on the audit bootstrap marker — it never clobbers a store the online
    sync has already advanced) and **delta-safe** (the seed still advances the
    audit watermark to the package's version, so the first online sync is a delta
    from that point, at worst re-applying a handful of rows already in the
    snapshot — never a missed change). A corrupt snapshot fails cleanly with no
    half-import, degrading to seeding from the first online sync.
  - New `SyncStore.importSnapshot(_:)` and a shared `SnapshotBootstrap` parser
    (reused by `AuditSyncClient`) guarantee the offline seed and the online
    bootstrap populate the store identically.

## [6.0.0-beta.29] — 2026-07-17

### Added
- **On-device wayfinding (R3): turn-by-turn instructions.** `ComputedRoute`
  gains `instructions: [RouteInstruction]` — turn-by-turn steps derived
  on-device from the route geometry (`GeoMath.bearing` deltas), in travel order
  from `.start` to `.arrive`. Each `RouteInstruction` is pure data (`kind`,
  `coordinate`, `distanceMeters` since the previous step, `level`) and carries
  **no display strings** — mapping a `kind` to localized text is the app's job.
  Turns are classified by signed bearing delta (slight 25°–60°, turn 60°–120°,
  sharp ≥ 120°; clockwise = right, counter-clockwise = left); near-straight
  vertices collapse into the next step, long straights drop a `.continueStraight`
  milestone, welded-graph jitter (< ~2 m) is filtered, and floor transitions are
  interleaved as `.levelChange` steps. Instructions ride on the existing result
  for both single-level and cross-level routes (additive; default empty). A new
  env-gated A/B parity harness (`WayfindingParityHarnessTests`, gated on
  `PROXIMIIO_ROUTES_PATH` / `PROXIMIIO_LAYOUT_PATH`, optional server comparison
  via `PROXIMIIO_SERVER_ROUTES_JSON`) validates seeded on-network pairs against
  a real venue network.
- **On-device wayfinding (R2): multi-level (cross-floor) routing.** A new
  additive facade method `Proximiio.computeRoute(from:fromLevel:to:toLevel:)`
  plans a walking route that crosses floors via level changers (elevators,
  staircases, escalators, hills, ramps) — still **entirely on-device** and
  fully offline once the network is cached. The per-floor R1 graphs are combined
  into one multi-level graph with weighted level-transition edges: each changer
  is associated with a floor when that floor's path network has a vertex within
  a horizontal radius (`levelChangerRadiusMeters`, default 4 m), and consecutive
  reached floors are linked at a distance-equivalent cost per change
  (`levelChangeCostMeters`, default 15 m), so a nearer changer is preferred over
  a longer walk to a far one. `ComputedRoute` gains `levelChanges: [LevelChange]`
  (changer type, from/to level, coordinate) in travel order for rendering "take
  the elevator to floor 2"; `level` is the origin floor. A cross-level request
  that cannot be linked throws `WayfindingRoutingError.noRoute(.noLevelTransition)`
  (new `NoRouteReason` case). Level changers are installed automatically from the
  wayfinding GeoJSON by `loadRouteNetwork()` / `loadCachedRouteNetwork()`. The
  existing single-level `computeRoute(from:to:level:)` is unchanged, and an
  equal-level cross-level call delegates to it (no `levelChanges`).
- **Prebuilt `proximiio-offline-fetch` CLI in the binary distribution.** The
  build-time offline-package fetcher now ships as a **prebuilt universal macOS
  binary** (`arm64` + `x86_64`) so binary-SDK customers — who consume the
  xcframework and cannot build from source — can run it in an Xcode build phase
  or CI step. `scripts/build-xcframeworks.sh` now also builds it (via the new
  `scripts/build-offline-fetch-cli.sh`, `swift build -c release --arch arm64
  --arch x86_64`), strips it, verifies the slices with `lipo -info`, and zips it
  as `proximiio-offline-fetch-macos.zip` with its SHA-256 recorded under the
  manifest's `cli` object. `scripts/publish-binary-release.sh` attaches that zip
  as an additional GitHub Release asset on the distribution repo, and the
  distribution README documents the download URL pattern, `chmod +x`, checksum
  verification, and the Gatekeeper step for the (currently) **unsigned** binary
  (`xattr -d com.apple.quarantine …`). Codesigning + notarization are noted as a
  future GA task.

## [6.0.0-beta.28] — 2026-07-16

### Added
- **On-device wayfinding (R1): single-level route computation.** A new additive
  facade method `Proximiio.computeRoute(from:to:level:)` computes a walking route
  across the loaded path network **entirely on-device** — no network request, and
  fully offline once the network is cached (via `loadRouteNetwork()`,
  `loadCachedRouteNetwork()`, or `setRouteNetwork(_:)`). It returns a
  `ComputedRoute` (ordered on-network coordinates, total distance in meters,
  per-segment breakdown, single level) and throws
  `WayfindingRoutingError.noRoute(_:)` with a typed `NoRouteReason`
  (`startOffNetwork`/`goalOffNetwork`/`disconnected`/`emptyNetwork`). The engine
  (new in `ProximiioWayfinding`: `RouteGraph`/`RouteGraphBuilder`, `RoutePlanner`,
  `WayfindingRouter`) builds a deterministic per-level graph from the routable
  polylines — joining endpoints within a configurable tolerance (default ~0.75 m)
  and splitting segments at T-junctions where a path ends on another's interior —
  then runs A* with a geodesic heuristic, projecting the start/goal onto the
  nearest edge. The graph is cached per network load and rebuilt on reload, and is
  structured so multi-level transition edges (R2) can be added without rework.
  Purely opt-in: existing behavior is unchanged unless you call it. R1 is
  single-level only; multi-level routing and turn-by-turn instructions come later.
- **Bundled offline seed: build-time fetch CLI + first-launch install.** A new
  `proximiio-offline-fetch` executable target downloads a venue's offline package
  into a bundle-ready directory (`manifest.json` + SHA-256-verified members) for
  bundling as a folder reference:
  `proximiio-offline-fetch --token <t> --output <dir> [--place <id>] [--api-url <url>]`.
  It reuses `ProximiioOffline`'s fetch/verify pipeline via a new testable
  `OfflinePackageFetcher` type, is idempotent (skips valid existing members), and
  exits with distinct codes for a bad token, unknown place, checksum failure, or
  disk error. A new additive facade method
  `Proximiio.installBundledOfflineSeedIfNeeded(packageId:bundle:subdirectory:)`
  installs that bundled seed on first launch — safe to call on every launch, it
  no-ops when an equal-or-newer package is already installed (version gating is
  delegated to the existing `installSeed`) and advances the audit watermark. The
  seed makes map data available instantly offline; SyncStore entities (geofences,
  inputs) still arrive via the first audit snapshot. Documented under
  docs-site → Offline → "Bundling an initial package".
- **CocoaPods distribution for the binary SDK (React Native consumers).**
  `scripts/publish-binary-release.sh` now also renders `Proximiio.podspec` from
  `distribution/Proximiio.podspec.template` and commits it to the distribution
  repo alongside `Package.swift`. The podspec `vendored_frameworks` the single
  `ProximiioBinary.xcframework` via an `:http` Release-asset source (the zip has
  the `.xcframework` at its top level, so no zip-layout change was needed) and
  verifies it with `:sha256` — the **same** digest SwiftPM pins via
  `swift package compute-checksum`. A one-line `@_exported import ProximiioBinary`
  source shim is compiled into the public `Proximiio` module (materialised at
  install time via `prepare_command`, keeping the SwiftPM archive byte-identical)
  so integrators keep writing `import Proximiio`. Customers reference the tagged
  podspec directly: `pod 'Proximiio', :podspec => 'https://raw.githubusercontent.com/proximiio/proximiio-sdk-ios-binary/<tag>/Proximiio.podspec'`.
  The podspec declares `GRDB.swift ~> 7` (matching the binary's GRDB 7 ABI);
  because GRDB has not published 7.x to the CocoaPods CDN, consumers add a
  one-line Podfile git override for GRDB 7 (documented in the distribution
  README and `docs/RELEASING.md`). Verified with `pod lib lint`
  (`--external-podspecs` supplying GRDB 7).

## [6.0.0-beta.27] — 2026-07-16

### Added
- **Binary (xcframework) distribution pipeline.** Customers can now integrate the
  SDK via SPM without access to source. `scripts/build-xcframeworks.sh` compiles
  all sources into a single flattened `ProximiioBinary` module (source layout,
  `Package.swift`, and the test suite in this repo are untouched — the flattening
  runs in a throwaway staging dir; verified zero internal symbol collisions across
  the eight modules) and produces an iOS device + simulator `xcframework` built
  Release / whole-module with `BUILD_LIBRARY_FOR_DISTRIBUTION=YES`,
  `ENABLE_TESTABILITY=NO`, stripped local symbols/debug info, public
  `.swiftinterface` only, dSYMs withheld from the zip, plus a merged
  `PrivacyInfo.xcprivacy` (precise-location + SystemBootTime), a
  `swift package compute-checksum`, and a `manifest.json`. A separate
  distribution repo (`proximiio/proximiio-sdk-ios-binary`, private until RC)
  vends a `Package.swift` whose `binaryTarget(url:checksum:)` is wired to a
  thin source `Proximiio` wrapper (`@_exported import ProximiioBinary` + GRDB),
  so integrators keep writing `import Proximiio` and GRDB links from source.
  `scripts/publish-binary-release.sh <version> [--dry-run]` tags, creates the
  GitHub Release, uploads the zip asset, rewrites the distribution
  `Package.swift`, and pushes. The two-step release flow and the flip-to-public
  checklist are documented in `docs/RELEASING.md`. Templates live under
  `distribution/`. Verified end-to-end: a scratch consumer `import Proximiio`
  builds for the iOS Simulator against the shipped xcframework.

## [6.0.0-beta.26] — 2026-07-16

### Added
- **Lint + format enforcement (Analysis proposal #1).** Checked-in `.swiftlint.yml`
  and `.swiftformat`, each tuned to a **zero-violation baseline** against the
  current tree so the guardrail lands with no mass-reformat churn. SwiftLint runs
  a curated opt-in set (collection/`first_where`/`redundant_nil_coalescing`/
  `implicit_optional_initialization`/`toggle_bool`/`yoda_condition` plus
  size guards `line_length`/`file_length`/`type_body_length` with thresholds set
  just above current maxima). SwiftFormat runs an allowlist of hygiene rules the
  code already satisfies; `indent`/`sortImports`/`redundantSelf` and other
  large-churn rules are held back with `TODO(format-ratchet)` notes for a future
  dedicated reformat PR. A new non-blocking `lint` job in `.github/workflows/ci.yml`
  (brew-installs both tools, `swiftlint --strict` + `swiftformat --lint`) activates
  when CI is re-enabled. Six genuine `?? nil` redundancies were removed from
  `GeoJSON`/`DecodingSupport`/`LocalSummary`/`CacheIntegrityChecker`; two
  load-bearing `TaskGroup.next() ?? nil` sites are documented and suppressed
  inline. All 1374 tests still pass.

### Changed
- **Test-suite speed & determinism (Phase 2.3, test-infra only — no product code
  touched).** Cut the local `swift test` wall time by ~4× with no loss of
  coverage; all 1374 tests still pass. Highlights:
  - **Eliminated a 120 s wall-clock hang.**
    `NetworkingTests.testRedirectIsNotFollowedAndTokenNeverReachesRedirectTarget`
    drove a refused cross-host redirect, which leaves the URL load idle and could
    only resolve via the request timeout — the production `requestTimeout`
    default of 30 s, retried 4× = ~120 s (90 % of the entire suite). The shared
    `makeClient` test helper now sets a short `requestTimeout` (2 s, an existing
    `APIClientConfiguration` field — no API change) and the redirect test runs a
    single bounded attempt. **120.18 s → 2.02 s.** The redirect-refusal and
    no-token-leak assertions are unchanged.
  - **De-`sleep`d the simulation state-transition test.** Fixed 180 ms/150 ms/
    180 ms `Task.sleep` waits in
    `ProximiioSimulationTests.testPauseResumeStopStateTransitions` replaced with
    an event-driven `pollUntil` that returns as soon as playback ticks; the
    paused-freeze negative check keeps a bounded wait. **0.554 s → 0.143 s.**
  - Added a reusable `pollUntil` helper to `TestSupport` and a suite-time budget
    doc at `docs/TESTING.md` (target: local `swift test` under ~90 s, per-test
    ceiling ~3 s excluding env-gated replay/benchmarks).

## [6.0.0-beta.25] — 2026-07-16

### Added
- **Dev-mode position simulation (DX).** Demo and test indoor positioning on the
  iOS Simulator — or at a desk — with no beacons. New public surface on the
  umbrella `Proximiio` actor drives the same custom-position seam real
  positioning uses, so `positions()`, `floorChanges()`, geofencing, wayfinding
  and route snapping all react to simulated fixes exactly as to real ones:
  - `simulatePosition(_:level:accuracy:)` — one-shot static fix (with a floor
    change when the level differs from the current floor).
  - `startSimulation(_:)` / `pauseSimulation()` / `resumeSimulation()` /
    `stopSimulation()` / `jumpToWaypoint(_:)` — route playback controls, plus the
    read-only `simulationState` (`.idle`/`.running`/`.paused`).
  - `ProximiioSimulatedRoute` (waypoints + `speed` m/s + `updateInterval`
    cadence + `loops` + `accuracy`, with a `demoLoop(around:)` convenience) and
    `ProximiioSimulatedWaypoint` (coordinate + floor `level`). The route is
    interpolated at a constant walking speed; crossing waypoint levels drives
    real floor-change events. Simulated fixes carry the existing
    `PositionSource.custom` (host-injected origin) — no new enum case, keeping
    the RC-frozen surface additive-only. Entirely inert (no task/timer/allocation)
    unless a simulation is explicitly started.

### Changed
- **Allocation discipline on the positioning hot paths (Phase 2.5).** Removed
  per-iteration/per-sample heap churn from the two positioning hot loops, with
  no behavior change — outputs are bit-identical and the full suite (plus the
  real-log replay: RMSE / max / jumpiness unchanged) is the oracle:
  - **Trilateration (2.5 s tick).** `TrilaterationSolver` now accumulates the
    weighted normal equations directly into scalars instead of allocating
    `[[Double]]` Jacobian / residual / weight buffers inside every
    Levenberg-Marquardt iteration; the IRLS re-weighting loop reuses one beacon
    buffer across passes; `RANSACTrilaterationSolver` reuses its sample-index,
    sample-beacon and inlier scratch buffers across sampling iterations (the RNG
    draw sequence is preserved, so sampling stays deterministic).
  - **PDR (50 Hz per-sample path).** `PrecisionStepDetector` no longer allocates
    `[Float]` wrapper arrays per sample: the last gyro sample is stored as
    scalars and the Butterworth filter / ZUPT detector gained allocation-free
    scalar overloads (bit-identical to the array APIs, which are retained).
  - Added env-gated timing benchmarks (`PROXIMIIO_BENCH=1`) and a deterministic
    RANSAC regression test.

## [6.0.0-beta.24] — 2026-07-16

### Added
- **Configuration presets (DX).** `ProximiioConfiguration` gains three static
  factory presets that bundle coherent accuracy/battery knob sets so a first
  integrator does not have to reason about ~18 raw fields:
  `.default(token:)` (equal to the memberwise defaults exactly),
  `.highAccuracy(token:)` (`1.0 s` BLE tick, GPS + stillness duty-cycling off,
  PDR fusion on, `bestForNavigation`) and `.lowPower(token:)` (`5.0 s` tick,
  `600 s` sync, duty-cycling on, PDR fusion off, `hundredMeters` + `10 m`
  distance filter). Purely additive — the presets only seed the existing
  initializer; no default or knob semantics changed. Each preset documents its
  tradeoffs in doc comments.
- **Actionable error copy.** `ProximiioError` now conforms to `LocalizedError`
  fully: every case carries a non-empty `failureReason` and `recoverySuggestion`
  alongside `errorDescription` (e.g. `.invalidToken` → check the dashboard token
  and `apiBaseURL`; `.notAuthenticated` → await `authenticate()` before
  `start()`).
- **Consumer log sink + `LogLevel` (observability).** The SDK previously logged
  only to `os.Logger` (Console.app), invisible to a host app's telemetry. New
  public surface lets a host capture SDK signal: `ProximiioLogLevel`
  (`debug`/`info`/`notice`/`warning`/`error`, `Comparable`), a `Sendable`
  `ProximiioLogEntry` (level, category, message, timestamp) and a thread-safe
  registration point — `Proximiio.logSink = { entry in … }` with a
  `Proximiio.logLevel` minimum-level filter. Internal logging is routed through a
  `ProximiioLogger` shim that still logs to `os.Logger` unchanged and fans out to
  the sink; it is zero-cost when no sink is installed (the message is not built
  unless a sink is active for the level or `os_log` has it enabled). Lifecycle,
  PDR and offline log sites are wired through the shim; other categories adopt it
  incrementally. Messages carry no PII (tokens are never logged).
- **Unified `diagnostics()` snapshot (DX).** New `Proximiio.diagnostics() async
  -> ProximiioDiagnostics`, a `Sendable` read-model answering "why is there no
  position?": lifecycle state, permission + Bluetooth authorization, visible /
  registered beacon counts, last-position age + source, PDR enabled/running,
  floor detection (reuses `floorDiagnostics()`), visitor-reporting state and an
  active-configuration summary (preset + knob highlights), plus a typed
  `NoPositionReason` and a support-ticket-ready `summary` string that names any
  blocking state. A pure read of existing internal state — starts no work and
  changes no behavior.

### Documentation
- **`docs/VERSIONING.md`.** New SemVer + deprecation policy: what constitutes a
  breaking change post-6.0, the deprecate-in-minor / remove-in-next-major window
  via `@available`, and the alpha/beta/rc pre-release conventions (references
  `RELEASING.md`).

## [6.0.0-beta.23] — 2026-07-16

### Added
- **Online step-length auto-calibration (P2).** `KimStepLengthModel.calibrate`
  was dead code, so fused PDR step length was effectively a fixed per-user
  constant. The engine now closes the loop: it accumulates the raw PDR trajectory
  between two *trusted* absolute anchors (a BLE trilateration solve or a good
  native GPS fix) and, over long-and-straight segments, learns a step-length
  **scale** = `anchorDistance / pdrPathLength`, EMA-smoothed and clamped, then
  rescales fused PDR steps by it. Reduces inter-beacon dead-reckoning drift on
  sparse-beacon corridors. The learned scale persists per-install like the
  adaptive RSSI model (`pdr-calibration.json` under Application Support), loaded
  on `start()` and written back on `stop()`. Configurable via
  `pdrStepLengthAutoCalibrationEnabled` (default `true`), `pdrStepScaleMin`/`Max`
  (`0.7`/`1.3`), `pdrCalibrationMinSegmentMeters` (`4.0`),
  `pdrCalibrationMinStraightness` (`0.8`), `pdrCalibrationMaxAnchorAccuracy`
  (`8.0`) and `pdrCalibrationEMAAlpha` (`0.2`). Doubly gated: inert unless
  `pdrFusionEnabled` is also set, so default (PDR-less) behaviour is unchanged.
  No Android equivalent.
- **Trajectory-based heading-bias (yaw offset) estimation (P4).** A constant
  compass-vs-map yaw bias (hard-iron residual, declination, building steel)
  rotates the entire dead-reckoned path so drift re-accrues in the same
  rotational direction every segment; BLE fixes corrected position but never this
  rotation. The engine now estimates a slowly-varying yaw bias by aligning the
  PDR net-displacement direction with the anchor-to-anchor bearing over the same
  trusted straight segments (shared machinery with P2), EMA-smoothed and clamped
  to `±pdrHeadingBiasMaxRadians` (default `π/6` = 30°), and rotates fused PDR
  steps by its negation — equivalent to correcting the compass heading at source
  through the `FusedHeadingProvider.externalHeadingRadians` hook, applied on the
  step vector because `ProximiioPositioning` is decoupled from `ProximiioPDR`.
  Persisted alongside the step scale. Configurable via
  `pdrHeadingBiasEstimationEnabled` (default `true`); shares the P2 segment gates.
  Doubly gated behind `pdrFusionEnabled`. No Android equivalent.
- **EKF innovation (Mahalanobis) gating on the fused position (P1).**
  `LocationEKF.updateMeasurement` now χ²-gates each BLE/native measurement on
  the squared Mahalanobis distance `d² = yᵀS⁻¹y` of its innovation (2 DOF).
  A single statistically implausible fix (crowd attenuation, NLOS-reflected
  beacon, momentary bad geometry) is rejected rather than folded into the
  position; a consecutive-rejection escape re-widens the position covariance and
  accepts the next fix so a genuine teleport (floor change, elevator exit, GPS
  re-acquire) re-anchors instead of being rejected forever. Configurable via
  `ekfInnovationGateChiSquare` (default `9.21`, the χ²₂ 0.99 quantile; `0`
  disables), `ekfInnovationGateMaxConsecutiveRejections` (default `3`) and
  `ekfRejectionEscapePositionVariance` (default `100.0`). Mirrors the existing
  per-beacon `rssiInnovationGateSigma`; no Android equivalent for the fusion EKF.
- **Motion-state-adaptive EKF process noise (P3).** The between-BLE-tick process
  noise was sized by a constant assumed pedestrian speed regardless of motion
  state. It now scales with a coarse motion state derived from the PDR feed:
  a step marks *walking* (`ekfProcessSpeedWalking`, default `1.0` — unchanged
  behaviour), a stillness/ZUPT signal marks *stationary*
  (`ekfProcessSpeedStationary`, default `0.1`), cutting standing-still jitter.
  Only active when PDR fusion is enabled and a stillness signal is fresh, so
  PDR-less builds and moving users are behaviour-identical.
- **Cold-start weighted-centroid EKF seed (P6).** While beacons are visible but
  below the two-beacon solve minimum, the engine now seeds the EKF from an
  RSSI-weighted centroid of the visible beacons at a large but finite covariance
  (`ekfColdStartSeedAccuracy`, default `15.0` m), so the first solved fix
  refines a warm filter instead of cold-starting it — cutting
  time-to-first-stable-fix. Scoped to the pre-solve gap, so a tick that can
  already solve is behaviour-identical to the legacy cold-start. Toggle via
  `ekfColdStartSeedEnabled` (default on). Replay-validated on the home and venue
  field logs: RMSE / maxError / jumpiness unchanged (the logs contain none of
  the targeted pathologies), confirming no default-behaviour regression.
- **Release automation.** `scripts/release.sh` reproduces the manual release
  convention (stamp `## [Unreleased]` → `## [<version>] — <date>`, re-seed an
  empty Unreleased section, commit, annotated tag with the changelog section
  body, push) behind explicit `--push`/`--dry-run` flags, with preflight checks
  (clean tree ignoring `TemporaryDirectory.*` junk, on `master`, `swift test`,
  no `Package.resolved` drift, non-empty Unreleased). RC/GA runs additionally
  update the README SPM pin and warn when the disabled CI/Release workflows need
  re-enabling. Documented in `docs/RELEASING.md`.

## [6.0.0-beta.22] — 2026-07-15

### Fixed
- **Frozen-GPS guard no longer bypassed by a jittering `horizontalAccuracy`.**
  Field session (65 min, stationary indoors) leaked **26** native fixes all
  carrying the byte-identical coordinate `48.557743, 17.837353` with fresh
  timestamps but **varying** accuracy (±11.6…±19.3 m, 20 distinct values). The
  beta.17 guard rejected a repeat only on coordinate match **and** exact
  `horizontalAccuracy` equality — a stuck receiver re-computes (and varies) its
  accuracy every delivery, so every fix looked new and leaked. Root cause: the
  accuracy-equality condition was the wrong jitter escape. A genuinely
  stationary receiver jitters the *coordinate itself* by metres, so a repeated
  sub-decimetre coordinate (against the LRU-4 memory) is now treated as frozen
  **regardless of accuracy**; a genuinely jittering stationary fix (coords
  differ by >0.1 m) is still accepted. Replaying the session through the guard:
  **26 → 1 accepted** (was 25 accepted). Only `PositioningEngine`; LRU-4 depth
  unchanged.
- **PDR step under-detection during continuous walking with a sporadic
  pedometer.** Field session detected only **27** steps for an expected 50-150
  (walking back and forth to an adjacent room). Root cause: the beta.18
  fail-open gate reopens after 3 s of pedometer silence, but a sporadic
  `CMPedometer` batch refreshed `lastHardwareStepTime`, and because the
  silence-grace check keys on that timestamp the gate **re-closed mid-walk** for
  up to the grace window. With the confirmation window (2.5 s) shorter than the
  grace (3 s) and `hardwareStepPending` consumed by a single step, soft steps
  landing in the re-closed band were rejected — detection oscillated between
  accepted bursts and dead zones. Fix: once fail-open engages it is **latched
  for the rest of the walking bout**, so a later hardware batch is purely
  *additive* confirmation and never a re-closing gate; the latch clears only at
  a stationary (bout-boundary) transition, restoring the strict gate for the
  next bout. The resting-phone zero-steps invariant is unaffected — the
  gyroscope gate rejects steps before the hardware gate is reached. Only
  `PrecisionStepDetector`.

## [6.0.0-beta.21] — 2026-07-15

### Changed
- **PDR fusion now emits a position for every detected step (classic dead-
  reckoning), so walking is reflected on the map almost instantly instead of
  gapping 5–13 s.** Field report: "the updating time needs some improvement" —
  during active walking the emitted fixes gapped 5–13 s even though the engine
  ticks at 2.5 s and the PDR step stream flowed cleanly. Root cause: every
  `.pdrFusion` sub-tick position passed through the shared `DistanceFilter`,
  whose displacement floor is `max(1.33 m, 0.5 × accuracy)`. With ±1 m PDR
  accuracy the floor sits at 1.33 m, so ~0.5 m steps coalesced 3+ at a time and
  slow/turning walks stretched the emitted cadence far past a tick — replaying
  the k4.log active segment (33 real steps) through the gate emitted just **1**
  position. PDR fusion emissions now **bypass the `DistanceFilter`** (each step
  is a meaningful ~0.5 m displacement whose jitter is bounded by the step
  length); the BLE trilateration tick remains the drift *correction* and keeps
  the gate, and PDR keeps the filter's anchor synced so a BLE fix that
  meaningfully corrects still emits while redundant sub-threshold fixes stay
  suppressed. Stillness produces no steps (ZUPT freezes drift), so per-step
  emission never spams a stationary position. Replaying the k4.log active
  segment: emitted count **1 → 33** (one per step), inter-fix gap **p50 5.0 s →
  1.0 s** (walking cadence, genuine pauses preserved), step→emit latency ~0 s.
  New `PositioningEngine.Configuration.pdrFusionBypassesDistanceFilter` (default
  `true`) restores the legacy gated cadence for battery-sensitive hosts.

## [6.0.0-beta.20] — 2026-07-15

### Fixed
- **PDR fusion now anchors from a native fix, so a GPS-only + PDR session moves
  the dot (map-never-moved regression).** Field report: 10 registered beacons in
  a box on a desk, the user walked ~6 m out and back, PDR detected every step
  with correct headings — but the session emitted exactly one native GPS fix
  (±11.6 m) and zero BLE fixes, and the map never moved. Root cause: PDR fusion
  was inert until the `LocationEKF` had an anchor, and *only a BLE trilateration
  fix ever seeded it* — the native path broadcast its fix but never touched the
  filter. With no BLE fix (beacons un-mapped, sparse, or co-located), the EKF
  stayed uninitialised, `processExternalDisplacement` bailed on
  `guard ekf.isInitialized`, and the clean PDR step stream drove nothing.
  `PositioningEngine.process(nativeLocation:)` now seeds the EKF from an accepted
  native fix (accuracy-weighted via `updateMeasurement`, dropping a stale
  retained anchor first) so PDR carries the estimate away from it; a later BLE
  fix re-anchors normally through the same call. Gated behind the existing
  `pdrFusionEnabled` knob — the seeded state is consumed only by PDR fusion, and
  native fixes are suppressed for `nativeActivationTime` after any BLE fix, so
  BLE-anchored behaviour is bit-identical. Replaying the field log's native fix +
  PDR steps: fusion off emits 0 PDR positions (the bug); fusion on emits 11,
  tracking 2.96 m out and 1.29 m back.
- **Diagnosed (no code change): the same session's zero BLE fixes were a beacon-
  registration gap, not a solver failure.** Running the field log + inputs-layout
  export through `ReplayRunner.diagnoseZeroEmission` reports
  `observations=0 … no observations survived the bridge (identifier join empty)`:
  all 10 physically-present box beacons (`F7826DA6…/1/1`–`/1/4` plus six random
  major/minor) are absent from the layout's 45 `F7826DA6` entries, so
  trilateration had no anchors to solve from. The beta.19 co-located-cluster
  path is confirmed intact — the solver returns an honest centroid fix
  (accuracy ≈ 10 m, HDOP 99) for even exactly-identical anchors, so co-located
  registration would still have produced a (weak) fix.

### Testing
- `EnginePdrFusionTests`: added `testNativeFixAnchorsEKFSoPDRCarries` (native fix
  with no beacons anchors the EKF and PDR carries north),
  `testNativeAnchorThenBLEReanchors` (BLE re-anchors and corrects after a native
  anchor), and `testNativeFixDoesNotAnchorWhenFusionDisabled` (fusion-off leaves
  the feed inert, guaranteeing BLE-anchored builds are unchanged).
- `LogTriageAndBridgeTests`: added the env-gated
  `testNativeAnchoredPdrReplayMovesTheDot`, an A/B replay of a real GPS-only +
  PDR export proving fusion-off emits zero PDR positions while fusion-on tracks
  the walk out and back.

## [6.0.0-beta.19] — 2026-07-14

### Fixed
- **A co-located beacon cluster no longer pins the fused position (walk-doesn't-
  move regression).** With every contributing anchor clustered in a box, the
  trilateration solve is only *radially* constrained: the measured ranges stay
  mutually consistent for any point on a circle around the cluster, so the
  residual RMS collapses toward zero and `TrilaterationSolver` reports a
  falsely tight accuracy (floored at 0.5 m) even though the direction is
  unobservable — the geometry term correctly flags it (HDOP ≈ 99), but accuracy
  is `UERE · HDOP` and `UERE → 0` erases the warning. Fed to `LocationEKF` that
  0.5 m pin yanked the estimate back to the cluster every 2.5 s tick, erasing
  PDR displacement: a walker who stood at the box and moved 6 m saw the map stay
  put. `PositioningEngine` now inflates the BLE measurement accuracy toward the
  solved range when the anchor spread is small relative to it
  (`GeometryAwareMeasurement`): a co-located cluster solved at 6 m reports ~6 m
  uncertainty, so PDR carries the direction while BLE keeps a weak positional
  anchor. Well-spread geometry (spread ≳ range) is left bit-identical, so
  existing replay goldens are unaffected. The inflation is *isotropic* rather
  than an anisotropic radial/tangential R because the solver's chosen bearing is
  arbitrary for a direction-blind cluster — tightening it along that ray would
  pull the estimate toward a spurious heading.

### Testing
- Added `GeometryAwareMeasurementTests` (spread, centroid, inflation onset/cap)
  and `EngineColocatedClusterTests` (a 6 m PDR walk survives a co-located BLE
  tick; a clustered fix reports honestly large accuracy).

## [6.0.0-beta.18] — 2026-07-14

### Fixed
- **Hand-held slow walking now registers PDR steps again (jumpy-track
  regression).** On the hardware path the step-confirmation gate *required* a
  `CMPedometer` step to accept each software step. `CMPedometer` batches and, for
  a gently swung/held phone, routinely under-reports or delivers nothing for long
  stretches, so the gate rejected every software step and the whole walk
  registered zero PDR displacement — a field session showed PDR active but only
  2 steps in 3.2 min (both mislabelled `table`), 0 % PDR fusion, and a track that
  wandered on BLE alone. The gate now **fails open once the pedometer has stayed
  silent past a grace window** (`precisionPedometerSilenceGraceMs`, default
  3000 ms, measured from the last delivered step or the first IMU sample): the
  software detector's own temporal, amplitude, peak-ratio and gyroscope
  validations then stand alone. The gyroscope gate (`≥ 0.03` rad/s) sits above
  the stationary threshold, so a resting phone still produces no steps.
  Trade-off: the hardware cross-check is unavailable while the pedometer is
  quiet. (The `table` placement label was a red herring — `recommendedParameters`
  is unused and `AutoMotionOnlyPolicy` is disabled by default, so placement never
  gated step acceptance.)
- **BLE-only tracks are no longer jumpier at a faster fix cadence.**
  `ConfidenceBasedSmoother` applied its alpha once per emitted fix, so the
  effective wall-clock time constant scaled with the fix cadence: when the field
  cadence dropped from ~5 s to ~2.5 s the same alpha tracked BLE multipath twice
  as fast and the track read jumpier. The smoother now rescales alpha to the
  actual gap between fixes against a reference cadence
  (`smootherReferenceIntervalSeconds`, default 5 s; `0` restores the legacy
  per-tick behaviour), so a 2.5 s track is smoothed as much as the old 5 s one.
  On the field log this cut the emitted path length by ~41 % and direction
  reversals by ~44 % (RMSE vs the device's own fix trace within ~0.1 m).

### Testing
- `ReplayMetrics` gained a jumpiness summary (emitted path length, path/net
  displacement ratio, direction-reversal count) for before/after replay scoring.

### Fixed
- **Frozen cached GPS fixes that *alternate* are now caught.** The beta.15
  identical-coordinate guard remembered only the *last* accepted native sample,
  so a stuck receiver re-reporting two frozen points interleaved (A, B, A, B …)
  slipped through — each arrival differed from its immediate predecessor. Field
  logs showed exactly this: two ±5 m coordinates re-reported ~150 s apart with
  fresh `CLLocation` timestamps (so the 10 s staleness guard correctly never
  fired — the fixes were re-emitted with current timestamps, not stale cached
  objects). `PositioningEngine` now keeps an LRU window of the last 4 accepted
  native samples and rejects a fix matching *any* of them (same coordinate
  within the ~0.1 m epsilon **and** exact `horizontalAccuracy`), catching an
  N-way alternation while still passing a genuinely moving user (whose distinct
  fixes evict the window) and a stationary receiver (whose several-metre jitter
  clears the epsilon).

## [6.0.0-beta.16] — 2026-07-13

### Fixed
- `enablePdr()` on the hardware path now checks Core Motion authorization and
  logs a warning (subsystem `io.proximi.sdk`, category `Positioning`) when
  motion access is denied, restricted or unavailable — previously the pedometer
  sources started and silently delivered nothing, making a missing
  Motion & Fitness permission indistinguishable from a dead PDR pipeline in
  field logs

## [6.0.0-beta.15] — 2026-07-13

### Fixed
- **Frozen cached GPS fixes no longer pollute the indoor track.** Indoors, once
  the BLE gap exceeds `nativeActivationTime` (30 s), CoreLocation with no fresh
  GPS could repeatedly re-leak its last cached fix — observed in field logs as
  many ±4.8 m native fixes at a ~30 s cadence, all sharing one byte-identical
  coordinate. `PositioningEngine`'s native-fix acceptance path now applies a
  frozen-GPS guard with two independent rejections: (1) **staleness** — a fix
  whose underlying `CLLocation` timestamp is older than 10 s at delivery is
  dropped (the direct signal, since the real fix time is plumbed through
  `NativeLocationSample`); and (2) **identical-coordinate** — a fix that repeats
  the last *accepted* native coordinate (within a sub-decimetre ~0.1 m epsilon)
  **and** its exact `horizontalAccuracy` is dropped as a re-delivered cache. The
  guard keys on exact coordinate + accuracy equality, not proximity, so a
  genuinely stationary outdoor user (whose receiver still jitters several metres
  and re-computes accuracy every fix) is never starved. Rejections are logged at
  debug under the `Positioning` category. No Android equivalent (Android's
  `LocationManager` path does not re-leak a single frozen fix this way).

### Changed
- **PDR fusion is now ON by default.** `ProximiioConfiguration.pdrFusionEnabled`
  defaults to `true` (was `false`) following field validation. Fusion only
  activates once PDR is enabled (`enablePdr(_:)`), so a host that never enables
  PDR sees **zero behavior change** — no PDR subsystem is started and nothing
  consumes the step stream regardless of the flag.
  - **Breaking for PDR‑enabled hosts:** with fusion on, the SDK is the sole
    consumer of the raw single‑consumer `PdrManager.updates` stream, so a host
    that also reads `pdrUpdates()` now competes with fusion for it. **Migrate
    per‑step observation to `pdrObservations()`** (a non‑competing fan‑out of
    every fused step) and read fused positions from `positions()` (source
    `.pdrFusion`). Set `pdrFusionEnabled: false` to restore the host‑owns‑PDR
    behavior where `pdrUpdates()` is the raw step stream.

## [6.0.0-beta.14] — 2026-07-13

### Fixed
- **Event reporting now works against the legacy `/core` deployment (was HTTP
  500).** A live probe of `api.proximi.fi` confirmed the events endpoint is
  served by the legacy "darkness" Express core, not Vulture: `POST
  /core/positions/batch` accepts our positions payload (HTTP 200) but `POST
  /core/events/batch` rejected our Vulture `{ events: [...] }` **object** body
  with HTTP 500, because the legacy handler treats the request body as a bare
  array. The reporting client now selects the `/events/batch` payload **dialect**
  from the ingestion path prefix (`VisitorEventEncoding`, derived — not a new
  knob):
  - `core` prefix (the default, and the current live deployment) → **legacy
    darkness dialect**: a bare JSON array of `{ "event": "enter"|"exit",
    "data": { location:{lat,`lng`,accuracy}, visitor_id, geofence_id?, floor_id?,
    beacon_id?, dwell_time_seconds?, timestamp } }` objects — the exact shape the
    Proximi.io v5 Objective-C SDK (`ProximiioEvent`/`ProximiioBatch`) POSTed to
    this same endpoint. The richer event types collapse to the legacy
    `enter`/`exit` transition; `lng` (not `lon`) spelling; ids nested under
    `data`; no `level`.
  - `v5` / any other prefix → the current Vulture `{ events: [EventPayload…] }`
    shape, unchanged.

  Positions are **not** dialected — the canonical positions envelope already
  returns HTTP 200 against `/core`. Legacy schema confidence is **high**: it is
  reconstructed verbatim from the v5 SDK that historically drove this endpoint,
  and the object-vs-array mismatch precisely explains the observed 500.
- **`EndpointProbeTests` extended and made non-failing.** The live probe now
  POSTs the legacy-shaped events body too (so re-running with a token confirms
  the 2xx), and is now a pure diagnostic: a transport error (route not deployed,
  e.g. `/v5/*`) is a *printed outcome*, never an assertion failure.

## [6.0.0-beta.13] — 2026-07-13

### Changed
- **BLE evaluation tick halved to 2.5 s (was 5 s).** The trilateration/EKF
  pipeline now re-evaluates twice as often, halving worst-case position latency
  and letting the smoother track motion more tightly. This is an *evaluation*
  cadence, not a scan cadence — BLE radio scanning is continuous, so battery is
  effectively unchanged; only the (cheap) solver step runs more often. The
  freshness windows are absolute wall-time (`maxBeaconAgeMillis` 8 s spans ≥3
  ticks, `rssiTrackMaxAgeMillis` 15 s ≥6 ticks) and the beacon-floor vote holds
  are wall-clock gated, so all remain unaffected. Deviation from Android parity
  (`DEFAULT_BLE_EVALUATION_INTERVAL = 5 s`), documented inline. Default for
  `ProximiioConfiguration.bleEvaluationInterval` /
  `PositioningEngine.defaultBLEEvaluationInterval`.

### Added
- **2.5D cross-floor beacon handling.** An other-floor beacon reports a *slant*
  range; feeding it into 2D trilateration as-is biased the fix outward. The
  calculator now range-corrects a beacon one floor from the committed floor
  (`d2D = √(max(0, d3D² − Δh²))`, Δh = floor-level difference × 3 m assumed
  storey height) and excludes any beacon two or more floors away from the
  position solve entirely (it still contributes to floor voting). Same-floor and
  unknown-floor beacons are unaffected. No Android equivalent.
- **Adaptive RSSI model now persists across sessions.** The per-beacon Bayesian
  TX-power / path-loss learning previously reset every launch because
  `exportModels`/`importModels` were never called. It is now loaded on engine
  `start()` and written on `stop()` and on app-background, LRU-bounded to 500
  beacons, tolerant of a missing/corrupt file (learning simply restarts). Stored
  as JSON under Application Support, mirroring the sync store.
- **RANSAC-seeded IRLS trilateration hybrid.** With ≥5 resolved beacons, a
  RANSAC inlier search now seeds the IRLS refine so a gross NLOS outlier cannot
  drag the fix; below that (or when RANSAC finds no model) it falls back to plain
  IRLS — a clean set is bit-for-bit identical to the previous result. Excluded-
  beacon hysteresis (a beacon must be an outlier on two consecutive solves before
  exclusion, readmitted after one inlier solve) keeps the inlier set from
  flapping. No Android equivalent (Android runs RANSAC and IRLS independently).
- **Beacon survey-calibration facade API.** `Proximiio.calibrateBeacon(id:rssi:trueDistance:)`
  supplies a site-survey ground-truth sample that seeds the adaptive RSSI→distance
  model (and persists with it). This deliberately folds calibration into the
  Bayesian model rather than double-wiring the redundant scalar-factor
  `BeaconCalibrationManager`; see `docs/DECISIONS.md`.

## [6.0.0-beta.12] — 2026-07-13

### Changed
- **Beacon-path floor changes are now tuned for latency (was up to ~10 s).**
  The beacon-majority floor override — which corrects a stuck barometric floor
  when the beacons overwhelmingly disagree — previously required the winning
  different-floor vote to survive **3 consecutive 5 s evaluation ticks**, so a
  genuine floor change took ~10 s (worse if a tick was skipped). Three changes,
  targeting a ~4–6 s beacon-path floor change without introducing false flips:
  - **Time-based disagreement hysteresis (replaces the tick-count streak).**
    The winning different-floor vote must now be sustained for a *wall-clock*
    **6 s** (`beaconFloorOverrideHoldSeconds`, clock-injected) before it
    overrides and corrects the committed floor — decoupled from the 5 s tick.
    The vote is advanced both on the 5 s tick **and** on beacon-registry updates
    between ticks (throttled to at most once per second,
    `beaconFloorUpdateEvalThrottleSeconds`), so an override can commit sub-tick.
    The streak resets whenever the vote returns to the committed floor or a
    different floor wins. The ≥60 % majority and ≥2-voter requirements are
    unchanged.
  - **Unanimity fast-path.** When *every* floor-voting beacon (≥3 of them)
    agrees on a single different floor, the override commits after just **1.5 s**
    (`beaconFloorUnanimityHoldSeconds`) — long enough to survive one spurious
    sample, short enough for a ~1.5–2 s floor change on unambiguous evidence.
  - **Vote-specific beacon age.** Floor voting now counts only beacons observed
    within **4 s** (`beaconFloorVoteMaxAgeSeconds`), separate from the 8 s
    `maxBeaconAgeMillis` that trilateration keeps: a beacon last heard 5–8 s ago
    can still refine a position fix but no longer casts a floor vote, so a stale
    vote can't drag the floor toward where the user *was*.

  All new constants are internal, named, and documented on `PositioningEngine`
  alongside the existing majority/voter gates; the deviations from Android
  parity (which has no beacon-majority floor override) are noted inline. The
  barometric floor path is unchanged.

## [6.0.0-beta.11] — 2026-07-12

### Added
- **`Examples/MinimalApp` — a minimal SwiftUI consumer of the SDK, built in CI.**
  A three-file SwiftUI example (auth → start → live `positions()` → current
  floor) plus `Config.swift` showcasing the notable tuning knobs
  (`allowsSingleBeaconPositioning`, `gpsDutyCyclingEnabled`,
  `stillnessDutyCyclingEnabled`, `pdrFusionEnabled`, `visitorReportingEnabled`,
  `analyticsPathPrefix`). It depends on the SDK via a local path and compiles
  against the **public** surface only (no `@testable`), so it is the CI-checked
  canary that catches an accidental over-demotion of a public API or snippet
  rot. A new `example-app` CI job cross-compiles it for the iOS 15 simulator
  (no signing).
- **MIGRATION.md §9 "Upgrading between 6.0 betas"** — per-beta upgrade notes from
  beta.8 up: the package demotions + "use the facade" remap, the removed
  `pdrBLEBearingOverrideEnabled` knob, the beta.9 additive enum cases
  (`SyncEvent.syncFailed`, `PdrEvent.stepStationary`, `PositionSource.pdrFusion`),
  `visitorReportingEnabled` default-ON + opt-out, the analytics knobs, the Swift 6
  language-mode note, and the beta.10 privacy-event contract +
  `analyticsPathPrefix` default change.

### Fixed
- **Geofence enter/exit analytics are now paired under privacy suppression.**
  Previously an enter reported outside a privacy zone whose matching exit landed
  inside one had the exit dropped, stranding an unpaired enter with an unbounded
  server-side dwell (and the mirror case produced an orphan exit). The umbrella
  now tracks which geofence enters were actually reported and pairs the exit
  accordingly: an exit that pairs a reported enter is always emitted — with the
  location **zeroed** when the exit fix is itself privacy-suppressed, so dwell is
  preserved without leaking the exit coordinate — while an exit whose enter was
  never reported (entered in-zone) is dropped so no orphan is created. The same
  pairing governs the synthetic `exitAll()` emitted on `stop()`.
- **Beacon found/lost events are now privacy-gated.** `beacon_found`/`beacon_lost`
  visitor events are no longer uploaded while the visitor is inside a privacy
  zone — a `beacon_id` pins location as effectively as a geofence id. Gated on
  the geofence engine's latest privacy-zone state (the same source the position
  and geofence-event suppression reads); the public `beaconEvents()` stream is
  unaffected.
- **A never-succeeding visitor registration now surfaces `SyncEvent.syncFailed`.**
  `flush()`'s early return when the visitor is not yet registered previously did
  not count as a failed flush, so a registration outage that persisted forever
  uploaded nothing in silence. Each registration-skipped flush now counts toward
  the consecutive-failure streak, so the outage surfaces after three skips and
  resets once registration and upload recover.
- **CI: pin the toolchain for every job.** The `example-app` job failed with
  "tools version 6.0.0 but installed 5.10" because the macOS 14 runner's default
  Xcode had drifted to a Swift 5.10 image. A workflow-level `DEVELOPER_DIR`
  selects the Xcode 16 (Swift 6) toolchain uniformly so no job depends on the
  mutable runner default. (CI remains disabled; validated by running the job's
  build commands locally.)

### Notes
- **`stop()` final-flush diagnostics.** The reporter-event pipeline that forwards
  `SyncEvent.syncFailed` onto the public `syncEvents()` stream is torn down before
  the reporter's final flush during `stop()`, and the streams finish immediately
  after, so a `syncFailed` raised by that last flush is not delivered on the
  public stream (which is ending anyway). This is accepted and documented: the
  outage is still recorded via `os_log`, the appropriate surface for a stop-time
  diagnostic; keeping the pipeline alive across the flush would only race the
  stream finish.

## [6.0.0-beta.10] — 2026-07-11

### Changed
- **Visitor analytics ingestion prefix now defaults to `"core"`** (was `"v5"`).
  The legacy device-token whitelist accepts `/core/positions/batch` and
  `/core/events/batch`; the `/v5` route to Vulture is unverified on
  `api.proximi.fi`. The `ProximiioConfiguration.analyticsPathPrefix` knob is
  retained — set it to `"v5"` for a Vulture deployment. An env-gated live probe
  test (`EndpointProbeTests`, run with `PROXIMIIO_TEST_TOKEN`) POSTs a synthetic
  batch to both prefixes to settle the deployment question.
- **`ProximiioVisitor.current(id:)` device capture is now MainActor-free.** It no
  longer reads `UIDevice` (which is `@MainActor` under Swift 6 and was accessed
  from the non-isolated component graph). `model` is now the hardware identifier
  from `uname` (e.g. `"iPhone15,3"`) — more specific than `UIDevice.model`'s
  generic `"iPhone"`; `systemName`/`systemVersion` are unchanged in meaning.

### Fixed
- **Privacy-zone coordinate leak via events.** A fix inside a privacy zone
  suppresses positions, but geofence/privacy-zone events were still stamped with
  the exact in-zone coordinate. Privacy contract now enforced: a **geofence**
  enter/exit whose fix is suppressed (inside a privacy zone) is **dropped** (its
  geofence id would itself reveal the in-zone location); a **privacy-zone**
  enter/exit is still reported but with its **location zeroed** to `(0, 0)` (the
  zone id is known server-side; the precise crossing point is the leak). No
  precise in-zone coordinate ever reaches the reporter.
- **Unpaired geofence enter without exit on `stop()`.** `stop()` now feeds the
  synthetic `exitAll()` exits (with dwell) to visitor analytics **before** the
  reporter's final flush, so stopping inside a geofence uploads the exit instead
  of stranding an enter. Synthetic exits carry a zeroed location (no
  authoritative stop-time fix) and a geofence exit is dropped when stopping
  inside a privacy zone (item-1 parity).
- **Stale `didRegister` latch across sign-out.** `signOut()` now resets the
  reporter's in-memory registration latch, and the persisted registration marker
  is scoped by the visitor + org/token identity, so a re-authenticate (or a new
  org) registers the visitor again instead of being suppressed.
- **Flush uploaded positions/events before registration succeeded.** `flush()`
  now gates uploads on a successful registration; buffered positions/events stay
  queued (bounded) and upload once registration recovers.
- **Reporting failures were invisible.** After 3 consecutive failed flush cycles
  the reporter emits `SyncEvent.syncFailed(reason:)` on the same `syncEvents()`
  channel the audit sync client uses; the streak resets on the first success.
- **Swift 6 concurrency fallout.** `IntegrityFacadeTests`' mock `URLProtocol`
  statics are lock-guarded (matching the other mocks), and `ProximiioVisitor`
  device capture is MainActor-correct (see *Changed*).

## [6.0.0-beta.9] — 2026-07-11

### Added
- **Visitor analytics reporting — positions *and* events (Android parity; the
  6.0 dashboard blocker).** The SDK registers the visitor and uploads batched
  position reports **and discrete events** to the Proximi.io ingestion service,
  so the web analytics dashboards (visitor counts, journeys, `lastLocation`,
  heatmaps, geofence/beacon activity) light up on iOS as they do on Android
  (`registerVisitor` + `ReportFlushWorker`). Payloads follow the canonical
  ingestion contract (the Rust core `network::api` `EventPayload` /
  `PositionPayload` shapes). New pieces, all additive:
  - **Registration** — on ``authenticate()`` the visitor is upserted via
    `PUT /core/visitors` with the stable Keychain visitor id, `platform`,
    `locale` and device data (`ProximiioVisitor.current(id:)`). The upsert is
    idempotent, an "already exists" (HTTP 409) is treated as success, and a
    persisted marker in the sync store prevents re-registering on every start.
  - **Batched positions** — each non-suppressed fix is buffered on a
    time+distance cadence (`VisitorReportPolicy`: latest-position every N seconds
    plus significant-change; sub-tick PDR fixes are collapsed, not uploaded) and
    flushed via `POST {prefix}/positions/batch`. The envelope carries
    `visitor_id` **once**, then per-position `lat`/`lon` (not `lng`), `accuracy`,
    optional `floor_id`, an always-present numeric `level` (0 when unknown), a
    `source` mapped from the positioning pipeline
    (`trilateration`/`native`/`fused`) and an ISO-8601 UTC `timestamp`. (This
    replaces the beta's provisional `/core`-guessed `lat`/`lng`+epoch-millis
    shape.)
  - **Batched events** — geofence enter/exit, privacy-zone enter/exit and beacon
    found/lost are buffered and flushed via `POST {prefix}/events/batch`
    (`{ "events": [EventPayload…] }`). Each event carries `type`, `visitor_id`,
    a `location` (`lat`/`lon`/`accuracy`), numeric `level` and ISO-8601
    `timestamp`; optional `geofence_id`/`beacon_id`/`floor_id`/
    `dwell_time_seconds` are **omitted when nil** (never `null`). Geofence
    **exit** events carry `dwell_time_seconds` in whole seconds (privacy-zone
    ids travel in the `geofence_id` field per the contract). The 202 response
    `{ accepted, rejected }` is honoured: server-**rejected** events are logged
    and dropped (invalid, not offline), while a transport failure requeues the
    whole batch.
  - **Beacon-events decision** — only `beacon_found`/`beacon_lost` are reported
    (naturally rate-bounded, one per beacon appearance/disappearance). Per-scan
    `beacon_updated` is **not** reported: even after the registry's 1 s
    per-beacon coalescing it fires per RSSI change across every tracked beacon
    and would flood ingestion for marginal value. (The Rust core buffers all
    three but relies on venue-tuned coalescing; iOS takes the conservative
    hard-throttle-to-zero option.) Beacon events carry a `(0,0,0)` placeholder
    location (Rust parity) since they originate in the BLE layer with no fix and
    reusing the last position could leak a privacy-zone-suppressed coordinate.
  - **Shared lifecycle** — positions and events share one flush loop, one
    bounded (drop-oldest) **per-kind** offline queue with front-requeue, and one
    periodic + backgrounding + `willTerminate` cadence — reusing `APIClient`
    (pinning/failover) and `SyncStore`, not a second sync engine.
  - **Privacy zones respected** — a fix while inside a privacy zone is never
    reported (checked against the just-recomputed geofence-engine state in the
    position pipeline). The zone *transition* itself is still reported (a privacy
    zone suppresses positions inside it, not the boundary-crossing event).
  - **Config knobs** — `ProximiioConfiguration.visitorReportingEnabled`
    (default **on**, Android parity; set `false` for privacy-sensitive hosts
    that must not send positions or events) and
    `ProximiioConfiguration.analyticsPathPrefix` (default `"v5"` — the gateway
    prefix the Rust core queues under: `/v5/positions/batch`, `/v5/events/batch`)
    for legacy deployments whose ingestion routes live under a different prefix.
  - **Note** — the beta's events-scope-out decision (deferring events to the
    realtime bus) was **overturned** by the ingestion-contract research, which
    documents a first-class `POST /events/batch` endpoint; events are now
    reported here directly.

## [6.0.0-beta.8] — 2026-07-11

### Changed
- **Swift 6 language mode.** The package now builds under
  `swift-tools-version:6.0` with `.swiftLanguageMode(.v6)` on every library
  target (replacing the `StrictConcurrency=complete` experimental setting, which
  mode 6 implies). No behaviour-visible change — the flip only tightens
  compile-time data-race checking; the two `CLLocationManagerLocationUpdater`
  closures were adjusted to capture `self` rather than the non-Sendable manager
  local, and three types (`KeychainTokenStore`, `KeychainVisitorIdentityStore`,
  `NoopBackgroundTaskManager`) dropped `@unchecked` for compiler-verified
  `Sendable`. iOS 15 stays the minimum deployment target. See
  `docs/DECISIONS.md` for the final `@unchecked Sendable` inventory.
- **API-freeze prep: engine internals demoted from `public` to `package`.** The
  positioning/PDR algorithm surface (filters, detectors, solvers, estimators and
  their stats/result payloads) is no longer part of the frozen public API. The
  public contract is now: the `Proximiio` facade, `PositioningEngine`/`PdrManager`
  and their config + stream payloads + injection seams, plus errors. Everything
  reachable only from the facade's public signatures stays public; pure
  implementation types are `package`-scoped (still fully accessible to the SDK's
  own `@testable` tests, which are in-package). Demoted, per module:
  - **ProximiioPDR (50 types):** `MadgwickFilter`, `ButterworthFilter`,
    `HammingWindow`, `LowPassFilter`, `StandardDeviationWindow`,
    `GyroscopeBiasEstimator`, `ComplementaryHeadingFilter`, `FusedHeadingProvider`,
    `PrecisionStepDetector`, `StepDetector`, `HardwareStepDetector`,
    `StepLengthEstimator`, `KimStepLengthModel`, `AdaptiveThresholds`,
    `ZUPTDetector`, `WalkingPatternRecognizer`, `MagneticDisturbanceDetector`,
    `MagnetometerCalibrator`, `CompassHealthMonitor`, `DeviceOrientationDetector`,
    `MotionStateDetector`, `MotionActivitySource`, `MobilityModeDetector`,
    `MobilityPdrHook`, `CoreMotionIMUSource`, `PedometerStepSource`,
    `BaseCalculator`, `SystemPdrClock`, the `HeadingSource`/`HardwareStepSource`/
    `HardwareStepSourceDelegate`/`ZUPTDetectorListener`/`PdrClock` protocols, the
    `*Stats`/`*Configuration`/policy value types, and the `GaitType`/`Gender`/
    `MotionState`/`PatternQuality`/`SensorDutyLevel`/`DeviceOrientation`/… enums.
    `PdrManager`'s `init` and neural-seam accessors are now `package`.
    Kept public: `PdrManager`, `PdrUpdate`, `PdrEvent`, `PdrConfiguration`,
    `StepDetectionConfiguration`, `IMUSample` (+`Vector3`), `DevicePlacement`,
    `CompassAccuracy`.
  - **ProximiioPositioning (27 types):** `LocationEKF`, `RANSACTrilaterationSolver`,
    `TrilaterationSolver`, `RSSIKalmanFilter`, `MedianRSSIFilter`,
    `AdaptiveRSSIModel`, `BeaconPositionCalculator`, `PositionConfidenceScorer`,
    `ConfidenceBasedSmoother`, `BLEScanner`, `IBeaconRanger`, `CoreLocationSource`,
    `BarometricPressureSource`, `BeaconCalibrationManager`, the solver/estimate/
    result value types (`RANSACSolution*`, `IRLSSolution*`, `Solution*`,
    `Estimate`, `DistanceEstimate`, `FilterResult`, `ConfidenceResult`,
    `SmoothedPosition`, `PositionResult`, `BeaconModel`, `TrackedBeacon` stays
    public), the Eddystone frame types + parser, `CoreLocationConfiguration`,
    `GPS*`/`LocationUpdateMode`/`Verdict`/`RejectionReason` and the
    `BLECentralManaging`/`LocationUpdating` seams. Kept public: `PositioningEngine`,
    `BeaconRegistry`, `FloorManager`, `FloorDetectionEngine`, the position/floor/
    beacon stream payloads (`PositionUpdate`, `ExternalDisplacement`,
    `NativeLocationSample`, `BeaconEvent`, `FloorChangeEvent`, `BeaconTelemetry`,
    `BLEBeaconObservation`, `RSSISample`, `BeaconIdentifier`), config
    (`TrilaterationConfiguration`, `DistanceFilter`), injection seams
    (`PositioningClock`, `PressureSource`) and `CoreLocationAccuracy`.

  These are source-breaking for any integrator that referenced the algorithm
  classes directly (the Proximi.io app does not). Migration: drive PDR/positioning
  through the `Proximiio` facade or the public `PdrManager`/`PositioningEngine`
  APIs. Re-publication of specific algorithm types post-6.0 by demand (see
  `docs/DECISIONS.md`). Core/RouteSnapping/Wayfinding/Geofencing were audited and
  left public for now (their surfaces are largely contract/model types) and
  recorded as follow-up.

### Fixed
- **`LocationEKF` no longer propagates non-finite inputs.** A NaN/Inf position or
  accuracy in `updateMeasurement`, a NaN/Inf reference in `initialize`, a
  non-finite or zero-`dt` PDR step in `predictStep`, or a non-finite `applyZUPT`
  confidence would flow through the innovation / motion model into the state and
  covariance and never recover (every subsequent estimate stayed NaN). Each entry
  point now rejects non-finite (and non-positive-`dt`) inputs and returns without
  mutating the filter. Exposed by the new EKF finite-output invariant tests
  (Phase 3, item 2).
- **GeoJSON decode now rejects non-finite / malformed coordinates.** A huge JSON
  exponent parses to `±Inf`, and a truncated position (`[lon]`) or empty
  coordinate array previously decoded silently and could corrupt snapping /
  wayfinding math. Every decoded position must now carry at least two finite
  components; a violating geometry throws at decode, which the tolerant feature
  decoder turns into a `nil` geometry (the feature survives, only its geometry is
  dropped).
- **Offline manifest install-time validation.** `OfflinePackageManifest` now
  exposes `validateForInstall()` — run by the package manager's preflight before
  any download/disk work — which rejects path-traversal / absolute / empty member
  paths (`OfflinePackageError.invalidPath`), negative declared byte counts
  (`.negativeMemberByteCount`, a hazard for the disk-space preflight) and
  duplicate member paths (`.duplicateMemberPath`), complementing the
  `PackageStore` resolve-time traversal guard.

### Removed
- **Dead public knob `RouteSnapperConfiguration.pdrBLEBearingOverrideEnabled` and
  the unused `PDRBLEBearingOverride` type.** Both had zero usages: the knob was
  never read and the sticky compass-flip state machine was never wired into
  `RouteSnapper` (only the path-constrain half — `PathConstrainedPDR.constrain` /
  `headingGatePasses` — is live, and it stays). Removing before the 6.0 freeze
  avoids a post-freeze breaking change. Migration: drop the
  `pdrBLEBearingOverrideEnabled:` argument (it defaulted to `false`, i.e. no-op).
  To be re-added post-6.0 if the Android bearing-override parity (step inversion
  across the PDR/BLE seam) lands.
- **`NeuralPdrProvider` demoted to `package`** (protocol had no shipping
  implementation — RoNIN deferred), along with `PdrManager`'s
  `setNeuralPdrProvider(_:)` / `setNeuralPdrEnabled(_:)` / `isNeuralPdrAvailable`.

### Performance
- BLE scan-processor pruning is throttled: the per-advertisement full age-expiry
  sweep of the per-peripheral association/telemetry maps (up to 512 entries,
  hundreds of times per second in a dense venue) now runs at most once per second
  using the scanner's existing (injectable) clock. The 512-entry hard cap is
  enforced on *every* advertisement independently of the throttle, so the bound
  can never be broken. Behavior-preserving; expected to cut a large share of the
  BLE consumer's CPU.
- The CoreMotion IMU sample stream is now bounded (`.bufferingNewest(64)`) instead
  of unbounded, matching the drop-oldest policy used by the SDK's other high-rate
  streams. A stalled PDR consumer can no longer accumulate stale 50 Hz samples
  without bound; the freshest sample is always retained.
- `PositioningEngine` now keys its configured-input lookup map by the canonical
  `BeaconIdentifier` (already `Hashable`) instead of an interpolated `String`
  built per beacon per tick/event, removing the per-lookup string allocation on
  the positioning hot path. Match semantics are unchanged.
- Added `BeaconRegistry.observe(_:)` for a batch of observations (single actor
  hop, applied in array order); the iBeacon ranging callback now delivers each
  `didRange` batch in one hop instead of one per beacon.
- Added `BeaconRegistry.snapshot(matching:)`, a filtered snapshot that
  materializes an RSSI-history array only for the requested identifier set. The
  positioning tick now resolves against the registered-beacon set alone, so
  unresolved advertisers in a dense venue no longer build 32-sample histories
  each tick. Equivalent, element-for-element, to `snapshot()` then filtering.

## [6.0.0-beta.7] — 2026-07-11

### Security
- Redirect control: `APIClient`'s URLSession now refuses **every** HTTP redirect
  (a `willPerformHTTPRedirection` delegate returning `nil`) on both the pinned
  and un-pinned session paths. Every API endpoint — auth, audit sync, offline
  package members — is first-party, so no legitimate 3xx exists; refusing stops
  URLSession from transparently re-sending the `Authorization` bearer to a
  redirect target (including a different, un-pinned host). Policy documented on
  `APIRedirectPolicy`; relax to a same-host/pinned-host allow-list (stripping
  `Authorization` on host change) only if a first-party CDN download flow lands
- `APIEndpoint.path` hardening: a caller-supplied path containing `..`, `?` or
  `#` is now rejected (`invalidURL`) before the request is built, so a crafted
  member path cannot climb above the base host or smuggle query items / a
  fragment onto the URL
- Offline package member resolution now re-checks the fully symlink-resolved
  path stays inside the (also symlink-resolved) package directory, rejecting a
  member symlink that escapes the package tree even when its lexical path looks
  contained (defense in depth)
- `download()`'s 4xx path now reads only a bounded 64 KiB prefix of the error
  body (via `FileHandle`) for error mapping instead of re-buffering the whole
  downloaded file into memory
- Offline `PackageStore` log lines now mark tenant/package identifiers `.private`
  instead of `.public`

### Added
- Privacy manifests (`PrivacyInfo.xcprivacy`) are now bundled as SPM resources:
  `ProximiioPDR` declares `NSPrivacyAccessedAPICategorySystemBootTime` (reason
  `35F9.1`, for `ProcessInfo.systemUptime` in step/heading fusion) and
  `ProximiioPositioning` declares precise-location collection (linked: no,
  tracking: no, purpose: app functionality)
- `SyncEvent.syncFailed(reason:)` — the periodic sync loop no longer swallows
  every failure. A mid-session token revocation (`unauthorized`) surfaces on the
  first failing tick; a persistent transport/server outage surfaces after 3
  consecutive failures. Additive enum case (API-safe pre-freeze); exhaustive
  `switch`es over `SyncEvent` gain a `.syncFailed` case
- `AppLifecycleEvent.willTerminate` — the SDK now observes
  `UIApplicationWillTerminate` and, on termination, best-effort flushes a final
  sync pass and ends any active background-task extension
- `start()` now emits a `SyncEvent.syncFailed` diagnostic (and logs a warning)
  when it has no viable positioning input — location denied/restricted **and**
  Bluetooth denied/restricted — so a silent `.running` with no fixes is
  diagnosable (iOS hardware path)

### Fixed
- `stop()` now tears the PDR runtime down: the CoreMotion feed pump, hardware
  motion sources and the stillness/fusion side channels are stopped, so nothing
  pumps CoreMotion after `stop()` (battery). PDR the host explicitly enabled is
  re-armed on the next `start()` with the same configuration; an explicit
  `disablePdr()` stays disabled across restarts
- `stop()`/`start()` restart race: added a `.stopping` state and stashed the
  teardown/unwind tasks (BLEScanner pattern). A `start()` arriving while a
  `stop()` is in flight now awaits the teardown and latches `.running` instead
  of being silently dropped; a `stop()` during `.starting` awaits the full
  unwind instead of returning before teardown completes
- `pdrObservations()` streams are now run-scoped: `stop()` finishes them like
  every other public stream (previously they hung until the next fused step)
- `start()` while the app is already backgrounded now configures background scan
  timeouts / GPS immediately, seeded from the lifecycle coordinator's current
  state, instead of waiting for the next `didEnterBackground`
- Offline audit-watermark threading now logs at error level when the store
  read/write fails (previously `try?`-swallowed — a failed write silently forced
  the next sync to re-pull from an older watermark)

### Documentation
- Rewrote the top-level `README.md` as an integrator-facing front door: SPM
  install, quick-start, required Info.plist keys, module overview and links to
  MIGRATION/DocC/CHANGELOG (replacing the stale internal phase-status stub)
- New DocC article **Tuning and Battery** documenting the accuracy/battery knobs
  (`gpsDutyCyclingEnabled`, `stillnessDutyCyclingEnabled`, `pdrFusionEnabled`,
  `allowsSingleBeaconPositioning`, `aggregatesBeaconRSSIHistory`, `minimumRSSI`)
  with verified defaults and the diagnostics APIs (`floorDiagnostics()`,
  `estimatedAltitude()`, `pdrObservations()`, `os.Logger` categories)
- DocC **Getting Started** now documents the run-scoped stream contract
  (streams finish on `stop()`; re-acquire after `start()`) and permission
  ordering (request before `start()`)
- `ProximiioConfiguration` documents that its fields are snapshotted at
  `Proximiio(configuration:)` init — later mutations have no effect
- MIGRATION.md adds a 5.x behavior-change-defaults section (GPS duty-cycling,
  single-beacon gating, RSSI aggregation, `minimumRSSI`) with each opt-out

## [6.0.0-beta.6] — 2026-07-11

### Added
- Accuracy: per-tick RSSI median aggregation. The positioning engine now feeds
  trilateration the median of each beacon's recent RSSI history (samples within
  `maxBeaconAgeMillis`) instead of the single latest raw advertisement, damping
  multipath/body-shadow outliers before the Kalman filter sees them. The
  previously dormant 32-sample registry history is finally consumed. Defaults
  on; set `TrilaterationConfiguration.aggregatesBeaconRSSIHistory = false` for
  the raw-latest (Android-parity) behavior
- Accuracy: RSSI Kalman innovation gating. Measurements whose innovation
  exceeds 3 sigma of the innovation covariance (body-shadow dips, multipath
  spikes) are rejected instead of entering the track at full weight — the rate
  state no longer extrapolates outliers. A consecutive-rejection escape hatch
  (3 in a row) accepts a genuine sustained level shift so the filter
  re-converges instead of rejecting forever. Tunable via
  `TrilaterationConfiguration.rssiInnovationGateSigma` /
  `rssiMaxConsecutiveRejections`. No Android equivalent
- Accuracy: iBeacon observations now carry CoreLocation's calibrated
  `CLBeacon.accuracy` distance and its per-beacon capture timestamp. The
  calibrated distance replaces the one derived from the global
  `defaultTxPower` in trilateration, and ranging batches land in the registry
  in callback order (previously one batch-wide `Date()` and unordered Tasks)

- PDR heading: the heading pipeline now consumes CoreMotion's *calibrated*
  magnetic field (`CMDeviceMotion.magneticField` under the
  `.xMagneticNorthZVertical` attitude frame) instead of the raw
  `CMMagnetometerData`, which carried tens–hundreds of µT of hard-iron bias
  that `MagnetometerCalibrator` never converged on indoors. While CoreMotion
  reports the field `.uncalibrated` the sample carries no magnetic field and
  heading degrades to gyro-only propagation. `MagnetometerCalibrator` stays as
  a near-no-op safety net (documented inline)
- PDR heading: the gyroscope yaw rate is now the rotation-rate component about
  the vertical (gravity) axis, `-(ω·ĝ)`, instead of the raw device-Z rate,
  which was only valid screen-up-flat and under-integrated turns by ~30 % at a
  ~45° hold. Reduces exactly to the previous behavior when flat, so existing
  behavior is preserved (`FusedHeadingProvider.projectedYawRate`). No Android
  equivalent
- PDR: `PdrManager.setMagneticDeclination(_:)` seam applies
  `trueHeading − magneticHeading` uniformly to every `PdrUpdate` heading and
  north/east vector, converting magnetic-north PDR output to the true-north
  frame the EKF and route corridors expect (default 0 preserves prior magnetic
  behavior). Wiring from `CLHeading` is deferred (documented TODO)
- PDR: new `PdrEvent.stepStationary(isStationary:)` surfaces the
  `PrecisionStepDetector`'s stationary/ZUPT signal (accel variance + gyro
  magnitude — stricter than the `MotionStateDetector` still/moving path). The
  positioning EKF prefers it for Zero-Velocity Updates, falling back to
  `deviceStill` when the classic step pipeline is not the active backend (no
  double-ZUPT). No Android equivalent

### Fixed
- PDR: the hardware step-confirmation gate compared incompatible clocks —
  `PedometerStepSource` stamped epoch milliseconds while `IMUSample.timestamp`
  is boot-uptime, so `PrecisionStepDetector.timeSinceHardwareStep` was off by
  ~1.7e12 ms (the gate failed open after the first `CMPedometer` batch and
  rejected every step before it). Pedometer events are now anchored onto the
  boot-uptime base (`HardwareStepTimestamp`). Until the first hardware step
  arrives the gate no longer treats a bare `0` reference as "recent"
- PDR: `MotionStateDetector`'s still fast-path is now time-based
  (`stillFastPathInterval`, 0.3 s) instead of a fixed 3-sample count, which was
  only 60 ms at 50 Hz and flapped the still/ZUPT state on mid-stride quiet gaps.
  Rate-independent by construction. Deviation from Android's
  `STILL_SAMPLE_BUFFER_SIZE` (retained but no longer gating), documented inline
- PDR: `SystemPdrClock` (used by `PdrManager.poll()`) now returns
  `ProcessInfo.systemUptime` rather than epoch time, aligning the poll timers
  with the boot-uptime sample-stream base (latent — `poll()` is currently
  uncalled)
- BLE scanning now restarts after a Bluetooth power-off/reset/unauthorized
  transition. Previously `scanActive` stayed set, so the scanner never
  re-issued the scan when Bluetooth came back; the radio dropping also sweeps
  tracked beacons immediately (no advertisement can arrive while it is down)
- Quick `stop()`→`start()` no longer races the deferred teardown: the rebuilt
  advertisement pipeline sequences itself after the pending
  processor-reset/registry-flush, so beacons observed right after a restart
  can no longer be erased by the previous stop
- Lost-beacon sweeps are background-aware: while backgrounded (with scanning
  kept running) the lost timeout widens 3x, because iOS coalesces duplicate
  advertisements in the background and still-present beacons refresh too
  slowly for the foreground timeout — false `.lost` events corrupted floor
  hints. The foreground timeout is restored on return

### Changed
- `TrilaterationConfiguration.minimumRSSI` default tightened from -100 dBm
  (a no-op gate; -99 dBm beacons clamp to the 30 m model ceiling and flatten
  solver geometry) to -90 dBm. Deviation from Android parity
  (`MINIMUM_RSSI = -100`), documented inline
- `TrilaterationConfiguration.rssiTrackMaxAgeMillis` default raised from
  10 s to 15 s (3 positioning ticks) so a single missed 5 s tick no longer
  re-initializes the Kalman track from the next raw sample. Deviation from
  Android parity (10 s), documented inline
- `EddystoneScanProcessor` per-peripheral association/parked-telemetry maps
  are now capped (512 entries) and expire after 5 minutes of peripheral
  silence, so TLM-only peripherals can no longer park telemetry forever
- `StepDetectionConfiguration.precisionHardwareConfirmationWindowMs` default
  widened from 500 ms to 2500 ms to tolerate `CMPedometer`'s ~1–2 s batching
  latency (Android `TYPE_STEP_DETECTOR` is real-time). Deviation from Android
  parity, documented inline

## [6.0.0-beta.5] — 2026-07-11

### Added
- Battery: GPS duty-cycling. While BLE coverage is fresh the positioning engine
  already discards every native fix for the 30 s native-activation window, yet
  the `CLLocationManager` kept running at `bestForNavigation` /
  `kCLDistanceFilterNone`. Each BLE-derived position now downgrades the native
  source to reduced accuracy + a large distance filter; losing BLE coverage (the
  window lapsing without a new BLE fix) re-arms full accuracy. Behavior-safe (the
  downgraded fixes are the ones the engine was already throwing away), so it
  defaults on — set `ProximiioConfiguration.gpsDutyCyclingEnabled = false` to keep
  the 5.x always-full-accuracy behavior. The fresh/stale → power-mode decision
  lives in the pure, unit-tested `GPSDutyCyclePolicy`; CoreLocation calls stay
  behind the main-confined `CoreLocationSource.setPowerMode(_:)` wrapper
- Battery: motion-sensor duty-cycling on stillness. When PDR is enabled the
  CoreMotion device-motion stream runs at ~50 Hz to resolve footsteps; once the
  device has been continuously still for a sustained period (60 s, Android
  `LONG_STILL_TIME` parity) it is throttled to 10 Hz, and the first motion sample
  restores the full rate immediately. Decision logic is the pure, unit-tested
  `StillnessDutyCyclePolicy`; the rate change stays behind
  `CoreMotionIMUSource.setReducedRate(_:)`. Defaults on — set
  `ProximiioConfiguration.stillnessDutyCyclingEnabled = false` to opt out.
  Deviation from the Android duty-cycling parity: BLE **scan** duty is
  intentionally left at full rate on stillness. Disabling
  `CBCentralManagerScanOptionAllowDuplicatesKey` (or pausing the scan on a coarse
  cycle) makes constant Eddystone UID advertisements coalesce, so still-present
  beacons stop refreshing and are falsely reported `.lost` after `lostTimeout` —
  reintroducing the exact iOS defect `BLEScanner` was written to avoid — so only
  the IMU rate is duty-cycled
- Accuracy: PDR → EKF fusion. The pedestrian dead-reckoning step stream is now
  consumed by the SDK and fed into the positioning `LocationEKF`, so the estimate
  advances between the 5 s BLE ticks instead of "teleporting" once per tick. Each
  PDR step advances the EKF process model (`predictStep`) and emits a
  `PositionSource.pdrFusion` sub-tick position whose accuracy degrades honestly
  from the growing covariance until the next BLE measurement corrects the
  accumulated drift; `deviceStill` applies a Zero-Velocity Update to freeze drift
  while stationary. The consumer seam is the platform-neutral
  `PositioningEngine.ExternalDisplacement` (fed via `processExternalDisplacement`
  / `applyStillness`), so `ProximiioPositioning` never imports `ProximiioPDR` —
  the umbrella `Proximiio` layer bridges `PdrManager.updates`/`events` to it,
  preserving the hub-and-spoke module graph. Steps are integrated in the EKF's own
  local metric frame (`x` = north, `y` = east) and converted back to lat/lng on
  read, so no separate geo-frame conversion is needed. Off by default: set
  `ProximiioConfiguration.pdrFusionEnabled = true` (and enable PDR). Enabling it
  makes the SDK the sole consumer of the internal PDR update stream, so read fused
  positions from `positions()` rather than `pdrUpdates()`. Fusion is inert until
  the first BLE fix anchors the filter, so nothing changes before positioning has
  produced a fix
- Accuracy: floor-detection robustness. Two fixes to the barometric floor logic:
  (1) beacon-majority floor correction — the engine used to defer unconditionally
  to the `FloorManager` once any floor was known, so a stale barometric floor
  stuck even when the resolved beacons overwhelmingly voted another floor; each
  evaluation tick now tallies a beacon floor vote and, after a sustained
  disagreement (three consecutive ticks with a ≥60 % majority of ≥2 tagged
  beacons — hysteresis to avoid flapping), overrides *and* corrects the committed
  floor. (2) multi-floor traversal — `FloorDetectionEngine` stepped only ±1 per
  confirmed movement and the 3 s debounce dropped intermediate commits during an
  elevator ride, stranding the user short of their floor; the number of floors
  traversed is now derived from the cumulative pressure change since the last
  *committed* floor, so a single large move spans multiple floors and a debounced
  ride still lands on the correct floor once a commit passes (Android-parity note:
  Android only ever stepped ±1). With one floor traversed the behavior is
  identical to before
- Offline: disk-space preflight before package install. Sync now estimates the
  peak additional bytes it will write (every downloaded member as a temp file
  plus a full staging copy of the target member set) and checks it against the
  volume's `volumeAvailableCapacityForImportantUsageKey` *before* writing a single
  byte. When the volume can't fit it, sync fails fast with the typed
  `OfflinePackageError.insufficientDiskSpace(requiredBytes:availableBytes:)`
  instead of part-downloading and dying on a write deep in the atomic-install
  pipeline. An unknown capacity never blocks (the preflight is an optimization,
  not a gate). The decision logic is the pure, unit-tested `DiskSpacePreflight`;
  the volume probe is injectable on `OfflinePackageManager`. Android-parity note:
  Android's `OfflineDataManager` streams members straight to their final location
  and surfaces the first failed write's `IOException`, so it has no equivalent
  preflight — iOS needs one because it stages the whole package (temp + staging +
  live copy briefly coexist) before an atomic swap
- Offline: stale-package enumeration and pruning. `PackageStore` can now list
  every installed package (`installedPackageIds()`) and drop all but the current
  one (`prunePackages(keeping:)`), also surfaced on `OfflinePackageManager`
  (`installedPackageIds()` / `pruneOtherPackages(keeping:)`). Pruning is **not**
  run automatically: a multi-place host can legitimately keep several packages
  (`<orgId>:<placeId>`) installed at once, so auto-pruning after an install would
  silently delete a sibling place's offline data. The API is the safe primitive
  for a deliberate organization/place switch; sign-out still uses
  `removeAllPackages()`. Android-parity note: Android scopes offline data to a
  single active place and clears on switch — the multi-package model is
  iOS-specific, hence the host-driven prune rather than an automatic one

### Performance
- Offline webview no longer stalls on large members and re-fetches every tile.
  The `proximiio-offline://` scheme handler served each member with a synchronous
  full-heap `Data(contentsOf:)` and no caching, so opening a big tile/mbtiles
  asset spiked resident memory and every map interaction re-requested already-
  served tiles. Members are now memory-mapped (`.mappedIfSafe`) instead of copied
  into the heap, and each 200 response carries `Cache-Control: private,
  max-age=86400` so the webview reuses fetched tiles/glyphs for the session. The
  content is content-addressed and a package update reinstalls the whole
  directory, so the TTL is safe
- Offline package install/sync memory footprint. The sync pipeline materialized
  every changed member as in-memory `Data` and handed the whole set to the store
  (full package in the heap → jetsam risk on large packages); members now stream
  to temp files and are passed to `PackageStore.install` as file URLs, verified
  via streaming `sha256HexOfFile` and copied straight into the atomic staging
  directory. Seed installs take the same file-URL path. Atomic-swap semantics are
  unchanged
- Offline sync no longer re-hashes the entire installed package on every poll.
  The "already up to date?" decision re-read and re-hashed every installed member
  from disk each sync; it now trusts the installed manifest's recorded SHA-256
  (verified when it was written) plus a cheap existence check, and only verifies
  bytes on (re)install
- Positioning-cadence spatial prefilter. `RouteSnapper.snap`,
  `GeofenceEngine.update` and `ProximityTriggerEngine.update` precompute a
  bounding box (per route feature / geofence / privacy zone) at set-time and
  cheap-reject candidates that cannot be in range before the exact
  nearest-point-on-line / haversine / ray-cast math runs — now that PDR fusion
  emits sub-tick positions these run far more often. The prefilter pad is
  conservative, so results are identical to a full scan
- `APIClient` reads response bodies in fixed 64 KiB chunks instead of appending
  one byte at a time to `Data` over up-to-10 MB pages. The streaming response
  size cap is enforced exactly as before
- Audit sync advances its watermark per committed page (records arrive ascending)
  instead of only at the end of a full pass, so a sync interrupted mid-way resumes
  from the last committed page rather than replaying every page from the original
  delta

### Changed
- `Proximiio.offlineWebViewConfiguration(packageId:)` is now `@MainActor`-isolated
  rather than isolated to the `Proximiio` facade actor: `WKWebViewConfiguration`
  and its `configureOffline(...)` builder are main-actor-isolated WebKit types, so
  the configuration is now produced and consumed on the main actor where WebKit
  requires it. Callers already `await` the method (it was a cross-actor call), so
  the move is source-compatible
- API surface: the `@_exported import ProximiioOffline` that lived in
  `Proximiio+Offline.swift` moved next to the other six subsystem re-exports in
  `Proximiio.swift`, so the umbrella's full re-exported namespace is defined in
  one auditable place. No change to the visible API — `ProximiioOffline`'s
  symbols remain available through `import Proximiio` exactly as before

### Fixed
- Offline seed installs no longer start with an empty data store. Seeding a
  bundled package advanced the audit watermark to the package's `auditTimestamp`
  without ever downloading the `/core/package` snapshot, so the first live sync
  ran with `delta > 0`, skipped the snapshot bootstrap (which was gated on
  `delta == 0`), and never pulled entities predating the watermark — geofencing
  silently had zero fences. The snapshot bootstrap is now gated on the persisted
  bootstrap marker instead of `delta == 0`, so an offline-seeded install seeds
  its full snapshot exactly once on first sync
- Locked-device Keychain miss no longer signs the user out permanently. Before
  first unlock the Keychain returns `errSecInteractionNotAllowed`, the token
  reads back as nil, the request 401s, and the token was cleared. The stored
  token is now preserved when it cannot be read back (it is only cleared when it
  was actually readable and still rejected), so a transient lock no longer
  destroys a valid session
- Geofence exit events are no longer swallowed by a preceding enter. Enter and
  exit debounce are now tracked separately per identifier, so a user walking
  straight through a small geofence gets both the enter and the exit rather than
  losing the exit for up to the minimum event interval. (Android-parity
  deviation: Android's `GeofenceManager` uses a single per-id interval; the split
  is intentional.)
- Proximity triggers no longer get stuck `pending`. A trigger that entered its
  dwell wait and was then replaced (via `setTriggers`) with a same-id trigger
  carrying no `minDwellMs` never fired; a nil dwell in the pending branch now
  fires immediately
- Wayfinding feature cache save is now crash-atomic. The cache cleared rows one
  by one and then inserted the new set, so a crash mid-save could leave a
  half-cleared / half-filled cache; the clear + insert now run in a single
  `SyncStore.replaceAll` transaction (bulk delete + batched inserts), so a crash
  leaves either the complete new set or the previous one intact. Undecodable
  cached rows are still skipped on load but are now logged instead of silently
  swallowed
- Route snapping: path-constrained PDR is no longer dead code. The position
  pipeline called `RouteSnapper.snap()` without a heading, so the
  `pathConstrainedPDREnabled` knob and the snapper's heading gate never engaged.
  The umbrella now captures the PDR travel heading (compass degrees) off the PDR
  update stream and threads it into `snap(heading:)`, so with the knob on and a
  fresh heading the snapper additionally gates candidate segments by direction of
  travel. Gated conservatively: the heading only constrains when the knob is on
  **and** a PDR heading is still fresh (a few seconds), so a BLE fix taken while
  the user stands still — no recent step — is never constrained by a stale
  bearing; with the knob off, snapping is byte-for-byte as before. Heading crosses
  the module boundary as plain `Double` data, so `ProximiioRouteSnapping` still
  never imports `ProximiioPDR`/`ProximiioPositioning`. Scope note: the separate
  `pdrBLEBearingOverrideEnabled` override (which inverts a step 180° when the
  compass disagrees with the BLE-derived travel bearing) stays opt-in and wired
  off — engaging it fully means inverting the step displacement across the
  PDR→Positioning seam and deriving a BLE travel bearing, out of scope for this
  surgical change

## [6.0.0-beta.4] — 2026-07-07

### Fixed
- CoreBluetooth no longer logs `API MISUSE: <CBCentralManager> has no restore
  identifier but the delegate implements centralManager:willRestoreState:` when
  state restoration is off (the default): the scanner's delegate now advertises
  the `willRestoreState` selector only when a restore identifier was supplied

## [6.0.0-beta.3] — 2026-07-07

Five-phase improvement pass (correctness → security → concurrency → test
coverage → structure); every change verified by the full suite, which grew
from 881 to 1004 tests. See `docs/IMPROVEMENT-PLAN.md` for the plan and status.

### Fixed
- Corrupt offline packages are now distinguishable from missing ones: package
  member resolution, manifest reads/decodes, install cleanup and orphan purges
  log diagnostics instead of failing silently; the package store resolves its
  base directory once and loudly flags the purgeable temp-directory fallback
- Malformed member headers no longer force-unwrap-crash inside the WKWebView
  scheme handler (the task now fails gracefully)
- Keychain items written by previous SDK releases into the legacy file keychain
  (Mac Catalyst/macOS) are found and migrated in place instead of being
  orphaned; visitor-id keychain write failures are logged instead of silently
  minting a new identity every launch
- Sync database file protection relaxed from `Complete` to
  `CompleteUntilFirstUserAuthentication`: `Complete` revoked file access ~10 s
  after every lock, silently stalling background sync — the SDK's core
  background-location use case (offline packages keep `Complete`; rationale in
  `docs/DECISIONS.md`)

### Security
- **Opt-in SPKI certificate pinning** for the API hosts
  (`ProximiioConfiguration.pinnedCertificates`): per-host sets of base64
  SHA-256 SPKI hashes with backup-pin support (RSA-2048/4096, EC P-256/P-384);
  hosts without pins keep system trust
- **Response size limits**: API responses are capped (default 10 MB), enforced
  both via `Content-Length` and while streaming so a lying header cannot
  bypass the cap; offline manifests are validated against member-count and
  per-member size limits, and large members stream to disk with incremental
  SHA-256 instead of buffering in memory
- All keychain queries use the data-protection keychain
  (`kSecUseDataProtectionKeychain`)

### Changed
- **Complete strict concurrency checking enabled on every target.**
  `SyncStore`, `GeofenceEngine`, `ProximityTriggerEngine`, `BLEScanner` and
  `CoreLocationSource` drop `@unchecked Sendable` for compiler-verified thread
  safety (mutable state confined to an audited lock-protected primitive);
  locking granularity and observable semantics unchanged
- GRDB upgraded 6.29.3 → 7.11.1 (no API changes required)
- The duplicated-and-diverging geo math (three haversine copies across
  geofencing, route snapping and trilateration) is unified into one
  package-internal implementation preserving both reference ports
- Internal restructuring with no public API change: the `Proximiio` facade
  delegates component construction and pipeline supervision to an internal
  coordinator; `PermissionsManager` (562 lines) and the trilateration
  enhancements grab-bag (511 lines) split into cohesive files

### Added
- **CoreBluetooth state restoration** (opt-in via
  `ProximiioConfiguration.bleRestoreIdentifier`): background BLE scanning can
  survive app termination; restored scans are adopted without double-starting.
  Requires the `bluetooth-central` UIBackgroundMode in the host app
- Test coverage for the previously untested PDR step-detection chain (48
  tests, synthetic accelerometer signals), golden-trace EKF regression tests
  with seeded deterministic noise (including the beta.2 covariance-collapse
  class), and behavioral facade tests (PDR lifecycle, privacy zones, offline
  accessors); timing-coupled concurrency tests replaced fixed sleeps with
  deterministic synchronization (~20× faster, no CI-load flakiness window)

## [6.0.0-beta.2] — 2026-07-05

Correctness, security and performance hardening on top of beta.1, plus fractional
floor-level support. Sourced from a multi-agent review pass (correctness / security /
performance) with every finding verified against the code.

### Fixed
- **EKF covariance collapse**: the positioning filter never ran a predict step, so the
  emitted position froze/lagged after ~8 minutes stationary; predict now runs with real
  dt before every measurement update (long gaps reset the filter)
- Position smoother no longer jumps when the visible beacon set changes (stable
  first-fix-anchored smoothing origin)
- Barometric floor detection requires a sustained pressure change (2 consecutive samples)
  — single-sample spikes from doors/HVAC no longer trigger floor changes
- Polygon geofences gained boundary hysteresis (enter on containment, exit only beyond a
  tolerance from the nearest edge) — no flapping on the boundary
- Gyro-bias calibration only accumulates while still (0.1 rad/s gate) — starting the app
  in motion no longer bakes in session-long heading drift
- Step lengths fall back to the nearest/last-known heading instead of being silently
  dropped when heading history is sparse
- Eddystone identifier matching is case-symmetric

### Security
- Offline packages reject server-served version downgrades (rollback protection)
- Keychain items (token, visitor id) are device-bound (`ThisDeviceOnly`)
- HTTPS enforced for the primary and all fallback API hosts (http allowed only for localhost)
- SQLite sidecar files inherit Complete file protection; SDK data dirs excluded from backups
- `signOut()` wipes the local synced store and offline packages (was: token only)
- Webview package responses send `X-Content-Type-Options: nosniff` and scope CORS to the
  requesting package origin instead of `*`
- Package ids of `.`/`..` are rejected

### Performance
- BLE advertisement path rebuilt (the SDK's largest steady-state battery cost): one
  long-lived consumer instead of a Task per advertisement, RSSI ring buffers instead of
  per-observation array copies, `.updated` events coalesced to 1/s per beacon, beacon
  event streams bounded (`bufferingNewest(256)`)
- Audit sync applies each page in a single write transaction (was one transaction + fsync
  per record; dominates cold sync of 5000-record pages)

### Added
- **Fractional floor levels** (e.g. parking mezzanine at 1.5): `level` is now `Double`
  end-to-end with epsilon matching (`FloorLevel`, ε = 0.01) and quantized route-network
  grouping. Map features at fractional levels additionally require the pending geo-api
  mapping fix (integer → double + reindex)

### Removed
- IndoorAtlas remnants (`ProximiioInput.triggerVenueChange`; the discontinued integration)

## [6.0.0-beta.1] — 2026-07-04

The 6.0 line is a ground-up **Swift-only** rewrite of the SDK (the 5.x line was
Objective-C, CocoaPods, min iOS 10). It targets **iOS 15+**, ships via **Swift
Package Manager**, and mirrors the Android SDK's module architecture. See
`MIGRATION.md` for the full 5.x → 6.0 migration guide.

### Added
- **Modular architecture**: `ProximiioCore`, `ProximiioPositioning`,
  `ProximiioPDR`, `ProximiioGeofencing`, `ProximiioRouteSnapping`,
  `ProximiioWayfinding`, `ProximiioOffline`, and the umbrella `Proximiio` facade.
- **Async public API**: `actor Proximiio` with `async/await` and `AsyncSequence`
  event streams (`positions()`, `geofenceEvents()`, `proximityEvents()`,
  `floorChanges()`, `beaconEvents()`, `syncEvents()`) replacing the 5.x
  singleton + delegate.
- **Positioning**: BLE trilateration (LM/IRLS, RANSAC, EKF, adaptive RSSI,
  per-beacon calibration), barometric floor detection, Eddystone TLM telemetry
  (battery/last-seen — fixes the broken 5.x receiver), a unified distance filter.
- **PDR**: step-detection stack ported 1:1 from Android (with its reference
  tests), device-placement (pocket/bag) detection, compass health, Madgwick
  heading fusion, CoreMotion sources. RoNIN neural PDR deferred behind a
  `NeuralPdrProvider` seam.
- **Geofencing**: circle + polygon geofences with dwell time, debounce and
  tolerance; a new first-class `ProximityTrigger` (distance-to-point with
  enter/exit hysteresis).
- **Route snapping** and **wayfinding v7** GeoJSON client.
- **Offline venue packages**: differential download, seed-package install,
  atomic verified install, and `WKURLSchemeHandler` webview serving.
- **Data sync via audit polling**: replaces 5.x SSE / Android Firebase push.
  Cold sync + delta polling with a developer-configurable `syncInterval`,
  tombstone deletes, 304/410 handling, and a cache-integrity check.
- **Platform**: two-step permission flow, low-power/thermal monitoring,
  background/foreground restore.
- **Experimental (`@_spi(Experimental)`, pending field validation)**:
  mobility-mode (wheelchair) detection and a device-capability database.

### Security
- Auth token stored in the **Keychain** (5.x used `NSUserDefaults`).
- Local sync database protected with **`NSFileProtectionComplete`** on iOS
  (see "Storage encryption" in `docs/DECISIONS.md`).

### Notes
- Pre-1.0: the public API is not yet source-stable. Breaking renames may land
  until the first tagged release.
