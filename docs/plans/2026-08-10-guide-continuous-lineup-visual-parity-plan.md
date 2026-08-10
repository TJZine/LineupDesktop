# Guide Continuous Lineup And Desktop Visual Parity Remediation Plan

**Plan Status:** active
**Task family:** feature/design
**Tier:** Tier 3

## Goal

Bring the Desktop Guide to current upstream Lineup feature and visual parity while using the larger viewport and resource envelope of a Windows PC.

The completed product must:

- populate and navigate the complete eligible channel lineup, not only the first twelve requested channels;
- let wheel, scrollbar, arrow/D-pad, Page Up/Page Down, pointer, and gamepad users move continuously across a 459+ channel lineup without silent blank rows or a manual refresh;
- retain bounded requests, DOM work, memory, cancellation, currentness, focus, accessibility, and renderer privilege;
- match the current upstream Guide's information hierarchy, states, focus treatment, artwork, channel rail, time ruler, tabs, Classic/Overlay composition, and Now Watching behavior;
- use a responsive PC row-density policy that materially increases useful 1440p/4K channel visibility without reducing readability at 720p/1080p;
- separate horizontal time range, vertical row density, and resource policy in Settings;
- default new installations to an evidence-backed `Auto` PC performance profile and provide a `Reduced resource` profile that reduces speculation and retention without hiding channels or changing navigation correctness; and
- produce Windows production-build performance and paired current-upstream visual proof before any WS5 parity row closes.

The evidence seed is [`docs/development/guide-large-lineup-performance-parity-bug-report.md`](../development/guide-large-lineup-performance-parity-bug-report.md), issue `WIN-TEST-010`. The observed checkpoint had 459 persisted channels, requested twelve default channels, displayed eleven complete rows plus one clipped row at 3840 x 2160/100%, and did not populate later channel content during ordinary vertical scrolling.

## Non-Goals

- Do not implement or modify the concurrent `WIN-TEST-006` playback remediation.
- Do not make renderer code responsible for Plex transport, credentials, raw URLs, filesystem access, Electron APIs, native handles, or native-player process ownership.
- Do not add a broad preload RPC surface or a second Guide IPC operation unless the existing paged `guide.getPresentation` contract is proven insufficient and the plan is re-reviewed.
- Do not import the upstream WebOS concurrency, cache, worker, blur, television-detection, Magic Remote, or hardware profile as Desktop performance authority.
- Do not remove `disable-gpu` inside a Guide package. Hardware acceleration remains a separate native-composition A/B decision under the existing WS5 proof authority.
- Do not close `EPG-10` through `EPG-13`, `UI-36`, or WS5 from synthetic tests, local DOM tests, historical frames, or reference-only upstream inspection.
- Do not preserve the current fixed-five-channel Page key movement, twelve-channel content ceiling, mislabeled Guide Density UI, or whole-array-only scroll behavior for compatibility.
- Do not add forwarding wrappers, one-implementation interfaces, generic UI services, unbounded page stores, unbounded workers, or a second persistence owner.

## Architecture And Invariants

### Authority and sequencing

This is a separate durable Guide handoff and does not supersede the user-modified `docs/plans/2026-07-22-tier3-parity-correction-plan.md`. That plan's `WIN-TEST-006 sequencing replan — Guide execution with mandatory proof debt (2026-08-10)` is the controlling amendment: after its clean independent review, product checkpoint `e7f1338` remains fixed, the still-pending two-channel operator proof moves into the consolidated G6 Windows/native campaign, and G0 is the next authorized product package. The proof is not passed or waived and remains required before G6, WS5, affected parity rows, or RD-27 Windows/native closeout.

Before G0 and each later package, freeze the exact selected write-file list and apply the amendment's collision gate: compare it with all tracked/untracked pre-existing changes and every active writer's exact write list; any path match stops the package without editing, staging, stashing, overwriting, or absorbing the other work. The live-proof writer is proof-only while Guide work is active and may write only ignored run-bundle and generated proof/build output. No Guide selected list may contain a `WIN-TEST-006A` commit-manifest path defined by the amendment. A collision, materially changed Guide baseline, requested playback-owner edit, or failed live playback attempt stops the current sequence for reviewed replan.

Package G0 is the only unconditional performance package. The functional continuous-lineup repair and the parity-first visual/settings work are explicit product requirements. Incremental DOM pooling, cache enlargement, concurrency changes, and GPU work remain evidence-gated even though their seams are recorded below.

### Process and trust ownership

- Electron main continues to own persisted Settings, eligible-channel enumeration, channel sorting, source resolution, schedule calculation, request authorization, and currentness rechecks.
- Preload continues to expose the existing narrow validated Settings and Guide methods. No raw Electron, Node, Plex, filesystem, source identity, token, header, native value, or free-form diagnostic crosses it.
- Renderer owns only renderer-safe sparse Guide window state, viewport/range calculation, request intent, focus/navigation, DOM reconciliation, presentation state, and ephemeral performance marks.
- Contracts continue to expose renderer-safe channel/program view models and the existing `{ offset, total }` channel window. The continuous-lineup design must first use the existing paged request/result contract.
- Native/helper ownership is unchanged. Guide HTML/native composition changes require the existing WS5 Windows proof rather than a new helper seam.

### Continuous lineup owner

Add one cohesive renderer Guide-window owner, expected near `src/renderer/guideChannelWindow.ts`, with these responsibilities:

- represent the eligible lineup as a sparse absolute-indexed window using `channelWindow.total`, loaded page offsets, and renderer-safe channel rows;
- key and merge pages only for the current server/profile identity, lineup revision, library scope/filter revision, time range, past-window, row density, performance profile, and request generation;
- expose the visible absolute row range, explicit loading placeholders for missing rows, and the next required foreground window;
- retain the current visible and focused windows while applying a finite LRU to other pages;
- invalidate on server, profile, library filter, lineup generation, time range, past-window, row-density, and performance-profile changes;
- never infer channel identity, source identity, or program data for unloaded rows; and
- never make an unloaded placeholder focusable, tunable, or accessibility-visible as a real program; and
- project explicit inert loading or retryable error rows for missing/failed windows, never silent blanks or fabricated channels.

`guidePresentationPolling.ts` remains the request/cancellation/currentness owner and consumes window intents. It retains one active foreground request plus one latest trailing foreground intent. Idle warming is lower priority, cancelable, and forbidden in `Reduced resource`. `src/renderer/index.ts` remains wiring-only: scroll/input callbacks delegate semantic intents and do not own paging, cache, or density policy.

The virtual grid must use the absolute eligible row count rather than `presentation.channels.length` for total spacer geometry. The mounted range stays bounded to no more than 24 real/loading rows and 400 live program cells unless Package G0 measurements and a reviewed amendment change those caps. A fast scrollbar jump may briefly show labeled loading placeholders, but never a silent empty grid; the target window must receive foreground priority.

### Navigation and settlement

- Wheel and scrollbar movement request the visible absolute window automatically.
- Up/Down crossing a loaded boundary requests the next/previous window, retains one semantic focus target, and restores focus only after the current row/program is loaded and connected. The focused row remains pinned/connected until explicit navigation or a deterministic invalidation fallback selects the nearest eligible current row.
- Page Up/Page Down move by the current count of complete visible rows, not a fixed five, clamp at lineup boundaries, and preserve the selected column/time intent.
- Pointer and gamepad navigation use the same absolute row and currentness rules.
- Ordinary wheel/scrollbar movement must not snap back to the previously focused row.
- A stale, canceled, timed-out, old-scope, old-window, old-density, or old-profile result cannot replace current rows or focus.
- Polling refreshes the current visible absolute window and must not reset the user to offset zero.
- Loading, no-channel, no-program, error, retry, and recovery states remain distinguishable. Unloaded rows use loading presentation, not no-program presentation.

### PC display and resource policy

Settings schema version 3 adds:

- `guideTimeRange: 'detailed' | 'wide'`;
- `guideRowDensity: 'auto' | 'comfortable' | 'compact'`; and
- `guidePerformanceProfile: 'auto' | 'reduced-resource'`.

It removes `guideDensity` and `aggressiveGuidePreloadEnabled`; version 3 retains no compatibility alias. Main-owned Settings migration maps version 2 as follows:

- `guideDensity: 'comfortable'` becomes `guideTimeRange: 'detailed'`;
- `guideDensity: 'compact'` becomes `guideTimeRange: 'wide'`;
- `aggressiveGuidePreloadEnabled: true` becomes `guidePerformanceProfile: 'auto'`;
- `aggressiveGuidePreloadEnabled: false` becomes `guidePerformanceProfile: 'reduced-resource'` to preserve the user's prior resource behavior; and
- `guideRowDensity` becomes `auto`.

New/missing Settings default to `guideTimeRange: 'detailed'`, `guidePerformanceProfile: 'auto'`, and `guideRowDensity: 'auto'`. Version 1 records migrate directly to version 3 while mapping historical `guideDensity` to the matching time range, preserving the other three historical values, and using `reduced-resource` for the performance profile to match the former conservative default. Each valid migration increments revision exactly once and atomically replaces the record. A corrupt record loads as the existing revision-zero `corrupt` snapshot and its original bytes remain untouched until the user performs the existing exact revision-zero replacement; that explicit repair atomically writes a valid version-3 record. A future/unsupported version rejects replacement and always preserves its bytes. An older version-2 binary must treat a version-3 record as unsupported without rewriting it. There is no down-migration, browser-storage fallback, or compatibility alias in version 3.

Row-density behavior is frozen as follows:

- `Comfortable` preserves the upstream-like 108 px schedule-row treatment.
- `Compact` uses a reviewed compact treatment with a 72 px target row and removes only secondary row metadata that cannot fit; channel number, channel name, program title/time, live/current/past state, focus ring, and tune/current indicators remain readable.
- `Auto` chooses the largest readable row size between the Compact and Comfortable treatments that meets the viewport floor below. It derives from measured Guide grid height and recomputes on resize/DPI/layout change without changing the selected channel/time.
- 3840 x 2160 at 100% shows at least 20 complete schedule rows in Auto, with no clipped partial row.
- 1920 x 1080 at 100% shows at least 8 complete rows in Auto.
- 1280 x 720 and supported high-DPI/narrow windows show at least 5 complete rows without clipping or unreadable focus treatment.

`Reduced resource` does not change row density, time range, or channel availability. It uses the same foreground viewport request and DOM correctness but disables idle page/time warming, limits retained presentation pages/programs to the existing default bounds, and uses conservative artwork predecode/retention. `Auto` may use the existing aggressive upper bounds of 12 cached entries/12,000 programs and idle adjacent-window warming only after Package G0 proves resource plateau and foreground priority. Both profiles retain the existing main response caps of 200 programs per row and 1,000 total programs.

### Visual parity policy

This is a parity-first correction, not a new visual language. Use the current upstream `code-health` Guide at audited baseline `0258dbe15b04d2d141d0a4a44575fecb5bb72d41`; before the visual-parity package, confirm the relevant current remote files are unchanged or refresh the reference and re-review.

The current single Guide artwork reference cannot express the required upstream poster/background/clear-logo hierarchy. Extend the renderer-safe result on the existing Guide presentation operation with one exact nullable set: `poster`, `background`, and `logo`, each an opaque self-owned artwork reference or `null`. Strict contracts and preload validation reject extra keys or non-opaque locators.

The privileged artwork policy is frozen:

- `poster` may bind only to a normalized existing item `thumb`/`showThumb` locator matching `/library/metadata/<numeric-id>/thumb` with one optional numeric timestamp segment;
- `background` may bind only to an existing item `art` locator matching `/library/metadata/<numeric-id>/art` with one optional numeric timestamp segment;
- `logo` is `null` in this plan because Desktop currently has no validated clear-logo source/locator. The renderer uses the upstream title fallback. Adding a logo locator requires a reviewed Plex domain/parser/transport amendment rather than admitting arbitrary paths;
- `GuideArtworkOwner.createRef` accepts the closed role and rejects a role/locator-family mismatch;
- authorization reuse is keyed by current Plex artwork session generation, lineup revision, role, and normalized locator. Reuse returns the same unexpired ref id across 15-second polls; display alt text remains per projected ref and is not part of authorization identity;
- reuse does not extend the existing 15-minute expiry. Session-generation change, disposal, or expiry revokes the authorization and cached bytes. At the existing 6,000-live-ref cap, expired refs are reclaimed and a still-full owner returns `null`; it does not evict a live authorization or widen the cap;
- existing fetch concurrency (4), byte/cache caps (32 entries/24 MiB), same-origin containment, timeout, MIME, and response-size rules remain; and
- renderer fetches only the selected visible poster/background refs. No Plex locator, URL, token, path, raw key, source identity, or new IPC operation crosses the boundary.

Missing background/logo roles fall back deterministically to the available poster or theme/title treatment. G3 tests must prove role allowlists, role mismatch rejection, same-poll and repeated-poll reuse, expiry, generation invalidation, cap behavior, arbitrary locator rejection, selected-only fetch, and fallback behavior.

Desktop must match, at behavior and hierarchy level:

- Classic and Overlay shell composition, including native-video reservation/PIP behavior where supported;
- rich selected-program information hierarchy using renderer-safe artwork/backdrop/poster/clear-logo availability, title, subtitle/episode, time, genres/tags/quality, and bounded description;
- channel-number/name rail, tuned/current-channel distinction, program-cell expansion/selection, 30-minute ruler, current-time marker, and current/past/future styling;
- All/per-library tabs, Now Watching presentation, loading/empty/error/retry states, artwork fallback, and focus handoff;
- upstream typography hierarchy, spacing rhythm, color roles, focus outline, selected/current contrast, artwork treatment, and density/layout variants.

PC divergence is limited to responsive use of additional width/height, the row-density and resource profiles above, pointer/wheel/scrollbar affordances, Desktop-safe artwork references, main-owned persistence, and native composition. WebOS blur, raw assets, source paths, browser persistence, and device-specific APIs are not parity requirements.

No upstream production source or asset is copied in the initial implementation. Upstream is reference-only. If the visual package materially copies or adapts the audited shell, virtualizer, focus, info-panel, markup, CSS, logic, or assets rather than independently re-expressing behavior in current Desktop owners, stop and add a new exact source/destination/provenance row to `docs/architecture/import-ledger.md` before or with that change. Historical Guide row `613b1c5` does not cover a new current-upstream adaptation.

### Performance evidence and optional optimization

Package G0 owns the exact trace marks and cohorts defined in the bug report: accepted input/focus, request lifecycle/cache class, state acceptance, Guide reconcile start/end, and Chromium frame presentation. It captures separate same-buffer, renderer-cache, source-cache, cold-live, quiet-poll, and poll-collision cohorts.

Whole-subtree replacement, repeated Guide view projection, source-cache churn, request contention, and GPU-disabled composition remain hypotheses until those traces assign cost. A persistent keyed DOM pool/reconciler is authorized only by evidence that Guide reconciliation/layout/presentation dominates. Cache/concurrency changes are authorized only by measured distinct-source churn, queue wait, miss cost, or foreground starvation. GPU changes are outside this plan unless a reviewed amendment incorporates the native-composition A/B campaign.

### File-shape dispositions

Any touched production owner over 500 lines records the required cohesion disposition before implementation review. The expected attention surfaces are:

- `src/renderer/index.ts`: composition root; wiring-only growth, mandatory fresh architecture review.
- `src/renderer/guidePresentationPolling.ts`: current request/cache/currentness lifecycle; keep request custody cohesive and extract the sparse channel-window state because it is a distinct renderer lifecycle.
- `src/renderer/epg.ts`: >800-line Guide state/navigation projection; keep semantic EPG navigation cohesive, do not add DOM or persistence policy, and require fresh architecture review.
- `src/renderer/epg/guideDom.ts`: Guide DOM/layout owner; parity composition is cohesive, while a persistent grid lifecycle is extracted only if G0 proves it is required.
- `src/contracts/settings.ts` and `src/main/persistence/desktopSettingsStore.ts`: strict Settings contract/migration owners; version 3 growth is cohesive and requires persistence/contract review.
- `src/renderer/settingsSetup.ts`: Settings presentation/action owner; Guide value changes are cohesive but require fresh architecture review when touched.
- `src/main/channel/guideRuntime.ts`: main Guide page/schedule/currentness owner; artwork-role projection is cohesive only while it remains renderer-safe and on the existing operation, and requires fresh architecture review when touched.
- G0 proof owners use these reviewed hard line caps: `src/main/guideWindowsProofController.ts` <=550, `src/main/guideWindowsProofAnalysis.ts` <=500, `tools/guide-proof-artifact-publisher.mjs` <=300, new `src/main/guideWindowsProofSampleAnalysis.ts` <=450, new `src/main/guideWindowsProofResourceSoak.ts` <=400, new `src/renderer/guideProofResourceOwner.ts` <=250, `src/renderer/guideVirtualization.ts` <=275, `src/contracts/guidePerformance.ts` <=180, and `src/main/singleInstanceOwner.ts` <=150. The controller remains orchestration-only, the existing analyzer remains raw-trace sanitation/diagnostics plus delegation, the publisher remains artifact validation/aggregation/publication, the single-instance owner remains lock/secondary-notification policy, and the new owners hold distinct sample-analysis, soak-analysis, and renderer resource-observation policy. Do not evade a cap through compressed formatting, forwarding wrappers, mirrored cache state, or an unreviewed helper.

Fresh architecture review is mandatory whenever this plan touches `src/renderer/index.ts`, `src/renderer/epg.ts`, `src/renderer/epg/guideDom.ts`, `src/renderer/guidePresentationPolling.ts`, `src/main/channel/guideRuntime.ts`, or `src/renderer/settingsSetup.ts`, regardless of final line count.

## Files In Scope

Plan and evidence:

- `docs/plans/2026-08-10-guide-continuous-lineup-visual-parity-plan.md`
- `docs/development/guide-large-lineup-performance-parity-bug-report.md`
- the ignored `docs/runs/windows-manual-validation/2026-08-10-lineup-desktop/*` session bundle for raw/operator proof only
- `docs/product/lineup-product-parity-matrix.md`, `docs/architecture/CURRENT_STATE.md`, `docs/architecture/renderer-architecture.md`, and `docs/roadmap/desktop-port-roadmap.md` only when a package produces a reviewed durable status change
- `docs/architecture/import-ledger.md` only if upstream source or assets are copied/adapted

Renderer Guide and Settings owners:

- `src/renderer/guideVirtualization.ts`
- `src/renderer/guidePresentationPolling.ts`
- `src/renderer/guidePresentation.ts`
- `src/renderer/epg.ts`
- `src/renderer/epg/*`
- `src/renderer/focusDom.ts` only for measured Guide-scoped registration/reveal behavior
- `src/renderer/settingsSetup.ts`
- `src/renderer/settings/*` when required by version 3 values
- `src/renderer/styles/guide-epg.css` and directly related Guide styles
- `src/renderer/index.ts` for wiring only
- `src/renderer/guideProofResourceOwner.ts` only for G0's fixed-schema, inert-until-requested resource observation
- one new cohesive renderer Guide-window owner and, only if measured, one Guide grid lifecycle owner

Contracts, preload validation, main Guide/Settings, and tests:

- `src/contracts/guide.ts` and `src/contracts/artwork.ts` for the exact nullable poster/background/logo renderer-safe set on the existing Guide operation
- `src/contracts/settings.ts` and its existing validation owners
- existing preload Guide/Settings validators and bridge tests required by strict version 3 values; no new IPC method
- `src/main/channel/guideRuntime.ts`, `src/main/channel/guideArtworkOwner.ts`, and the existing public-reference owner for the exact safe artwork roles and any measured request-policy/currentness correction; the existing paged operation remains
- `src/main/plex/livePlexTransport.ts` only for the exact numeric `/thumb` and `/art` Guide artwork locator families and their containment/transport tests
- `src/main/persistence/desktopSettingsStore.ts` and existing Settings policy/snapshot consumers for version 3 migration
- focused Guide, Settings, preload, persistence, renderer DOM/focus, smoke, and performance-harness tests under `src/__tests__/*`
- the existing production-build/manual proof harness surface selected by Package G0; no replacement general harness

G0's reviewed selected boundary contains exactly these forty-two paths:

- `package.json`
- `tools/smoke-electron.mjs`
- `tools/guide-windows-proof.mjs`
- `tools/copy-renderer-assets.mjs`
- `tools/guide-proof-artifact-publisher.mjs`
- `tools/__tests__/smoke-electron.test.mjs`
- `tools/__tests__/guide-windows-proof.test.mjs`
- `tools/__tests__/copy-renderer-assets.test.mjs`
- `tools/__tests__/guide-proof-artifact-publisher.test.mjs`
- `src/main/smokeBootstrapOwner.ts`
- `src/main/singleInstanceOwner.ts`
- `src/main/guideWindowsProofController.ts`
- `src/main/guideWindowsProofAnalysis.ts`
- `src/main/guideWindowsProofSampleAnalysis.ts`
- `src/main/guideWindowsProofResourceSoak.ts`
- `src/main/channel/guideWindowsProofFixture.ts`
- `src/main/channel/channelComposition.ts`
- `src/main/channel/guideRuntime.ts`
- `src/main/index.ts`
- `src/domain/channel/contentResolver.ts`
- `src/domain/channel/sourceResolutionCache.ts`
- `src/contracts/guidePerformance.ts`
- `src/renderer/guidePerformanceMarks.ts`
- `src/renderer/guideProofResourceOwner.ts`
- `src/renderer/guideVirtualization.ts`
- `src/renderer/guidePresentationPolling.ts`
- `src/renderer/epg/guideDom.ts`
- `src/renderer/index.ts`
- `src/__tests__/main/smokeBootstrapOwner.test.ts`
- `src/__tests__/main/singleInstanceOwner.test.ts`
- `src/__tests__/main/guideWindowsProofController.test.ts`
- `src/__tests__/main/guideWindowsProofAnalysis.test.ts`
- `src/__tests__/main/guideWindowsProofSampleAnalysis.test.ts`
- `src/__tests__/main/guideWindowsProofResourceSoak.test.ts`
- `src/__tests__/main/guideWindowsProofFixture.test.ts`
- `src/__tests__/main/guideRuntime.test.ts`
- `src/__tests__/domain/channelDomain.test.ts`
- `src/__tests__/contracts/guidePerformanceContracts.test.ts`
- `src/__tests__/renderer/guidePerformanceMarks.test.ts`
- `src/__tests__/renderer/guideProofResourceOwner.test.ts`
- `src/__tests__/renderer/guidePresentationPolling.test.ts`
- `src/__tests__/renderer/guideVirtualization.test.ts`

The first reviewed expansion from the approved thirty-three-path boundary was exactly `src/main/guideWindowsProofSampleAnalysis.ts`, `src/__tests__/main/guideWindowsProofSampleAnalysis.test.ts`, `src/main/guideWindowsProofResourceSoak.ts`, `src/__tests__/main/guideWindowsProofResourceSoak.test.ts`, `src/renderer/guideProofResourceOwner.ts`, `src/__tests__/renderer/guideProofResourceOwner.test.ts`, and `src/renderer/guideVirtualization.ts`. The accepted no-interruption amendment adds exactly `src/main/singleInstanceOwner.ts` and `src/__tests__/main/singleInstanceOwner.test.ts`, taking the boundary from forty to forty-two. Both expansions and the complete forty-two-path boundary have zero overlap with all twenty-one `e7f1338` paths. Any further path is a collision/replan event rather than an implicit expansion.

## Files Out Of Scope

- all concurrent playback-remediation changes under `src/main/player/*`, `src/main/plex/*`, and their tests
- native helper protocol/host/binary, native HWND ownership, and player command/runtime contracts
- Plex auth, discovery, credentials, media-detail, or stream-resolution contracts; Plex transport is out of scope except the exact Guide `/thumb` and `/art` locator allowlist named above
- channel builder, scheduler semantics, channel persistence schema, source format, and lineup generation
- packaging, installer, updater, release signing, and unrelated CI workflows
- broad Electron shell/security changes or new renderer privilege
- unrelated Settings categories or a redesign of the global application shell
- the user-modified active Tier 3 correction plan except a separately reviewed sequencing/status amendment by its current owner

## Execution Packages

Packages are serial unless a package explicitly authorizes read-only sidecars. Each package ends with focused tests, risk-matched verification, independent review, a conventional commit, and a fresh worktree/collision check. Do not carry unreviewed changes into the next package.

### G0 — Instrumented Windows baseline and frozen visual reference

Outcome:

- reproduce ordinary wheel/scrollbar content exhaustion beyond twelve with a known initial focus and request trace;
- add the eight fixed categorical/numeric semantic Guide marks `input-received`, `input-accepted`, `request-start`, `request-settled`, `state-accepted`, `reconcile-start`, `reconcile-end`, and Chromium `frame-presented`; `state-accepted` always means requested product state became eligible to render and is never a harness delimiter;
- record the exact 459-channel source cardinality/cache classes and separate input, request, reconcile, layout/paint, and presented-frame timing;
- capture sanitized paired current-upstream/Desktop references for Classic/Overlay and required viewports/states;
- freeze the current package budgets and decide whether later incremental DOM, cache/concurrency, or GPU work is actually required.

Write boundary: Guide-specific fixed marks, a proof-only main-owned tracing/controller seam gated by the existing validated smoke/proof capability, the exact forty-two-path boundary above, `tools/guide-windows-proof.mjs`, its package-script entry/tests, and the local ignored proof bundle; no product visual or optimization change and no renderer-facing application API.

G0 additionally authorizes exactly two resource-handshake records, distinct from the eight product-semantic marks and the separately defined sample-boundary record below:

- main's validated proof controller emits `lineup-guide-proof-v1:resource-request` with the exact closed detail `{ schemaVersion: 1, requestId, run, cycle, phase, cohort, sample }`, where all ids are bounded nonnegative integers, `phase` is one of `pre-entry`, `soak`, `post-exit`, `reentry`, or `post-reentry-exit`, and `cohort` is a closed G0 cohort id or `none`;
- the renderer resource owner observes only a valid request and emits one correlated `lineup-guide-proof-v1:resource-snapshot` with the same identity plus the fixed numeric resource fields below.

This handshake is inert until the validated main proof controller emits an exact request. It is proof-only User Timing evidence, not an application command surface: no preload/IPC method, `window`-callable or other global hook, DOM proof field, renderer privilege, persistent value, private text, arbitrary key, or free-form field is allowed. The renderer observer disconnects during normal renderer cleanup; every request and response mark is cleared after emission. A malformed, duplicate, unsolicited, mismatched, or unpaired record fails or is ignored according to the closed contract and cannot affect product behavior.

The response's exact additional keys are `heapAvailable`, `usedJsHeapBytes`, `totalJsHeapBytes`, `domNodes`, `guideRows`, `guideCells`, `guideAccessibilityTargets`, `performanceEntries`, `guideInputListeners`, `activeAbortListeners`, `pollTimers`, `pollScheduled`, `distanceToNextPollMs`, `idleCallbacks`, `requestTimeouts`, `activeRequests`, `trailingRequests`, `pendingPageRequests`, `warmCandidates`, `presentationCacheEntries`, `presentationCachePrograms`, `presentationCacheEntryLimit`, `presentationCacheProgramLimit`, `viewportWidth`, `viewportHeight`, and `devicePixelRatio`. Every value is a bounded nonnegative finite number; `heapAvailable` and `pollScheduled` are exactly 0 or 1. Unavailable heap bytes and unscheduled poll distance are present as 0 only while the corresponding availability flag prevents them from being interpreted as observations. No extra key is accepted.

### G0 sample, cohort, and frame contract

Harness sample boundaries use a separate fixed `lineup-guide-proof-v1:sample-boundary` record with bounded numeric run/sample/boundary identity, a closed cohort id, and `phase: start | end`. They never impersonate a semantic product mark. Every measured sample must contain exactly one expected accepted input between its exact start/end boundaries. The analyzer binds, without reuse, the matching received/accepted input, expected renderer request start/settle when applicable, exact main runtime request slice when applicable, relevant state/reconcile events, and the first allowed presented frame after the applicable semantic terminal event and before that sample's end boundary. A global later frame, a frame after sample end, an event reused by another sample, or an unrelated request cannot satisfy coverage.

Each raw sample and each per-run/per-cohort row stores only fixed categorical fields and bounded numbers. Every scalar timing/count field is exactly `number | 'not-applicable'`; absent events are never zero-filled. Exact scalar keys are `acceptedToReconcileEndMs`, `acceptedToPresentedFrameMs`, `stateAcceptedToPresentedFrameMs`, `rendererRequestDurationMs`, `mainRequestDurationMs`, `layoutDurationMs`, `paintDurationMs`, `longTaskCount`, `longTaskDurationMs`, and `distanceToNextPollMs`. A sample with an exact main request additionally retains `sourceSettlements`, an ordered array of at most the request's channel limit of 24 fixed `{ sourceClass, durationMs }` records; a sample with no main source settlement uses `sourceSettlements: 'not-applicable'`, not an empty array or synthetic zero. Per-run/cohort `sourceSettlementDurationMs` p50/p95/max is computed over the flattened raw settlement durations, never over per-request averages. Same-buffer request/state/source fields, renderer-cache main/source fields, and other structurally absent values are `not-applicable`. Polling's selected owner supplies its next monotonic deadline. Immediately before every measured input, the controller sends a resource request with the same run/cohort/sample identity; the correlated snapshot supplies `pollScheduled` and `distanceToNextPollMs`. The analyzer projects the distance as a number only when scheduled and otherwise as `not-applicable`, never as a false zero.

Use only the official exact Chromium M148 presented-frame signatures confirmed for the Electron 42 runtime: `FrameSequenceTracker` with categories containing `cc` and `benchmark` and exactly `args.step === 'FramePresented'`, or `Display::FrameDisplayed` with categories containing `benchmark`, `viz`, and `disabled-by-default-display.framedisplayed`. The sanitizer chooses one canonical family for a run and never mixes families to manufacture coverage. Generic top-level `FramePresented`, `FrameSequenceTracker` without the exact step, and `devtools.timeline.frame` scheduler diagnostics are not presentation proof. If the exact emitted M148 argument location, category signature, or target-renderer-main attribution cannot be observed reliably, stop for a reviewed evidence amendment; do not fall back to a nested guessed step, generic frame name, `requestAnimationFrame`, or inferred paint.

Trace configuration uses `excluded_categories: ['*']`, explicitly includes `benchmark`, `viz`, `cc`, `disabled-by-default-display.framedisplayed`, `devtools.timeline`, and `toplevel`, and omits a process-id restriction so Electron content tracing captures all processes. Layout/paint accepts only target-renderer-main-thread duration events named `Layout`, `UpdateLayoutTree`, `PrePaint`, `UpdateLayerTree`, or `Paint` under `devtools.timeline`, parsing complete `dur` slices or matched `B`/`E` pairs in trace microseconds. These are lifecycle/paint cost, not presentation. Long-task evidence accepts any complete `toplevel` slice attributed to the target renderer main thread with duration >=50,000 microseconds; scheduler task names vary and must not be hard-coded. Failure to obtain deterministic renderer-main attribution or authoritative duration event shapes is a stop condition rather than `0` evidence.

Actual presented-frame proof requires a visible native proof window. Guide proof mode, and only Guide proof mode, may show its native window for bounded sampling; ordinary smoke keeps its existing hidden-window behavior. Live preflight must first prove it owns the primary instance and is not interrupting an existing user session, so it refuses rather than stealing focus. If a visible presentation surface cannot be established, stop/replan. Hidden-renderer Layout/Paint is never accepted as display proof. Electron content tracing is parsed only after recording stops; the fixed harness boundaries delimit action windows in the completed trace.

Live preflight still requires the operator's normal app to be closed before launch. The race after that preflight is fail-closed and noninterrupting. Only after the child has authoritatively validated its complete Guide-proof capability, it passes Electron's single-instance lock one exact closed additional-data marker `{ lineupSecondInstance: 'guide-proof-v1' }`; no nonce, proof root, user-data path, argv, environment value, or other private field is included. An existing primary recognizes only that exact one-key marker and suppresses restore/show/focus and all argv/deep-link routing for that notification. It does not validate, start, resume, or otherwise trust the proof. The proof child that loses the lock exits nonzero before proof controller/window/tracing startup, produces no trace/summary/final evidence artifact, and lets the launcher remove its temporary bootstrap root. Missing, malformed, extra-key, argv-only, or normal second-instance data follows the existing normal restore/show/focus behavior unchanged.

Race acceptance covers both lock orders. If normal Desktop wins, the proof child exits nonzero and the existing window remains completely untouched. If validated proof wins, a later normal launch retains the normal secondary-instance behavior against the bounded visible proof primary; it cannot be reclassified as proof. The main composition root supplies only the already validated child mode and exit wiring. `singleInstanceOwner.ts` exclusively owns the lock additional-data shape, exact marker recognition, suppression, normal-secondary behavior, and proof-secondary nonzero exit policy.

Cohort binding is exact:

- `same-buffer` contains wheel/scroll work that intentionally remains inside the loaded buffer and has no request;
- `directional` binds arrow/gamepad accepted inputs and rejects an unintended boundary request;
- `renderer-cache` binds one foreground renderer request settled as `renderer-cache` and zero main requests;
- `source-cache` prepares outside the sample, then binds one measured foreground Page request using a new renderer key over already resolved sources, exactly one main request, cache-hit source settlements, and no cold source settlement;
- each live process run's `cold-live` cohort dispatches and binds one accepted Page action to an unseen window, one exact foreground main request with at least one cold settlement, an accepted loading/focus-intent reconcile/presented frame, and a separately bound final accepted-state/presented frame; an earlier cold request or a record with no dispatched input is invalid;
- `quiet-poll` binds one exact `poll-interval` request that settles before its input sample set, then requires zero renderer and main requests inside every one of its 100 sample boundaries. All 100 samples must finish before the next scheduled poll; an intervening interval invalidates and restarts the cohort rather than being relabeled as quiet; and
- `poll-collision` first proves the active/trailing queue is empty, arms the proof latch, binds the exact renderer `poll-interval` request and its bounded main request, accepts the collision input while that request is held, and releases it. A leftover foreground request fails origin/request binding.

After one discarded warm-up, every run contains exactly 100 measured samples for each applicable `same-buffer`, `directional`, `renderer-cache`, `pointer`, and `quiet-poll` cohort, plus exactly one `poll-collision` sample. Every live run additionally contains exactly 100 `source-cache` samples and one `cold-live` sample. Synthetic `source-cache` and `cold-live` rows are present as `not-applicable`; synthetic evidence never claims live Plex/source-cache proof. The 100-sample same-buffer and directional cohorts are independent and are never satisfied by splitting or combining smaller mixed-input runs.

Every run emits a complete cohort matrix and raw bounded samples. Top-level summary contains `runs[]` and `aggregateByCohort[]`; p50/p95/max are recomputed from raw samples, never averaged or derived from child percentiles. Each live child contains exactly one local run. The publisher validates all three children, assigns top-level process-run identities 1 through 3, rejects missing/duplicate/mislabeled/undersized cohorts, creates the three-run aggregate, retains each child trace/summary under `runs/run-N`, and writes a top-level run-indexed trace record rather than presenting run 1 as the whole live trace.

### G0 exhaustion diagnostic and resource soak

Before performance cohorts, reproduce the reported defect without fixing it. Establish the known first window and top scroll position, focus a known first-page program, record start offset/eligible total/scroll top/scroll height/client height/focus index, then dispatch sustained downward wheel input through the terminal twelfth loaded row. Next drive the native scrollbar to its maximum. Record end offset/total/scroll extent/focus, accepted wheel and scroll counts, and whether a next absolute-window foreground request occurred. The diagnostic passes only by honestly recording absence or presence of that request and whether content remains exhausted at the first twelve; it must not alternate direction, use a 48 px nudge, or claim G2's continuous-window fix.

Resource evidence has no renderer-private probing. `guidePresentationPolling.ts` supplies truthful fixed numeric counts for active/trailing/pending requests, poll timer, idle callback, request timeout, abort listener, warm candidates, its next poll deadline, and its presentation cache. `GuidePresentationLru` supplies its exact entry/program counts and active profile limits; mirrored cache accounting is forbidden. `renderer/index.ts` only wires the resource owner and records the six actual Guide listener registrations/removals adjacent to those operations. Renderer snapshots also contain heap availability/used/total bytes, DOM nodes, Guide rows/cells, accessibility targets, performance-entry count, viewport dimensions, and DPI. Main adds exact numeric fields `processCount`, `cpuPercent`, `workingSetKb`, `privateBytesKb`, `browserProcessCount`, `rendererProcessCount`, `gpuProcessCount`, `utilityProcessCount`, `otherProcessCount`, `activeMainGuideRequests`, `sourceCacheEntries`, `sourceInFlightEntries`, `sourceGenerationKeys`, `sourceParentDependencyKeys`, `sourceChildDependencyKeys`, and `showCacheEntries` directly from their selected owners; none crosses to renderer and no process id is retained.

The main soak owner correlates exactly one snapshot to each request id within two seconds, then captures main metrics. Duplicate, mismatched, late, or missing responses fail. Heap unavailability is recorded explicitly and is not represented as an observed zero.

For each process run, use existing trusted F3 navigation to reach Settings. Assert `activeRoute === 'settings'` and quiescence before every non-Guide snapshot: active/trailing/pending requests, request timeout, abort listener, poll timer, idle callback, and warm candidates are all zero. Capture `pre-entry`; enter Guide through trusted F2 input; discard the warm-up; execute at least 100 complete input/settlement cycles; and capture observations at cycles 0, 10, 20, 30, 40, 50, 60, 70, 80, 90, and 100. Then use F3 to return to Settings, assert the same route/quiescence, and capture `post-exit`. Re-enter through F2, perform a bounded warm re-entry, capture `reentry`, return through F3, reassert Settings/quiescence, and capture `post-reentry-exit`.

Plateau comparison is deterministic:

- the earlier window is cycles 60, 70, and 80; the later window is cycles 80, 90, and 100; cycle 80 is the fixed shared boundary observation;
- for discrete retained counts, `max(later) <= max(earlier)` and the least-squares slope across cycles 60, 70, 80, 90, and 100 must be <=0; transient active counts at observation points must remain within the explicit bounds below;
- renderer Guide rows are <=24 and cells are <=400; DOM/accessibility counts use the same no-positive-trend rule; presentation cache is <= its reported profile limit of 6/12 entries and 6,000/12,000 programs; active requests <=1, trailing requests <=1, pending Page requests <=1, poll timers <=1, idle callbacks <=1, request timeouts <=1, abort listeners <=1, and warm candidates <=4;
- source cache is <= its retained owner cap of 24, source in-flight and active main Guide requests are zero at observation points, and retained source generation/dependency/show-cache counts use the same later-max/earlier-max and nonpositive-slope rule because no lower product cap is authorized by G0;
- used renderer heap passes when `median(later) - median(earlier) <= max(8 MiB, median(earlier) * 0.10)`; aggregate working set and private bytes each pass when the difference is <=`max(32 MiB, median(earlier) * 0.10)`; CPU/GPU are reported but are not retention counters; and
- `post-exit` and `post-reentry-exit` separately require zero active/trailing/pending requests, timers, idle callbacks, request timeouts, abort listeners, warm candidates, and presentation-cache entries/programs. Because the current route renderer retains hidden Guide DOM on Settings, Guide rows/cells/accessibility targets must return exactly to their respective `pre-entry` baselines and are required to be zero only when that baseline is zero. The six app-lifetime Guide input listeners likewise equal the `pre-entry` listener baseline rather than zero. Retained main source/cache/dependency counts must stay within owner caps and the baseline-relative plateau rule; G0 does not silently change their route-retention policy.

### G0 accepted implementation-review corrections before rerun

The next implementation pass must correct every accepted finding below before another synthetic or live evidence run:

- sample binding requires exactly one received input and one accepted input of the expected kind inside each boundary, rejects every extra received/accepted input of any kind, and prevents reuse of input, state, reconcile, renderer request, main request, layout/paint/long-task, and frame events across samples. Exact expected state counts/classes are cohort assertions, not a search for any convenient matching event;
- every run, including synthetic runs two and three, re-enters Guide through trusted F2, asserts `activeRoute === 'guide'`, establishes focus/quiescence, and completes its cohort matrix before that run's soak may exit through F3;
- source-cache preparation waits for its exact renderer and main request settlement before the measured boundary. Exact request binding uses one unambiguous bounded tuple of sample boundary, renderer request sequence/origin/offset/limit, main request sequence/offset/limit, and controller-observed runtime slice; ambiguous or additional same-window work fails. Raw classification is `renderer-cache` for a renderer hit, `main-source-cache` when all bounded main source settlements are cache hits, `cold-source` when any is cold, and `shared-source` when none is cold and any is shared in flight; `none` is not accepted for a completed main-backed cohort;
- cold-live schema distinguishes `loading-intent` from `final-data` state acceptance, records the real intended absolute target for both, and binds each class plus its distinct reconcile/presented-frame evidence. Two undifferentiated same-sequence state marks or target `-1` cannot pass;
- exhaustion begins only after offset zero, scroll top zero, valid eligible total, and a known actual focused Guide program are asserted. Sustained wheel and scrollbar-to-max use trusted Electron native mouse/wheel input against measured grid/scrollbar geometry, never a programmatic scroll mutation or synthetic DOM event. Counts come from accepted marks rather than constants, and the next-window result binds a foreground request with the expected changed absolute offset; polling or an unrelated main request cannot satisfy it;
- every soak cycle awaits its exact accepted input and semantic request/state/reconcile/frame settlement before the next cycle or observation. Plateau evaluation covers every frozen retained metric, including performance entries, app-lifetime listener baseline, timers, idle/timeout/abort owners, active/trailing/pending queues, warm candidates, presentation/source caches, dependency maps, DOM/accessibility, heap, and process memory. All frozen point bounds, slope/median formulas, post-exit zeros, and retained-main baseline-relative checks run; no unchecked metric may be reported as passed;
- publisher requires three distinct canonical live bootstrap roots and rejects aliases or repeated directories. Every child independently records and matches source/build/profile/eligible-total authority, run/sample identities, exact known cohort set, scalar/`not-applicable` shapes, bounded source-settlement shape, navigation/exhaustion checkpoints, resources, and sampling metadata. Top-level output preserves and indexes that evidence instead of dropping it; authority is captured per child rather than fabricated once after all children finish;
- remove every `window.__lineupGuideProof*` or other global proof hook and every proof-only DOM attribute, including Guide window offset/total fields added only for the harness. Controller waits use closure-scoped one-shot observers/promises and fixed trace records; product-owned focus/accessibility DOM may be read but is not widened for proof;
- trace target attribution binds the proof WebContents' actual renderer process/main thread, not the only convenient pid/tid pair. Every complete duration uses `[ts, ts + dur]`; every `B`/`E` pair uses its matched start/end interval; layout/paint/long-task evidence must be wholly contained by its sample boundary. Start-only or end-only attribution cannot pass; and
- the single-instance no-interruption policy above passes exact-marker suppression, malformed/missing/extra-marker normal behavior, proof-secondary nonzero exit/no-artifact behavior, normal-secondary behavior, teardown, and both race-order tests.

Acceptance:

- trace proves which inputs were accepted and whether/when a next absolute channel window was requested;
- no private lineup titles, tokens, URLs, paths, native handles, or raw screenshots enter tracked docs;
- `npm run build:electron` builds the exact Desktop checkpoint under test;
- `npm run proof:guide:windows -- --mode synthetic --channels 500 --runs 3 --samples 100 --output docs/runs/windows-manual-validation/2026-08-10-guide-remediation-g0/synthetic` launches the built Electron app through the validated proof capability with a disposable in-memory 500-channel/48-program fixture. It proves deterministic first/middle/last navigation, DOM/resource bounds, fixed input/reconcile/frame marks, and one discarded warm-up plus three independent 100-sample cohorts; it does not claim live Plex latency or source-cache proof;
- `npm run proof:guide:windows -- --mode live --expected-total 459 --runs 3 --samples 100 --output docs/runs/windows-manual-validation/2026-08-10-guide-remediation-g0/live` launches the built app against the operator's existing selected server/profile and refuses to start sampling unless the renderer-safe Guide result reports exactly 459 eligible channels. It never exports channel/program text or private identifiers. The proof-only main controller dispatches input and owns Chromium content tracing; renderer emits only the fixed categorical/numeric marks above;
- `npm --prefix ..\Lineup run dev -- --host 127.0.0.1` launches the audited current-upstream reference for operator-driven paired capture. `docs/runs/windows-manual-validation/2026-08-10-guide-remediation-g0/paired-visual-checklist.md` records the upstream/Desktop checkpoint, exact viewports/states, observed hierarchy, and redaction result; raw captures stay beside it in the ignored bundle;
- both proof modes fail rather than overwrite an existing output directory and write `manifest.json`, `summary.json`, `trace.json`, and `replay.txt`. The manifest records mode, Desktop/upstream commit, build hash, fixture kind or live eligible total, environment, runs/samples, mark schema version, cache/poll cohorts, artifact hashes, redaction status, and command. `replay.txt` contains the exact successful command with secrets and local user paths omitted;
- baseline records raw samples plus per-run and aggregate p50/p95/max, CPU/GPU/RAM, display/DPI, build, profile, source cardinality, cache state, request class, layout/paint, >50 ms long-task evidence, and `distanceToNextPollMs` for same-buffer, directional, renderer-cache, pointer, source-cache, cold-live, quiet-poll, and poll-collision cohorts, preserving `not-applicable` rather than false zeroes;
- candidate comparison gates are same-buffer reconcile p95 <=50 ms/max <=100 ms; arrow reconcile p95 <=16 ms and presented-frame max <=32 ms; warm page/wheel/pointer presented p95 <=100 ms; cold accepted loading intent <=100 ms; no sustained >50 ms long tasks; and a 100-cycle memory/DOM/accessibility/listener/timer/request/cache plateau with route-exit cleanup;
- plan is amended and re-reviewed only if measurements contradict the continuous-window or package assumptions.

### G1 — Settings version 3 and independent PC policies

Outcome:

- migrate main-owned Settings from version 2 to version 3;
- replace the experimental aggressive toggle with `Performance profile: Auto/Reduced resource`;
- replace `guideDensity` with `guideTimeRange` and present `Time range: Detailed (2h)/Wide (3h)`;
- add `Row density: Auto/Comfortable/Compact`;
- project accepted settings into Guide window/cache/layout owners without new privilege or browser storage.

Write boundary: existing Settings contracts/validation/store/snapshot/policy, preload validation, renderer Settings presentation, Guide setting consumers, and focused migration/contract tests.

Acceptance:

- missing/new, version 1, and version 2 records produce the exact version 3 values defined above;
- corrupt bytes produce the revision-zero `corrupt` snapshot and remain unchanged until an exact revision-zero replacement atomically repairs them as version 3; future/unsupported versions reject replacement and preserve bytes;
- compare-and-swap, strict exact-key validation, redaction, and atomic mode-0600 replacement remain intact;
- valid migrations increment revision exactly once; a version-2 binary encountering version 3 fails closed and preserves bytes;
- changing any Guide setting settles once, preserves eligible current focus where possible, cancels stale work, and invalidates only affected window/cache state;
- Reduced resource never reduces visible channel count or navigation reach.

Rollback: version 3 is a persistence boundary. Do not roll source back after a version 3 record has been written without an explicit backward-migration/recovery decision. Before release, retain the pre-G1 commit as the code rollback point and use disposable test profiles for migration proof.

### G2 — Continuous sparse lineup window and navigation

Outcome:

- add the renderer sparse absolute channel-window owner on the existing paged Guide contract;
- replace literal twelve/twenty-four foreground request selection with the complete visible row count plus bounded overscan, clamped to 24;
- project total spacer geometry from the full eligible count;
- automatically fetch/merge visible windows for wheel, scrollbar, boundary arrows, viewport-sized Page keys, pointer, and gamepad;
- show bounded explicit loading/retry rows instead of silent blanks;
- preserve pinned focus, time column, currentness, cancellation, polling offset, and finite LRU behavior.

Write boundary: Guide window/virtualization/polling/navigation/DOM owners and focused tests; main/preload operations remain unchanged unless a proven blocker triggers replan.

Acceptance:

- a 459- and 500-channel fixture can traverse first, middle, and last rows through wheel/scrollbar, arrows, and Page keys;
- every settled real row has channel and program content or an explicit no-program state; missing/failed windows are visibly loading/retryable and fetch automatically;
- request count never exceeds the viewport-derived limit capped at 24; one active plus one latest trailing foreground intent remains true and foreground work preempts idle warming;
- focused row/cell remains connected after boundary loads until explicit navigation or deterministic fallback, stale responses cannot settle, and route/filter/profile changes release the sparse store;
- polling refreshes the current absolute window rather than offset zero;
- mounted real/loading/error rows remain <=24 and live program cells remain <=400.

Rollback: revert the G2 commit as one unit; the existing twelve/twenty-four page behavior returns without an IPC or persistence rollback.

### G3 — Current-upstream visual and interaction parity

Outcome:

- extend the existing Guide result with the exact nullable opaque poster/background/logo set and strict validation;
- correct the Guide shell, detail hierarchy, artwork treatment, channel rail, grid/ruler, cell states, tabs, Now Watching, loading/error/empty states, and Classic/Overlay variants to the current upstream reference;
- retain Desktop security/native boundaries and the independent PC density policy;
- remove superseded Desktop-only visual structures only when their behavior has a current parity owner.

Write boundary: renderer-safe Guide/artwork contracts and existing operation validators, Guide/public-reference/artwork main owners, renderer Guide view models/DOM/CSS/artwork projection, native presentation intent wiring when the existing contract already supports the layout, and focused contract/UI/focus tests. No new IPC operation and no upstream copy/adaptation without a new exact ledger row.

Acceptance:

- paired current-upstream/Desktop captures cover 1280 x 720, 1920 x 1080, 2560 x 1440, 3840 x 2160, resizable widths, and 100/125/150% scaling;
- controller and independent UI reviewer accept hierarchy, typography, spacing, focus, selected/current/past/future contrast, artwork fallback, tabs, ruler, states, and both layouts;
- keyboard, pointer, page, gamepad, current-only tune, future detail-only, Play-to-now, Back, filter persistence, and Now Watching behavior pass without a material parity finding;
- renderer fetches only selected visible artwork, and missing roles use deterministic poster/theme fallback without authorization growth across polls;
- no raw Plex/artwork URL, token, path, source identity, or native value enters renderer state or tracked proof.

### G4 — Responsive PC row density and complete-row geometry

Outcome:

- implement the frozen Auto/Comfortable/Compact row behavior against the completed parity shell;
- derive request/window size from measured complete visible rows plus bounded overscan;
- remove clipped partial rows at supported viewports/DPI;
- preserve focus, accessibility, forced colors, reduced motion, and time-range semantics through resize/DPI/layout changes.

Write boundary: Guide CSS/DOM geometry, pure virtualization/range calculation, Guide Settings consumers, and focused layout/viewport tests.

Acceptance:

- the 4K/1080p/720p complete-row floors in this plan pass at 100%, plus 100/125/150% DPI and supported resizable widths;
- Auto never selects a smaller readable treatment than Compact or a larger one than Comfortable;
- row-density changes do not alter time range, library filter, selected channel/time, or resource profile;
- no horizontal overflow, clipped focus ring, inaccessible buffer row, or wheel snapback.

### G5 — Evidence-gated performance remediation

Outcome:

- implement only the smallest measured optimization needed to meet the frozen G0 budgets;
- possible authorized seams are one Guide view computation per generation, Guide-scoped keyed DOM reconciliation, range-local focus registration, measured source/cache policy, or foreground/poll scheduling;
- skip this package when G1-G4 already satisfy budgets.

Write boundary: only the owner(s) named by the G0 trace and a reviewed G5 amendment. No speculative cache increase, worker, dependency, renderer privilege, or GPU change.

Acceptance:

- three warmed repetitions meet the reviewed handler/reconcile/presented-frame budgets in each required cache/request cohort;
- 100-cycle soak shows bounded/plateaued heap, working set, DOM, accessibility targets, timers, listeners, request queue, and page cache, with reviewed cleanup after Guide exit;
- the optimization has a focused regression test or deterministic harness assertion at its public owner seam and no material architecture/performance review finding.

### G6 — Windows/live consolidation and durable closeout

Outcome:

- run the full Windows production Guide campaign with 459+ live channels and native composition;
- record `WS5-PROOF-01` through `WS5-PROOF-06` fields applicable to Guide;
- reconcile stale parity-matrix rows and update current architecture/roadmap truth;
- close only rows supported by current artifacts.

Acceptance:

- physical keyboard/pointer/media/Page/gamepad focus/navigation, loading/retry/recovery, density/profile/layout changes, long soak, DPI/multi-monitor, and native video compositions pass;
- every proof record contains environment, build/checkpoint, exact row, steps, expected/observed result, sanitized artifact locator, redaction check, blocker owner, and replay command;
- independent UI, architecture, persistence, performance, and final implementation review has no material finding;
- raw proof remains ignored; only sanitized durable conclusions are tracked.

## Verification Commands

**Verification classification:** broader integration/manual proof required

Every product package runs its exact focused new/affected tests first. Before its commit/review checkpoint, run:

- `npm run typecheck` — no TypeScript error.
- `npm run build:electron` — production Electron build succeeds.
- `npm run verify:architecture` — no process-boundary or composition-root violation.
- `npm run verify:maintainability` — report reviewed; every touched >500-line or named owner has a cohesion disposition.
- `npm run verify:redaction` — no forbidden secret/path/native material.
- `npm run verify:docs` when tracked documentation changes.
- `npm run verify` — full repository verification passes before any implementation package is called complete.
- `git diff --check` — no whitespace error.

Focused proof must include:

- G0 contract tests for the eight semantic marks, the exact proof request/snapshot and sample-boundary schemas, malformed/unsolicited/duplicate/mismatched resource records, two-second correlation timeout, mark clearing, and renderer observer cleanup;
- G0 sample-analysis tests for sample-end-bounded canonical frame selection, uniqueness of every semantic/request/duration/frame event, rejection of extra inputs/states, exact accepted-input/request-origin/request-class/main-request binding, `number | 'not-applicable'` fields, cold-live loading/final schema, quiet-poll and poll-collision origin binding, settled and identity-separated source-cache preparation, authoritative proof-renderer-main layout/paint/long-task interval attribution, and `distanceToNextPollMs`;
- G0 controller/orchestration tests that complete the full matrix, re-enter Guide for runs two and three, and reject invalid cold, cache, poll, frame, route, and resource lifecycles; helper-only happy-path coverage or mocks that emit Guide marks while on another route are insufficient;
- G0 exhaustion tests for asserted known top/focus, trusted native sustained downward wheel plus scrollbar-to-max evidence, observed accepted counts, and exact foreground next-absolute-window request identity;
- G0 resource tests for semantic settlement of every cycle, exact LRU counts after replace/evict/clear, polling timer/queue/cache counters, listener registration/removal accounting, 99-cycle rejection, observations at 0/10/.../100, every frozen plateau formula/bound, Settings/F3 route and quiescence assertions, post-exit/re-entry cleanup, retained main-cache treatment, growing-metric counterexamples, and honest unavailable-heap reporting;
- G0 publisher tests for three distinct complete live child roots, per-child authority/shape validation, preservation of navigation/exhaustion/resource/sampling evidence, top-level run identities, raw-sample percentile aggregation, run-indexed trace output, and rejection of a repeated root, unknown/duplicate/missing/mislabeled/undersized cohort, invalid scalar/source-settlement shape, or authority mismatch;
- single-instance tests for exact proof marker suppression without window/argv effects, malformed/missing/extra marker normal behavior, normal secondary acquisition/focus behavior, proof-secondary nonzero exit before artifacts, teardown, and both lock-race orders;
- Guide sparse-window merge/invalidation/LRU/currentness tests with 459 and 500 channels;
- wheel/scrollbar/arrow/viewport-Page/pointer/gamepad boundary tests;
- real/fake DOM tests for total spacers, explicit loading rows, mounted caps, focus/accessibility registration, and cleanup;
- Settings version 1/version 2/version 3 migration, strict contract/preload, compare-and-swap, failed-write, and future-version tests;
- row-density/resize/DPI/forced-colors/reduced-motion tests at stable public seams;
- production Electron trace/soak proof using G0 markers and per-cohort sampling;
- paired current-upstream visual/manual proof and native-video composition proof.

Expected outcome: automated checks are green, Windows artifacts satisfy the exact package acceptance rows, reviewers find no material correctness/security/architecture/performance/visual issue, and no unrelated playback or user changes enter a Guide commit.

## Acceptance Criteria

- Ordinary vertical scroll traverses all 459 observed channels and a 500-channel boundary fixture; content does not stop after the first twelve.
- Fast scroll never presents silent blank rows. Unloaded absolute rows are explicit, inert loading rows and fetch automatically.
- Arrow, viewport-sized Page, pointer, and gamepad navigation cross request boundaries with stable channel/time intent and no stale or lost focus.
- Default new-install Auto profile uses the complete viewport-derived row count and bounded PC cache/warming policy; Reduced resource preserves identical correctness and visible-row density with less speculative work.
- Auto/Comfortable/Compact and Detailed/Wide are independent and match the frozen row/time semantics.
- Complete-row floors pass: >=20 at 4K/100%, >=8 at 1080p/100%, >=5 at 720p/high-DPI narrow supported surfaces, with no clipped row.
- Current-upstream parity review accepts the complete visual hierarchy and interaction/state matrix; the Guide is not closed because a few constants or screenshots happen to match.
- Renderer/main/preload/persistence/native trust boundaries remain unchanged except the reviewed renderer-safe Settings version 3 contract.
- Performance budgets are based on accepted-input through actual frame-presentation traces and pass in warm/cold/poll-collision cohorts, or a reviewed evidence packet explicitly defers a platform-specific blocker.
- Windows/live/large-lineup/native-composition proof is recorded before parity rows close.
- Current-state, roadmap, matrix, renderer architecture, and import ledger are updated only to the level supported by reviewed evidence.

## Replan Triggers

Stop the current package and return to feature planning/review when:

- the existing paged Guide operation cannot support sparse visible windows without a new IPC method or renderer-visible private identity;
- continuous scrolling requires main to send the full 459-channel schedule or otherwise breaks the 24-row/400-cell/1,000-program bounds;
- a package would widen renderer privilege, expose Plex/source/native/private data, or create browser/filesystem persistence;
- Settings version 3 migration cannot preserve valid version 1/version 2 records atomically and fail closed;
- current upstream Guide behavior or source materially differs from the frozen reference;
- visual parity requires copying/adapting upstream source/assets without an import-ledger decision;
- G0 traces do not reproduce the reported content exhaustion or contradict a proposed performance owner;
- G0 proof requires any path outside its exact forty-two-path boundary, overlaps a concurrent writer or `e7f1338`, or exceeds a reviewed owner cap without a cohesive extraction;
- exact sample/resource correlation would require preload/IPC, a renderer-callable or global hook, DOM proof fields, private/free-form data, persistent state, or wider renderer privilege;
- F3 cannot deterministically reach Settings or the required Settings/polling/request quiescence cannot be established before a resource snapshot;
- no-interruption single-instance behavior cannot be implemented entirely by the selected single-instance owner plus already selected main wiring, requires the primary to read/validate proof nonce/root/argv/private data, changes normal second-instance behavior, or cannot guarantee proof-secondary nonzero exit before evidence artifacts;
- the exact M148 presented-frame, layout/paint, or target-renderer-main long-task signatures cannot be observed and attributed reliably enough to satisfy sample boundaries;
- cold-live cannot bind one accepted cold Page action and loading/final frames in every live child, a poll/cache cohort cannot bind its exact origin and main request, or the three live children differ in build/source/profile/eligible-total authority;
- route-exit acceptance would require changing retained main source-cache policy rather than measuring its reviewed cap and baseline-relative plateau;
- a persistent DOM pool, cache/concurrency change, dependency, worker, or GPU change is proposed without its required measurement;
- native video/HTML layering fails under Guide Classic/Overlay, DPI, resize, fullscreen, multi-monitor, or teardown;
- a selected file overlaps unresolved concurrent playback/user edits;
- a touched composition root or >800-line owner lacks the required independent architecture review; or
- package verification, manual proof, or independent review has a material unresolved finding.

## Rollback And Commit Checkpoints

Use conventional commits and one reviewed checkpoint per package. Suggested intent:

- G0: `test(guide): instrument large-lineup Windows proof`
- G1: `feat(settings): add Guide PC policies`
- G2: `fix(guide): populate continuous channel windows`
- G3: `fix(guide): restore upstream visual parity`
- G4: `feat(guide): adapt row density to desktop viewports`
- G5, only if required: `perf(guide): optimize measured rendering bottleneck`
- G6: documentation-only parity/proof checkpoint after product review

Do not squash G1 with later packages because G1 changes the persistence schema and has a different rollback boundary. Do not stage or commit unrelated playback/user files. If a package fails review, revert only that package's owned diff or amend it under the same reviewed scope; never reset the shared worktree.

## Handoff

MODEL_SUGGESTION
PLANNER: n/a
IMPLEMENTER: n/a
REVIEWER: n/a
WHY: Tier 3 spans multiple owner boundaries; select each role/model/effort from the repository role TOML at dispatch rather than freezing it in the plan.

NEXT_SESSION_HANDOFF
NEXT_SESSION_LAUNCHER: `lineup-desktop-feature-quality-loop`
TASK: Complete Guide continuous-lineup and Desktop visual parity remediation through the Tier 3 quality loop
TASK_FAMILY: feature/design
TIER: Tier 3
PLAN: `docs/plans/2026-08-10-guide-continuous-lineup-visual-parity-plan.md`
ARTIFACT: `docs/development/guide-large-lineup-performance-parity-bug-report.md`
FILES:
- `docs/plans/2026-08-10-guide-continuous-lineup-visual-parity-plan.md`
- `docs/development/guide-large-lineup-performance-parity-bug-report.md`
- current Guide/Settings owners named by the selected package
BLOCKERS: clean independent review of the `WIN-TEST-006` sequencing replan, then the exact selected-package no-overlap/collision gate; the operator proof remains mandatory G6/Windows closeout debt
MESSAGE:
After clean independent review of the `WIN-TEST-006` sequencing replan, select G0 as the next product package, freeze its exact write-file list, and pass the collision gate before editing. Execute G0 through G6 serially with a review/verification/conventional-commit checkpoint after each package while preserving unrelated playback and user edits. Carry the pending two-channel playback proof into G6's consolidated Windows/live/native-composition campaign; neither synthetic proof nor the current Computer Use input-control failure can close it. Complete continuous populated scrolling across all 459+ channels, current-upstream visual parity, and PC-specific row/resource policies; do not stop at the former twelve-channel presentation, synthetic proof, or a visual-only approximation.
