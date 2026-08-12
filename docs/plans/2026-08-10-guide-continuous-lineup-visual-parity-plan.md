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
- Do not add pre-MVP compatibility exports, dual old/new methods, alias paths, deprecated schemas, migration branches, or transition wrappers. Update every caller atomically when an API or persisted shape changes.
- Do not add forwarding wrappers, one-implementation interfaces, generic UI services, unbounded page stores, unbounded workers, or a second persistence owner.

## Architecture And Invariants

### Authority and sequencing

This is a separate durable Guide handoff and does not supersede the user-modified `docs/plans/2026-07-22-tier3-parity-correction-plan.md`. That plan's `WIN-TEST-006 sequencing replan — Guide execution with mandatory proof debt (2026-08-10)` is the controlling amendment: product checkpoint `e7f1338` remains fixed and the still-pending two-channel operator proof stays in the consolidated G6 Windows/native campaign. The proof is not passed or waived and remains required before G6, WS5, affected parity rows, or RD-27 Windows/native closeout.

G0 is complete at `65adb69`, G1 at `b89dcd1`, G2 at `b69f7ae`, G3 at `cb384f7`, `a6538f6`, and `7446861`, and G4 at `0147d45`. G5 was conditional on measured evidence and was not activated. G6, consolidated with WS5 Unit 5H, is the next authorized Guide package. It owns the still-pending Windows, live Plex, physical-input, DPI/multi-monitor, and native-composition evidence; none of that evidence is passed or waived. No new proof harness, artifact publisher, compatibility layer, or migration scaffold is authorized.

Before G0 and each later package, freeze the exact selected write-file list and apply the amendment's collision gate: compare it with all tracked/untracked pre-existing changes and every active writer's exact write list; any path match stops the package without editing, staging, stashing, overwriting, or absorbing the other work. No Guide selected list may contain a `WIN-TEST-006A` commit-manifest path defined by the amendment. A collision, materially changed Guide baseline, requested playback-owner edit, or failed live playback attempt stops the current sequence for reviewed replan. G0 creates no proof writer or generated output.

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

It removes `guideDensity` and `aggressiveGuidePreloadEnabled`; version 3 retains no compatibility alias, migration branch, dual reader, deprecated key, or old/new adapter. New/missing Settings default to `guideTimeRange: 'detailed'`, `guidePerformanceProfile: 'auto'`, and `guideRowDensity: 'auto'`. Any persisted record that is not the exact current version-3 shape follows the existing generic invalid/corrupt recovery path; do not distinguish or translate version 1 or version 2. Original invalid bytes remain untouched until the user performs the existing exact revision-zero replacement, which atomically writes one valid version-3 record. There is no down-migration, browser-storage fallback, or compatibility export. Pre-MVP profiles may be deleted manually instead of adding product compatibility code.

Row-density behavior is frozen as follows:

- `Comfortable` preserves the upstream-like 108 px schedule-row treatment.
- `Compact` uses a reviewed compact treatment with a 72 px target row and removes only secondary row metadata that cannot fit; channel number, channel name, program title/time, live/current/past state, focus ring, and tune/current indicators remain readable.
- `Auto` chooses the largest readable row size between the Compact and Comfortable treatments that meets the viewport floor below. It derives from measured Guide grid height and recomputes on resize/DPI/layout change without changing the selected channel/time.
- 3840 x 2160 at 100% shows at least 20 complete schedule rows in Auto, with no clipped partial row.
- 1920 x 1080 at 100% shows at least 8 complete rows in Auto.
- 1280 x 720 and supported high-DPI/narrow windows show at least 5 complete rows without clipping or unreadable focus treatment.

`Reduced resource` does not change row density, time range, or channel availability. It uses the same foreground viewport request and DOM correctness but disables idle page/time warming, limits retained presentation pages/programs to the existing default bounds, and uses conservative artwork predecode/retention. `Auto` may use the existing aggressive upper bounds of 12 cached entries/12,000 programs and idle adjacent-window warming; G5/G6 manual Windows evidence must validate or reduce that policy before the affected parity rows close. Both profiles retain the existing main response caps of 200 programs per row and 1,000 total programs.

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

Package G0 owns only seven renderer-local User Timing marks: `input-received`, `input-accepted`, `request-start`, `request-settled`, `state-accepted`, `reconcile-start`, and `reconcile-end`. They are lightweight DevTools/Chromium trace landmarks, not an automated proof protocol. G0 adds no custom frame mark; an operator may inspect the native Chromium presentation events available in a visible production window. Informal G0 observations help aim later work but do not block G1-G5; Windows/live/native proof remains a user-operated G6 closeout gate.

Whole-subtree replacement, repeated Guide view projection, source-cache churn, request contention, and GPU-disabled composition remain hypotheses until those traces assign cost. A persistent keyed DOM pool/reconciler is authorized only by evidence that Guide reconciliation/layout/presentation dominates. Cache/concurrency changes are authorized only by measured distinct-source churn, queue wait, miss cost, or foreground starvation. GPU changes are outside this plan unless a reviewed amendment incorporates the native-composition A/B campaign.

### File-shape dispositions

Any touched production owner over 500 lines records the required cohesion disposition before implementation review. The expected attention surfaces are:

- `src/renderer/index.ts`: composition root; wiring-only growth, mandatory fresh architecture review.
- `src/renderer/guidePresentationPolling.ts`: current request/cache/currentness lifecycle; keep request custody cohesive and extract the sparse channel-window state because it is a distinct renderer lifecycle.
- `src/renderer/epg.ts`: >800-line Guide state/navigation projection; keep semantic EPG navigation cohesive. G0 does not touch it or add a proof-only Page-acceptance seam.
- `src/renderer/epg/guideDom.ts`: Guide DOM/layout owner; parity composition is cohesive, while a persistent grid lifecycle is extracted only if G0 proves it is required.
- `src/contracts/settings.ts` and `src/main/persistence/desktopSettingsStore.ts`: strict current Settings contract/store owners; version 3 growth is cohesive and requires persistence/contract review, but no migration owner or legacy reader remains.
- `src/renderer/settingsSetup.ts`: Settings presentation/action owner; Guide value changes are cohesive but require fresh architecture review when touched.
- `src/main/channel/guideRuntime.ts`: main Guide page/schedule/currentness owner; artwork-role projection is cohesive only while it remains renderer-safe and on the existing operation, and requires fresh architecture review when touched.
- `src/domain/channel/channelManager.ts`: 1,022-line named hotspot and channel mutation/state owner; G0 and G1 do not touch it. Any later package that truly changes its resolver/cache API must update every caller atomically without a wrapper and receive fresh architecture review.
- G0 caps the exact retained owners at: `src/renderer/guidePerformanceMarks.ts` <=90 lines, `src/renderer/index.ts` <=1,225, `src/renderer/guidePresentationPolling.ts` <=755, `src/renderer/epg/guideDom.ts` <=765, `src/__tests__/renderer/guidePerformanceMarks.test.ts` <=90, `src/__tests__/renderer/guidePresentationPolling.test.ts` <=720, and `src/__tests__/renderer/epg/guideDom.test.ts` <=265. The seven selected files total <=3,910 physical lines, at most 332 over their 3,578-line `HEAD` baseline and at most 171 production lines over baseline. Do not meet a cap through compressed formatting, forwarding, mirrored state, or structural line-count tests.

Fresh architecture review is mandatory whenever this plan touches `src/renderer/index.ts`, `src/renderer/epg.ts`, `src/renderer/epg/guideDom.ts`, `src/renderer/guidePresentationPolling.ts`, `src/main/channel/guideRuntime.ts`, `src/domain/channel/channelManager.ts`, or `src/renderer/settingsSetup.ts`, regardless of final line count. G0's review is limited to the selected renderer composition, polling, and DOM owners.

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
- one new cohesive renderer Guide-window owner and, only if measured, one Guide grid lifecycle owner

Contracts, preload validation, main Guide/Settings, and tests:

- `src/contracts/guide.ts` and `src/contracts/artwork.ts` for the exact nullable poster/background/logo renderer-safe set on the existing Guide operation
- `src/contracts/settings.ts` and its existing validation owners
- existing preload Guide/Settings validators and bridge tests required by strict version 3 values; no new IPC method
- `src/main/channel/guideRuntime.ts`, `src/main/channel/guideArtworkOwner.ts`, and the existing public-reference owner for the exact safe artwork roles and any measured request-policy/currentness correction; the existing paged operation remains
- `src/main/plex/livePlexTransport.ts` only for the exact numeric `/thumb` and `/art` Guide artwork locator families and their containment/transport tests
- `src/main/persistence/desktopSettingsStore.ts` and existing Settings policy/snapshot consumers for the current-only version-3 replacement
- focused Guide, Settings, preload, persistence, renderer DOM/focus, smoke, and performance-harness tests under `src/__tests__/*`
- the existing user-operated Windows/manual proof surface only in G6; G0 adds no harness or generated evidence surface

The user-directed minimal G0 retained boundary contains exactly seven paths:

- `src/renderer/guidePerformanceMarks.ts`
- `src/__tests__/renderer/guidePerformanceMarks.test.ts`
- `src/renderer/index.ts`
- `src/renderer/guidePresentationPolling.ts`
- `src/__tests__/renderer/guidePresentationPolling.test.ts`
- `src/renderer/epg/guideDom.ts`
- `src/__tests__/renderer/epg/guideDom.test.ts`

These seven paths are unique and have zero overlap with all twenty-one `e7f1338` paths. Any additional retained path stops G0 for replan; deletion/restoration of the explicitly superseded G0 proof work below is cleanup, not permission to retain or redesign it.

For historical record, G0 required its owned hunks outside the retained seven-path boundary to be restored while unrelated user or playback hunks were preserved by patch rather than reset/stash. The tracked inventory was: `package.json`, `src/__tests__/domain/channelDomain.test.ts`, `src/__tests__/main/guideRuntime.test.ts`, `src/__tests__/main/singleInstanceOwner.test.ts`, `src/__tests__/main/smokeBootstrapOwner.test.ts`, `src/__tests__/renderer/epg.test.ts`, `src/__tests__/renderer/guideVirtualization.test.ts`, `src/domain/channel/channelManager.ts`, `src/domain/channel/contentResolver.ts`, `src/domain/channel/sourceResolutionCache.ts`, `src/main/channel/channelComposition.ts`, `src/main/channel/guideRuntime.ts`, `src/main/index.ts`, `src/main/singleInstanceOwner.ts`, `src/main/smokeBootstrapOwner.ts`, `src/renderer/epg.ts`, `src/renderer/guideVirtualization.ts`, `tools/__tests__/copy-renderer-assets.test.mjs`, `tools/__tests__/smoke-electron.test.mjs`, `tools/copy-renderer-assets.mjs`, and `tools/smoke-electron.mjs`. This paragraph is evidence context, not a current cleanup instruction.

The following twenty-path untracked inventory was the superseded G0 proof set: `src/__tests__/contracts/guidePerformanceContracts.test.ts`, `src/__tests__/main/guideWindowsProofAnalysis.test.ts`, `src/__tests__/main/guideWindowsProofController.test.ts`, `src/__tests__/main/guideWindowsProofEvidenceBinding.test.ts`, `src/__tests__/main/guideWindowsProofFixture.test.ts`, `src/__tests__/main/guideWindowsProofResourceSoak.test.ts`, `src/__tests__/main/guideWindowsProofSampleAnalysis.test.ts`, `src/__tests__/renderer/guideProofResourceOwner.test.ts`, `src/contracts/guidePerformance.ts`, `src/main/channel/guideWindowsProofFixture.ts`, `src/main/guideWindowsProofAnalysis.ts`, `src/main/guideWindowsProofController.ts`, `src/main/guideWindowsProofEvidenceBinding.ts`, `src/main/guideWindowsProofResourceSoak.ts`, `src/main/guideWindowsProofSampleAnalysis.ts`, `src/renderer/guideProofResourceOwner.ts`, `tools/__tests__/guide-proof-artifact-publisher.test.mjs`, `tools/__tests__/guide-windows-proof.test.mjs`, `tools/guide-proof-artifact-publisher.mjs`, and `tools/guide-windows-proof.mjs`. At G0 execution, each listed path had to be present, untracked, unchanged from the inventoried superseded artifact, and validated as G0-owned by content before removal. Any missing, tracked, unexpectedly modified, or ownership-unknown path required aborting deletion and inventorying the full set; any additional untracked proof file was the same stop condition. Only validated G0-owned files were eligible for removal. This is a historical safety requirement, not authorization to delete a current file matching one of these names.

## Files Out Of Scope

- all concurrent playback-remediation changes under `src/main/player/*`, `src/main/plex/*`, and their tests
- native helper protocol/host/binary, native HWND ownership, and player command/runtime contracts
- Plex auth, discovery, credentials, media-detail, or stream-resolution contracts; Plex transport is out of scope except the exact Guide `/thumb` and `/art` locator allowlist named above
- channel builder, scheduler semantics, channel persistence schema, source format, and lineup generation
- packaging, installer, updater, release signing, and unrelated CI workflows
- broad Electron shell/security changes or new renderer privilege
- unrelated Settings categories or a redesign of the global application shell
- the user-modified active Tier 3 correction plan except a separately reviewed sequencing/status amendment by its current owner
- for G0 specifically: all main, preload, domain, shared-contract, resolver/cache, Channel Manager, EPG navigation, virtualization, smoke, package-script, copy-asset, launcher, publisher, synthetic/live child, authority/provenance, resource-soak, single-instance, IPC, public API, and DOM proof-field changes

## Execution Packages

Packages are serial unless a package explicitly authorizes read-only sidecars. Each package ends with focused tests, risk-matched verification, independent review, a conventional commit, and a fresh worktree/collision check. Do not carry unreviewed changes into the next package.

### G0 — Minimal renderer timing landmarks and manual baseline

This amendment supersedes every earlier G0 harness, provenance, cohort, resource-soak, publisher, synthetic/live-child, paired-capture, and automated Windows-proof requirement in this plan. Those designs are removed from G0, not deferred implementations.

Outcome:

- retain one small renderer-local User Timing owner for exactly seven marks: `lineup-guide-v1:input-received`, `lineup-guide-v1:input-accepted`, `lineup-guide-v1:request-start`, `lineup-guide-v1:request-settled`, `lineup-guide-v1:state-accepted`, `lineup-guide-v1:reconcile-start`, and `lineup-guide-v1:reconcile-end`;
- make the marks useful as optional DevTools/Chromium trace landmarks without making them a publication, pass/fail, or product-command protocol;
- restore/delete all superseded G0 proof work named above; and
- let the user record current exhaustion, visual, and performance observations informally. Manual/live/native proof is deferred to G6 and does not block G1-G5 product packages.

Architecture and mark contract:

- All mark types, closed literal categories, and detail shapes live in `src/renderer/guidePerformanceMarks.ts`. Do not add or retain `src/contracts/guidePerformance.ts`, preload/IPC/public API, a window/global hook, a DOM proof attribute, persistence, filesystem access, Electron/main ownership, or a copy-assets step.
- Every detail contains a bounded monotonic numeric `sequence`. Input details additionally contain only `inputKind: 'arrow' | 'page' | 'wheel' | 'scroll' | 'pointer' | 'gamepad' | 'other'` and numeric `targetIndex` (use `-1` when not applicable). Request details additionally contain numeric `generation`, `channelOffset`, `channelLimit`, `windowStartMs`, and `windowDurationMs`, plus `requestOrigin: 'foreground' | 'poll' | 'warm'`; `request-settled` adds `requestClass: 'renderer-cache' | 'runtime' | 'rejected'` and `accepted: boolean`. State details additionally contain numeric `generation`, `targetIndex`, and `stateClass: 'loading' | 'ready'`. Reconcile details additionally contain numeric `generation`. No title, channel/program id, source identity, URL, token, path, native value, arbitrary key, free-form text, cohort, run, sample, resource, provenance, or conclusion field is allowed.
- The owner may retain only the current bounded input/request correlation needed to keep a manual trace readable. Rejected/aborted settlement clears its active request immediately; accepted settlement clears after the matching final state/reconcile. Every emitted mark is immediately cleared from the User Timing buffer after `performance.mark` so the trace event remains observable without accumulating performance entries. Instrumentation is strictly fail-open: the owner catches failures from both `performance.mark` and `performance.clearMarks`, and neither failure may escape, change a return/result, skip product cleanup, alter input/request/state/reconcile behavior, or replace an original product/render error. In particular, a reconcile-end mark attempted from `finally` cannot mask the error that caused the render to exit.
- `src/renderer/index.ts` remains wiring-only. It records Guide input receipt/acceptance at existing input/semantic handler seams and state acceptance immediately before the existing render, without adding proof-specific Page target math, an EPG callback, input simulation, resource accounting, or persistent listener state. Any listener added solely to observe an existing renderer input must be removed in the existing renderer cleanup.
- `src/renderer/guidePresentationPolling.ts` remains the request/cancellation/currentness owner. It emits one request-start and one terminal request-settled mark for the existing network/cache/cancel/failure lifecycle without changing request order, loading policy, Page behavior, queueing, cache policy, timers, or public interfaces except the smallest renderer-local callback/value needed by the seven marks.
- `src/renderer/epg/guideDom.ts` brackets the existing Guide reconcile with start/end marks and guarantees the end mark through the existing early-return/error paths. It adds no DOM field or retained proof state.
- Do not add a custom `frame-presented` mark. Optional manual inspection uses native Chromium presentation events from a visible production window; hidden-renderer Layout/Paint is not claimed as display proof.

Write boundary: exactly the seven retained paths above. No dependency, new abstraction layer, proof mode, command-line option, package script, fixture, child process, controller, analyzer, validator, trace parser, artifact writer, resource observer, soak counter, provenance record, single-instance exception, or compatibility path.

Focused verification:

- `guidePerformanceMarks.test.ts` proves the exact seven public mark names and closed primitive details, request reuse for the active semantic chain, rejected/aborted and final-reconcile cleanup, immediate `clearMarks`, and fail-open behavior when either `mark` or `clearMarks` throws; it does not probe private symbols, source shape, or the absence of superseded implementations;
- `guidePresentationPolling.test.ts` proves exactly one start/terminal-settle pair for runtime, renderer-cache, rejection, and cancellation paths without changing existing request/loading/currentness behavior;
- `guideDom.test.ts` proves reconcile end is emitted for ordinary render and early-return/error cleanup, and that a throwing end-mark path never replaces the original render error;
- the existing production build and Electron smoke remain the integration proof for renderer composition. Do not add a synthetic Guide proof smoke or a private-source/structure test.

Informal user checklist (optional before G6):

- note the Desktop checkpoint, window size/DPI, approximate eligible total, initial visible/focused row, and whether wheel plus scrollbar-to-maximum reaches populated content beyond the first twelve channels;
- note Arrow/Page/pointer/gamepad reach, focus continuity, blank/loading/error behavior, and any visible Guide hierarchy/density/parity problem;
- optionally record a DevTools Performance trace and note whether the seven fixed marks appear in useful semantic order, whether a native Chromium presentation event is visible, and any obvious long task or sustained memory growth; and
- keep these as user notes only. G0 generates no trace, screenshot bundle, manifest, replay, authority file, summary, hash, tracked conclusion, or formal pass/fail result.

Acceptance:

- the retained diff is confined to the exact seven-path boundary; the twenty-one tracked superseded G0 surfaces are restored by owned hunk, the twenty untracked proof files are absent, shared proof contracts/copy changes are gone, and unrelated user/playback changes are preserved;
- all seven owner/file caps and the <=3,910 selected-line total pass without compressed formatting or a new abstraction;
- focused tests, `npm run typecheck`, `npm run build:electron`, `npm run smoke:electron`, `npm run verify`, and `git diff --check` pass;
- fresh correctness/architecture review has no material finding and an independent ponytail review returns `Lean already. Ship.`; and
- G0 lands as one conventional commit. Missing informal Windows observations do not block G1-G5.

Rollback: revert only the seven-path G0 commit. This removes optional timing landmarks without changing Guide behavior, IPC, persistence, main ownership, or Windows proof state.

### G1 — Settings version 3 and independent PC policies

Pre-entry gate: discover every current Settings contract, store, preload, policy, renderer, and Guide consumer before editing. Replace the version-2 shape atomically with the one version-3 shape; delete old migrations, deprecated keys, aliases, fixtures, and adapters in the same package. If an outside caller cannot consume version 3 directly, expand and review the package rather than retaining compatibility code.

Outcome:

- replace main-owned Settings version 2 with the sole current version-3 schema;
- replace the experimental aggressive toggle with `Performance profile: Auto/Reduced resource`;
- replace `guideDensity` with `guideTimeRange` and present `Time range: Detailed (2h)/Wide (3h)`;
- add `Row density: Auto/Comfortable/Compact`;
- project accepted settings into Guide window/cache/layout owners without new privilege or browser storage.

Write boundary: existing Settings contracts/validation/store/snapshot/policy, preload validation, renderer Settings presentation, Guide setting consumers, and focused current-schema/invalid-record tests.

Acceptance:

- missing/new records produce the exact version-3 defaults defined above;
- every non-version-3 or malformed record follows the same revision-zero invalid/corrupt path and remains unchanged until an exact revision-zero replacement atomically repairs it as version 3;
- compare-and-swap, strict exact-key validation, redaction, and atomic mode-0600 replacement remain intact;
- no version-specific migration, backward reader, dual writer, alias, or old-binary accommodation remains;
- changing any Guide setting settles once, preserves eligible current focus where possible, cancels stale work, and invalidates only affected window/cache state;
- Reduced resource never reduces visible channel count or navigation reach.

Rollback: version 3 is a persistence boundary. Before release, retain the pre-G1 commit as the code rollback point and use disposable pre-MVP profiles. If source rollback is required, delete the disposable profile rather than adding a backward migration.

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
- every foreground request satisfies `completeVisibleRows <= channelLimit <= min(completeVisibleRows + (2 * overscanRows), 24)`, with the existing two-row overscan on each side represented by `overscanRows = 2`; request concurrency remains one active request plus at most one latest trailing foreground intent;
- foreground work continues to preempt and cancel lower-priority idle warming independently of the request-size and concurrency constraints;
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

- implement only the smallest measured optimization justified by reviewed G0/G3/G4 user observations or a fresh G5 manual DevTools/Windows measurement;
- possible authorized seams are one Guide view computation per generation, Guide-scoped keyed DOM reconciliation, range-local focus registration, measured source/cache policy, or foreground/poll scheduling;
- skip this package when G1-G4 already satisfy budgets.

Write boundary: only the owner(s) named by reviewed manual measurement and a G5 amendment. No speculative cache increase, worker, dependency, renderer privilege, or GPU change.

Acceptance:

- the user-observed regression is materially improved in repeated visible production-window checks without regressing continuous navigation, focus, or cleanup;
- any stronger latency, frame, or resource claim is supported by the G6 user-operated Windows proof, not by a resurrected G0 harness;
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

G0 uses focused automated seam coverage; G6 retains the broader user-operated Windows/live/native proof.

Every product package runs its exact focused new/affected tests first. Before its commit/review checkpoint, run:

- `npm run typecheck` — no TypeScript error.
- `npm run build:electron` — production Electron build succeeds.
- `npm run smoke:electron` — the ordinary built-app smoke passes unchanged.
- `npm run verify:architecture` — no process-boundary or composition-root violation.
- `npm run verify:maintainability` — report reviewed; every touched >500-line or named owner has a cohesion disposition.
- `npm run verify:redaction` — no forbidden secret/path/native material.
- `npm run verify:docs` when tracked documentation changes.
- `npm run verify` — full repository verification passes before any implementation package is called complete.
- `git diff --check` — no whitespace error.

G0 runs `node --import tsx --test src/__tests__/renderer/guidePerformanceMarks.test.ts src/__tests__/renderer/guidePresentationPolling.test.ts src/__tests__/renderer/epg/guideDom.test.ts` before the commands above. Review also confirms the exact seven retained paths, the restoration/deletion inventory, all small caps, no shared proof contract or proof-only Page/DOM/global seam, and preservation of unrelated work. G0 has no generated proof command, trace parser, soak, fixture, child, publisher, manifest, or paired-capture gate. Its optional user checklist is informal and cannot block G1-G5.

Later focused proof must include:

- Guide sparse-window merge/invalidation/LRU/currentness tests with 459 and 500 channels;
- wheel/scrollbar/arrow/viewport-Page/pointer/gamepad boundary tests;
- real/fake DOM tests for total spacers, explicit loading rows, mounted caps, focus/accessibility registration, and cleanup;
- Settings version-3 exact-shape, generic invalid-record recovery, strict contract/preload, compare-and-swap, and failed-write tests;
- row-density/resize/DPI/forced-colors/reduced-motion tests at stable public seams;
- current-upstream visual/manual review and G6 Windows/live/native-video composition proof; and
- G5 measurement-specific regression coverage only when a reviewed G5 amendment authorizes an optimization.

Expected outcome: automated checks are green, the G0 correctness/architecture reviewer has no material finding, the G0 ponytail reviewer returns `Lean already. Ship.`, later Windows/manual evidence supports only the rows it closes, and no unrelated playback or user changes enter a Guide commit.

## Acceptance Criteria

- Ordinary vertical scroll traverses all 459 observed channels and a 500-channel boundary fixture; content does not stop after the first twelve.
- Fast scroll never presents silent blank rows. Unloaded absolute rows are explicit, inert loading rows and fetch automatically.
- Arrow, viewport-sized Page, pointer, and gamepad navigation cross request boundaries with stable channel/time intent and no stale or lost focus.
- Default new-install Auto profile uses the complete viewport-derived row count and bounded PC cache/warming policy; Reduced resource preserves identical correctness and visible-row density with less speculative work.
- Auto/Comfortable/Compact and Detailed/Wide are independent and match the frozen row/time semantics.
- Complete-row floors pass: >=20 at 4K/100%, >=8 at 1080p/100%, >=5 at 720p/high-DPI narrow supported surfaces, with no clipped row.
- Current-upstream parity review accepts the complete visual hierarchy and interaction/state matrix; the Guide is not closed because a few constants or screenshots happen to match.
- Renderer/main/preload/persistence/native trust boundaries remain unchanged except the reviewed renderer-safe Settings version 3 contract.
- Performance claims are limited to reviewed user-operated Windows/DevTools evidence; optional G0 landmarks alone do not prove frame latency, cache behavior, resource plateau, or closeout.
- Windows/live/large-lineup/native-composition proof is recorded before parity rows close.
- Current-state, roadmap, matrix, renderer architecture, and import ledger are updated only to the level supported by reviewed evidence.

## Replan Triggers

Stop the current package and return to feature planning/review when:

- the existing paged Guide operation cannot support sparse visible windows without a new IPC method or renderer-visible private identity;
- continuous scrolling requires main to send the full 459-channel schedule or otherwise breaks the 24-row/400-cell/1,000-program bounds;
- a package would widen renderer privilege, expose Plex/source/native/private data, or create browser/filesystem persistence;
- G1 would require a version-specific legacy reader, migration, alias, dual writer, or compatibility wrapper;
- current upstream Guide behavior or source materially differs from the frozen reference;
- visual parity requires copying/adapting upstream source/assets without an import-ledger decision;
- G0 needs a retained path outside the exact seven, overlaps a concurrent writer or `e7f1338`, exceeds a small cap, or cannot separate current G0-owned hunks from unrelated user/playback changes;
- G0 marks would require main/preload/shared contracts, IPC/public/window/global access, DOM proof fields, a custom frame mark, package/tool/smoke changes, EPG Page-target changes, resource/provenance fields, generated artifacts, or persistent/unbounded state;
- G0 cannot restore the twenty-one tracked superseded surfaces and delete the twenty untracked proof files without losing unrelated work;
- another untracked proof file appears outside the exact deletion inventory;
- a changed API has an outside caller that cannot be updated atomically inside the selected package;
- a persistent DOM pool, cache/concurrency change, dependency, worker, or GPU change is proposed without reviewed user measurement and a G5 amendment;
- native video/HTML layering fails under Guide Classic/Overlay, DPI, resize, fullscreen, multi-monitor, or teardown;
- a selected file overlaps unresolved concurrent playback/user edits;
- a touched composition root or >800-line owner lacks the required independent architecture review; or
- package verification, the applicable manual proof, correctness review, or ponytail review has a material unresolved finding.

## Rollback And Commit Checkpoints

Use conventional commits and one reviewed checkpoint per package. Suggested intent:

- G0: `chore(guide): add local timing landmarks`
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
TASK: Execute the consolidated Guide G6 / WS5 Unit 5H Windows proof and closeout package
TASK_FAMILY: feature/design
TIER: Tier 3
PLAN: `docs/plans/2026-08-10-guide-continuous-lineup-visual-parity-plan.md`
ARTIFACT: `docs/development/guide-large-lineup-performance-parity-bug-report.md`
FILES:
- `docs/plans/2026-08-10-guide-continuous-lineup-visual-parity-plan.md`
- `docs/development/guide-large-lineup-performance-parity-bug-report.md`
- current Guide/Settings owners named by the selected package
BLOCKERS: G0-G4 are landed; G5 was not activated without measured need; Windows/live/native/physical-input/DPI evidence remains pending and cannot be substituted by local automation
MESSAGE:
Start from the landed G0-G4 state recorded above and the current WS5 authority. Apply the exact no-overlap/collision gate, then execute only the consolidated G6 / Unit 5H evidence and documentation scope. Preserve the pending two-channel operator proof and require real Windows production-build observation for physical input, live Plex, DPI/multi-monitor, native composition, and affected parity rows. Do not resurrect G0 proof infrastructure, activate G5 without new reviewed measurements, or claim an automated/macOS substitute for Windows evidence. Run all applicable focused and full gates, review the evidence binding and closeout claims adversarially, and commit only the reviewed closeout scope.
