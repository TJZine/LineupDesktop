# Accepted Suggestion Production Remediation Plan

**Plan Status:** active
**Task family:** feature/design
**Tier:** Tier 3

## Goal

Implement the accepted or valid findings from the 2026-08-11 suggestion review as bounded, reversible production-quality corrections. The authorized findings are `#1`–`#15` and `#17`–`#30`. Findings `#16` and `#31` remain rejected and are explicitly excluded.

The completed remediation must:

- strengthen private-playback and redaction proof without exposing privileged values;
- keep playback terminal error events and snapshots on one retained request identity;
- simplify the renderer-safe Guide artwork contract, render a real poster fallback, and keep opaque artwork authorization usable during active Guide polling;
- make sparse Guide geometry, paging, focus, DOM caps, and scroll reconciliation consistent without rerendering unrelated application owners;
- correct the initial native-presentation epoch handshake without weakening later currentness checks;
- align Settings and Guide accessibility presentation with their real behavior;
- harden Windows packaging environment-sanitization proof;
- normalize EPG paging offsets in the semantic EPG owner; and
- strengthen Settings publication to the repository's strongest honest Node-level Windows durability posture without claiming power-loss-safe rename durability.

This plan is a narrow remediation amendment to [`2026-08-10-guide-continuous-lineup-visual-parity-plan.md`](./2026-08-10-guide-continuous-lineup-visual-parity-plan.md), not a replacement for its remaining G6/WS5 proof authority.

## Non-Goals

- Do not implement rejected findings `#16` or `#31`. In particular, do not add a second placement lookup map to `guideDom.ts`, and do not duplicate polling failure settlement or diagnostics inside `applyPresentation`.
- Do not close G6, WS5, `EPG-10`–`EPG-13`, `UI-36`, RD-27, `WS2-POST-VALIDATION-01`, or any Windows/live/native/physical-input/DPI proof row.
- Do not execute, replace, waive, or reinterpret the pending two-channel operator proof carried by the controlling WS5 amendment.
- Do not add a new Guide IPC method, renderer privilege, raw Plex locator, token, header, filesystem path, Electron object, native handle, browser persistence, dependency, compatibility layer, or migration branch.
- Do not alter Plex playback candidate selection, PMS lease custody, stream resolution, helper commands, native protocol, or retained runtime snapshot identity beyond the exact terminal-error normalization in Package R1.
- Do not add a generic renderer service, generic partial-render framework, persistent DOM pool, broader cache/concurrency policy, worker, GPU change, or speculative abstraction.
- Do not add parent-directory `fsync`, a Win32 native write-through layer, or a claim that Node `rename` is power-loss durable on Windows.
- Do not change the general `ArtworkRef.kind` union. Only the Guide-specific set loses its unused `logo` member; non-Guide clear-logo capability remains available to its existing owners.
- Do not copy or adapt upstream source or assets. If implementation stops being an independent correction in current Desktop owners, stop for an import-ledger decision.

## Architecture And Invariants

### Authority reconciliation

This plan supersedes only three decisions in the active Guide plan for this remediation:

1. **Guide logo shape:** `GuideArtworkSet` becomes exactly `{ poster, background }`. The old `logo: null` member was a permanently unavailable public shape with no Guide consumer. `ArtworkRef.kind: 'logo'` and non-Guide clear-logo settings remain unchanged.
2. **Artwork authorization expiry:** reissuing the same current session/generation/role/locator authorization refreshes its full 15-minute expiry in place. Object identity, ref id, session generation, lineup revision, role, locator, caps, revocation, and in-flight currentness remain unchanged. This is sliding expiry for an actively reissued opaque bearer, not an unbounded session or cache lifetime.
3. **Guide-scoped scrolling:** the observed call from scroll reconciliation to whole-application `renderApp()` is sufficient code evidence of unrelated work and authorizes one narrow Guide render path. This is a correctness/ownership correction and a bounded G5 amendment; it does not claim a measured latency improvement or satisfy G5/G6 performance evidence.

All other Guide plan constraints remain authoritative. G6/WS5 and the pending two-channel proof remain open and unchanged.

The Guide plan's playback and packaging exclusions continue to govern Guide packages. Packages R1, R5, and R8 below are independent non-Guide remediation commits with their own owner boundaries; they must not be staged into a Guide commit.

### Process and trust ownership

- Electron main retains private Plex descriptors, credentials, artwork locators, artwork sessions, persisted files, and player settlement.
- Preload continues to validate one exact renderer-safe Guide result and exposes no raw transport or filesystem material.
- Renderer owns Guide DOM, focus, viewport calculation, scoped reconciliation, Settings presentation, and native-presentation request currentness only.
- Shared contracts contain renderer-safe public shapes only.
- Every diagnostic assertion remains negative proof over serialized safe output. Dummy credentials and connection URIs may exist only as privileged test inputs.

### Playback identity

`DesktopPlayerAdapter` remains the sole adapter snapshot/error mutation owner. A runtime terminal error accepted against `previousRequestId` must be recorded with the adapter's retained current request id when those identities match. `PlexPlaybackRuntime` continues to pass `previousRequestId` only as the settlement guard. It must not rewrite the retained snapshot to a rejected candidate id.

Accepted settlement must produce one identity across the emitted error event, embedded safe error, snapshot `requestId`, and `lastError.requestId`. Stale settlement remains rejected.

### Guide artwork and rendering

- `GuideArtworkSet` has exactly `poster` and `background`; strict preload validation rejects extra keys.
- `projectArtworkRef` accepts and returns `ArtworkRef | null` and preserves the frozen renderer-safe projection.
- `createProgramArtworkSet` explicitly returns `GuideArtworkSet`.
- Reuse refreshes the existing authorization's expiry in place only after all existing identity/current-session checks pass. Generation change, disposal, expiry before reuse, cap exhaustion, or role/locator mismatch still revokes or rejects as today.
- A valid poster fallback is loaded into the background image with the same generation/ref/currentness protections as background artwork. Poster failure terminates in the theme fallback without recursion or stale replacement.
- No raw artwork locator or external URL reaches renderer state; renderer continues to use the self-origin opaque artwork route.

### Guide viewport, composition, and accessibility

- `GUIDE_DOM_ROW_CAP` is the single runtime source for the 24-row mounted cap, including adjacent semantic cap use in the Guide DOM owner. Exact type-level policy literals may remain only when they do not create an independent runtime value.
- Focused-row absolute index, rendered-row absolute index, and virtualization lookup use the same `absoluteIndex ?? channelWindow.offset + localIndex` rule.
- Missing measurement falls back to both density row height and density row gap.
- The pure virtualization projection may build one absolute-index map because it replaces repeated scans and duplicated index derivation. `guideDom.ts` keeps its existing bounded placement lookup; finding `#16` is not revived.
- Absolute-target foreground requests carry both the window owner's `channelOffset` and `channelLimit`.
- Scroll reconciliation updates only Guide workflow DOM, Guide pending state, Guide focus registration/restoration, renderer focus presentation, and Guide tune-pending presentation. It must not invoke Plex, Settings, setup, shell, player-overlay, route, or native-presentation owners.
- The scoped path remains local wiring in the renderer composition root or a cohesive existing Guide renderer owner. Do not create a generic partial-render API.
- The channel header exposes one real `LIVE` status element when `isNowWatching` is true. Do not fabricate a distinct tuned state from the same boolean, and do not use CSS generated text for user-facing labels.
- The status element is hidden from accessibility when the rowheader accessible name already includes `Live`; there is no duplicate announcement.
- The Guide badge label has a valid semantic group target. PIP spacing uses logical inline-end properties consistently for both shell padding and detail margin.

### Native presentation currentness

An initial request with `documentEpoch: null` may accept a successful positive returned epoch. Once a document epoch exists, every later successful settlement requires exact epoch equality in addition to request identity, revision, latest-request, intent, and lifecycle checks. Failure, stale, teardown, and trailing-request behavior remain unchanged.

### Persistence durability policy

Package R7 aligns `DesktopSettingsStore` with the established channel-store publication sequence:

1. create a same-directory private temporary file through an owned file handle;
2. write the complete record;
3. enforce the existing mode policy where applicable;
4. synchronize the temporary file contents/metadata through the handle;
5. close successfully;
6. atomically replace through same-directory rename; and
7. retain best-effort cleanup without replacing the primary fixed safe error.

The filesystem seam must make write, sync, close, rename, and cleanup stages independently testable. A sync or close failure occurs before rename and preserves authoritative destination bytes. A post-rename failure stage is not introduced.

This policy improves resistance to process/OS failure before publication. It does **not** claim that Node's Windows rename is power-loss durable, because the current Node seam exposes neither a portable directory-sync guarantee nor Win32 `MOVEFILE_WRITE_THROUGH`. Parent-directory sync and a native Win32 owner are therefore prohibited by this plan. The residual rename/power-loss limitation must be recorded in the persistence architecture text as a release risk rather than hidden behind the word `durable`.

This package changes only Desktop Settings publication. It does not refactor credential, Guide-preference, or channel persistence into a shared writer. Those owners have different security, CAS, cancellation, and capability invariants; a generic atomic-file helper would increase coupling. The existing channel store remains the stronger precedent, while a future cross-store hardening pass requires separate reviewed scope.

### File-shape dispositions

The following dispositions are frozen before implementation:

- **Owner:** `src/renderer/index.ts`
  **Existing responsibility:** renderer composition and lifecycle wiring.
  **New behavior:** replace scroll-driven whole-app rendering with Guide-only wiring.
  **Decision:** cohesive correction; remove work from the composition root and add no domain policy or generic renderer abstraction. This named composition root requires the one final holistic architecture review.
- **Owner:** `src/renderer/epg/guideDom.ts`
  **Existing responsibility:** Guide DOM, layout, artwork presentation, row semantics, and focusable cell construction.
  **New behavior:** consistent geometry/focus fallback, real poster background fallback, cap alignment, and accessible live status.
  **Decision:** cohesive growth; do not extract a forwarding renderer or add the rejected second map. The >800-line owner requires final architecture review.
- **Owner:** `src/renderer/epg.ts`
  **Existing responsibility:** semantic EPG selection/navigation.
  **New behavior:** deterministic integer page offsets.
  **Decision:** cohesive growth; normalization belongs at the public semantic owner, not the workflow wrapper. The >800-line owner requires final architecture review.
- **Owner:** `src/main/channel/guideRuntime.ts`
  **Existing responsibility:** main-owned safe Guide projection.
  **New behavior:** explicit two-role artwork return contract.
  **Decision:** cohesive contract narrowing; no new owner.
- **Owner:** `src/main/player/desktopPlayerAdapter.ts`
  **Existing responsibility:** player boundary validation, request custody, snapshot and error settlement.
  **New behavior:** retained terminal request-id normalization.
  **Decision:** cohesive growth; this named player boundary requires final architecture review.
- **Owner:** `src/renderer/settingsSetup.ts`
  **Existing responsibility:** Settings section and control presentation policy.
  **New behavior:** truthful enabled state and reason projection.
  **Decision:** cohesive correction; no new settings policy owner.
- **Owner:** `src/main/persistence/desktopSettingsStore.ts`
  **Existing responsibility:** serialized current-schema Settings CAS and atomic replacement.
  **New behavior:** handle-backed pre-rename synchronization.
  **Decision:** cohesive persistence hardening; no shared file-writer abstraction.

Implementation must run `npm run verify:maintainability` and record any changed line-count evidence. Any new production file, dependency, generic service, or unexpected hotspot growth stops for replan.

## Files In Scope

### R1 — playback identity and private-boundary proof

- `src/main/player/desktopPlayerAdapter.ts`
- `src/__tests__/main/player/desktopPlayerAdapter.test.ts`
- `src/__tests__/main/player/playbackRuntimeBootstrap.test.ts`
- `src/__tests__/main/player/productionPlaybackMediaIdentityIntegration.test.ts`
- `src/main/player/plexPlaybackRuntime.ts` and its test only if needed to preserve and prove the unchanged guard call; no behavior edit is expected there

### R2 — Guide artwork contract and authorization

- `src/contracts/artwork.ts`
- `src/contracts/guide.ts` only if the narrowed artwork type requires direct fixture/guard alignment
- `src/preload/guideBridge.cts`
- `src/main/channel/channelPublicReferenceOwner.ts`
- `src/main/channel/guideArtworkOwner.ts`
- `src/main/channel/guideRuntime.ts`
- renderer/test fixtures and focused contract, preload, main, and renderer tests that construct `GuideArtworkSet`

### R3 — Guide sparse geometry and request consistency

- `src/renderer/guideChannelWindow.ts`
- `src/renderer/guideVirtualization.ts`
- `src/renderer/epg/guideDom.ts`
- `src/renderer/index.ts` only for the exact `channelLimit` forwarding and adjacent runtime cap constant
- corresponding Guide window, virtualization, paging, row-density, and DOM tests

### R4 — Guide scoped rendering, poster fallback, and presentation semantics

- `src/renderer/index.ts`
- `src/renderer/routeDom.ts` only if a narrow existing Guide render export is needed without duplicating workflow rendering
- `src/renderer/epg/guideDom.ts`
- `src/renderer/staticDom.ts`
- `src/renderer/styles/guide-epg.css`
- `src/renderer/settingsSetup.ts`
- focused renderer Guide, focus, artwork, settings, accessibility, layout, and composition tests

### R5 — native presentation handshake

- `src/renderer/player/nativePlayerPresentationController.ts`
- `src/__tests__/renderer/nativePlayerPresentationController.test.ts`
- `src/__tests__/renderer/fullscreenTransport.test.ts`

### R6 — review-test maintainability cleanup

- `src/__tests__/renderer/guideChannelWindow.test.ts`
- `src/__tests__/renderer/guidePagingNavigation.test.ts`
- `src/__tests__/renderer/guideDetailArtworkDom.test.ts`
- `src/__tests__/renderer/guideLayoutArtworkDom.test.ts`
- `src/__tests__/renderer/guidePastItemsWindow.test.ts`
- `src/__tests__/renderer/guideRowDensity.test.ts`

### R7 — Settings publication hardening

- `src/main/persistence/desktopSettingsStore.ts`
- `src/__tests__/main/settingsPersistence.test.ts`
- `docs/architecture/security-and-secret-flow.md`
- `docs/architecture/CURRENT_STATE.md` only if its Settings durability wording becomes inaccurate

### R8 — Windows package environment proof

- `tools/__tests__/package-windows-internal.test.mjs`
- `tools/package-windows-internal.mjs` only if the new duplicate-casing fixture exposes a real sanitizer defect; a production change requires controller adjudication before editing

### R9 — deterministic EPG page offsets

- `src/renderer/epg.ts`
- `src/__tests__/renderer/epg.test.ts`
- workflow tests only if required to prove delegation remains unchanged

## Files Out Of Scope

- rejected `guideDom.ts` per-placement map work from finding `#16`
- duplicate merge-rejection settlement/diagnostic work from finding `#31`
- native helper source, helper protocol, player IPC/preload contracts, player command vocabulary, stream policy, PMS cleanup, Plex resolver/transport, and scheduler behavior
- main/preload Guide IPC expansion or renderer-visible private identity
- Plex library clear-logo parsing and non-Guide clear-logo presentation
- credential persistence, Guide-preference persistence, channel aggregate persistence, their schemas, and a shared atomic-file framework
- parent-directory synchronization, Win32 native filesystem calls, installer/signing/updater/release behavior, and unrelated package scripts
- G6/WS5 proof artifacts, parity-matrix closure, roadmap closure, and the pending two-channel operator proof
- upstream source/assets and the import ledger unless implementation discovers actual copying/adaptation
- unrelated user changes or concurrent work; no reset, stash, or broad checkout is authorized

## Execution Packages

Packages execute serially. Before each package, the controller freezes its exact write list, compares it with tracked/untracked changes and active writers, and stops on overlap. A package may use one bounded implementing worker only after its outcome and write boundary are frozen. The controller owns all plan interpretation, integration, and finding adjudication.

No reviewer is used between packages. Exactly one fresh read-only reviewer is invoked once, after R1–R9 are integrated and all pre-review verification is green. If that reviewer reports accepted fixes, the controller routes each fix back to the original implementing worker for that owner seam; no second reviewer is invoked. The controller reruns the affected focused proof and the full final gates after integrating review fixes.

### R1 — Retain one playback terminal request identity

**Outcome:** implement findings `#1`, `#2`, and `#13` without changing playback selection or cleanup policy.

**Required behavior:** exact private URL/header values reach only the injected host context in tests; renderer events, snapshots, and diagnostics remain free of them. Retained terminal settlement normalizes the safe error to the adapter's current request id only when it matches the supplied previous-request guard. Stale or unrelated terminal errors remain no-ops.

**Direct proof:** adapter tests cover event/snapshot/last-error identity agreement and stale rejection; bootstrap and production integration tests assert the exact privileged input and negative serialized safe output.

**Commit:** `fix(playback): preserve terminal request identity`

**Rollback:** revert R1 alone; no public contract or persisted state changes.

### R2 — Narrow and refresh Guide artwork authorization

**Outcome:** implement findings `#10`, `#11`, `#12`, and `#30` atomically across contract, preload, main projection, and every fixture.

**Required behavior:** Guide artwork has two exact roles; strict validation rejects the former extra key. Current repeated projection returns the same ref id/object authorization with an expiry refreshed to a full TTL from the current clock. An already expired authorization is revoked and replaced only through the existing new-ref path. In-flight fetch currentness, generation revocation, cap behavior, role/locator allowlists, alt-text projection, and renderer privacy remain intact.

**Direct proof:** contract/preload exact-key tests, main projection tests, authorization sliding-expiry tests, in-flight fetch tests across refresh, generation invalidation, expiry-before-reuse, cap, locator mismatch, and redaction tests.

**Commit:** `fix(guide): narrow artwork authorization contract`

**Rollback:** revert the entire contract/projection/fixture commit; never partially restore only the contract member.

### R3 — Align sparse Guide geometry and paging

**Outcome:** implement findings `#14`, `#15`, `#18`, `#19`, and `#21`, including the adjacent semantic cap literal in the DOM owner.

**Required behavior:** focus and rendered rows share one absolute-index fallback; density fallback includes row gap; all runtime mounted-row caps derive from `GUIDE_DOM_ROW_CAP`; pure virtualization uses one canonical index map without changing ordering/eviction; foreground absolute requests preserve the window owner's exact limit.

**Direct proof:** no-measurement density, missing-absolute-index focus, first/middle/last sparse windows, focused insertion/eviction, cap, ordering, channel-limit forwarding, stale/cancel behavior, and existing 459/500-channel traversal tests.

**Commit:** `fix(guide): align sparse viewport geometry`

**Rollback:** revert R3 alone; existing paged IPC and Guide contract remain unchanged.

### R4 — Scope Guide scroll rendering and correct UI semantics

**Outcome:** implement findings `#17`, `#20`, and `#23`–`#26` as one renderer-behavior checkpoint.

**Required behavior:** valid poster fallback is visibly loaded and currentness-guarded; poster failure reaches theme; scroll reconciliation touches only Guide/focus/tune presentation; Settings enabled state matches action policy; badges have a semantic group; one real LIVE status represents the single current-channel fact; PIP spacing uses logical inline-end properties.

**Direct proof:** poster load/failure/stale-generation tests; a scoped-reconcile seam or integration instrumentation proving unrelated renderers and native presentation are not invoked; scroll focus retention; Settings control enabled/disabled parity; DOM accessibility assertions; no generated LIVE/TUNED text; Classic/Overlay layout assertions for logical properties.

Do not create a generic renderer callback registry solely to spy on private functions. Prefer public DOM invariants plus the narrowest existing injectable/composition seam. If deterministic proof requires a new production-wide instrumentation seam, stop for replan.

**Commit:** `fix(guide): scope viewport presentation updates`

**Rollback:** revert R4 alone. The preceding sparse-window and artwork contract commits remain valid.

### R5 — Accept the initial native presentation epoch

**Outcome:** implement finding `#22` and the adjacent fullscreen fixture constant cleanup from finding `#3`.

**Required behavior:** a successful positive epoch may establish the first null-epoch request; later requests require exact epoch equality. Applied/hidden/deferred, trailing, stale revision, superseded request, rejection, teardown, and aperture-close behavior retain current semantics.

**Direct proof:** initial applied and hidden positive-epoch success, initial invalid/nonpositive result rejection, later matching success, later mismatch rejection, trailing epoch adoption, and existing teardown/currentness tests. Fullscreen fixtures use `SETTINGS_SCHEMA_VERSION` for both schema fields.

**Commit:** `fix(player): accept initial presentation epoch`

**Rollback:** revert R5 alone; no main/helper protocol changes.

### R6 — Strengthen stable review-test contracts

**Outcome:** implement findings `#4`–`#9` without production behavior changes.

**Required behavior:** non-vacuous Guide row assertions; explicit pending-request preconditions; exact data-attribute boundary; per-selector behavior assertions; complete typed Guide bridge mocks including `setLibraryFilter`; density-derived arithmetic; deletion of the unowned `9px` literal assertion.

The typed mock must satisfy the real bridge contract rather than cast away missing members. Do not introduce a generic fixture framework or CSS parser abstraction.

**Commit:** `test(guide): strengthen behavior contract coverage`

**Rollback:** revert R6 alone.

### R7 — Harden Settings publication honestly

**Outcome:** implement valid follow-up `#28` using the frozen Node-level Windows policy.

**Required behavior:** private same-directory temp write, file sync, successful close, then rename; every pre-rename failure maps to the fixed safe operation error, attempts owned-temp cleanup, and preserves destination bytes. No directory sync or power-loss-safe rename claim is added.

**Direct proof:** ordered write/chmod-or-policy/sync/close/rename observation; independent write, sync, close, and rename failures; cleanup success/failure; destination preservation for all pre-rename failures; successful real-filesystem round trip and POSIX mode proof where applicable. Architecture text distinguishes serialized/atomic replacement from residual Windows power-loss durability.

**Commit:** `fix(persistence): sync settings before publication`

**Rollback:** revert code, tests, and associated architecture wording together. Persisted schema and bytes remain compatible.

### R8 — Prove case-insensitive package environment sanitization

**Outcome:** implement finding `#27`.

**Required behavior:** forbidden-key assertions inspect every case-insensitive environment-key match; fixtures include duplicate casing. PATH lookup may keep a value-returning helper, but forbidden checks use a presence helper that cannot stop at the first benign/missing match.

If the fixture exposes a production sanitizer defect, stop R8, let the controller confirm the package script is within the same security finding, then apply the smallest sanitizer correction and retain the same commit intent.

**Commit:** `test(packaging): cover duplicate environment casing`

**Rollback:** revert R8 alone.

### R9 — Normalize semantic EPG page offsets

**Outcome:** implement valid follow-up `#29` in `pageEpgSelection`, not `applyWorkflowEpgPage`.

**Required behavior:** finite fractional offsets are truncated to an integer; non-finite offsets normalize to zero; existing boundary clamping and ready-state rules remain deterministic. A zero normalized movement must not fabricate a state change.

**Direct proof:** positive and negative fractional offsets, `NaN`, positive/negative infinity, zero, ordinary page movement, and lineup boundary tests at the public EPG seam.

**Commit:** `fix(epg): normalize page selection offsets`

**Rollback:** revert R9 alone.

### Integrated review and review-fix checkpoint

After R1–R9 and all pre-review gates pass, invoke exactly one fresh holistic reviewer over the integrated commit range. The packet must include this plan, the amended Guide-plan conflicts, all nine commits, file-shape dispositions, persistence residual risk, focused/full verification evidence, and the unchanged G6/WS5 proof debt.

The reviewer must inspect correctness, security/redaction, process boundaries, contract exactness, persistence honesty, renderer composition, focus/accessibility, test quality, over-engineering, and commit separability. The controller alone adjudicates findings. Accepted fixes return to the original worker for the affected package and land as a conventional `fix(...)` or `test(...)` follow-up commit scoped to that seam. No second reviewer, parallel reviewer, or package-level reviewer is authorized.

## Verification Commands

**Verification classification:** new regression/contract test required

Run each package's focused command before its commit:

- R1: `node --import tsx --test src/__tests__/main/player/desktopPlayerAdapter.test.ts src/__tests__/main/player/playbackRuntimeBootstrap.test.ts src/__tests__/main/player/plexPlaybackRuntime.test.ts src/__tests__/main/player/productionPlaybackMediaIdentityIntegration.test.ts`
- R2: `node --import tsx --test src/__tests__/contracts/contracts.test.ts src/__tests__/integration/preloadContractVocabulary.test.ts src/__tests__/main/channelPublicReferenceOwner.test.ts src/__tests__/main/guideArtworkOwner.test.ts src/__tests__/main/guideRuntime.test.ts`
- R3: `node --import tsx --test src/__tests__/renderer/guideChannelWindow.test.ts src/__tests__/renderer/guidePagingNavigation.test.ts src/__tests__/renderer/guideRowDensity.test.ts src/__tests__/renderer/guideVirtualization.test.ts src/__tests__/renderer/epg/guideDom.test.ts`
- R4: `node --import tsx --test src/__tests__/renderer/guideDetailArtworkDom.test.ts src/__tests__/renderer/guideLayoutArtworkDom.test.ts src/__tests__/renderer/settingsSetup.test.ts src/__tests__/renderer/epg/guideDom.test.ts src/__tests__/renderer/routeDom.test.ts src/__tests__/renderer/rendererRuntimeOwners.test.ts`
- R5: `node --import tsx --test src/__tests__/renderer/nativePlayerPresentationController.test.ts src/__tests__/renderer/fullscreenTransport.test.ts`
- R6: `node --import tsx --test src/__tests__/renderer/guideChannelWindow.test.ts src/__tests__/renderer/guidePagingNavigation.test.ts src/__tests__/renderer/guideDetailArtworkDom.test.ts src/__tests__/renderer/guideLayoutArtworkDom.test.ts src/__tests__/renderer/guidePastItemsWindow.test.ts src/__tests__/renderer/guideRowDensity.test.ts`
- R7: `node --import tsx --test src/__tests__/main/settingsPersistence.test.ts`
- R8: `node --test tools/__tests__/package-windows-internal.test.mjs`
- R9: `node --import tsx --test src/__tests__/renderer/epg.test.ts`

Expected focused outcome: all selected tests pass with no skip newly introduced. R2 must also run `npm run typecheck` before commit because it atomically changes a public contract. R1, R3, R4, R5, R7, and R9 run `npm run typecheck` before commit because they change production TypeScript. R8 runs the complete package test file because the environment sanitizer is a packaging security boundary.

Before the single holistic reviewer, run and observe:

- `npm run typecheck`
- `npm run build:electron`
- `npm run smoke:electron`
- `npm run verify:architecture`
- `npm run verify:maintainability`
- `npm run verify:redaction`
- `npm run verify:docs`
- `npm run verify`
- `git diff --check`

Expected outcome: all commands succeed; maintainability output is reconciled with the dispositions above; redaction finds no private URL/header/credential/connection material; Electron build and ordinary smoke remain unchanged; docs verification accepts the active plan and persistence wording.

After any accepted review-fix commit, rerun its package-focused command, `npm run typecheck` when TypeScript changed, and the complete final command set above. Do not invoke another reviewer.

G6/WS5 Windows/live/native/manual proof is intentionally not run or claimed by this remediation. Its absence does not block these correction commits, and these corrections do not reduce that later proof obligation.

## Acceptance Criteria

- All authorized findings `#1`–`#15` and `#17`–`#30` are implemented or, for the test-only findings, reflected in stable seam-focused coverage.
- Findings `#16` and `#31` have no implementation residue.
- Private playback URL/header values reach the host test seam but never renderer events, snapshots, diagnostics, or serialized safe output.
- Runtime terminal error event and snapshot identities agree without adopting a rejected candidate id.
- `GuideArtworkSet` has exactly poster/background, strict validation is aligned, and active same-identity reissue refreshes expiry in place without weakening revocation/currentness/caps.
- Poster fallback visibly loads; its stale/error paths end safely in the current poster or theme state.
- Guide focus, geometry, mounted caps, virtualization, and request sizes share one absolute-window policy.
- Scroll-driven Guide reconciliation does not invoke unrelated app renderers or native-presentation reconciliation and preserves focus/tune/pending behavior.
- Initial native presentation can establish a positive epoch; later epoch mismatch remains stale.
- Settings enabled states, badge semantics, LIVE presentation, accessible names, and logical PIP spacing agree with actual state.
- Windows package tests detect every case-insensitive forbidden environment-key occurrence.
- Settings writes synchronize and close the temp file before rename, preserve old bytes on every pre-rename failure, and make no false Windows power-loss durability claim.
- EPG paging is deterministic for fractional and non-finite offsets in the EPG owner.
- Every commit is conventional, reviewable, independently reversible at its owner seam, and contains no unrelated user work.
- Exactly one holistic reviewer is used once after integration; accepted review fixes return to the original implementing worker and all final verification is green.
- G6/WS5, RD-27, affected parity rows, and the pending two-channel operator proof remain explicitly open.

## Replan Triggers

Stop the affected package and return to controller-owned planning when:

- the worktree or exact package file list overlaps unrelated user changes, an active writer, the pending G6/WS5 proof bundle, or an unresolved playback remediation;
- terminal request normalization requires changing candidate selection, cleanup custody, helper protocol, or player public contracts;
- removing Guide `logo` breaks a current production consumer outside the discovered Guide projection/validation/fixture surface;
- sliding artwork expiry requires replacing authorization object identity, widening session lifetime/caps, or exposing a raw locator;
- scoped Guide rendering cannot preserve focus, pending filter, tune state, artwork currentness, or viewport refresh without a generic renderer framework or duplicated workflow projection;
- deterministic proof of scoped rendering requires production-wide instrumentation or a private global test hook;
- a new IPC method, renderer privilege, shared persistence abstraction, dependency, compatibility shim, or new production owner appears necessary;
- Settings durability requires parent-directory sync, native Win32 calls, a power-loss guarantee, or changing credential/Guide/channel persistence in the same package;
- the duplicate-casing packaging fixture exposes behavior outside environment sanitization;
- EPG normalization changes the public input type or navigation semantics beyond integer coercion;
- implementation copies/adapts upstream source or assets without an import-ledger decision;
- a package cannot remain independently buildable, focused tests fail for a reason outside its seam, or a conventional rollback would leave contract/caller mismatch;
- maintainability evidence shows unrelated hotspot growth or a composition root gains domain policy;
- pre-review or final full verification is not green; or
- the one holistic reviewer identifies an unresolved material issue that requires ownership, public-contract, security, persistence, or proof-policy expansion. Because no second reviewer is authorized, material expansion after that review requires a new user-approved plan rather than silent continuation.

## Rollback And Commit Checkpoints

Use the nine conventional commits named under R1–R9 in order. R2 is an atomic shared-contract checkpoint and must never be split between contract and consumers. R3 precedes R4 so the scoped renderer consumes settled sparse-window policy. Other commits remain semantically independent.

If a package fails before commit, revert only its owned hunks with a reviewed patch; do not reset, stash, or overwrite the shared worktree. If a committed package fails integration, revert that commit and any later commit that directly depends on it, then re-run the preceding checkpoint's focused proof. Persistence rollback never adds a schema migration, and Guide artwork rollback restores the complete former exact shape rather than a mixed validator/contract state.

After closeout, move durable policy changes into the named architecture/current-state surfaces, preserve G6/WS5 open proof truth, and archive this completed plan body according to the runbook.

## Handoff

NEXT_SESSION_HANDOFF
NEXT_SESSION_LAUNCHER: `lineup-desktop-feature-implement`
TASK: Implement the accepted-suggestion Tier 3 remediation packages
TASK_FAMILY: feature/design
TIER: Tier 3
PLAN: `docs/plans/2026-08-11-accepted-suggestion-remediation-plan.md`
ARTIFACT: the controller-provided 2026-08-11 accepted-suggestion review attachment
FILES:
- `docs/plans/2026-08-11-accepted-suggestion-remediation-plan.md`
- `docs/plans/2026-08-10-guide-continuous-lineup-visual-parity-plan.md`
- current owners named in R1-R9
BLOCKERS: The controller must adjudicate this plan directly before dispatch; G6/WS5 Windows/live/native proof and the two-channel operator proof remain pending but do not block these code corrections
MESSAGE:
After controller-only plan adjudication, execute R1-R9 serially with exact collision checks and focused proof. Preserve the three explicit Guide-policy amendments, disjoint playback/Guide/persistence/packaging owner seams, Windows-first honest Settings publication policy, file-shape dispositions, nine reversible commits, and G6/WS5 proof debt. Findings #16/#31 remain excluded. Do not dispatch any reviewer during implementation. After every package is integrated and pre-review verification is green, invoke exactly one fresh holistic reviewer once; route accepted fixes back to the original implementing worker for that seam, then rerun focused and full verification without a second reviewer.
