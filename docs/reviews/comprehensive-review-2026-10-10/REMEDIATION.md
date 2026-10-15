# Production remediation plan

Planning only, October 10, 2026. **No implementation, permanent tests, patches or implementation chats are authorized by this document.**

Source: [REPORT.md](REPORT.md), HEAD 4fb7758034f4f47290fae13a4ea8275860ba1284, branch codex/desktop-ui-second-pass. Reviewed source and current obligations are in [the report's scope and provenance](REPORT.md#target-boundaries-and-provenance) and [INPUT_IDENTITY.json](INPUT_IDENTITY.json); the original census is available in [Git history](../../README.md#historical-material-in-git). The plan uses the repo-production-remediation-plan skill. “Accepted” means retained after evidence adjudication, not user approval to implement.

## Scope and constraints

Accepted: F-001–F-007 confirmed; F-008 likely and gated. Preserve Flutter interaction/application ownership, native mechanism ownership, durable save/publication ordering, credential separation, reference/redirect security, current approved UI and data contracts. Do not replace existing meaningful fixtures or weaken negative/security checks to obtain green results.

Excluded: old resolved October 7 findings, speculative rewrites, aesthetic redesign, arbitrary test-count/coverage work, docs-only drift, planned transcoding/automatic fullscreen HDR, macOS playback, deployment and publication.

Parked: CAND-009 early EOF ordering, CAND-010 mounted artwork refresh, CAND-011 aggregate playlist scale, H1 live Plex response shapes, existing F15 buffering observation, and documented product-parity limitations. No corrective work is ready for these until evidence/authorization changes.

No schema migration is expected for the confirmed packages. If implementation discovers one, stop and define data preservation/migration/rollback before changing storage. Existing dirty review/design work must be preserved.

## Summary and sequence

Seven packages follow coherent owners. P-001–P-006 are ready for implementation approval; P-007 needs Windows facts and D-001 first. P-005 is a small but important prerequisite to treating authenticated-reference CTest results as usable positive/negative runtime acceptance. It need not block unrelated portable fixes.

P-006 has the broadest playback regression surface; P-004 has the broadest numeric consumer surface. P-002 joins two related Guide focus/edit ownership defects but must preserve their separate behavioral proof. P-003 should settle lifecycle ownership rather than add timeouts around callers.

| Package | Findings | Goal / scope | Gate and readiness |
|---|---|---|---|
| P-001 profile completion | F-001 | Separate accepted PIN/profile commit from server recovery | Real-shell precommit failure and existing origin/save controls; ready for approval |
| P-002 Guide input ownership | F-002/F-003 | Focused controls activate; raw edits survive unrelated notifications | Actual key and interleaving widget assertions; ready for approval |
| P-003 worker readiness | F-004 | Every startup/build future settles on disposal/failure | Deterministic lifecycle permutations plus actual isolate stress; ready for approval |
| P-004 temporal schedule validity | F-005 | Reject unusable item/cycle arithmetic before publication | Parser/persisted/direct inputs, schedule/consumer typed failure; ready for approval |
| P-005 reference harness completion | F-006 | Successful ended terminal recognized without weakening rejection | Release-active decoder controls + Windows pinned CTest; ready for approval, runtime gate later |
| P-006 multipart seek coordinates | F-007 | Seek uses displayed local/aggregate coordinate contract | Later-part incomplete metadata and complete controls; ready for approval |
| P-007 path ancestry policy | F-008 | Consistent intended physical containment before output mutation | D-001 + W-012 prerequisite; evidence/decision dependent |

## P-001 — Profile acceptance and server recovery

**Owner:** application/onboarding engineer. **Findings/evidence:** F-001, E-009, independent C calibration.

**Goal/expected behavior:** Once profile authentication and state persistence commit, PIN presentation retires. Delayed connection/library/precommit server-save failure exposes Servers recovery. An invalid PIN or failed profile save still leaves appropriate PIN/profile recovery.

**Scope:** controller selectProfile/_discoverServers/selectServer completion semantics; onboarding PIN presentation and stage lifetime; necessary real-shell fixtures/assertions. Primary files: lib/app/lineup_controller.dart, lib/app/onboarding_view.dart; shell only where an actual presentation contract requires it; test/app/lineup_controller_test.dart and existing onboarding/shell suites.

**Approach:** Give accepted profile commit a result/lifetime independent of downstream reconnect currentness. Make presentation follow committed state. Preserve supersession checks; do not return success for failed profile persistence. Avoid merely suppressing the epoch guard or forcing a visual clear on any completion.

**Non-goals:** account model redesign, new credential persistence, new screen design, authentication error taxonomy changes, token compensation policy.

**Verification:** Reuse FixtureStore, synthetic credentials/Plex and real LineupController/LineupShell. Send PIN keys; gate/fail connection, library enumeration and server save before commit. Assert correct profile durability, busy/error recovery, PIN dismissal and visible server options. Controls: wrong PIN, failed profile save, no saved server, success, postcommit restoration replacement, superseding profile selection and Back/Escape origin. Run affected app suites and analyzer; W-010 adds actual protected account/server failure recovery.

**Risks/rollback:** Confusing acceptance with currentness could publish stale scope or clear valid wrong-PIN feedback. Restore prior implementation if regression; no data rewrite. Preserve old-scope authorization until successful persistence.

**Dependencies/open decisions:** No product decision or unrelated package prerequisite. Coordinate edits with anyone changing controller completion APIs.

## P-002 — Guide focus and raw search editing

**Owner:** Flutter interaction engineer. **Findings/evidence:** F-002/F-003, E-011, A calibration.

**Goal:** Grid activation occurs only in its focus context; focused buttons/dropdowns/retry receive Enter/Space/Select. Raw text, caret and composition survive schedule/live/settings notifications while normalized matching still works.

**Scope:** lib/guide/guide_view.dart key dispatch/editor synchronization, lib/guide/guide_controller.dart only if a minimal explicit external-search signal is necessary; existing Guide/navigation widget suites. Shared controls change only if their actual contract needs it.

**Approach:** Align logical program selection and Flutter focus ownership. Prefer cohesive focus/Actions scoping over an expanding list of button-specific exceptions. Distinguish externally requested search/reset from local editor-to-query normalization. Preserve useful controller APIs and external-search behavior without mirroring normalized state on every notification.

**Non-goals:** Guide layout/navigation redesign, new shortcuts, menu redesign, IME framework replacement, speculative shared input abstraction.

**Verification:** Real key events on menu, close/Now, hours/library dropdown and row-local Retry with ready/error mixed rows; assert intended action and zero unintended tune. Controls: grid activation tunes, search edits stay local, global chords still reach shell, popup navigation and menu trap/restoration work. Search: trailing space across another row completion, midpoint/case edit with selection, composition preservation using editing values, explicit external query/reset, empty/multiword matching. Keep F-002 and F-003 assertions distinct. Run relevant Guide/navigation tests; required alpha suite when shared layout/render structure changes, otherwise reuse unaffected baseline until integration. W-009 is physical keyboard/remote/IME/AT acceptance.

**Risks/rollback:** Overbroad key propagation could activate two actions or disable grid shortcuts; overly local editor state could ignore content-scope resets. Revert behavior as one coherent package if necessary; no persisted data changes.

**Dependencies/open decisions:** No new visual approval needed; restore existing input contracts. Independent of other packages unless shared shell state is edited.

## P-003 — Explicit worker startup settlement

**Owner:** Dart scheduling/concurrency engineer. **Finding:** F-004, E-008, B calibration.

**Goal:** A build awaiting handshake completes normally or with an owned cancellation/error when dispose/start failure occurs. No unreachable completer remains.

**Scope:** lib/channels/schedule_worker.dart readiness/disposal/error ownership; existing test/channels/schedule_worker_test.dart; controller callers only for a required contract adjustment.

**Approach:** Retain and settle startup readiness through a single lifecycle owner, including disposal before spawn, during spawn, between spawn and handshake, and after readiness. Ensure idempotent settlement, kill/port cleanup and rejection of late messages. Do not fix the symptom by adding independent arbitrary timeouts to every caller.

**Verification:** Existing real worker normal/retry tests; deterministic handshake/dispose seam if feasible with minimal production surface; immediate/microtask/queued-event disposal; simultaneous waiting builds; spawn/exit failure; dispose twice; late message; new worker after failure. Actual isolate repetition is supplemental race evidence. Assert settlement and resource cleanup, not exact timing alone. Preserve Guide deadline/currentness and Air Check queue tests where touched.

**Risk/safety/rollback:** Double completion, use-after-dispose and leaked ports/isolates. No persistence migration or credential involvement. A focused revert restores former behavior but reopens the race; retain evidence until replacement passes.

**Dependencies:** Independent owner; serialize SDK execution with other packages. No Windows acceptance required for the pure Dart invariant, though ordinary Windows app smoke remains part of release acceptance.

## P-004 — Valid temporal schedules and owned projection failure

**Owner:** channel/scheduler engineer. **Finding:** F-005, E-010, A calibration.

**Goal:** A successfully published ScheduleIndex has representable item/cycle/transition arithmetic for its supported projection contract. Invalid external or persisted duration yields the existing typed invalidProgramDuration outcome and usable recovery, never a silently truncated program.

**Scope:** scheduler checked validation/arithmetic and necessary channel/parser validation; Guide/Air Check projection completion/error ownership if they can still receive invalid projection results. Primary files lib/channels/scheduler.dart, lib/channels/channel.dart, lib/plex/plex_client.dart, lib/guide/guide_controller.dart, lib/channels/channel_air_check.dart, with existing domain/Plex/controller tests.

**Approach:** Define numeric invariants from Dart Duration/DateTime and actual schedule anchor/projection usage. Check cumulative and transition arithmetic before publishing. Do not choose an arbitrary maximum film length without a product requirement. Preserve deterministic shuffle, duplicate occurrences, sequential/block semantics and anchor migrations. Consumers should route projection failures through their normal error owner and avoid retaining a poisoned cache.

**Non-goals:** schedule algorithm rewrite, shortening media, new persisted schema, unrelated performance tuning or catalog limits.

**Verification:** Real parseMediaItem→channelItemFor→buildSchedule→programAt/scheduleWindow; normal duration, one extreme value, cumulative overflow, boundary/transition values and direct/persisted items. Assert stable typed failure before publication. Exercise Guide/Air Check loading-success/projection-failure path to prove owned error/retry and cache behavior. Reuse DST/fold/midnight/large-elapsed/determinism/participation tests; full New York suite at integration. Live invalid catalog reproduction is unnecessary for the numeric fact.

**Risks/rollback:** Valid long schedules rejected, subtle DST/anchor overflow, mismatched main-isolate/worker serialization. Preserve original stored bytes and signal errors; no automated data cleanup. Revert algorithm and consumer changes together if necessary.

**Dependencies:** Independent of P-003 with disjoint scheduler/worker ownership; coordinate shared tests. No unresolved product decision unless a deliberate new domain cap is proposed.

## P-005 — Native reference harness terminal contract

**Owner:** Windows/native verification engineer. **Finding:** F-006, E-013, independent D/E evidence.

**Goal:** A successful short authenticated MP4/MKV ending naturally completes the observation, while any rejection remains failure regardless of later states.

**Scope:** windows/runner/authenticated_reference_test.cpp and necessary Python expectations/fixtures in tool/windows/authenticated-reference-test.py; native production behavior should remain unchanged unless new evidence requires otherwise.

**Approach:** Treat ended as successful terminal observation and extend existing Release-active real-codec contract cases. Preserve progress requirement, monotonic rejection, blocked redirects/nested references, rejected required-option and untrusted-CA controls. Do not make progress alone success or send artificial Stop to conceal the mismatch.

**Verification:** Compile actual Release harness, run ended/progress→ended/error→ended and existing error→stop cases with assertions active. Then documented authenticated_reference CTest three times against exact prepared/copied DLL hashes, all positive/negative controls present. W-002 records results. A portable source trace cannot close the execution gate.

**Risks/safety/rollback:** Early termination can miss a queued rejection; terminal recognition must preserve observation ordering and rejection latch. Test-local CA/null outputs remain isolated, no trust-store or production option changes. Revert harness correction if negative controls weaken; do not revert correct production EOF semantics to satisfy old tests.

**Dependencies:** Approve independently; before a later campaign relies on authenticated-reference positive controls. Does not require P-006, and does not itself authorize Windows campaign execution.

## P-006 — Consistent multipart seek coordinates

**Owner:** playback coordinator engineer. **Finding:** F-007, E-012, E calibration.

**Goal:** Public position/duration and all interactive seek entry points agree: current-part fallback seeks within active part; known aggregate timeline seeks across parts.

**Scope:** lib/playback/player_coordinator.dart public timing/seek mapping; Player slider/caller only if interface needs explicit coordinate context; existing coordinator/Player tests.

**Approach:** Centralize coordinate-mode decision without duplicating media policy in view/native code. Keep initial live join and active interactive seek semantics distinct. Preserve pending target replacement, authorization refresh/retry, stale generation rejection, loaded-program identity and complete-map cross-part seeks.

**Verification:** Reuse frozen continuation fixture with first=60 seconds, second metadata absent, second native position=10/duration=90. Forward +30 and backward within the part must not load part one; slider target must match displayed local position. Complete metadata positive control must retain aggregate cross-part behavior. Add later-part unknown boundaries, map becoming complete at EOF, repeated seeks during pending readiness, auth replacement and superseded continuation. Existing stop/readiness/seek/load suites remain relevant. W-003 verifies physical multipart and transport/slider behavior with exact runtime.

**Non-goals:** transcode/HDR work, speculative precommit EOF fix, native seek protocol change unless independently needed.

**Risks/rollback:** Changing live-join mapping or clamping may regress tune offsets; carry separate initial-load controls. No persisted format changes. Revert coordinator/caller change coherently; preserve diagnostic reproduction.

**Dependencies/open decisions:** No product decision; user guide already specifies fallback. P-005 only gates reference-harness evidence, not implementation of this package.

## P-007 — Build/package ancestor containment (gated)

**Owner:** release tooling engineer. **Finding:** F-008 LIKELY, E-013/C calibration.

**Prerequisites:** W-012 actual Windows reproduction and D-001 explicit policy for linked build roots. Until both are resolved, this is an investigation/correction outline, not ready behavior change.

**Expected behavior if strict policy is confirmed:** Reject unsupported reparse components below the repository boundary before marker removal, Flutter build writes or package copy/archive creation. Legitimate ordinary paths, spaces and unique package destinations keep working.

**Scope:** shared tool/windows/build-inputs.ps1 plus build-release.ps1/package.ps1 ordering, focused policy/Windows CI controls and exact operational documentation for the resolved policy.

**Approach:** One authoritative ancestry policy used by relevant producers/consumers. Preserve existing tracked-symlink, descendant reparse, dirty-source, marker/artifact/runtime/license hash checks. Explicitly state any supported linked-root exception; do not silently impose a global filesystem policy or reject unrelated ancestors above the repository.

**Verification:** Disposable clean checkout with owned target: ordinary output control, current descendant-junction rejection, build ancestor junction, marker-present case and package no-overwrite. Assert expected rejection before external mutation using directory inventories/hashes, then ordinary valid artifact package. Real PowerShell/Windows only; no Python imitation. Run verify-release-policy.ps1 and applicable Windows package tests. W-012 and W-013 separate path and exact-package outcomes.

**Risks/safety/rollback:** New restrictions may break intentional linked build workflows; TOCTOU protection is not guaranteed merely by a preflight walk. Do not claim protection from a concurrently hostile local actor without such a requirement/design. Never repoint the user's existing build tree; cleanup removes only operation-owned links/targets. No saved application data changes.

**Dependencies/decision:** D-001 may reject strict containment; if so, document intentional supported behavior and reconsider F-008 rather than implementing this outline automatically.

## Verification and integration matrix

| Proof obligation | Cheapest faithful evidence | Broader gate / limit |
|---|---|---|
| PIN/stage recovery | Existing real shell/controller, gated Plex and store; actual digit keys | W-010 actual account; not fake-profile-only |
| Guide activation/raw edit | Focused control key events and schedule notification interleaving | W-009 physical focus/remote/IME; alpha when render tree changes |
| Worker completion | Explicit lifecycle assertions + real isolate control | No timeout-only claim of permanence |
| Temporal validity | Real numeric owners, direct/persisted/parser inputs, typed failure consumer | Existing New York schedule suite; no arbitrary duration cap |
| Native test terminal | Real Release codec contract and pinned DLL CTest | W-002 headless only, not GPU output |
| Multipart seek | Real coordinator fixture, local/aggregate controls | W-003 physical multipart/seek |
| Path policy | Real script in isolated Windows junction fixture | D-001/W-012 before behavior change; W-013 exact package |

After separately approved implementation, run affected suites while iterating. At integration, rerun format without writes, analyzer and full TZ=America/New_York Flutter suite once on stable merged inputs; retain required Guide alpha inclusion. Run PowerShell policy when tooling is touched and the executable is available. Do not repeat unaffected broad checks merely to accumulate passes. Preserve source/toolchain/runtime identity and distinguish new execution from reused evidence.

Independent implementation can overlap with disjoint ownership; shared controller, Guide or test inputs must have one integration owner. No fixed panel or sequential pipeline is required. A reviewer should challenge each corrected mechanism and relevant negative controls, not demand unrelated cleanup.

## Parking lot and stop

CAND-009 needs real adapter/native ordering evidence before a continuation fix. CAND-010 needs reachable mounted refresh. CAND-011 needs credible live scale/budget observations. H1 and F15 remain live/physical evidence work. Minor doc drift and spelling tests have no material corrective package.

Next authorization may approve selected ready packages, the separately bounded Windows observation campaign, or D-001. This plan dispatches none of them.

