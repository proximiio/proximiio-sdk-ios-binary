# Changelog

All notable changes to the Proximi.io iOS SDK are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
