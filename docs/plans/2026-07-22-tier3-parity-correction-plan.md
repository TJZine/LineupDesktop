# 2026-07-22 Tier 3 Parity Correction Plan

**Plan Status:** active
**Task family:** feature/design
**Tier:** Tier 3

## Goal

Close every open stable ID in the 2026-07-22 product parity audit through nine dependency-ordered workstreams, beginning with a real channel builder and ending with packaged Windows proof. Preserve desktop ownership and security boundaries while adapting only the useful, audited builder semantics from upstream Lineup commit `0258dbe`.

This is the canonical durable handoff for the full parity-correction program. It is not evidence that any row is implemented or proven. A row moves only when its own implementation and proof criteria are observed. `RD-27` remains blocked until WS1–WS8 plus WS9 prerequisite implementation/hardening are complete and reviewed and the current Windows proof plan has been refreshed. It then executes as WS9's observation/soak phase; reviewed RD-27 completion unblocks the subsequent RD-28 internal package lifecycle proof. Program closeout follows only after WS9, RD-27, and RD-28 all close.

Codanna was available during planning, but its current index returned no useful semantic match or `ChannelRuntime` symbol for the builder owners. Discovery therefore fell back to `rg`, direct reads of current source and tests, and scoped reads of the audited upstream checkout.

## Non-Goals

- Do not copy the upstream browser application, storage/session owners, network boundary, or UI framework.
- Do not expose Plex tokens, raw Plex payloads, endpoint URIs, machine paths, or unrestricted request facilities to preload or renderer code.
- Do not turn `src/domain/channel/channelManager.ts`, `src/main/channel/guideRuntime.ts`, or `src/domain/scheduler/channelScheduler.ts` into channel-builder policy owners.
- Do not merge Channel Builder and Custom Channels into one feature. They may share the persisted lineup mutation coordinator only.
- Do not infer builder completion from existing channels during migration.
- Do not claim live Plex, packaged Windows, accessibility, performance, or visual proof from unit tests or synthetic fixtures.
- Do not promote later-workstream file guesses into scope. Their exact paths require a freshness read and review when that workstream becomes active.
- Do not begin WS3 through WS9 product implementation while an earlier
  workstream is active. WS2 is the sole exception: the reviewed
  `ACTIVE_WS1_PROOF_DEFERRAL_AND_WS2_ENTRY_OVERRIDE_2026_07_28` below permits
  WS2 planning and later reviewed implementation while WS1 proof debt remains
  open.

## Architecture And Invariants

### Program ownership and dependency order

The controller executes the workstreams in this order:

1. **WS1 — Channel Builder:** safe Plex facets, deterministic planning, atomic application, cancellation, renderer setup/review/result flow, and focused proof.
2. **WS2 — Playback:** playback correctness and the player surface needed by later media settings and input work; `PB-22`–`PB-24` implementation lands here but remains open through the WS3 preference/control contribution and any required native/Windows proof.
3. **WS3 — Settings:** persisted behavior settings, including media and guide preferences, after the relevant runtime hooks exist; `ST-11`–`ST-16` contracts/persistence land here but remain open through their WS5 Guide/EPG consumers, and `ST-23` must implement and verify the persistent Settings “Switch Profile” affordance before WS8 can close `ON-08`.
4. **WS4 — Input And Overlay:** keyboard, D-pad, mouse, gamepad, remote, overlay, and navigation behavior after playback contracts are stable.
5. **WS5 — Guide:** guide behavior and presentation after builder lineup and guide settings are stable.
6. **WS6 — Custom Channels:** distinct custom-channel behavior after WS1 stabilizes the shared lineup persistence boundary.
7. **WS7 — Fresh UI Proof:** current-upstream visual comparison only after WS1–WS6 behavior is complete.
8. **WS8 — Credential And Lifecycle:** remaining onboarding, Plex, lifecycle, and recovery closure after all runtime hooks exist, including the live/profile-switch lifecycle proof for `ON-08` after the WS3 `ST-23` persistent Settings affordance contribution, and the shared main-owned power-request and sleep/resume implementation prerequisite for WS9's `PB-27` proof.
9. **WS9 — Packaging And Soak:** the program wrapper for prerequisite packaging/runtime hardening, RD-27 Windows observation/soak, and subsequent RD-28 internal package lifecycle proof.

WS2 must precede the media-dependent portion of WS3 and WS4. WS3 supplies the `PB-22`–`PB-24` preference/control contribution and freezes `ST-11`–`ST-16` contracts before WS5 consumes them for `EPG-08`–`EPG-13` as applicable. WS3 must also complete and verify `ST-23`'s persistent Settings “Switch Profile” affordance before WS8 may claim `ON-08` closure; WS8 remains the owner of live/profile-switch lifecycle proof and contributes that proof back to `ON-08` without taking `ST-23` registry ownership. WS6 may start only after WS1's lineup persistence and mutation coordinator are stable, and it must close before WS7 when its rows change visible surfaces. WS8 follows the feature work whose runtime lifecycle it proves and must close its reviewed local/non-packaged power-lifecycle gate before WS9. WS9 starts only after WS1–WS8 close and then executes its three subphases serially; it preserves rather than cancels or supersedes the roadmap's RD-27 and RD-28 owners.

| Contribution gate | Implementation/verification owner | Closure/proof owner | Required closure condition |
| --- | --- | --- | --- |
| Persistent Settings profile switch → onboarding/profile lifecycle | WS3 `ST-23` | WS8 `ON-08` | `ST-23` implements and verifies the persistent Settings “Switch Profile” affordance first; only then may WS8 execute live/profile-switch lifecycle proof, and `ON-08` remains open until both contributions pass. |

### WS9 wrapper and RD-27/RD-28 gates

At WS9 freshness opening, before any WS9 product change or proof execution, update the roadmap through its normal reviewed authority-doc path to record this exact wrapper mapping and unblock sequence. That gate is a future WS9 authority update, not permission for this plan revision to edit the roadmap. Then refresh and adversarially review WS9 with bounded owner surfaces but no inherited file guesses from this plan.

That same freshness opening must make and record one explicit reviewed product-scope/release-authority decision for the broad existing `PKG-03` row before any `PKG-03` implementation or proof:

- **Alternative A — approved private-MVP posture:** only after explicit product/release approval, update the matrix and roadmap through their reviewed authority path to classify public installer distribution, signing, and updater delivery as an intentional divergence/deferred release posture with a concrete rationale and revisit trigger. WS9 prerequisite hardening then implements the approved internal installer behavior, and RD-28 proves the internal install/uninstall/delete lifecycle. This does not silently redefine the row: its acceptance is the approved divergence/defer decision plus the internal lifecycle implementation/proof.
- **Alternative B — public release posture:** create and approve a separate release plan that extends WS9 prerequisite hardening with exact owners/files for a public installer, signing, and updates, then implement and prove that release surface before `PKG-03` can close.

There is no default between A and B and no implementer may choose one locally. Until one decision is recorded in the reviewed authority surfaces and all acceptance belonging to that alternative passes, `PKG-03`, WS9 completion, and program closeout remain blocked. RD-28's internal package lifecycle evidence alone cannot close the current broad matrix row.

WS9 executes exactly these serial subphases:

1. **Prerequisite implementation/hardening:** freshness-read the assigned rows, current owners/tests, packaging/release architecture, the reviewed WS8 power-lifecycle gate, and relevant upstream behavior; record and approve the Alternative A or B `PKG-03` release-posture decision above; then freeze and review exact files for missing `PKG-02` and the decision-approved `PKG-03` behavior and any runtime/package correction required by partial `PB-28` or `WIN-05`. WS9 does not invent a second `PB-27` lifecycle implementation owner: it consumes WS8's shared main-owned power-request plus sleep/resume implementation and local/non-packaged tests. If freshness exposes a gap in that prerequisite, route the smallest reviewed repair through this prerequisite gate with the shared WS8 owner explicit before observation. Complete and review every required runtime, helper, IPC/preload, package, provenance/license, installer/lifecycle, signing/updater work required by the approved posture, or evidence-policy correction before RD-27 begins. RD-27 is observation-only, so any such correction discovered after this gate triggers its roadmap stop/replan rule and returns to this prerequisite subphase.
2. **RD-27 Windows MVP UI proof and operational soak:** only after subphase 1, WS1–WS8, and the refreshed current Windows proof plan are complete/reviewed, unblock and execute RD-27 as the Windows observation owner. It owns `PB-26` long-playback continuity, `PB-28` multi-monitor/DPI/fullscreen observation, `WIN-05`, and the packaged Windows observation/proof portion of WS8-gated `PB-27`; it does not absorb new runtime or package implementation.
3. **RD-28 internal package lifecycle proof:** only after RD-27 is complete and reviewed, execute RD-28 as the internal Windows package install/delete lifecycle owner. It carries closure proof for `PKG-01`, `PKG-02`, the internal install/uninstall/delete portion of decision-approved `PKG-03`, and `WIN-08`, plus WS9's packaged helper/libmpv redistribution and replacement-helper recovery contribution to `PB-07`/`WIN-07`. It closes `PKG-03` only when the selected Alternative A authority decision or Alternative B public-release implementation/proof has also passed. Missing implementation found here returns to a reviewed WS9 prerequisite hardening slice rather than being mislabeled as proof.

WS9 is complete only when its prerequisite implementation/hardening, RD-27, and RD-28 have each closed with their own required review and evidence. Program closeout occurs afterward; neither the WS9 wrapper nor this plan cancels, renames, or treats either roadmap item as already complete.

### Stable-ID registry

The following registry is exhaustive and authoritative for this plan. Each of the 227 audit IDs occurs exactly once in this block.

<!-- STABLE_ID_REGISTRY_START -->
- **WS1 — Channel Builder (41):** `ON-13`, `LIB-06`, `CB-01`, `CB-02`, `CB-03`, `CB-04`, `CB-05`, `CB-06`, `CB-07`, `CB-08`, `CB-09`, `CB-10`, `CB-11`, `CB-12`, `CB-13`, `CB-14`, `CB-15`, `CB-16`, `CB-17`, `CB-18`, `CB-19`, `CB-20`, `CB-21`, `CB-22`, `CB-23`, `CB-24`, `CB-25`, `CB-26`, `CB-27`, `CB-28`, `CB-29`, `CB-30`, `CB-31`, `CB-32`, `UI-17`, `UI-18`, `UI-19`, `UI-21`, `UI-22`, `UI-23`, `UI-24`
- **WS2 — Playback (24):** `LIB-05`, `PB-01`, `PB-02`, `PB-03`, `PB-04`, `PB-05`, `PB-06`, `PB-07`, `PB-08`, `PB-12`, `PB-13`, `PB-14`, `PB-19`, `PB-20`, `PB-21`, `PB-22`, `PB-23`, `PB-24`, `WIN-01`, `WIN-06`, `WIN-07`, `UI-41`, `UI-42`, `UI-43`
- **WS3 — Settings (40):** `ON-12`, `ST-01`, `ST-02`, `ST-03`, `ST-04`, `ST-05`, `ST-06`, `ST-07`, `ST-08`, `ST-09`, `ST-10`, `ST-11`, `ST-12`, `ST-13`, `ST-14`, `ST-15`, `ST-16`, `ST-17`, `ST-18`, `ST-19`, `ST-20`, `ST-21`, `ST-22`, `ST-23`, `ST-24`, `ST-25`, `ST-26`, `ST-27`, `ST-28`, `ST-29`, `ST-30`, `WIN-02`, `UI-14`, `UI-28`, `UI-29`, `UI-30`, `UI-31`, `UI-32`, `UI-33`, `UI-34`
- **WS4 — Input And Overlay (35):** `PB-09`, `PB-10`, `PB-11`, `PB-15`, `PB-16`, `PB-17`, `PB-18`, `PB-25`, `NAV-01`, `NAV-02`, `NAV-03`, `NAV-04`, `NAV-05`, `NAV-06`, `NAV-07`, `NAV-08`, `NAV-09`, `NAV-10`, `NAV-11`, `NAV-12`, `NAV-13`, `NAV-14`, `NAV-15`, `NAV-16`, `WIN-03`, `WIN-09`, `UI-44`, `UI-45`, `UI-46`, `UI-47`, `UI-48`, `UI-49`, `UI-50`, `UI-51`, `UI-52`
- **WS5 — Guide (21):** `EPG-01`, `EPG-02`, `EPG-03`, `EPG-04`, `EPG-05`, `EPG-06`, `EPG-07`, `EPG-08`, `EPG-09`, `EPG-10`, `EPG-11`, `EPG-12`, `EPG-13`, `EPG-14`, `EPG-15`, `UI-35`, `UI-36`, `UI-37`, `UI-38`, `UI-39`, `UI-40`
- **WS6 — Custom Channels (15):** `CC-01`, `CC-02`, `CC-03`, `CC-04`, `CC-05`, `CC-06`, `CC-07`, `CC-08`, `CC-09`, `CC-10`, `UI-20`, `UI-25`, `UI-26`, `UI-27`, `UI-54`
- **WS7 — Fresh UI Proof (7):** `UI-01`, `UI-02`, `UI-03`, `UI-04`, `UI-05`, `UI-06`, `UI-53`
- **WS8 — Credential And Lifecycle (36):** `ON-01`, `ON-02`, `ON-03`, `ON-04`, `ON-05`, `ON-06`, `ON-07`, `ON-08`, `ON-09`, `ON-10`, `ON-11`, `ON-14`, `ON-15`, `ON-16`, `ON-17`, `ON-18`, `LIB-01`, `LIB-02`, `LIB-03`, `LIB-04`, `LIB-07`, `LC-01`, `LC-02`, `LC-03`, `LC-04`, `LC-05`, `UI-07`, `UI-08`, `UI-09`, `UI-10`, `UI-11`, `UI-12`, `UI-13`, `UI-15`, `UI-16`, `WIN-04`
- **WS9 — Packaging And Soak (8):** `PB-26`, `PB-27`, `PB-28`, `PKG-01`, `PKG-02`, `PKG-03`, `WIN-05`, `WIN-08`
<!-- STABLE_ID_REGISTRY_END -->

### Implementation gaps versus proof obligations

The registry assigns ownership; it does not flatten different closure states.

| Workstream | Missing implementation owned here | Partial behavior requiring correction | Implemented/additive behavior whose remaining obligation is proof or comparison |
| --- | --- | --- | --- |
| WS1 | `LIB-06`, `CB-03`–`CB-21`, `CB-28`–`CB-32` | `ON-13`, `CB-24`–`CB-27`, `UI-18`, `UI-19`, `UI-22`–`UI-24` | `CB-01`, `CB-02`, `CB-22`, `CB-23`, `UI-17`, `UI-21` |
| WS2 | Determined by its freshness review from the assigned rows | `PB-04`–`PB-08`, `PB-13`, `PB-19`–`PB-24`, `WIN-01`, `WIN-06`, `UI-43` | `LIB-05`, `PB-01`–`PB-03`, `PB-12`, `PB-14`, `WIN-07`, `UI-41`, `UI-42` |
| WS3 | `ON-12`, `ST-02`–`ST-13`, `ST-15`–`ST-25` including `ST-23`'s persistent Settings “Switch Profile” affordance prerequisite for `ON-08`, `WIN-02`, `UI-14`, `UI-28`, `UI-29`, `UI-31` | `ST-01`, `ST-14`, `ST-30`, `UI-30`, `UI-32`, `UI-33` | `ST-26`–`ST-29`, `UI-34`, plus recovery proof for `ST-30` |
| WS4 | `PB-25`, `NAV-05`, `NAV-08`, `WIN-03`, `UI-51` | `PB-09`–`PB-11`, `NAV-02`–`NAV-04`, `NAV-06`, `NAV-07`, `WIN-09`, `UI-44`, `UI-47` | `PB-15`–`PB-18`, `NAV-01`, `NAV-09`–`NAV-16`, `UI-45`, `UI-46`, `UI-48`–`UI-50`, `UI-52` |
| WS5 | `EPG-08`, `EPG-12`, `EPG-13` | `EPG-04`, `EPG-06`, `EPG-09`–`EPG-11`, `UI-36`, `UI-40` | `EPG-01`–`EPG-03`, `EPG-05`, `EPG-07`, `EPG-14`, `EPG-15`, `UI-35`, `UI-37`–`UI-39` |
| WS6 | `CC-05`, `CC-10`, `UI-54` | `CC-08`, `CC-09`, `UI-26` | Desktop additions `CC-01`–`CC-04`, `CC-06`, `CC-07`, `UI-20`, `UI-25`, `UI-27`; these stay distinct from Builder |
| WS7 | None frozen by this plan | None frozen by this plan | `UI-01`–`UI-05` need fresh current-upstream comparison; `UI-06` and `UI-53` are intentional-divergence proof |
| WS8 | `ON-17`, `ON-18`, `LC-01`, `LC-04`, `LC-05`, `WIN-04` | `ON-11`, `ON-15`, `ON-16`, `LC-02`, `LC-03`, `UI-13` | `ON-01`–`ON-10`, including `ON-08` live/profile-switch lifecycle proof only after verified WS3 `ST-23`, plus `ON-14`, `LIB-01`–`LIB-04`, `LIB-07`, `UI-07`–`UI-12`, and additions `UI-15`, `UI-16` |
| WS9 | `PKG-02`, `PKG-03`; no independent `PB-27` lifecycle implementation | `PB-28`, `WIN-05` | `PB-26`, `PKG-01`, `WIN-08`, plus packaged Windows proof for the WS8 power-lifecycle prerequisite under `PB-27` |

The later workstream classifications are audit inputs, not permission to implement from stale assumptions. Each later workstream must reread its rows, owners, tests, current architecture, and relevant current upstream source before freezing files.

### WS1 channel-builder boundary

The current synchronous fallback builder creates one `libraryFallback` channel per selected library. Renderer “cancel” only changes view ownership while the main commit can still persist. WS1 replaces that fallback rather than extending it.

The builder is divided into three owners:

- **Main-only facet source:** authenticated Plex transport resolves only normalized, allowlisted facet DTOs needed by the planner. It does not return raw Plex responses, tokens, URIs, paths, or a generic request primitive.
- **Pure domain planner:** normalized configuration, explicit facet DTOs, the domain-only existing-lineup projection, clock value, and seed produce deterministic candidate drafts, review diff, warnings, caps, and a stable plan identity. It has no Electron, Node, Plex transport, filesystem, global timers, `Date.now`, or `Math.random` dependency.
- **Main operation owner:** owns operation IDs, abort controllers, plan retention, context revalidation, atomic application, and post-commit guide refresh. Renderer and preload remain unprivileged clients.

The planner covers all audited builder strategies, scope and priority controls, maximum channel count, minimum item count, Expand behavior including the 500/1 case, append/replace/merge, alternate copies, sequential and block variants, slow/blocked states, warnings, and deterministic caps.

Custom Channels remains a separate feature and policy owner. It may use the same lineup mutation coordinator so builder and custom-channel full-snapshot mutations cannot race, but it must not import builder strategy/configuration semantics. `UI-20` belongs to WS6, not WS1.

### Pure planner invocation, safe facets, and existing-lineup projection

The exact pure invocation is `buildChannelSetupPlan(input: ChannelBuilderPlannerInput)`, where `ChannelBuilderPlannerInput` is exactly `{ normalizedConfig, facetSnapshot, existingLineup, clock, seed }`:

- `normalizedConfig: NormalizedChannelSetupConfig` is the validated/default-complete config frozen below;
- `facetSnapshot: ChannelBuilderFacetSnapshot` is the safe snapshot defined below;
- `existingLineup: readonly ChannelBuilderExistingLineupEntry[]` is projected in main from the one aggregate loaded for review;
- `clock: { nowMs: number }` is a finite non-negative safe integer captured from the operation owner's injected clock before the pure call;
- `seed: string` is an explicit non-empty deterministic seed.

No default parameter or hidden global supplies any of these inputs. Same normalized config, facet snapshot, existing-lineup projection, `clock.nowMs`, and seed must produce byte-stable candidates, identity keys, diff, warnings, caps, and plan identity.

`ChannelBuilderExistingLineupEntry` is an in-process domain-only discriminated union. Both variants require exact common `{ id, number, name, sourceDisposition, sourceReference, playbackMode, contentFilterIdentity, builderProvenance }` and presence-preserving optional `{ isAutoGenerated?, sortOrder?, blockSize?, lineupReplicaIndex?, isPlaybackModeVariant? }`. `contentFilterIdentity` is `ChannelBuilderContentFilterIdentity | null`: main maps absent/empty persisted filters to null and every nonempty valid conjunction to the opaque identity frozen below; raw persisted filter values never enter the pure planner DTO. The source-disposition null rules are exhaustive:

- matchable is exactly `{ sourceDisposition: 'matchable', sourceReference: ChannelBuilderSafeSourceReference, builderProvenance: ChannelBuilderChannelProvenanceV1 | null }`;
- retained-unmatchable is exactly `{ sourceDisposition: 'retained-unmatchable', sourceReference: null, builderProvenance: null }`.

Persisted existing-channel `id` and `name` are explicit total exceptions to every new binding/facet/source 512-character and control-bearing identifier limit. Package 1A accepts the exact current loader domain: `id` is the loader-normalized trimmed nonempty raw string, and `name` is any nonempty raw string. Neither has a planning length cap; controls, astral characters, unpaired-surrogate/code-unit edge cases admitted by the loader, and NFC-equivalent distinct raw spellings are not truncated, rejected, aliased, or display-sanitized in the main-only planner input/ledger. The 500-row persisted-lineup maximum bounds count. This raw representation remains main-only inside planner input, identity construction, ledgers, retained mapping, and persistence/application owners; no planner DTO exposes it publicly. Separately, the public-reference owner below may emit a persisted raw ID byte-for-byte only after the complete value matches `/^[A-Za-z0-9._-]{1,120}$/u` and is unique within the accepted full generation; every hostile, unsafe, duplicate, or otherwise unvalidated raw ID is rejected as corruption or projected to its deterministic alias and never crosses a public DTO raw. A row's matchable versus retained-unmatchable disposition is decided solely by the source/provenance rules below, never by ID/name display safety.

`src/main/channel/channelBuilderRuntime.ts` is the sole current-valid existing-source projection owner. It projects every currently persisted channel row in original lineup order, first accepting the complete current `isValidContentSource`/persistence domain, current persisted content-filter domain, and the exact hostile ID/name domain above unchanged, then attempting Identity V1, content-filter-identity, and safe-reference construction only when those valid fields also fit the builder's deliberately narrower matchability constraints. A current-valid source or nonempty content-filter conjunction that does not fit becomes retained-unmatchable; it never blocks, omits, truncates, rewrites, or reorders the channel or its existing-ledger row. This includes source identifiers or keys longer than 512 characters or containing allowed control characters; current-valid positive finite integers outside the safe-integer range; manual or mixed child arrays or total leaf counts above 500; valid source-tree depth 9–25; and every other source/filter shape rejected by an Identity V1 typed constructor. The current `MAX_CONTENT_SOURCE_DEPTH = 25` remains owned by `channelContentSourceValidator.ts` and `channelRepository.ts`; Package 1A's depth-8/500-leaf builder-safe source-identity boundary does not change those validators or newly planned source caps.

For matchable rows, main derives the complete safe ordered source tree and independently validates any provenance marker. For retained-unmatchable rows, it emits only the discriminator/nulls and drops any stale or otherwise present provenance marker independently during repair without channel loss. Raw `ChannelContentSource`, raw identifiers, the reason for unmatchability, and partial/truncated trees never enter the pure DTO, IPC, preload, renderer, facet materialization index, or reviewed plan body. The pure planner receives exactly one safe projection row per persisted channel and emits one safe warning `{ code: 'EXISTING_SOURCE_UNMATCHABLE', phase: 'planning', strategy: null, affectedCount }` when the count is nonzero. It deduplicates as the single `(code, phase, null)` record, sorts under the common code/phase/strategy rule, and exposes only the count; renderer copy is exactly `Some existing channels can be retained but cannot be matched or updated by Channel Builder.`

One exported Identity V1 implementation in `src/domain/channelBuilder/planIdentity.ts` is shared by binding, facet, tag-group, content-filter, source, candidate, existing-lineup, and plan identity construction. Its byte serializer, exact preimages, domains, exclusions, collision guard, and golden vectors are frozen in the decision-complete section below. No other package may invent a serializer or concatenate identity fields independently.

The Package 1A typed Identity V1 constructors are the deliberate narrow exception to “raw never enters Package 1A code.” Main-owned Package 1B/1C call sites may pass already-validated raw `key`, `tagValue`, normalized fastKey-derived runtime filters, complete runtime source values, and persisted content-filter values directly into the owning synchronous pure constructor solely to build its typed preimage, canonicalize/hash it, and return the opaque identity. The constructor must not retain, cache, memoize, log, diagnose, stringify into an exception, return, yield, asynchronously capture, or place any raw input in module/global state; it returns only the prefixed digest or a fixed value-free validation failure. Raw inputs exist only in the caller stack and constructor stack for that synchronous call. No raw tag/filter/runtime-source value enters `ChannelBuilderFacetSnapshot`, `ChannelBuilderExistingLineupEntry`, `ChannelBuilderCandidateDraft`, planner input/output, candidate/plan ledgers, reviewed body, IPC, preload, renderer, persisted provenance, logs, diagnostics, or errors. Package 1A does not acquire raw Plex/persistence data and no planner/strategy function accepts those raw constructor inputs.

Package 1A `src/domain/channelBuilder/types.ts` is the sole credential-marker and safe display-string owner. It exports exact pure `containsChannelBuilderCredentialMarker(raw): boolean`: normalize the complete input to NFC, replace each C0/C1 code point U+0000–U+001F or U+007F–U+009F with one ASCII space, collapse each ECMAScript-whitespace run to one ASCII space, then return the result of exact case-insensitive marker regex `/(^|[^A-Za-z0-9_])(?:bearer|token|authorization|headers?)(?=$|[^A-Za-z0-9_])/iu`. It also exports exact pure `projectChannelBuilderSafeDisplayString(raw, { fallback, maxUtf16Units })`, which must call that predicate on the original raw input rather than duplicate or restate the regex/normalization. If the predicate is true, projection replaces the complete string with exactly `[redacted]`; no prefix, suffix, or credential-adjacent text survives. Otherwise it performs the same NFC/control/whitespace intermediate normalization, replaces `<`/`>` with U+2039/U+203A, and replaces every case-insensitive `http://` or `https://` non-whitespace token with `[link]`. Finally it collapses whitespace again, trims, truncates without splitting a surrogate pair to `maxUtf16Units`, and, if empty, returns the frozen already-safe fallback. `maxUtf16Units` is a positive integer at most 2,000. Literal golden vectors include `Authorization: Bearer secret` → `[redacted]`, `Bearer secret` → `[redacted]`, `token=secret` → `[redacted]`, singular/plural and mixed-case `header`/`headers` variants → `[redacted]`, an innocent URL-only string → its non-URL text plus `[link]`, and control/angle/astral/surrogate-boundary cases with exact expected output. Predicate vectors include `token-secret`, `Bearer-secret`, `authorization-secret`, and singular/plural/mixed-case header variants as true, while boundary near-misses including `mytoken` are false. Package 1A review-diff samples call the projector for every existing and planned name with `{ fallback: 'Untitled channel', maxUtf16Units: 160 }` before any sample ordering, concatenation, or six-name cap. Package 1B imports the projector for every non-tag facet `title` and for the separately projected tag `displayTitle`, always with `{ fallback: 'Untitled facet', maxUtf16Units: 160 }`; for tags, raw semantic derivation plus semantic ordering and cap admission finish first, then only admitted entries are projected before safe snapshot construction and display-label attachment. The raw main-only semantic `tagValue` is never passed through the projector. Package 1C imports both exact functions: its public-reference owner calls the predicate for raw channel/source-library passthrough eligibility and the projector with the exhaustive per-public-field options table below. No package duplicates or weakens either behavior.

`ChannelBuilderFacetSnapshot` contains only:

- context `{ contextEpoch, profileBinding, serverBinding, librarySetBinding }`;
- libraries `{ facetId, sourceIdentity, title, mediaType: 'movie' | 'show', contentCount }`;
- playlists `{ facetId, sourceIdentity, title, itemCount, durationMs }`;
- collections `{ facetId, sourceIdentity, libraryFacetId, title, itemCount }`;
- tag facets, as the exact discriminated `ChannelBuilderTagFacet` union with common `{ facetId, sourceIdentity, libraryFacetId, displayTitle, itemCount, episodeCount, distinctSeriesCount }` plus the family-specific safe semantic fields frozen below;
- recently-added facets `{ facetId, sourceIdentity, libraryFacetId, itemCount }`, exactly one per selected eligible library;
- aggregate status `{ status: 'ready' | 'blocked' | 'slow', warningCodes, omittedMalformedCount, omittedCappedCount }`.

WS1 has no item-facet family, item-facet identity domain/prefix, item-facet snapshot member, item-facet materialization-index entry, or new candidate path that produces a `manual` source or a mixed tree containing a manual child. Current-valid persisted manual sources and mixed sources containing manual children remain eligible for the existing-lineup safe-source/Identity V1 projection when they fit the frozen matchability bounds; their projected leaves have null `facetId`, are comparison/provenance inputs only, and are never requested from the materialization index. This removal changes no stable-ID registry ownership: no registered WS1 requirement depends on a new manual-item producer.

Package 1A `src/domain/channelBuilder/types.ts` owns `ChannelBuilderFacetWarningCode`, exactly the discovery-only union `'FACET_UNAVAILABLE' | 'FACET_PARTIAL_FAILURE' | 'FACET_DISCOVERY_TIMEOUT' | 'FACET_EMPTY' | 'FACET_CAP_REACHED' | 'FACET_MALFORMED_ENTRIES_OMITTED' | 'TV_PEOPLE_METADATA_INCOMPLETE'`. `warningCodes` is a deeply immutable `readonly ChannelBuilderFacetWarningCode[]`: every value is unique, strings are in ascending lexical code order, and length is at most seven. An unknown, duplicate, unsorted, or over-cap array is invalid. `omittedMalformedCount` is a non-negative safe integer no greater than 50,000: it is positive if and only if `FACET_MALFORMED_ENTRIES_OMITTED` is present. `omittedCappedCount` is exactly `number | null`: it is `0` if and only if no cap was reached and `FACET_CAP_REACHED` is absent; it is an exact positive safe integer 1–50,000 if a cap was reached and the source can determine the complete omitted remainder without issuing any extra request page; and it is `null` if a cap was reached but any omitted remainder is unknowable from responses already obtained or the exact aggregate omitted remainder exceeds 50,000. `FACET_CAP_REACHED` is present if and only if `omittedCappedCount` is positive or null.

The pure planner converts `warningCodes` in array order into exact `ChannelSetupWarning` records with `phase: 'discovery'`. All seven aggregate facet codes use `strategy: null`. `FACET_MALFORMED_ENTRIES_OMITTED` receives `affectedCount: omittedMalformedCount`, `FACET_CAP_REACHED` receives `affectedCount: omittedCappedCount`, and each of the other five receives `affectedCount: null`. A strategy-specific warning, if a later requirement introduces one, must be generated separately by planning from explicit strategy state; it cannot be encoded or inferred through `warningCodes`.

Except for `omittedMalformedCount` and the tri-state `omittedCappedCount` frozen above, every facet count is a finite non-negative integer or `null` where Plex supplied no count. `episodeCount` and `distinctSeriesCount` are non-null only for actor/director TV breadth. Every library/playlist/collection `title` and tag `displayTitle` is the nonempty 1–160-UTF-16-unit result of the sole helper call with fallback `Untitled facet`; no raw title or main-only `tagValue` is retained in the safe snapshot. For a tag entry, main first derives and validates `tagValue` from the raw Plex title for identity/runtime-query ownership, then invokes the pure constructors for the opaque semantic identities and safe numeric year metadata below, completes the frozen non-display semantic ordering and all family/global cap admission, and only then independently projects the original raw title to `displayTitle` for admitted entries before safe snapshot construction. Projected `displayTitle` may drive only the attached display label; it never feeds `tagValue`, facet/source/content-filter identity, runtime filters, semantic grouping, year parsing, a comparator/tie-breaker, source/member/candidate order, candidate seeds, skip counts, or family/global cap admission.

`ChannelBuilderTagFacet` has exact family-specific semantics:

- genre, studio, and actor are common fields plus `{ family, semanticGroupIdentity, contentFilterIdentity: null, yearValue: null }`;
- director is common fields plus `{ family: 'director', semanticGroupIdentity, contentFilterIdentity, yearValue: null }`;
- year is common fields plus `{ family: 'year', semanticGroupIdentity: null, contentFilterIdentity: null, yearValue }`.

`semanticGroupIdentity` is the opaque `ChannelBuilderTagSemanticGroupIdentity` below and is non-null exactly for the four families whose audited strategy may group equal semantic tags across libraries. Director `contentFilterIdentity` is the opaque identity of exact `[{ field: 'director', operator: 'eq', value: tagValue }]`; no other tag family carries one. `yearValue` is `number | null`: main applies exact pinned `Number.parseInt(tagValue, 10)`, retains the result only when finite, and otherwise emits null; Package 1A derives a decade only from this numeric field as `Math.floor(yearValue / 10) * 10` and never parses `displayTitle`. Non-year `yearValue` is always null. `facetId`, `sourceIdentity`, all semantic identities, the three bindings, and all cross-references are lowercase SHA-256 identities with the exact prefixes frozen below, never Plex keys. No safe/planner/public DTO contains a rating key, metadata key, fast key, `tagValue`, raw content-filter string value, URI, path, token, header, connection, raw payload, thumbnail, media item, profile name, server name, or account name.

The main-only facet source returns the `ChannelBuilderFacetMaterializationIndex` frozen below. The pure planner returns only safe source references. `startApply` revalidates the epoch and lineage, then the main builder runtime uses the transferred index to materialize domain `ChannelCreateInput` values immediately before persistence. The index never crosses IPC or enters persisted builder state, and its exact single-owner lifetime follows the reviewed-plan rules below.

Discovery uses distinct selected library IDs with a maximum of 24. Directory/list requests use pages of 100 and stop after five pages per family/library; playlists stop at 500 total, collections and each tag family stop at 500 per library, and the entire snapshot stops at 50,000 facet entries. A review has a 60-second discovery deadline. Reaching a cap drops the remainder and records the single aggregate `FACET_CAP_REACHED` code plus the frozen exact-positive-or-null `omittedCappedCount`; discovery never fetches another page merely to count omitted entries. Multi-library/family omissions are aggregated only when every remainder is known and the exact sum is at most 50,000; any unknown remainder or exact sum above 50,000 yields null. The planner performs the public-warning conversion unchanged, including `affectedCount: null` for the unknown/over-bound case.

Malformed entries are omitted individually and recorded as the single `FACET_MALFORMED_ENTRIES_OMITTED` code plus exact positive `omittedMalformedCount`; raw values and parser messages are not returned. Failure of every source needed by any enabled strategy produces `blocked` and no apply-capable pure output. If at least one eligible selected library succeeds but another enabled-family source times out, fails, or reaches a cap, the source returns `slow` with a partial snapshot and bounded aggregate codes. Disabled-family failures do not affect status. Only the planner-converted exact stable warning records defined below cross IPC; facet titles never appear in a warning payload.

After strategy enablement, eligibility, minimum-item enforcement, identity handling, and deterministic caps, any zero-candidate pure result emits exactly one deduplicated `PLAN_EMPTY` warning with `{ phase: 'planning', strategy: null, affectedCount: 0 }`. This includes all-disabled, all-ineligible, and all-skipped configurations in append, merge, and replace. Package 1A returns `status: 'blocked'`, `applyCandidateIds: []`, and `retainedMaterializationCandidateIds: []`, with no apply-capable pure output or materialization request. The pure planner owns no runtime `planId`, reviewed body, or materialization-index retention decision. Package 1C projects this blocked result to public `planId: null`, retains no reviewed body/index, rejects `startApply`, and proves no persisted/guide change even in replace mode.

### Decision-complete exported WS1 seams

These are the only exported seams Packages 1A, 1B, and 1C may consume. Their declaration owners and focused tests must compile at each package checkpoint; an implementer may not invent an omitted field, alternate null convention, extra union member, or compatibility overload.

#### Pure planner, safe source identity, and retained review body

##### Identity V1 — canonical bytes, preimages, and issuance

`src/domain/channelBuilder/planIdentity.ts` is the sole Identity V1 byte/hash owner and exports `canonicalJsonV1` plus the typed identity constructors. `canonicalJsonV1` emits compact UTF-8 JSON with no whitespace: object keys are NFC-normalized then sorted recursively in lexical Unicode-code-point order, never ECMAScript integer-index enumeration order—therefore ordinary keys `"10"` and `"2"` serialize in exactly that order; arrays preserve input order; string values are NFC-normalized and use standard JSON escaping; booleans and null use JSON literals; and every finite IEEE-754 JavaScript number is emitted by ECMAScript `JSON.stringify` number serialization after `-0` is normalized to `0`. It rejects `undefined`, symbols, bigint, `NaN`, positive or negative infinity, sparse arrays, non-plain objects, duplicate ordinary object keys after NFC normalization, and any field not admitted by the exact typed preimage constructor. It does not reject a finite number merely because it is fractional, exponent-serialized, or outside the safe-integer range; exact typed constructors continue to enforce finite integer/safe-integer/range rules wherever that field's contract requires them. There is no generic fallback serialization. Every Identity V1 digest is exactly lowercase-hex `sha256(UTF8(domainSeparator + canonicalJsonV1(preimage)))`; the named domain string is the only concatenated delimiter, and every structured value is inside the canonical JSON object. The synchronous SHA-256 implementation is a focused pure TypeScript FIPS 180-4 implementation in this module, checked byte-for-byte against Node `crypto` golden vectors in tests; production domain code gains no Node/browser-global/dependency import.

Identity input strings are NFC-normalized. New binding/facet/source identifier/key inputs are additionally trimmed, must remain 1–512 characters, and reject U+0000–U+001F and U+007F. The exact persisted existing-channel ID/name exception does not use that rule. Identity V1 represents each persisted existing `id` and `name` as exact `PersistedStringV1 = { nfc, utf16 }`: `nfc` is the complete raw loader string normalized to NFC without trimming/truncation, while `utf16` is the complete ordered array of the original raw loader string's UTF-16 code units, each integer 0–65535. Thus NFC-equivalent but raw-distinct strings, controls, astral pairs, and overlength values remain losslessly distinct. The typed existing-lineup Identity V1 constructor replaces every raw existing-row `id`/`name` position in the `planIdentity` input and output/ledger identity projection—and any other identity tuple containing an existing row ID/name—with this record before `canonicalJsonV1`; raw strings are never delimiter-concatenated. Pure runtime DTOs/ledgers retain the raw strings for main-only mapping, but canonical plan bytes contain the typed records.

Raw main-only semantic `tagValue` is derived exactly once from current `PlexTagDirectoryItem.title.trim()` after NFC normalization, before any display projection, because that same normalized value is used for facet identity and main-only runtime tag filters. It remains only in the privileged facet record/materialization index and closed main-only facet-count request, except for transient synchronous passage into the Package 1A typed identity constructors under the no-retention contract above; it never enters `ChannelBuilderFacetSnapshot`, any pure-planner DTO, IPC, preload, renderer state, logs, errors, or diagnostics. Package 1B calls those constructors to derive only the following safe semantic projections before discarding raw values from the snapshot boundary:

- `ChannelBuilderTagSemanticGroupIdentity` matches `/^tag-group:[a-f0-9]{64}$/u`, uses domain `lineup-builder/tag-group/v1:`, and hashes exact `{ profileBinding, serverBinding, family, groupValue }`, where family is `genre | director | studio | actor` and `groupValue` is exact `tagValue.toLowerCase().normalize('NFC')`; this locale-independent audited grouping value is nonempty and never returned unhashed;
- `ChannelBuilderContentFilterIdentity` matches `/^content-filters:[a-f0-9]{64}$/u`, uses domain `lineup-builder/content-filters/v1:`, and hashes exact `{ profileBinding, serverBinding, filters }`, where filters is a nonempty semantic conjunction sorted by each exact filter's `canonicalJsonV1` bytes. Absent/empty filters normalize to null rather than a digest. Package 1B invokes the Package 1A constructor transiently with exact `[{ field: 'director', operator: 'eq', value: tagValue }]`; Package 1C main existing-lineup projection invokes the same constructor transiently with current persisted filters and expected lineage; Package 1A planner code invokes it only over raw-free inline numeric filters and the snapshot lineage.

The tag-group digest is grouping-only: it never becomes a Plex query/filter value, source filter, candidate display string, or runtime identifier. The content-filter digest is equality/materialization validation only: it never substitutes for a runtime filter value. The separately projected safe `displayTitle` is produced from the original raw Plex title under the sole helper/options rule above only after semantic ordering/cap admission are final; it affects naming only and never feeds or replaces `tagValue`, either semantic identity, numeric year metadata, a comparator, tie-breaker, group key, seed, identity, source order, candidate order, or cap decision. Manual titles and library-filter string values preserve their non-trimmed runtime value after NFC normalization. Every raw value must satisfy its owning main-only domain validator before the transient Package 1A constructor call, including the explicit persisted-string exception above. Main derives every binding after joining renderer-known selected IDs to current main-owned records; no caller supplies a binding or semantic digest. The existing public `serverId`/`selectedLibraryIds` request fields remain unchanged, but active profile IDs and library UUIDs never cross IPC, and no raw binding input is stored in channel provenance.

Bindings have these exact prefixes, domains, and preimages:

| Value | Regex | Domain string | Exact preimage |
| --- | --- | --- | --- |
| profile binding | `/^profile-binding:[a-f0-9]{64}$/u` | `lineup-builder/profile-binding/v1:` | `{ activeProfileId }`, from trimmed `DesktopPlexAuthService.getActiveUserId()` |
| server binding | `/^server-binding:[a-f0-9]{64}$/u` | `lineup-builder/server-binding/v1:` | `{ serverId }`, from trimmed selected `PlexServer.id`, which is the normalized Plex resource `clientIdentifier` |
| library-set binding | `/^library-set-binding:[a-f0-9]{64}$/u` | `lineup-builder/library-set-binding/v1:` | `{ libraries }`, where libraries is the non-empty array of exact `{ libraryId, libraryUuid }` pairs resolved from current `PlexLibrarySection.id` and `.uuid`, unique by both pair and libraryId, sorted lexically by libraryId then libraryUuid |

Failure to resolve any selected library ID to exactly one current main-owned `{ id, uuid }` pair is `CHANNEL_CONTEXT_CHANGED`; main never substitutes the renderer ID for a missing UUID. Profile/server/library bindings stored in snapshot/context/provenance are the prefixed digests only.

`ChannelBuilderFacetId` matches `/^(library|playlist|collection|genre|director|year|studio|actor|recently-added):[a-f0-9]{64}$/u`. Each facet uses the corresponding exact domain `lineup-builder/facet/<family>/v1:` and the same `<family>:` output prefix:

| Family | Exact preimage |
| --- | --- |
| library | `{ profileBinding, serverBinding, family: 'library', libraryId, libraryUuid, libraryType }`, using current `PlexLibrarySection.id`, `.uuid`, and mapped `movie | show`; title/count/art/thumb/agent/scanner/timestamps are excluded |
| playlist | `{ profileBinding, serverBinding, family: 'playlist', libraryId: null, libraryUuid: null, ratingKey, key }`, using current `PlexPlaylist.ratingKey` and `.key`; Plex playlists are server-wide in the current source, so absent library ownership is represented by both explicit nulls, never omission or guessed ownership |
| collection | `{ profileBinding, serverBinding, family: 'collection', libraryId, libraryUuid, ratingKey, key }`, using its owning library pair plus current `PlexCollection.ratingKey` and `.key` |
| genre/director/year/studio/actor | `{ profileBinding, serverBinding, family, libraryId, libraryUuid, key, tagValue, fastKey }`, using the owning library pair, current `PlexTagDirectoryItem.key`, exact raw-main-only trimmed/NFC runtime-semantic `title` as `tagValue`, and exact NFC `fastKey` or null; count/thumb and separately projected `displayTitle` are excluded |
| recently-added | `{ profileBinding, serverBinding, family: 'recently-added', libraryId, libraryUuid, libraryType }`; this is the library-level recently-added facet and has no invented Plex key |

All facet raw values are retained only in the main materialization index. Display titles, counts, duration, artwork, names, safe tag-group/content-filter digests, and numeric year metadata never enter a facet ID. The raw main-only `tagValue` is the sole title-derived facet-ID semantic exception because the pinned strategy uses that value in runtime filters; it is not a display title, is never projected first, and never crosses the safe snapshot boundary. The safe semantic digests are separately domain-bound projections and cannot be reversed or substituted for the raw value.

`ChannelBuilderSourceIdentity` matches `/^source:[a-f0-9]{64}$/u`. Source identities intentionally omit origin; cross-server/profile/library-set isolation is composed exactly by the candidate preimage below. Every current `ChannelContentSource` variant has one exact domain and preimage:

| Source | Domain string | Exact preimage |
| --- | --- | --- |
| library | `lineup-builder/source/library/v1:` | `{ type: 'library', libraryId, libraryType, includeWatched, libraryFilter }`; absent filter is null, otherwise `libraryFilter` is the exact canonical entry array defined immediately below |
| collection | `lineup-builder/source/collection/v1:` | `{ type: 'collection', collectionKey }`; `collectionName` is excluded because resolution uses only the key |
| show | `lineup-builder/source/show/v1:` | `{ type: 'show', showKey, seasonFilter }`; `seasonFilter` is sorted-unique positive safe integers and absent/empty normalizes to `[]`; `showName` is excluded |
| playlist | `lineup-builder/source/playlist/v1:` | `{ type: 'playlist', playlistKey }`; `playlistName` is excluded |
| manual item leaf | `lineup-builder/source/manual-item/v1:` | `{ ratingKey, title, durationMs }`; title is included because it is persisted/runtime manual-item semantics, duration is a positive safe integer, and item order is not represented here |
| manual | `lineup-builder/source/manual/v1:` | `{ type: 'manual', items }`, where items is the original-order array of manual-item source identities |
| mixed | `lineup-builder/source/mixed/v1:` | `{ type: 'mixed', mixMode, sources }`, where `mixMode` is `sequential | interleave` and sources is the original-order array of recursively computed child source identities |

`libraryFilter` is the one typed dictionary exception to ordinary exact-object unknown-field and plain-object rejection. After the current library-filter validator accepts any non-null, non-array object, the source constructor reads exactly its own enumerable string-key entries with `Object.entries`; prototype state, non-enumerable properties, and symbol keys remain outside the dictionary exactly as they are in current validation. There is no positive key allowlist and no generic “unknown key” rejection inside this dictionary. It rejects only an exact raw key equal to one of `CHANNEL_DOMAIN_FORBIDDEN_KEYS`: `rawMediaUrl`, `tokenizedUrl`, `authHeaders`, `rawAuthHeaders`, `persistentToken`, `credentialMaterial`, `nativeHandle`, `libmpvObject`, `engineId`, `electronApi`, `nodeApi`, `rawPlexPayload`, `streamKey`, `partKey`, `secretDiagnostics`, `localStorage`, `storageKey`, `currentChannelKey`, `serverUri`, or `connectionUri`. Each value is admitted if and only if it is a string or any finite JavaScript number. The identity-only canonical representation is an array of exact `{ keyNfc, keyUtf16, value }` entries: `keyNfc` is the raw key normalized to NFC, `keyUtf16` is the raw key's complete ordered UTF-16 code-unit array with each unit an integer 0–65535, string values use the normal NFC string rule, numeric values use the finite-number rule above, and entries sort by `keyNfc` in lexical Unicode-code-point order then lexicographically by `keyUtf16`. Exact raw object keys are unique, so the second key is total; NFC-equivalent distinct raw keys remain separate entries with multiplicity and raw spelling preserved. This conversion exists only in the library-source identity preimage: it never changes the retained runtime `libraryFilter`, and outer typed source/preimage objects still reject unknown fields normally.

Only explicitly semantic sets/maps are reordered: the canonical library-filter entry array, sorted-unique `seasonFilter`, the content-filter conjunction frozen above, and the selected library-pair set. `manual.items` and `mixed.sources` preserve original order for both mixed modes. Collection/show/playlist names are excluded because their resolvers use keys; library title is excluded; manual title remains included as stated.

The main index retains exact `{ facetId, sourceIdentity, source }` linkage plus each tag entry's recomputable semantic-group/content-filter identities and numeric year metadata; it rejects a requested pair/reference unless every supplied digest and safe numeric value recomputes from the same retained raw record/source. Linkage and planner use are frozen as follows:

- library and recently-added facets map to the unfiltered `includeWatched: true` library source; playlist maps to `{ type: 'playlist', playlistKey: PlexPlaylist.ratingKey, playlistName }`; collection maps to `{ type: 'collection', collectionKey: PlexCollection.ratingKey, collectionName }`;
- genre facets map to the owning library source with `{ genre: tagValue }`; per-library genre uses that facet/source directly, while cross-library genre groups only by `semanticGroupIdentity` and forms an interleave tree from the grouped facets' source references;
- director facets map to the owning library source with `{ director: tagValue }`; cross-library director groups only by `semanticGroupIdentity` and uses those filtered facet/source references, while per-library director deliberately references the unfiltered owning library facet/source and carries `contentFilterPlan: { kind: 'main-index-reference', facetId: <director facet>, contentFilterIdentity }`;
- year facets never provide a string filter to Package 1A. Per-library decade construction groups only by the exact safe `yearValue`, references the unfiltered owning library facet/source, and uses an inline numeric content-filter plan for exact `year >= decade` and `year < decade + 10`;
- actor/studio facets map to the owning library source using the exact pinned `buildChannelSetupTagFilter` result. Per-library separate mode uses each facet/source directly. Combined or cross-library mode groups only by `semanticGroupIdentity`, preserves the audited sequential/interleave choice, and builds the ordered mixed source from the grouped facet/source references. For actor/studio source filters, parse only allowlisted `actor | studio | type` entries from `fastKey`, require the requested family entry to have a nonempty value, and then add or override exact `type = mediaType`; any invalid parse or missing/empty requested-family entry falls back exactly to `{ type: mediaType, [family]: key }`. Neither `tagValue`, `displayTitle`, nor either safe digest is an actor/studio runtime-filter fallback.

This separation preserves the pinned upstream grouping, filtering, eligibility, count, strategy-membership, and mix behavior without importing its raw title-bearing planner inputs: `ChannelSetupStrategyBuilders.ts` lines 190/203 and 563–580 group/filter genre/director by semantic title; lines 225–270 and 617–675 group actor/studio/people sources and apply exact tag filters; lines 481–499 keep per-library director on an unfiltered library source plus a director equality content filter; and lines 531–560 parse year titles and construct numeric decade ranges. The only authorized behavior change is the explicit security/determinism replacement of upstream display-title tie-breaks with the display-free semantic tuples below.

Tag ordering is exact and contains no display field. All opaque strings compare by binary lexical code-unit order. After pinned enablement, TV people breadth eligibility, and minimum-item decisions are applied at their owning phase, each admitted facet uses `(itemCount ?? 0)` descending followed by its family tail:

- genre, studio, and actor tail: `(semanticGroupIdentity, sourceIdentity, facetId)`;
- director tail: `(semanticGroupIdentity, contentFilterIdentity, sourceIdentity, facetId)`;
- year tail: `(yearValueNullRank, yearValueOrZero, sourceIdentity, facetId)`, where non-null ranks before null and non-null years sort numerically ascending.

Package 1B uses that exact count-plus-family tuple for deterministic tag-family ordering and for family/global snapshot cap admission among valid entries already fetched; page/request order and `displayTitle` cannot choose the retained side of a cap. Package 1A uses the same tuple for per-library candidate generation after eligibility/minimum-item filtering. Per-library genre/actor/studio seed input is exact `(strategy, library sourceIdentity, tag sourceIdentity)`; per-library director seed input is `(strategy: 'directors', library sourceIdentity, contentFilterIdentity)`; neither seed includes `facetId` or display data.

Cross-library/combined grouping is keyed only by `semanticGroupIdentity`. Group eligibility/count aggregation uses only numeric/null count and TV-breadth metadata. Groups order by `(aggregateSortCount descending, semanticGroupIdentity)`, where `aggregateSortCount` is the exact sum of known member counts and is `0` when none are known. A group's mixed children order by `(selectedLibraryOrdinal ascending, member itemCount ?? 0 descending, family tail)`; this preserves selected-library priority while making every within-library tie semantic. Cross/combined seed input is exact `(strategy, semanticGroupIdentity, ordered child sourceIdentity array, mixMode)`. Skipped-group cardinality, candidate generation, candidate-ledger ordinal, maximum-channel/candidate admission, mixed child order, source identity, candidate identity, and plan identity all consume these frozen semantic orders.

Decade candidate eligibility/count aggregation uses only `yearValue` and numeric/null counts. Admitted decade candidates remain in pinned numeric decade-ascending order, then library source identity and library facet ID; seed input is exact `(strategy: 'decades', library sourceIdentity, decade)`. No tag label participates.

Only after the applicable facet/group/member/candidate ordering and every facet/candidate cap admission are frozen does Package 1B project admitted raw titles to `displayTitle`, and only after Package 1A semantic ordering/admission is frozen does the planner attach names. A grouped candidate selects the `displayTitle` of its first already-semantically-ordered admitted member as its label; per-library candidates attach their own admitted tag label. Redaction, truncation, fallback, collision, or divergence between raw semantics and `displayTitle` can change display copy only—never a comparator, tie-breaker, group key, member/source/candidate order, seed, identity, skip count, or cap survivor.

This is an explicit Desktop security/determinism divergence from pinned upstream title-based ordering tie-breaks, while preserving its count/eligibility, grouping meaning, strategy membership, filters, and sequential/interleave behavior. Package 1A and Package 1B must amend their serialized import-ledger entries before acceptance to record that title-based tie-breaks were replaced by the exact opaque semantic tuples above and that display projection occurs only after semantic cap admission; the ledger must not contain raw examples. `PlexPlaylist.key` and `PlexCollection.key` remain only in their facet locator/preimage and are never selected as `playlistKey` or `collectionKey`; this matches pinned `ChannelSetupStrategyBuilders.ts` lines 378 and 416. New candidate source trees contain only those audited facet-backed source families and their ordered mixed composition; they never contain manual leaves. WS1 canonicalizes current-valid persisted manual, manual-containing mixed, and show sources for provenance/matching when safe, but emits no new manual or show-source candidate and invents no item/show facet family.

`ChannelBuilderCandidateIdentity` matches `/^candidate-identity:[a-f0-9]{64}$/u` and uses domain `lineup-builder/candidate-identity/v1:`. Its exact preimage is `{ identityVersion: 1, origin, sourceTree, contentFilterIdentity, sortOrder, lineupReplicaIndex, isPlaybackModeVariant, variantPlaybackMode, variantBlockSize }`: origin is exact `{ profileBinding, serverBinding, librarySetBinding }`; sourceTree recursively keeps node kind/mixMode/sourceIdentity and child order but excludes every facetId; `contentFilterIdentity` is the candidate plan's exact opaque digest or null and excludes the plan kind, inline values, and main-index facetId; sortOrder is value or null; replica null normalizes to `0`, while admitted non-null replica indices are integers 0–3 with base `0` and configured alternates exactly `1..alternateLineupCopies`; playback-variant null normalizes to false; variantPlaybackMode is the playback mode only when true, otherwise null; and variantBlockSize is the block size only for a true block variant, otherwise null. It excludes candidate/channel IDs, ordinal, strategy/buildStrategy, name/displayName, auto-generated flag, number, estimated count, shuffle seed, source-library display metadata, timestamps, and main facet IDs/handles.

`candidateId` matches `/^candidate:[a-f0-9]{64}$/u` and uses domain `lineup-builder/candidate-id/v1:` over exact `{ seed, strategy, candidateIdentity, occurrence }`. Seed is the explicit planner seed after NFC validation; strategy is the exact strategy key; occurrence is the zero-based count of earlier candidates with the same `(strategy, candidateIdentity)` in deterministic generation order before matching or exclusions. Candidate identity never depends on candidateId, ordinal, or planIdentity, so there is no cycle.

`planIdentity` matches `/^plan-identity:[a-f0-9]{64}$/u` and uses domain `lineup-builder/plan-identity/v1:` over exact `{ input, output }`. Input is `{ normalizedConfig, facetSnapshot, existingLineup, clock: { nowMs }, seed }`, the exact five planner inputs after their validators; output is `{ status, candidateDrafts, applyCandidateIds, retainedMaterializationCandidateIds, candidateLedger, existingLedger, diff, warnings, reachedCap, capacity }`, the complete normalized planner output excluding only `planIdentity` itself. Main-only indexes/handles, planId, operation IDs, retention timestamps, and abort state are never inputs. Candidate IDs are already fixed by the non-circular rule above.

Digest equality is necessary but not sufficient for existing/candidate matching. The planner retains each candidate's canonical candidate-preimage bytes transiently and main recomputes bytes only for a sourceDisposition-matchable existing channel from its persisted source/fields; retained-unmatchable rows never reach hashing or comparison. Append/merge pairs require byte equality plus a valid same-lineage provenance marker and equal candidate digest. This tuple guard makes an injected digest collision with unequal preimages unmatched. Duplicate byte-equal tuples use the existing-lineup-order then candidate-occurrence one-to-one queue. Canonical preimage bytes never cross IPC or persist in provenance.

Main-issued public IDs are intentionally opaque and do not participate in deterministic identity. `planId` is exactly `channel-builder-plan-<randomHex128>` and an operation ID is exactly `channel-builder-(review|apply)-<randomHex128>`, using injected production `crypto.randomBytes(16).toString('hex')`; issuance retries a collision against all available, consumed, retained, and tombstoned IDs at most eight times, then returns `CHANNEL_BUSY`. The retained body stores both planId and planIdentity; `startApply` resolves the opaque planId to that body and never reconstructs or accepts a caller-supplied planIdentity.

`src/__tests__/domain/channelBuilderIdentity.test.ts` owns literal golden vectors. Each vector hardcodes the typed preimage, exact canonical JSON string/UTF-8 byte sequence, prefixed digest, and expected rejection where applicable; expected hashes are independently generated once with Node `crypto` and thereafter constants, not recomputed by the function under test. The set covers all three bindings; every facet family; both tag semantic identity domains; every source variant; actor/studio fastKey fallback; playlist null ownership; playlist and collection cases where `ratingKey !== key`; manual and both mixed-mode order reversals; same key across two server bindings; duplicate occurrence IDs; process-restart stability; NFC-equivalent ordinary strings; lexical normalized ordinary keys including the exact numeric-like-key vector whose canonical bytes place `"10"` before `"2"`; integers; fractional and exponent-serialized numbers; `Number.MAX_VALUE`; `-0` normalization; rejection of `NaN`, positive infinity, and negative infinity; arbitrary library-filter keys; fractional/exponent/large-finite library-filter values; NFC-equivalent distinct raw filter keys with stable entry multiplicity/order; undefined/sparse/duplicate-normalized ordinary object key/unknown outer-field rejection; candidate identity using only content-filter identity rather than plan-kind/facet/raw values; candidateId; planIdentity self-exclusion; and an injected candidate-digest collision rejected by unequal canonical tuple bytes. Tag vectors prove exact case-folded family-scoped grouping, cross-library equal-group equality, family inequality, exact director content-filter identity, raw-distinct filter inequality, display-projection independence, year metadata exclusion from digests that do not own it, and rejection of malformed prefixes/preimages. It additionally pins `PersistedStringV1` and complete plan-input/output positions for existing IDs and names over >512-code-unit values, C0/C1 controls, astral pairs, NFC-equivalent raw-distinct strings, hostile URL/credential/angle text, restart determinism, and injected digest collisions; no vector truncates, aliases, or applies display projection to identity input.

`ChannelBuilderStrategyKey` is exactly the eight configured strategy keys.

The recursive safe source type is exact:

- leaf: `{ kind: 'facet', facetId: ChannelBuilderFacetId | null, sourceIdentity: ChannelBuilderSourceIdentity }`;
- manual: `{ kind: 'manual', sourceIdentity: ChannelBuilderSourceIdentity, items: readonly ChannelBuilderSafeSourceLeafReference[] }`;
- mixed: `{ kind: 'mixed', sourceIdentity: ChannelBuilderSourceIdentity, mixMode: 'sequential' | 'interleave', sources: readonly ChannelBuilderSafeSourceReference[] }`.

Persisted manual items and all mixed sources admitted to the builder-safe identity type are non-empty ordered arrays of 1–500; the complete matchable tree has depth at most 8 and at most 500 leaves. These are matchability limits for existing manual-bearing trees and new-plan limits for audited non-manual trees only; they do not narrow the current persisted-source validator. Every planned leaf has non-null facetId and a non-manual audited facet family; every matchable existing projected leaf has null facetId; retained-unmatchable rows have a null sourceReference rather than a partial tree. Identity construction uses only the Identity V1 source domains/preimages above, while no item-facet identity exists. Reversing existing manual items or any mixed sources changes source/candidate identity for sequential and interleave alike.

`ChannelBuilderOriginBinding` is exactly `{ profileBinding, serverBinding, librarySetBinding }`. `ChannelBuilderChannelProvenanceV1` is exactly `{ schemaVersion: 1, identityVersion: 1, profileBinding, serverBinding, librarySetBinding, sourceIdentity, candidateIdentity }`; all bindings/source/candidate identities are the exact safe prefixed Identity V1 values. It never contains contextEpoch, canonical preimage bytes, raw source bytes, Plex keys, names, tokens, URI, or paths.

`ChannelBuilderCandidateContentFilterPlan` is the exact raw-free discriminated union:

- `{ kind: 'none', contentFilterIdentity: null }`;
- `{ kind: 'inline', contentFilterIdentity, filters }`, where `filters` is a nonempty `readonly ContentFilter[]`, every value is numeric, the identity recomputes over the normalized conjunction, and Package 1A constructs this variant only for the exact two-filter decade range;
- `{ kind: 'main-index-reference', contentFilterIdentity, facetId }`, where `facetId` must be a director facet and the identity must equal that facet's safe `contentFilterIdentity`.

No variant contains a raw tag/filter string or a generic deferred query. Expansions preserve the base candidate's plan byte-for-byte. `kind` and `facetId` control materialization but are excluded from candidate identity; equal final normalized filter conjunctions share the same `contentFilterIdentity`.

`ChannelBuilderCandidateDraft` is exactly `{ candidateId, candidateIdentity, origin, strategy, displayName, sourceReference, estimatedItemCount, playbackMode, shuffleSeed, contentFilterPlan, sortOrder, blockSize, buildStrategy, sourceLibraryId, sourceLibraryName, lineupReplicaIndex, isPlaybackModeVariant }`:

- `candidateId` matches `/^candidate:[a-f0-9]{64}$/u`;
- `strategy` is `ChannelBuilderStrategyKey`;
- `candidateIdentity` and `origin` are the exact lineage-bound values above;
- `displayName` is a trimmed safe 1–160 character string;
- `sourceReference` is the complete ordered tree with every leaf facetId non-null;
- `estimatedItemCount` is a finite non-negative integer or null;
- `playbackMode` reuses `PlaybackMode`;
- `shuffleSeed` is a finite integer;
- `contentFilterPlan` is the exact discriminated union above and is never omitted;
- `sortOrder` is `SortOrder | null`;
- `blockSize` is an integer 2–5 only for block playback, otherwise null;
- `buildStrategy` is `ChannelBuilderStrategyKey | null`;
- `sourceLibraryId` is a safe renderer-known library ID or null and `sourceLibraryName` is a safe 1–160 character name or null;
- `lineupReplicaIndex` is an integer 0–3 or null; the base candidate uses `0`, and when `alternateLineupCopies = N` the alternates use exactly `1..N`, so the allowed maximum `N = 3` emits `1`, `2`, and `3`;
- `isPlaybackModeVariant` is boolean or null.

For the seven directly projected nullable generated optionals—`sortOrder`, `blockSize`, `buildStrategy`, `sourceLibraryId`, `sourceLibraryName`, `lineupReplicaIndex`, and `isPlaybackModeVariant`—non-null means emit/replace that property and null means omit/remove it. `contentFilters` is the eighth generated optional, but its emit/remove decision is represented by `contentFilterPlan`: `none` means omit/remove, `inline` means emit the validated numeric filters, and `main-index-reference` means emit only the exact main-resolved director filter after identity/linkage validation. This explicit convention preserves the pinned optional-property behavior without retaining raw semantic filter strings in Package 1A planner inputs/outputs; the only Package 1A contact with such strings is the synchronous no-retention typed-constructor call frozen above.

`ChannelBuilderCandidateLedgerClassification` is exactly `'matched-retained' | 'new-apply' | 'excluded'`. `ChannelBuilderCandidateExclusion` is exactly `'minimum-items' | 'configured-capacity' | 'channel-number-capacity'`. `ChannelBuilderCandidateLedgerEntry` is exactly `{ ordinal, candidateId, strategy, sourceIdentity, classification, exclusion, retainedChannelId }`: ordinal is zero-based; exclusion is non-null only for excluded; retainedChannelId is a valid existing ID only for matched-retained and otherwise null. `ChannelBuilderExistingLedgerEntry` is exactly `{ ordinal, existingChannelId, disposition, matchedCandidateId }`, where disposition is `'matched-retained' | 'unmatched-retained' | 'replace-remove'`; matchedCandidateId is non-null only for matched-retained. It has exactly one row per persisted channel in original order. A retained-unmatchable projection can only become `unmatched-retained` in append/merge or `replace-remove` in replace; it can never become `matched-retained` or acquire a matchedCandidateId.

Candidate and existing ledgers are deterministic before materialization. In append/merge, only sourceDisposition-matchable rows with lineage-valid equal candidate identities may form matched-retained pairs, one-to-one in existing lineup then candidate ordinal order. Retained-unmatchable rows never enter an identity queue. Append retains a match without rematerializing it. Merge includes every matched-retained candidate in retained materialization. Replace has no match; every existing row, including retained-unmatchable, is replace-remove and appears in the explicit reviewed removal diff. Main later derives terminal created/skipped accounting; materialization-unavailable is apply-time and never forged into the pure ledger.

`ChannelBuilderPlannerOutput` is exactly `{ status, planIdentity, candidateDrafts, applyCandidateIds, retainedMaterializationCandidateIds, candidateLedger, existingLedger, diff, warnings, reachedCap, capacity }`:

- `status: 'ready' | 'slow' | 'blocked'`;
- `planIdentity` matches `/^plan-identity:[a-f0-9]{64}$/u` and is deterministic for the exact five-field input plus normalized output;
- `candidateDrafts: readonly ChannelBuilderCandidateDraft[]` and `candidateLedger: readonly ChannelBuilderCandidateLedgerEntry[]` have identical length/order and cap at 50,000;
- `applyCandidateIds: readonly string[]` is the ordered subset classified new-apply, contains no duplicates, and caps at 500;
- `retainedMaterializationCandidateIds: readonly string[]` is empty for append/replace and, for merge, contains every matched-retained candidate in candidate-ledger ordinal order;
- `existingLedger: readonly ChannelBuilderExistingLedgerEntry[]` has exactly one entry per persisted existing lineup row, preserves existing lineup order without omission, and caps only at the existing persisted lineup maximum of 500;
- `diff` is the exact closed review-diff DTO;
- `warnings` is the sorted/deduplicated `readonly ChannelSetupWarning[]`, capped at 50;
- `reachedCap` is boolean;
- `capacity` is exactly `{ requestedMaxChannels, effectiveMaxChannels, availableCreateSlots }`, each a finite integer 0–500, with `effectiveMaxChannels = min(requestedMaxChannels, 500)` and mode-specific `availableCreateSlots` frozen by the existing-lineup rules.

For blocked, both materialization ID arrays are empty. Package 1A asserts only the pure output: status blocked, the sole PLAN_EMPTY warning when applicable, empty `applyCandidateIds`, empty `retainedMaterializationCandidateIds`, and no apply-capable pure output or materialization request even if deterministic diagnostics include excluded or retained-unmatchable ledger entries. Package 1C alone proves that main assigns public `planId: null` and retains no body/index. `src/domain/channelBuilder/types.ts` owns the pure types; `planner.ts` exports exactly `buildChannelSetupPlan(input): ChannelBuilderPlannerOutput`; `src/__tests__/domain/channelBuilderContracts.test.ts` pins every field, discriminant/null rule, regex, cap, deterministic order, reversed manual/mixed source order, lineage/provenance matching, duplicate queue collision, same-key cross-server non-match, one-ledger-row-per-channel invariant, exact facet-warning validation/conversion, safe unmatchable warning, and absence of raw content/Plex keys.

The main-only `ChannelBuilderReviewedPlanBody` is exported from `channelBuilderOperationOwner.ts` and is exactly `{ planId, planIdentity, status, normalizedConfig, context, lineupRevision, candidateDrafts, applyCandidateIds, retainedMaterializationCandidateIds, candidateLedger, existingLedger, diff, warnings, reachedCap, capacity, materializationIndex }`. Status is only ready/slow; context is exactly `{ contextEpoch, profileBinding, serverBinding, librarySetBinding }`; lineupRevision is finite/non-negative; all pure fields are exact immutable planner values; and materializationIndex is the live main-only handle below. It contains no raw existing-lineup content source, Plex key, token, URI, path, payload, or public serialization method. The public result exposes only plan ID, lineage, status, diff, warnings, and cap flag.

#### Main-only facet source and index lifetime

`ChannelBuilderFacetDiscoveryInput` is exactly `{ normalizedConfig, context, deadlineAtMs, signal }`, where context is the exact four-field binding above, `deadlineAtMs` is a finite non-negative integer, and `signal` is the caller-owned `AbortSignal`. `ChannelBuilderFacetSource` exports one method, `discover(input): Promise<ChannelBuilderFacetDiscoveryResult>`. The result union is exactly:

- `{ kind: 'ready' | 'slow', snapshot, materializationIndex }`;
- `{ kind: 'blocked', snapshot, materializationIndex }`;
- `{ kind: 'canceled', snapshot: null, materializationIndex: null }`;
- `{ kind: 'failed', snapshot: null, materializationIndex: null, error: { code, retryable } }`, where code is `'CHANNEL_PLEX_REQUIRED' | 'CHANNEL_CONTEXT_CHANGED' | 'CHANNEL_UNKNOWN'` and retryable is boolean.

`snapshot` is the exact safe `ChannelBuilderFacetSnapshot`. The source converts per-family failure/partial state only into the exact aggregate status, `ChannelBuilderFacetWarningCode[]`, and two consistent omission counts; it does not construct strategy warnings or public `ChannelSetupWarning` records and never places exception text in the result. The pure planner owns the exact discovery-warning conversion above.

Package 1B `desktopPlexChannelBuilderFacetSource.ts` owns exact injected `ChannelBuilderFacetAccessPort` with only `withSession<T>(input, run): Promise<T>`. Input is exact `{ expectedContext, selectedLibraryIds, deadlineAtMs, signal }`; selected IDs must be byte-equal to normalized config's distinct ordered IDs. `run` is `(session: ChannelBuilderFacetSession) => Promise<T>`. The session is callback-scoped, main-only, non-serializable, invalid after callback settlement, and contains authoritative selected UUID-bearing library records plus only these allowlisted methods: `listCollectionsPage(request)`, `listServerPlaylistsPage(request)`, `listTagDirectoryPage(request)`, and `listLibraryItemsPage(request)`. It has no token, connection URI/object, headers, endpoint/path string, raw fetch, unrestricted request, generic method, or public serialization.

Exact session request DTOs are closed and reject unknown keys. Collections are `{ sectionId, offset, limit, signal }`; playlists are `{ offset, limit, signal }`; tags are `{ sectionId, family: 'genre' | 'director' | 'year' | 'studio' | 'actor', mediaType, offset, limit, signal }`; tag-directory mediaType is exact: movie-library genre/detail uses 1, show-library genre uses 2, and show-library detail families use 4. Items are `{ sectionId, query, offset, limit, signal }`, where `query` is exactly one of:

- `{ kind: 'recently-added', mediaType: 1 | 2 }`, mapping only to `type=<mediaType>` and `sort='addedAt:desc'`;
- `{ kind: 'tv-people-index' }`, mapping only to `type=4` with no sort or other filter;
- `{ kind: 'facet-count', mediaType: 1 | 2 | 4, family: 'genre' | 'director' | 'year' | 'studio' | 'actor', key, tagValue, fastKey }`. `key` is the validated nonempty raw `PlexTagDirectoryItem.key` retained main-only; `tagValue` is the exact raw-main-only normalized semantic value derived before display projection. Genre/director/year map exactly to `{ type: mediaType, [family]: tagValue }`. Actor/studio parse only allowlisted `actor | studio | type` entries from `fastKey`, require a nonempty value for the requested family, and then add or override exact `type = mediaType`; a malformed parse, any non-allowlisted credential/header/container/other entry, or a missing/empty requested-family entry falls back exactly to `{ type: mediaType, [family]: key }`. Actor/studio never fall back to `tagValue` or `displayTitle`.

No caller supplies a raw sort string, filter dictionary, query key, path, or media type outside that discriminated union. `key` and `fastKey` stay inside main and never enter the safe snapshot, public DTOs, IPC, preload, renderer state, logs, errors, or diagnostics. `fastKey` is the already-validated exact string or null. Offset is an integer 0–400 and limit is exactly 100. Recently-added uses only its exact union variant; the library-level facet issues no extra request when authoritative catalog counts already satisfy its frozen semantics.

`discover` performs every privileged operation only inside one `withSession` callback, rechecks deadline/abort/context before each page/family and after callback settlement, never retains or returns the session, and maps missing authentication to safe failed `CHANNEL_PLEX_REQUIRED`, stale context to `CHANNEL_CONTEXT_CHANGED`, cancellation to canceled, and transport/parser/other safe failure to existing `CHANNEL_UNKNOWN` without raw detail.

The existing `livePlexTransport.ts` defines a separate `LivePlexChannelBuilderFacetTransport` with only the fixed typed `listCollectionsPage(request)`, `listServerPlaylistsPage(request)`, and `listTagDirectoryPage(request)` methods. The existing `LivePlexLibraryTransport` declaration and its key set remain byte-for-byte unchanged. The real `LivePlexTransport` implements both interfaces. Package 1B's access adapter takes exactly one closed dependency object with two separately named fields: `{ facetTransport: LivePlexChannelBuilderFacetTransport, itemTransport: Pick<LivePlexLibraryTransport, 'listLibraryItems'> }`. Its collection, server-playlist, and tag-directory methods route only through `facetTransport`; its fourth session method, `listLibraryItemsPage`, privately composes the existing bounded item listing only through `itemTransport`. There is no intersection-typed dependency, combined transport parameter, cast, fallback, or runtime method detection, and neither the new interface nor the adapter acquires the rest of the legacy library surface.

Package 1B defines the new interface and fakeable access source but does not alter `DesktopPlexRuntimeOptions` or claim production injection. Package 1C adds exactly one separately named optional constructor option in existing `desktopPlexRuntime.ts`: `channelBuilderFacetTransport?: LivePlexChannelBuilderFacetTransport`. The constructor stores `options.channelBuilderFacetTransport ?? null` in a dedicated `LivePlexChannelBuilderFacetTransport | null` field; it does not infer it from `libraryTransport`, intersect the two interfaces, cast either transport, add an overload/setter, or probe for methods at runtime. Omission and explicit `undefined` have the same exact default: facet transport is unavailable while every pre-WS1 runtime operation remains unchanged. Existing constructors that supply only the unchanged required `libraryTransport` remain source-compatible. Existing `plexComposition.ts` is the sole production composition owner and passes the real `liveTransport` explicitly under both distinct names, `libraryTransport` and `channelBuilderFacetTransport`, with ordinary type checking proving that the real class satisfies each interface.

`desktopPlexChannelBuilderFacetSource.ts` owns exact main-only `ChannelBuilderFacetTransportUnavailableError`, a fixed no-argument error with no transport, URI, request, or exception-detail fields. `DesktopPlexRuntime.withChannelBuilderFacetSession` checks the dedicated field before context, auth, connection, or callback acquisition and throws only that sentinel when it is null. The source recognizes it by exact class identity, invokes no callback, performs no context/auth/connection/legacy-library transport work, and maps it to `{ kind: 'failed', snapshot: null, materializationIndex: null, error: { code: 'CHANNEL_UNKNOWN', retryable: false } }` with no exception text or diagnostic detail. When present, Package 1C constructs the Package 1B adapter's exact two-field dependency object with the dedicated `channelBuilderFacetTransport` as `facetTransport` and the existing required `libraryTransport` narrowed to `Pick<LivePlexLibraryTransport, 'listLibraryItems'>` as `itemTransport`. Collection/playlist/tag methods bind only the former and item listing only the latter. There is no fallback from a missing facet transport to `libraryTransport`, even if the runtime object happens to implement both interfaces.

Collections issue fixed `GET /library/sections/<encodeURIComponent(sectionId)>/all` with exact query `type=18`, `includeGuids=1`, `includeMeta=1`, `X-Plex-Container-Start=<offset>`, and `X-Plex-Container-Size=100`. Server playlists issue fixed `GET /playlists` with only the two container parameters. Tag family maps internally to fixed `/library/sections/<encoded sectionId>/<family>` and accepts only current allowlisted media-type integer constants plus the container parameters; no caller supplies a path. Library items delegate to existing bounded `listLibraryItems` through fixed facet-owned sort/filter/count-recovery requests only. Section IDs are encoded exactly once with `encodeURIComponent`; no unapproved query/header/path is accepted. Neither interface exposes a generic path/request/header primitive.

Response ownership is exact: `parseCollections`, `parsePlaylists`, and `parseDirectoryTags` plus their existing/new focused extractors parse the corresponding Plex `MediaContainer.Metadata` for collections/playlists and `MediaContainer.Directory` for tag families; library items retain their existing parser. Each result is exact `{ entries, offset, totalSize }` with ownership-safe parsed entries, non-negative safe integer offset, and totalSize non-negative safe integer or null. Paging starts at 0, advances by returned entry count/100-page offset as supported by the parsed container, stops on empty/short page or when next offset reaches known totalSize, and never exceeds offsets 0–400, five pages, family/library caps, or the 50,000 global facet cap. Malformed containers/offsets/totals become the frozen malformed/partial handling; 401/403 maps to auth loss, abort/deadline remains canceled/timeout, network failures remain safe transport failures.

`ChannelBuilderFacetMaterializationIndex` is exactly `{ context, materialize(input), dispose() }`. `context` is the immutable four-field binding. `materialize` accepts exactly `{ candidate, expectedContext, signal }`, where candidate is `ChannelBuilderCandidateDraft`, expectedContext is the four-field binding, and signal is an `AbortSignal`; it returns `Promise<ChannelBuilderFacetMaterializationResult>`. That result is exactly:

- `{ status: 'ready', candidateId, createInput }`, where `createInput` is main-only `ChannelCreateInput`;
- `{ status: 'skipped', candidateId, reason, warning }`, where reason is only `'facet-unavailable' | 'source-member-unavailable'` and warning is the exact safe `MATERIALIZATION_SKIPPED` record;
- `{ status: 'failed', candidateId, reason, error }`, where reason is `'context-changed' | 'source-member-mismatch' | 'invalid-materialization' | 'index-disposed'`; `context-changed` and `source-member-mismatch` carry exactly `{ code: 'CHANNEL_CONTEXT_CHANGED', retryable: true }`, `invalid-materialization` carries exactly `{ code: 'CHANNEL_VALIDATION_FAILED', retryable: false }`, and `index-disposed` carries exactly `{ code: 'CHANNEL_PLAN_EXPIRED', retryable: true }`;
- `{ status: 'canceled', candidateId }`.

The index recursively resolves every leaf of the candidate's complete ordered non-manual source-reference tree against the retained main-only index. It requires every leaf's non-null `facetId` and `sourceIdentity` to name the same retained entry; rejects manual/item-facet input as contract-invalid; revalidates the candidate identity, origin binding, and expected four-field context; preserves `mixed.sources` order exactly; and reconstructs the complete domain `ChannelContentSource` tree only after all descendants pass. Playlist reconstruction always assigns `playlistKey = PlexPlaylist.ratingKey`, and collection reconstruction always assigns `collectionKey = PlexCollection.ratingKey`; each retained raw `.key` is locator-only and cannot become the runtime source key.

The same materialization pass resolves `contentFilterPlan` exactly once. `none` emits no `contentFilters`. `inline` requires nonempty numeric-only filters, recomputes the candidate's `contentFilterIdentity`, and emits those normalized filters. `main-index-reference` requires the referenced facet to be the retained director facet from the same context, recomputes both its facet ID and exact director content-filter identity from the retained raw record, requires byte-equal `contentFilterIdentity`, and only then emits exact `[{ field: 'director', operator: 'eq', value: tagValue }]` inside the main-only `ChannelCreateInput`. It never accepts `displayTitle`, `semanticGroupIdentity`, the digest itself, or caller-supplied text as a runtime filter value. A genuinely missing facet/child/reference returns the corresponding unavailable skip; an identity mismatch, wrong family, invalid inline plan/source, stale context, or disposed index returns failed, never skipped. No case returns or persists a partial source/filter result. It never returns raw source/index values other than inside the main-only `ChannelCreateInput`. `dispose(): void` is synchronous and idempotent, clears every privileged reference, and causes later materialization to return failed/index-disposed.

For `ready`, the materializer constructs an exact own-key `ChannelCreateInput` projection from the validated candidate: required keys are `contentSource`, `name: candidate.displayName`, `playbackMode`, `shuffleSeed`, and `isAutoGenerated: true`; `contentFilters` is present exactly when the validated `contentFilterPlan` resolves to a nonempty conjunction, and each of the seven directly projected nullable generated fields `sortOrder`, `blockSize`, `buildStrategy`, `sourceLibraryId`, `sourceLibraryName`, `lineupReplicaIndex`, and `isPlaybackModeVariant` is present with its candidate value if and only if that value is non-null. `number` is always absent. Every other `ChannelCreateInput` optional—`description`, `hidden`, `icon`, `color`, `phaseSeed`, `startTimeAnchor`, `skipIntros`, `skipCredits`, `maxEpisodeRunTimeMs`, and `minEpisodeRunTimeMs`—is absent. Unknown keys, an omitted required key, a present-null generated optional, unresolved/reference digest as filter data, `number`, or any other create optional makes the nominal ready result contract-invalid. This projection is the sole materializer output; no later apply layer enriches it with additional create fields.

Ownership transfers exactly once. Discovery owns the index while pending. It disposes internally before returning canceled/failed. The operation owner immediately disposes a blocked result or a ready/slow result canceled before body retention. A retained ready/slow review body becomes sole owner; expiry, eviction, context invalidation, review cancellation, process shutdown, or any rejection before apply consumption disposes it. Accepted `startApply` atomically removes the body and transfers its index exactly once to that apply operation; consumed records and tombstones never retain it. The apply owner disposes in one terminal `finally` path after success, cancellation, or failure. Tests prove one transfer, idempotent disposal, every disposal path, no use after disposal, and no privileged serialization.

#### Exhaustive public operation and status DTOs

`ChannelSetupOperationProgress` is exactly `{ completed: number, total: number | null }`. `completed` is a finite integer 0–50,000; non-null total is a finite integer 0–50,000 and `completed <= total`. Progress is a phase-local contract:

- review `discover-facets` queued/running/canceling is `{ completed: <bounded completed request units>, total: null }`; queued begins at zero, completed is monotonic within the phase, and an unknowable total is never fabricated;
- review `plan` is `{ completed: 0, total: 1 }` before the synchronous pure-planner call and `{ completed: 1, total: 1 }` after it returns while the required post-plan event-loop yield and stale/cancel checks remain pending;
- `review-ready` is `{ completed: 1, total: 1 }`;
- apply `materialize` queued/running/canceling is `{ completed: settledCount, total: materializationCount }`;
- apply `persist` is `{ completed: 0, total: 1 }` before the aggregate rename and `{ completed: 1, total: 1 }` after it;
- apply `refresh-guide` is `{ completed: 0, total: 1 }` before the non-abortable refresh settles and `{ completed: 1, total: 1 }` after it;
- apply success is `{ completed: 1, total: 1 }`; every canceled or failed terminal, for either operation kind and regardless of its prior phase or unknowable discovery total, is normalized to exactly `{ completed: 1, total: 1 }`, where lifecycle completion does not imply successful work.

Within one phase, completed never decreases. `updatedAtMs` advances whenever phase or progress changes; terminal normalization also advances it. Tests cover every phase, cancellation and failure from every phase, unknown-total discovery, and rejection of fabricated totals or decreasing within-phase progress.

Every `ChannelSetupOperation` variant carries `{ operationId, kind, state, phase, startedAtMs, updatedAtMs, progress, result, error }`; timestamps are finite non-negative integers with `updatedAtMs >= startedAtMs`. The exhaustive valid union is:

- review nonterminal: `kind: 'review'`, `state: 'queued' | 'running' | 'canceling'`, phase `discover-facets` for queued and `discover-facets | plan` for running/canceling, `result: null`, `error: null`;
- review ready: `kind: 'review'`, `state: 'review-ready'`, `phase: 'review-ready'`, `result: { kind: 'review', planId, contextEpoch, lineupRevision, status, diff, warnings, reachedCap }`, `error: null`; status is `ready | slow | blocked`, planId is non-null only for ready/slow and null for blocked;
- apply nonterminal: `kind: 'apply'`, `state: 'queued' | 'running' | 'canceling'`, phase `materialize` for queued/canceling and `materialize | persist | refresh-guide` for running, `result: null`, `error: null`;
- succeeded: `kind: 'apply'`, `state: 'succeeded'`, `phase: 'done'`, `result: { kind: 'apply', commit: 'committed', summary, guideRefresh: 'completed' | 'failed' }`, `error: null`;
- canceled: either kind, `state: 'canceled'`, `phase: 'done'`, `result: { kind: 'canceled' }`, `error: null`;
- failed: either kind, `state: 'failed'`, `phase: 'done'`, `result: null`, `error: ChannelSetupRuntimeError`.

No other kind/state/phase combination validates. Operation ID kind must match the operation kind. Public result warnings/diffs/summaries retain their existing exact caps; no operation body/index/candidate/ledger enters this union. `contracts.test.ts`, preload guard tests, `channelBuilderOperationContracts.test.ts`, and renderer projection tests enumerate every valid variant and reject cross-product combinations, wrong nullability, invalid progress totals, unknown keys, and over-cap payloads.

`ChannelSetupStatusValue` remains exactly `'not-configured' | 'configured' | 'recovering' | 'recovery-failed'`. `ChannelSetupPersistedChannelSummary` is exactly `{ id, number, name, sourceLibraryId, sourceLibraryName, itemCount }`: id and non-null sourceLibraryId match `[A-Za-z0-9._-]{1,120}`; number is an integer 1–500; required `name` is a safe 1–160-UTF-16-unit display string; non-null `sourceLibraryName` is a safe 0–160-UTF-16-unit display string, so present empty is valid; both are truncated without splitting a surrogate pair; itemCount is any finite non-negative number; source-library fields are independently nullable. Contract, preload-guard, and public-reference tests must reject empty `name`, accept `sourceLibraryName` as null or `''`, accept its nonempty safe values through 160 units, and reject only its unsafe or over-160-unit strings. `getStatus` success is exactly `{ status, lineupRevision, channelCount, currentChannelId, currentChannelNumber, currentChannelName, channelNumbers, channels, builder, recovery, updatedAtMs }`:

- `lineupRevision`, `channelCount`, and `updatedAtMs` are finite non-negative integers; channelCount is 0–500;
- `channels` is ordered, capped at 500, contains exact summaries only, and has length `channelCount`; `channelNumbers` is the same ordered unique number projection;
- the current-channel ID/number/name triple is all null or exactly matches one returned channel;
- `builder` is exactly `{ completion: 'unknown' | 'complete', normalizedConfig: ChannelSetupConfig | null, completedAtMs: number | null }`; unknown requires both nullable fields null, complete requires normalizedConfig and a finite non-negative timestamp;
- `recovery` is exactly `{ loaded: boolean, repaired: boolean }`; repaired implies loaded;
- `not-configured` requires unknown builder state, while configured requires complete builder state; recovering/recovery-failed may carry either according to the last valid aggregate.

Package 1C adds one shared main-process `ChannelPublicReferenceOwner`, constructed and injected by `channelComposition`, as the sole public Channel Setup status and guide-presentation channel/library reference, Guide program-reference, and display-string projection owner. Existing `ChannelRuntime` exposes exact main-only `loadPublicReferenceGeneration(): Promise<ChannelPublicReferenceGeneration>`. One generation comes from one repaired, read-only, complete aggregate load and contains `lineupRevision`, the complete ordered channel rows needed for status projection, each exact raw channel ID, each normalized hidden flag, each non-null raw source-library ID, `currentChannelId`, and `fingerprint`. The fingerprint is lowercase SHA-256 hex over UTF-8 canonical JSON of the complete tuple `[lineupRevision, [[rawChannelId, hidden, rawSourceLibraryId], ...], currentChannelId]`; the ordered rows and tuple are derived from that same aggregate with no intervening read. Duplicate raw channel IDs remain storage corruption and no generation is returned.

The owner allocates all channel and source-library public references from the full generation before projecting status or any visible Guide subset. It never allocates from Guide rows, cache contents, or call order. A generation's mapping reserves every safe passthrough channel/library value first—including hidden safe channel IDs—then allocates every unsafe alias against that complete reserved/allocated set. Given the same generation, status-first, Guide-first, repeated status, and repeated Guide calls are byte-identical. A cached mapping may be reused only for an equal fingerprint and can never override a later full generation. `ChannelRuntime.getStatus` loads one generation and delegates projection to this owner.

Guide `getPresentation` executes one bounded consistency attempt as: load full generation A; call unchanged `guideRuntime.getPresentation`; load full generation B; accept only when A and B fingerprints are byte-equal and every raw Guide channel ID and `nowWatching.channelId` is present in A with matching visibility (every presented reference must name a non-hidden row). Otherwise it discards that raw presentation and retries the complete A/runtime/B sequence, for at most three total attempts. Exhaustion returns exactly `{ code: 'GUIDE_PRESENTATION_STALE', message: 'Guide changed while loading. Try again.', retryable: true, recoverable: true, operation: 'getPresentation' }`. An accepted raw presentation is projected only with generation A. No partial row, stale cache, or mixed generation is returned.

For channel IDs, a persisted raw value passes through byte-for-byte only after the owner validates the complete accepted generation has unique raw channel IDs, the value matches `/^[A-Za-z0-9._-]{1,120}$/u`, and imported `containsChannelBuilderCredentialMarker(raw) === false`. Every other distinct raw ID receives `legacy-channel-<digest>-<collisionOrdinal>-<allocationAttempt>`, where `digest` is lowercase SHA-256 hex of UTF-8 `lineup-status-channel-ref/v1:` followed by the raw ID; unequal raw IDs with the same digest are ordered by their complete UTF-16 code-unit arrays and receive collision ordinals 0–499; and allocation attempts are 0–500 inclusive, giving 501 candidates and at most 500 retries to avoid every full-generation safe passthrough ID and every already allocated alias. Source-library IDs use the identical three-part eligibility rule and alias procedure with domain `lineup-status-library-ref/v1:` and prefix `legacy-library-`. Repeated identical non-null source-library IDs share one public reference. Exhausting an ordinal or allocation range is a redacted validation/projection failure, never omission or mutation. Digesting is injected for focused collision tests; production uses SHA-256. Given the same generation, aliases are deterministic across restart. Exact tests prove `token-secret`, `Bearer-secret`, `authorization-secret`, and header variants alias despite matching the character regex, safe boundary near-miss `mytoken` passes through when unique, and overlength/control/otherwise-hostile values alias; duplicate channel IDs reject the generation. No unsafe, marker-bearing, or unvalidated raw value reaches preload or renderer.

Every Guide program ID is projected and never passes through. For each program in presentation order, its base tuple is `[publicChannelId, rawProgramId, startsAtMs, endsAtMs]`; `occurrence` is the count of earlier byte-equal base tuples. The exact identity tuple is `{ publicChannelId, rawProgramId, startsAtMs, endsAtMs, occurrence }`. Its canonical JSON is `canonicalJsonV1(identityTuple)` under the already-frozen key-order/string/number rules, and its digest is lowercase SHA-256 hex of UTF-8 `lineup-guide-program-ref/v1:` followed by that canonical JSON. Unequal identity tuples with the same digest sort by their complete canonical tuple UTF-8 bytes and receive collision ordinals 0–49,999. The returned ID is exactly `guide-program-<64hex>-<collisionOrdinal>`. A presentation over 50,000 programs, an exhausted collision ordinal, an invalid time/tuple, or duplicate final public program reference rejects the entire presentation with exactly `{ code: 'GUIDE_PRESENTATION_FAILED', message: 'Guide presentation could not be projected.', retryable: true, recoverable: true, operation: 'getPresentation' }`; programs are never omitted or truncated. Digesting remains injected for collision fixtures, including a 120-character safe channel ID with programs.

Package 1C's exhaustive public display projection policy is:

| Public field | Null/empty behavior | `fallback` | `maxUtf16Units` |
| --- | --- | --- | --- |
| `ChannelSetupPersistedChannelSummary.name` | Required; an input that normalizes to empty becomes the fallback | `'Untitled channel'` | `160` |
| `ChannelSetupSummary.currentChannelName` | Remains `null` when there is no current channel; otherwise reuses byte-for-byte the projected `name` of the matching returned channel summary and makes no second projection choice | `'Untitled channel'` | `160` |
| `ChannelSetupPersistedChannelSummary.sourceLibraryName` | Raw `null` remains `null`; a present safe 0–160-unit string that is empty or normalizes to empty remains the contract-valid empty string | `''` | `160` |
| `EpgChannelViewModel.name` | Required; an input that normalizes to empty becomes the fallback | `'Untitled channel'` | `160` |
| `EpgProgramViewModel.title` | Required program label; an input that normalizes to empty becomes the fallback | `'Untitled program'` | `2_000` |
| `EpgProgramViewModel.subtitle` | Optional metadata; empty/normalizes-empty remains `''` | `''` | `2_000` |
| `EpgProgramViewModel.description` | Optional metadata; empty/normalizes-empty remains `''` | `''` | `2_000` |
| `EpgProgramViewModel.showTitle` | Optional metadata; empty/normalizes-empty remains `''` | `''` | `2_000` |
| `EpgProgramViewModel.episodeLabel` | Optional metadata; empty/normalizes-empty remains `''` | `''` | `2_000` |
| `EpgProgramViewModel.rating` | Optional metadata; empty/normalizes-empty remains `''` | `''` | `2_000` |
| each `EpgProgramViewModel.quality[]` entry | Optional metadata entry; empty/normalizes-empty remains `''` and still occupies its original array position | `''` | `2_000` |
| each `EpgProgramViewModel.genres[]` entry | Optional metadata entry; empty/normalizes-empty remains `''` and still occupies its original array position | `''` | `2_000` |
| `EpgCurrentProgramViewModel.title` | Required current-program label; an input that normalizes to empty becomes the fallback | `'Untitled program'` | `2_000` |
| `EpgCurrentProgramViewModel.subtitle` | Optional metadata; empty/normalizes-empty remains `''` | `''` | `2_000` |

This table is exhaustive for Package 1C Channel Setup/Guide display projection: identifiers, channel numbers, counts, times, fixed error messages, and builder configuration are validated by their own contracts and are not display-projector inputs. The `160` limits preserve the current Channel Setup contract and one channel-name value across status and Guide; the `2_000` limits and empty-string fallbacks preserve the current Guide contract's optional-empty metadata semantics. No implementer chooses another fallback or limit.

All public Guide channel/current references use the accepted full-generation mapping. Package 1C's public-reference owner imports the sole Package 1A `projectChannelBuilderSafeDisplayString` and calls it for every non-null field/entry in the table with exactly that row's options; it owns no second sanitizer or alternate normalization. Quality and genre arrays preserve input order, project every entry independently before the public cap, and then retain only the first 20 projected entries; no rejected/remaining raw entry or unknown raw text is exposed. Source-library null remains null. Status `itemCount` remains any finite non-negative number. Status number/current-channel fields are derived from the same generation row after public-reference projection, so the current ID/number/name triple remains all null or exactly matches a returned summary.

Tune never trusts the last visible-presentation cache. It loads the latest full generation, requires the submitted public reference to be current in that generation, resolves it to the raw ID in main, and calls unchanged `guideRuntime.tuneChannel(rawChannelId)`. Unknown/stale input returns the existing Guide validation result. Any lineup race, deletion, or content/runtime failure after resolution discards exception text and returns exactly `{ code: 'GUIDE_TUNE_FAILED', message: 'Channel could not be tuned.', retryable: true, recoverable: true, operation: 'tuneChannel' }`; diagnostics may contain only that fixed code/copy and never a raw legacy ID. Projection is total for the full 500-row generation, does not persist or mutate aliases/labels/raw IDs, and never drops an otherwise valid status or accepted Guide row. This correction changes no renderer, preload, `guideRuntime`, overlay, persistence-schema, or public Guide-contract file.

#### Aggregate persistence and mutation coordinator

`ChannelBuilderPersistedStateV1` is exactly `{ schemaVersion: 1, normalizedConfig, completedAtMs, profileBinding, serverBinding, librarySetBinding, channelProvenance }`, with normalized config and bindings using the exact contracts above, completedAtMs a finite non-negative integer, and `channelProvenance` an exact null-prototype record from at most 500 valid persisted channel IDs to `ChannelBuilderChannelProvenanceV1`. The optional on-disk `ChannelPersistenceFileV1` is exactly `{ schemaVersion: 1, storedChannelData, currentChannelId, lineupRevision?, channelBuilderState? }`: storedChannelData is `StoredChannelData | null`; currentChannelId is string or null; optional lineupRevision, when present, is a finite non-negative integer; optional channelBuilderState, when present, is `ChannelBuilderPersistedStateV1`. The normalized `ChannelAggregate` has the same fields but requires `lineupRevision: number` and `channelBuilderState: ChannelBuilderPersistedStateV1 | null`; missing optional fields normalize to `0` and null under the frozen migration rules.

Package 1C makes persisted-ID-keyed provenance a dictionary-safe owner, not a normal `{}`. Serialized input may have `Object.prototype` or null as its prototype, but arrays, other prototypes, symbol keys, non-enumerable own keys, and accessor properties invalidate the provenance container to the empty null-prototype record without channel loss or inferred provenance. Validation enumerates only own enumerable string data properties through descriptors; it never uses inherited lookup, `in`, or an unguarded indexed read. Each exact raw key is validated against the current loader-normalized persisted channel ID and the loaded lineup, including valid IDs exactly equal to `__proto__`, `constructor`, or `prototype`; each marker value then receives the existing marker-local validation/recomputation rules, so one invalid marker drops only itself.

Existing `channelDomainClone.ts` owns one reusable `cloneOwnEnumerableStringRecordWithNullPrototype` helper for both `libraryFilter` and `channelProvenance`. It constructs `Object.create(null)`, defines each exact raw key as an enumerable/writable/configurable own data property, and applies the caller's ownership-safe value clone; provenance marker objects are cloned rather than shared. Repository normalization, startup repair, aggregate CAS preparation, builder/non-builder mutation, repeated `cloneChannelForOwnership` paths, and restart loading all retain a null prototype and use exact own-property checks for lookup/delete/update. Object spread into `{}`, `Object.assign` with a normal-object target, inherited reads, prototype-bearing accumulators, and direct assignment into a normal object are forbidden. JSON serialization must emit the three magic keys as ordinary own keys, and parse → normalize/repair → clone → serialize → restart must retain each valid marker byte-semantically while leaving `Object.prototype` and every global prototype unchanged.

The provenance record is the sole persisted builder-match authority. A successful builder mutation writes an exact versioned marker for every newly created channel and every merge-matched retained channel; append preserves a matchable retained channel's marker only if it is already valid; merge preserves unmatched matchable existing markers only if already valid; retained-unmatchable markers are always absent; replace retains markers only for the committed replacement lineup. Every successful full-lineup mutation removes mappings for IDs absent from the committed lineup. Any non-builder mutation that changes or deletes an identity-bearing channel clears that channel's marker, while a current-channel-only mutation leaves the record unchanged. Lineup bytes, provenance, builder completion/configuration/bindings, and revision commit in the same aggregate rename.

On load, every current-valid persisted source remains attached to its channel unchanged and in original order. Main classifies it matchable or retained-unmatchable by the exact projection rule before provenance repair. Matchable markers are independently exact-validated and recomputed through the null-prototype own-property owner; unknown schema/identity versions, unknown channel IDs, malformed values, lineage mismatch, source mismatch, and recomputation mismatch drop only that marker. Every current-valid library filter—including arbitrary non-forbidden keys, finite fractional/exponent/large values, and distinct NFC-equivalent raw keys—remains eligible for matchable recomputation when its outer source fits the builder-safe constraints. A retained-unmatchable row is never recomputed and any marker for it is dropped, while its raw source/channel remains unchanged. A legacy builder state without `channelProvenance` normalizes to an empty null-prototype record, so legacy channels never match by inference. Restart preserves the same disposition deterministically: matchable rows—including rows whose exact ID is `__proto__`, `constructor`, or `prototype`—require a surviving own valid marker plus exact current profile/server/library-set lineage, exact recomputation, and byte-equal canonical identity tuples; retained-unmatchable rows remain stable and unmatched. Same raw source keys on another server, playlist/collection `.key` values that differ from their runtime `ratingKey`, malformed markers, inherited marker lookalikes, and injected digest collisions with unequal tuples cannot match. No repair or migration may omit, truncate, alter, or reorder a current-valid channel because its source is unmatchable.

Package 1C makes the surgical `channelRepository.ts` normalization path and its existing ownership-clone dependency total for library-filter magic keys without narrowing the current validator. `src/domain/channel/channelDomainClone.ts` owns the single named `cloneOwnEnumerableStringRecordWithNullPrototype` helper frozen above: it creates `Object.create(null)`, reads only exact own enumerable data entries, and installs each exact raw key/value with `Object.defineProperty` using `{ enumerable: true, writable: true, configurable: true }`. `cloneContentSource` must use that helper for every non-null `libraryFilter`, and provenance normalization/cloning must use the same helper with its marker-value clone; object spread, indexed writes into `{}`, inherited reads, prototype-bearing accumulators, and a second local-equivalent behavior are forbidden. Consequently exact own keys `__proto__`, `constructor`, and `prototype`, alone or together, survive load/repair/save/repeated ownership clone/identity/restart byte-for-byte as ordinary data, and neither `Object.prototype` nor any global prototype is mutated. Package 1A identity and Package 1C builder/repository copy paths likewise consume own-entry enumeration and preserve the same multiplicity and values. This is clone/repository normalization and safe copying only: it adds no key allowlist, validator restriction, builder policy, persistence migration side effect, or new exported persistence schema.

`ChannelAggregateMutate` is exactly `(current: Readonly<ChannelAggregate>) => ChannelAggregate`; it is synchronous, must not throw, must return a complete replacement, and may not retain/mutate the input. `ChannelAggregateMutationRequest` is the exhaustive union:

- `{ kind: 'builder-lineup', expectedLineupRevision: number, mutate, onCommitBarrier }`, with a finite non-negative required revision;
- `{ kind: 'custom-lineup', expectedLineupRevision: null, mutate, onCommitBarrier }`;
- `{ kind: 'current-channel', mutate, onCommitBarrier }`, with `expectedLineupRevision` omitted and forbidden.

`onCommitBarrier` is exactly `() => 'proceed' | 'cancel'`, synchronous and called once under the timing contract below. A null custom revision means “serialize against the latest aggregate under the coordinator queue without CAS”; omission for current-channel means the same latest-aggregate rule while forbidding a lineup revision increment. `ChannelAggregateMutationResult` is exactly `{ status: 'committed', aggregate } | { status: 'conflict', actualLineupRevision } | { status: 'canceled' }`; conflict is possible only for builder, canceled only when that request's barrier returns cancel.

`ChannelLineupMutationCoordinator` exports exactly:

- `mutateBuilderLineup({ expectedLineupRevision, mutate, onCommitBarrier }): Promise<ChannelAggregateMutationResult>`;
- `mutateCustomLineup({ mutate }): Promise<{ status: 'committed', aggregate: ChannelAggregate }>`;
- `setCurrentChannel({ channelId }): Promise<{ status: 'committed', aggregate: ChannelAggregate } | { status: 'invalid-channel', aggregate: ChannelAggregate }>`, where channelId is a valid persisted channel ID or null.

The coordinator is the only builder/custom full-lineup serialization owner and delegates one request to `ChannelPersistenceStore.mutateChannelAggregate`; it contains no builder strategy or Custom Channels policy. Custom supplies the implicit proceed barrier and null revision. Current-channel supplies the implicit proceed barrier, validates against the latest lineup, changes only both current pointers, and never increments lineupRevision. Contract/domain/main tests pin the exact request/result union, callback synchronicity and replacement validation, null/omitted revision semantics, method return narrowing, metadata preservation, and absence of extra public overloads.

### Public channelSetup IPC contract

The legacy public `commit` operation is removed; no compatibility shim is retained. The narrow `channelSetup` bridge exposes:

- `getStatus`
- `startReview`
- `startApply`
- `getOperation`
- `cancel`

`src/contracts/channel.ts` owns the request/result discriminated unions and safe validators; `src/contracts/ipc.ts` owns exactly five invoke-channel constants. Every call uses the existing `{ requestId, payload }` envelope and `ChannelSetupIpcResult<T>`. A request ID is caller-generated, matches `[A-Za-z0-9._-]{1,120}`, exists only for one invoke/response correlation, and is never an operation identity. A main-generated operation ID matches `/^channel-builder-(review|apply)-[a-f0-9]{32}$/u` and is the only lookup/cancel key.

The exact payloads are:

- `getStatus`: `{}`;
- `startReview`: `{ config }`, where config has exactly the eight strategy keys, distinct `selectedLibraryIds`, current `serverId`, `maxChannels`, `minItemsPerChannel`, `buildMode`, actor/studio combine mode, expansion, and series-ordering fields;
- `startApply`: `{ planId, confirmReplace }`;
- `getOperation`: `{ operationId }`;
- `cancel`: `{ operationId }`.

`planId` matches `/^channel-builder-plan-[a-f0-9]{32}$/u`, and operation IDs match `/^channel-builder-(review|apply)-[a-f0-9]{32}$/u` as issued by the exact Identity V1-adjacent opaque-ID rule above. `confirmReplace` is a required boolean: it must be true for a reviewed replace plan and false for append/merge. Operation and plan IDs are main-issued opaque values; preload accepts only the exact patterns and never manufactures them.

`ChannelSetupConfig` has no optional IPC fields. It is exactly:

- `serverId: string`;
- `selectedLibraryIds: readonly string[]`;
- `maxChannels: number`;
- `minItemsPerChannel: number`;
- `buildMode: 'append' | 'replace' | 'merge'`;
- `actorStudioCombineMode: 'separate' | 'combined'`;
- `strategyConfig`, with exactly `collections`, `playlists`, `genres`, `directors`, `decades`, `recentlyAdded`, `studios`, and `actors`; every value is `{ enabled: boolean, priority: number, scope: 'per-library' | 'cross-library' }`;
- `channelExpansion: { addAlternateLineups: boolean, alternateLineupCopies: number, variantType: 'none' | 'sequential' | 'block', variantBlockSize: number }`;
- `seriesOrdering: { basePlaybackMode: 'shuffle' | 'sequential' | 'block', baseBlockSize: number }`.

Package 1A `src/domain/channelBuilder/config.ts` is the single default/normalization owner. It exports deeply frozen `CHANNEL_SETUP_BEHAVIOR_DEFAULTS`, exactly `{ maxChannels: 200, minItemsPerChannel: 5, buildMode: 'replace', actorStudioCombineMode: 'separate', strategyConfig, channelExpansion: { addAlternateLineups: false, alternateLineupCopies: 1, variantType: 'none', variantBlockSize: 3 }, seriesOrdering: { basePlaybackMode: 'shuffle', baseBlockSize: 3 } }`; all eight strategies are enabled with `per-library` scope, and priorities are playlists 1, collections 2, recentlyAdded 3, genres 4, studios 5, actors 6, decades 7, directors 8. The constant contains no server/library placeholder.

The same module exports pure `createDefaultChannelSetupConfig(context)` and `normalizeChannelSetupConfig(input, expectedContext)`. Context is exactly `{ serverId, selectedLibraryIds }`; both functions return exactly `{ ok: true, config: NormalizedChannelSetupConfig } | { ok: false }` and never throw. The factory validates context under the caps below, deep-clones the immutable behavior defaults, and returns one complete exact config. Normalization rejects unknown/omitted/invalid fields and context mismatch and produces a deep-cloned normalized config on success. Public main validation returns `CHANNEL_VALIDATION_FAILED` on `{ ok: false }`; persisted recovery explicitly calls the default factory after an invalid legacy config rather than silently making an invalid public request valid. No preload or renderer module duplicates default literals.

Caps are frozen: 1–24 distinct library IDs; `serverId` and every library ID must be trimmed, non-empty, at most 120 characters, and match `/^[A-Za-z0-9._-]{1,120}$/u`; `maxChannels` is an integer 1–500; `minItemsPerChannel` is an integer 1–500; priority is an integer 1–100; alternate copies are 1–3; both block sizes are integers 2–5. Only genres, directors, studios, and actors accept `cross-library`; the other four strategies require `per-library`. Requests reject unknown keys at every nesting level, duplicate libraries, non-finite numbers, identifiers outside that exact pattern, forbidden fields, and serialized payloads over 64 KiB.

`startReview` and `startApply` return promptly with `{ accepted: true, operation }`, where operation is the exhaustive `ChannelSetupOperation` union frozen above. `getStatus` returns only the exact nested status DTO frozen above. `getOperation` success is `{ operation }`. `cancel` success is `{ accepted, reason: null | 'already-terminal' | 'commit-started', operation }`.

`ChannelSetupWarning` is exactly `{ code, phase, strategy, affectedCount }`. `phase` is `discovery | planning | materialization | refresh`; `strategy` is one of the eight strategy keys or null; `affectedCount` is a non-negative safe integer or null. The exhaustive warning-code union is `FACET_UNAVAILABLE`, `FACET_PARTIAL_FAILURE`, `FACET_DISCOVERY_TIMEOUT`, `FACET_EMPTY`, `FACET_CAP_REACHED`, `FACET_MALFORMED_ENTRIES_OMITTED`, `TV_PEOPLE_METADATA_INCOMPLETE`, `EXISTING_SOURCE_UNMATCHABLE`, `MIN_ITEMS_SKIPPED`, `MAX_CHANNELS_REACHED`, `PLAN_EMPTY`, `MATERIALIZATION_SKIPPED`, and `GUIDE_REFRESH_FAILED`. `EXISTING_SOURCE_UNMATCHABLE` is valid only as `{ phase: 'planning', strategy: null, affectedCount: <positive retained-unmatchable count> }`; it never carries a raw identifier, source, or reason. Main deduplicates by `(code, phase, strategy)`: if every member count is numeric, it sums them and requires the result to remain a non-negative safe integer; if any member is null, the aggregate `affectedCount` is null. It then sorts by code, phase, and strategy and returns at most 50 warnings. Renderer text for this code is the exact safe sentence frozen in the projection section; all other UI text remains a local exhaustive code mapping, so CB-21 warning meaning does not depend on raw Plex/error prose.

Apply `summary` is exactly `{ created, removed, unchanged, skipped, finalChannelCount, reachedMaxChannels, watchChannelId, byStrategy, warnings }`. After successful rename, the operation computes and holds the count, `byStrategy`, cap, Watch-target, and materialization-warning values internally from the persisted lineup immediately before apply, the successfully materialized candidates, and the committed final lineup; review-diff counts must never be copied into them. The public/retained summary object does not exist yet. If CAS, validation, serialization, cancellation, exclusive open, handle write/policy-check/sync/stat/close, post-close temp identity validation, destination guard, or rename prevents a commit, there is no apply summary. All five counts are finite non-negative integers; `reachedMaxChannels` is boolean; `watchChannelId` is a safe persisted channel ID or null and is the only CB-25 Watch target. `byStrategy` has exactly the eight strategy keys, each `{ created, skipped }`.

The non-abortable guide refresh settles before final result construction. On success, final warnings omit `GUIDE_REFRESH_FAILED`. On failure, main applies the frozen warning dedupe/sort/cap rule and inserts exactly `{ code: 'GUIDE_REFRESH_FAILED', phase: 'refresh', strategy: null, affectedCount: 1 }` if it is not already present. If insertion would exceed 50 warnings, the deterministic final sort drops the last non-refresh warning so the refresh failure remains present and the public cap remains 50. Only then does main construct and freeze the public summary exactly once, pair it with `guideRefresh: 'completed' | 'failed'`, and retain that immutable terminal result. Repeated polls return the same final summary value; no later mutation or warning append is allowed.

Let `B` be the set of persisted channel IDs loaded immediately before the successful mutation and `F` the set committed by that mutation. IDs are unique, and replace materialization allocates IDs outside `B`. The exact committed-lineup equations are:

- `created = |F \ B|`;
- `removed = |B \ F|`;
- `unchanged = |B ∩ F|`, where “unchanged” means that the persisted channel identity was retained, not that every field is byte-identical;
- `|B| = removed + unchanged`;
- `finalChannelCount = |F| = created + unchanged = |B| - removed + created`.

Mode semantics are frozen to the audited upstream build-committer behavior, adjusted only for candidates that actually survive capacity and materialization:

- **append:** retain every member of `B`, so `removed = 0` and `unchanged = |B|`; successfully materialized unmatched candidates join membership and count as created, then the complete `F` is number-sorted rather than preserving or concatenating prior order;
- **merge:** retain every member of `B`, so `removed = 0` and `unchanged = |B|`; every identity-matched candidate is materialized and updates its retained record in place, while successfully materialized unmatched candidates are created;
- **replace:** only after the non-empty replacement-survival guard below passes, build the replacement lineup from the successfully materialized candidates, remove every member of `B`, and retain none, so `removed = |B|` and `unchanged = 0`; unavailable candidates are absent from `F`, but a terminal-invalid candidate or zero surviving candidates prevents any commit.

Append and merge carry each retained-unmatchable persisted channel record byte-for-byte into aggregate membership, count it unchanged, preserve it as an unmatched existing row, and never builder-update it; its final position is determined only by the mandatory ascending unique channel-number sort. Replace lists each such row in the reviewed remove diff/ledger and may remove it only after explicit replace confirmation, successful non-empty replacement materialization, the normal synchronous proceed barrier, and successful aggregate rename. PLAN_EMPTY review, rejected confirmation, failed/canceled/conflicted apply, pre-barrier storage failure, or all-unavailable replacement leaves every retained-unmatchable row and destination byte-identical. That explicit confirmed replace is a user-reviewed mode action, not migration or projection loss.

For each strategy, the planner preserves the exact deterministic candidate and existing ledgers frozen above. In append/merge, identity-matched entries are `matched-retained`; unmatched survivors are `new-apply`; and pure exclusions are `excluded` with exactly one of `minimum-items`, `configured-capacity`, or `channel-number-capacity`. Main consumes those immutable reviewed ledgers and derives exactly one terminal application classification for every unmatched entry: created if its successfully materialized channel ID is present in `F`, otherwise skipped for its pure exclusion or the later `materialization-unavailable` reason. A merge-matched entry is neither created nor skipped: its retained ID remains in `B ∩ F` and its existing-ledger disposition remains `matched-retained`. Therefore `created = sum(byStrategy[*].created)` and `skipped = sum(byStrategy[*].skipped)`, and for each strategy `byStrategy[strategy].created + byStrategy[strategy].skipped` equals that strategy's unmatched candidate-ledger-entry count. `MIN_ITEMS_SKIPPED`, `MAX_CHANNELS_REACHED`, and `MATERIALIZATION_SKIPPED` affected counts reconcile with those terminal classifications; one candidate skipped for multiple reasons is classified once by the first deterministic reason.

Let `cap = min(config.maxChannels, 500)`, and let `occupiedNumbers(B)` be the distinct valid persisted channel numbers in the repaired aggregate. For replace, configured create capacity is `cap`, channel-number capacity is 500, and `availableCreateSlots = min(cap, 500)`. For append/merge, configured create capacity is `max(0, cap - |B|)`, channel-number capacity is `500 - |occupiedNumbers(B)|`, and `availableCreateSlots` is the minimum of those two values. After minimum-item exclusions and identity matching, unmatched candidates are admitted in candidate-ledger order through configured capacity and then channel-number capacity; overflow receives exactly the first applicable exclusion, `configured-capacity` before `channel-number-capacity`. A repaired valid aggregate has unique channel numbers 1–500, so configured capacity normally binds first; the channel-number check remains an explicit defensive invariant and may not be inferred from IDs. `reachedMaxChannels` is true if and only if the deterministic ledger contains at least one `configured-capacity` exclusion; `MAX_CHANNELS_REACHED.affectedCount` is the number of those exclusions. It is false merely because `finalChannelCount === cap`, and false when all omissions arise from identity matching, minimum-item enforcement, channel-number capacity, materialization failure, or later materialization skips. `watchChannelId` follows the mandatory final number-sorted-order rule below, never candidate or settlement order.

#### Builder persisted-channel ID allocation

Existing `src/main/channel/channelBuilderRuntime.ts` owns an injected main-only `ChannelBuilderChannelIdAllocator`. After deterministic materialization/classification and the replace-survival guard, but before aggregate construction or the commit barrier, it allocates one persisted ID for each surviving `new-apply` candidate in candidate-ledger order. For each allocation attempt it calls injected `randomHex128()`, accepts only `/^[a-f0-9]{32}$/u`, and forms exactly `channel-builder-<hex>`. The occupied set begins with every ID in `B` even for replace and grows after every accepted proposed ID; therefore every proposed new ID is safe, unique, and outside `B`, and the committed `F` retains that uniqueness. Matched merge rows keep their exact retained ID and never invoke the allocator.

A candidate gets exactly eight attempts. A collision consumes one attempt and requests a fresh value. Any invalid generator result fails immediately; eight collisions fail after the eighth value. Either failure aborts remaining allocation/work, disposes the materialization index through the common terminal path, and occurs before the barrier with byte-identical aggregate/revision, no write, no guide refresh, and no summary. The exact public terminal error is `{ code: 'CHANNEL_UNKNOWN', message: 'Channel setup could not allocate channel identifiers.', retryable: true, recoverable: true, operation: 'startApply' }` from source `channel-id-allocation`. The builder constructs its apply-local `ChannelAuthoringService` with an allocator closure returning these preallocated IDs; `channelAuthoringService.ts` remains unchanged and out of Package 1C scope. Tests pin append/merge/replace allocation order, matched-ID retention, invalid output, repeated collision then success, eighth-collision exhaustion, `B`/proposed/`F` uniqueness, safe `watchChannelId`, and byte-identical failure.

#### Exact create/update projection and channel-number ownership

After materialization, survival checks, and ID preallocation, the apply owner processes successful candidates serially in candidate-ledger order through the unchanged `ChannelAuthoringService`; it never constructs channel numbers itself. For append and merge new rows, the evolving create aggregate starts with every member of `B`, and each successful `new-apply` row calls `createChannel(exactMaterializedInput, evolvingChannels)` before the created channel is appended to that evolving set. Because `number` is absent, the unchanged authoring service assigns the lowest unused number in 1–500 against `B` plus all preceding created rows. Materialization skips consume neither a number nor an ID slot in the evolving lineup. For replace, the evolving create aggregate starts empty, while the separate ID allocator's occupied-ID set still includes every ID in `B`; successful rows call `createChannel` in candidate-ledger order and therefore receive numbers 1, 2, … through the surviving count. Holes in append/merge are filled lowest-first; promise settlement order never changes numbering.

For merge, each successful `matched-retained` row is an update, not a create, and is processed at its ledger position against the evolving existing set. `src/main/channel/channelBuilderRuntime.ts` owns the builder-local matched-update projection; no helper file or `channelAuthoringService.ts` edit is authorized. Main locates the exact retained ID and first calls unchanged `ChannelAuthoringService.updateChannel` against the evolving aggregate with an exact non-null update input: it always includes `contentSource`, `playbackMode`, and `shuffleSeed`; includes `name: displayName` only when the current evolving retained record has `isAutoGenerated === true`; includes resolved `contentFilters` exactly when the materialized input contains them; and includes each of the seven directly projected builder-owned generated optionals only when its candidate value is non-null. Invalid resolved filters or other non-null values fail under unchanged authoring validation before aggregate construction. Main then ownership-clones the validated returned channel without mutating either the persisted/current input or authoring result, explicitly deletes `contentFilters` when `contentFilterPlan.kind === 'none'`, and explicitly deletes each of `sortOrder`, `blockSize`, `buildStrategy`, `sourceLibraryId`, `sourceLibraryName`, `lineupReplicaIndex`, and `isPlaybackModeVariant` whose candidate value is null, before placing the clone into the evolving aggregate. No other field is deleted or updated. The result preserves exact existing `id`, `number`, `createdAt`, `isAutoGenerated`, and every field outside those eight builder-owned generated optionals; `updatedAt` is assigned only by unchanged authoring semantics from the apply owner's injected clock. The match never calls the ID or number allocator. Subsequent matched updates and creates observe this evolving set.

After every mode has its complete membership `F`, the apply owner derives the sole persisted `channelOrder` by sorting all members of `F` ascending by unique validated channel `number`; valid final numbers are unique, so there is no tie-breaker or preservation-of-prior-order fallback. Append retains all `B` members but not their prior sequence, then includes new rows and sorts the complete result. Merge retains/update-matches and creates new rows into the evolving set, then sorts the complete result. Replace's serial 1..N assignment naturally yields candidate-ledger order after the same mandatory sort. `watchChannelId` is the first member of `F \\ B` in this committed number-sorted order, or null when none exists. Status/Guide refresh consume that committed order, so no pre-sort candidate, materialization-settlement, or prior persisted order may influence Watch or Guide order.

Focused fixtures pin append with existing numbers 1/3/5 and new rows receiving 2/4/6, then exact final order 1/2/3/4/5/6; arbitrary prior `B` order; additional holes; merge interleaving of matched updates and new creates; replace renumbering from 1 despite occupied `B` numbers while retaining `B` in the ID collision set; all three modes with candidate-ledger ordering different from promise settlement; materialization skips not consuming numbers; the 500-number boundary; configured-capacity versus channel-number-capacity classification; exact ready-create own keys/omissions; all-eight-present → all-eight-omitted matched removal with `contentFilterPlan.kind = 'none'`; inline numeric filters and main-index director references both replacing prior filters; mixed non-null replace/null delete; no deletion of user/unlisted fields; invalid inline/reference/non-null update rejection before aggregate construction; preservation of matched `id`/`number`/`createdAt`; and exact number-sorted persisted/status/Guide/Watch consequences.

#### Pre-barrier materialization outcomes and non-destructive replace

The apply owner consumes materialization outcomes against immutable candidate-ledger ordinal order. The following table is exhaustive; `—` means no `ChannelSetupRuntimeError` is constructed. No worker, preload guard, or renderer may invent different flags or copy.

| Materialization outcome | Exact apply disposition | Code | Safe message | Retryable | Recoverable | Operation |
| --- | --- | --- | --- | --- | --- | --- |
| valid `ready` with the exact requested `candidateId` and valid exact `ChannelCreateInput` | collect as ready and continue; not terminal | — | — | — | — | — |
| `facet-unavailable` or `source-member-unavailable` | for `new-apply`, record the one frozen `MATERIALIZATION_SKIPPED` classification and continue; for `matched-retained`, fail terminally because a reviewed retained update may not silently degrade | matched only: `CHANNEL_CONTEXT_CHANGED` | matched only: `Channel context changed. Review and try again.` | matched only: `true` | matched only: `true` | matched only: `startApply` |
| `context-changed` | fail terminally | `CHANNEL_CONTEXT_CHANGED` | `Channel context changed. Review and try again.` | `true` | `true` | `startApply` |
| `source-member-mismatch` | fail terminally | `CHANNEL_CONTEXT_CHANGED` | `Channel context changed. Review and try again.` | `true` | `true` | `startApply` |
| `index-disposed` | fail terminally | `CHANNEL_PLAN_EXPIRED` | `Channel setup review expired. Review and try again.` | `true` | `true` | `startApply` |
| `invalid-materialization` | fail terminally | `CHANNEL_VALIDATION_FAILED` | `Channel setup could not validate the reviewed plan.` | `false` | `true` | `startApply` |
| nominal `ready` with a wrong `candidateId`, invalid `createInput`, unknown key, or any other contract-invalid result shape | fail terminally | `CHANNEL_VALIDATION_FAILED` | `Channel setup could not validate the reviewed plan.` | `false` | `true` | `startApply` |
| unexpected materializer promise rejection | fail terminally without exposing rejection text | `CHANNEL_UNKNOWN` | `Channel setup could not complete the reviewed plan.` | `true` | `true` | `startApply` |
| `canceled` | use the exact terminal canceled operation variant `{ state: 'canceled', phase: 'done', result: { kind: 'canceled' }, error: null }`; never convert it to an error | — | — | — | — | — |
| after all nonterminal availability outcomes settle, non-empty replace has zero ready replacements | fail under the replacement survival guard | `CHANNEL_REPLACEMENT_EMPTY` | `No replacement channels remained available. Review and try again.` | `true` | `true` | `startApply` |

Each declared `ChannelBuilderFacetMaterializationResult` status/reason has exactly the disposition above. When multiple candidates have settled, the lowest candidate-ledger ordinal carrying a terminal disposition chooses the public terminal mapping regardless of promise settlement timing. Once that winner is knowable, main stops launching further materialization, aborts still-pending later work where supported, ignores later outcomes for error selection, disposes the index in the single terminal path, persists nothing, leaves aggregate/revision bytes unchanged, constructs no summary, and does not refresh the guide. It may not choose a faster later rejection over an earlier ordinal. Availability skips for `new-apply` are nonterminal and remain ordered; the all-unavailable replace decision occurs only after every replacement candidate has a valid unavailable outcome.

After all deterministic materialization settles and before constructing the aggregate mutation, a non-empty reviewed replace plan must have at least one ready replacement. If every replacement candidate is genuinely unavailable, apply fails exactly with `CHANNEL_REPLACEMENT_EMPTY`, message `No replacement channels remained available. Review and try again.`, `retryable: true`, `recoverable: true`, and operation `startApply`. It disposes the index, never invokes the commit barrier, preserves the complete aggregate and revision byte-for-byte, constructs no summary, and does not refresh the guide. A replace with at least one ready candidate may commit those candidates and classify unavailable candidates once as skipped under the frozen warning/accounting rules.

Append and merge never remove `B`. If their non-empty reviewed plan has no ready new candidate, append still commits the reviewed builder completion/configuration/provenance metadata with `created = 0`, `removed = 0`, `unchanged = |B|`, and deterministic skips; merge does the same only when it has no matched-retained update, while any successfully materialized match is updated normally. These are deliberate metadata commits with one revision increment and a committed summary, not implicit no-write successes. A pure zero-candidate review remains blocked earlier by `PLAN_EMPTY` and cannot reach this rule.

#### Merge retained materialization and exact update-in-place semantics

Append and replace materialize the `new-apply` entries named by `applyCandidateIds`; merge materializes both `matched-retained` entries named by `retainedMaterializationCandidateIds` and `new-apply` entries named by `applyCandidateIds`, interleaved by original ledger ordinal rather than by concatenating the two arrays. It prepares the complete proposed lineup and provenance record in memory before the commit barrier. A new candidate's genuinely unavailable result may become its one deterministic `materialization-unavailable` skip; every invalid result follows the terminal rule above. An accepted abort before the barrier remains terminal canceled under the common cancellation contract.

For each successfully materialized merge match, main locates the exact retained channel ID recorded in the candidate ledger and applies only the runtime-local validated-update-then-owned-clone/delete sequence frozen above. It preserves `id`, `number`, `createdAt`, `isAutoGenerated`, and every unlisted user-owned metadata field; replaces only the named always/non-null fields; deletes only the named null builder-owned optionals from the owned clone; and assigns `updatedAt` solely through unchanged authoring validation. `isAutoGenerated` itself is never copied from the planned candidate. The same retained ID receives the newly validated `ChannelBuilderChannelProvenanceV1` marker in the atomic aggregate.

Tests pin mixed matched/new processing, all matched candidates being materialized, retained-ID lookup, reversed composite-child order, all-present→all-null deletion, mixed optional replace/delete behavior, invalid non-null rejection, auto-generated versus user-authored naming, preservation of ID/number/createdAt/user metadata/`isAutoGenerated`, no mutation of current/validated source objects, exact provenance replacement, final number-sorted order, and unchanged-by-ID accounting. They also prove that every row of the exhaustive settlement table yields its exact code/message/flags/operation or non-error disposition; lowest-ledger-ordinal precedence is independent of promise settlement order; every invalid result and every matched-retained failure aborts remaining pre-barrier work with no write/summary/refresh; an all-unavailable replace returns exact `CHANNEL_REPLACEMENT_EMPTY` with byte-identical aggregate/revision; a mixed-success replace commits only ready candidates with exact skips; and append/merge zero-new-success follows the explicit metadata-update rules above.

The public review diff DTO is exactly `{ summary: { created, removed, unchanged }, samples: { created, removed, unchanged } }`, with no unknown keys at either level. Every summary count is a finite non-negative integer. Each sample category is a deterministically ordered array of at most six renderer-safe channel names; every existing or planned raw name first passes the sole Package 1A `projectChannelBuilderSafeDisplayString(raw, { fallback: 'Untitled channel', maxUtf16Units: 160 })` call before sample ordering/concatenation/capping, and every returned sample is nonempty and at most 160 UTF-16 units without a split surrogate. Samples contain no channel IDs, Plex keys, facet IDs, bindings, raw metadata, paths, URIs, or other privileged values.

The planner first computes an exact replace-style comparison between the planned identities and the existing-lineup projection. In `replace`, that exact comparison is returned unchanged. In `append` and `merge`, persisted identities absent from the generated plan are retained rather than removed, so the public projection is normalized exactly to `removed = 0`, `unchanged = raw.unchanged + raw.removed`, `samples.removed = []`, and `samples.unchanged = firstSix(raw.samples.unchanged followed by raw.samples.removed)`; `created` and `samples.created` remain the exact unmatched planned values. Both source arrays use the pinned deterministic identity order before concatenation and capping. Contract validation, preload guards, and renderer projection tests must reject non-integer/negative/non-finite counts, a seventh sample, unsafe or overlength names, privileged-looking fields, and every unknown key, and must pin replace removal plus append/merge retention/reclassification.

Progress exposes counts and phase only, never Plex labels or raw task details. Every returned collection is capped by the contract; status returns at most the persisted 500-channel maximum. Responses over 256 KiB are validation failures rather than truncated objects.

The frozen error-code union is `CHANNEL_UNAUTHORIZED`, `CHANNEL_VALIDATION_FAILED`, `CHANNEL_BUSY`, `CHANNEL_PLEX_REQUIRED`, `CHANNEL_CONTEXT_CHANGED`, `CHANNEL_LINEUP_CONFLICT`, `CHANNEL_PLAN_NOT_FOUND`, `CHANNEL_PLAN_EXPIRED`, `CHANNEL_PLAN_ALREADY_USED`, `CHANNEL_OPERATION_NOT_FOUND`, `CHANNEL_OPERATION_EXPIRED`, `CHANNEL_REPLACE_CONFIRMATION_REQUIRED`, `CHANNEL_REPLACEMENT_EMPTY`, `CHANNEL_STORAGE_UNAVAILABLE`, `CHANNEL_STORAGE_CORRUPT`, and `CHANNEL_UNKNOWN`. Errors contain only `{ code, message, retryable, recoverable, operation }`, with a safe 1–160 character message and one of the five operation names. Materialization-related `CHANNEL_CONTEXT_CHANGED`, `CHANNEL_PLAN_EXPIRED`, `CHANNEL_VALIDATION_FAILED`, `CHANNEL_UNKNOWN`, and `CHANNEL_REPLACEMENT_EMPTY` values use only the exact message/flags/`startApply` combinations frozen in the exhaustive table above.

The following non-materialization table is exhaustive. The `Source` strings are exact internal classification literals, and “all five” means the explicit operations `getStatus`, `startReview`, `startApply`, `getOperation`, and `cancel`. No unlisted `(code, operation, source)` tuple is constructible.

| Code | Operation | Source | Exact safe message | Retryable | Recoverable |
| --- | --- | --- | --- | --- | --- |
| `CHANNEL_UNAUTHORIZED` | all five | `request-auth` | `Channel setup request is not authorized.` | `false` | `false` |
| `CHANNEL_VALIDATION_FAILED` | all five | `request-envelope` or `request-payload` | `Channel setup request is invalid.` | `false` | `true` |
| `CHANNEL_BUSY` | `startReview`, `startApply` | `active-operation` | `Another channel setup operation is active. Try again.` | `true` | `true` |
| `CHANNEL_BUSY` | `startApply` | `consumed-plan-capacity` | `Channel setup is retaining too many recently consumed reviews. Try again.` | `true` | `true` |
| `CHANNEL_PLEX_REQUIRED` | `startReview` | `plex-prerequisite` | `Connect to Plex and select a server and libraries before building channels.` | `true` | `true` |
| `CHANNEL_CONTEXT_CHANGED` | `startReview`, `startApply` | `context-revalidation` | `Channel context changed. Review and try again.` | `true` | `true` |
| `CHANNEL_LINEUP_CONFLICT` | `startApply` | `lineup-revision` | `Channels changed after review. Review and try again.` | `true` | `true` |
| `CHANNEL_PLAN_NOT_FOUND` | `startApply` | `plan-missing` | `Channel setup review was not found. Review again.` | `false` | `true` |
| `CHANNEL_PLAN_EXPIRED` | `startApply` | `plan-expired` or `plan-tombstone` | `Channel setup review expired. Review and try again.` | `true` | `true` |
| `CHANNEL_PLAN_ALREADY_USED` | `startApply` | `plan-consumed` | `Channel setup review was already used. Review again.` | `false` | `true` |
| `CHANNEL_OPERATION_NOT_FOUND` | `getOperation`, `cancel` | `operation-missing` | `Channel setup operation was not found.` | `false` | `true` |
| `CHANNEL_OPERATION_EXPIRED` | `getOperation`, `cancel` | `operation-tombstone` | `Channel setup operation expired.` | `false` | `true` |
| `CHANNEL_REPLACE_CONFIRMATION_REQUIRED` | `startApply` | `replace-confirmation` | `Replacing channels requires confirmation.` | `false` | `true` |
| `CHANNEL_REPLACEMENT_EMPTY` | `startApply` | `replacement-survival` | `No replacement channels remained available. Review and try again.` | `true` | `true` |
| `CHANNEL_STORAGE_UNAVAILABLE` | `getStatus`, `startReview`, `startApply` | `storage-unavailable` | `Channel storage is unavailable.` | `true` | `true` |
| `CHANNEL_STORAGE_CORRUPT` | `getStatus`, `startReview`, `startApply` | `storage-corrupt` | `Channel storage could not be loaded.` | `false` | `true` |
| `CHANNEL_UNKNOWN` | `startApply` | `channel-id-allocation` | `Channel setup could not allocate channel identifiers.` | `true` | `true` |
| `CHANNEL_UNKNOWN` | all five | `nonmaterialization-unknown` | `Channel setup could not complete the request.` | `true` | `true` |

The materializer's source `materialization-rejection` uses `CHANNEL_UNKNOWN` copy exactly `Channel setup could not complete the reviewed plan.`, and source `materialization-invalid` uses `CHANNEL_VALIDATION_FAILED` copy exactly `Channel setup could not validate the reviewed plan.`; those distinct materialization sources must not collapse into the non-materialization request rows above. Contract, main-operation, preload/bridge, and renderer copy/projection tests enumerate every row/source/operation expansion and every materialization row, reject every extra or altered tuple/message/flag, and prove renderer copy maps exhaustively from code without embedding materialization detail or rejection text.

There is one active builder operation process-wide. A second `startReview` or `startApply` while any review/apply is non-terminal returns `CHANNEL_BUSY`; it never implicitly cancels or replaces work. Public invoke precedence is authorization → envelope/payload validation → active-operation `CHANNEL_BUSY` for `startReview`/`startApply` → operation/plan lookup → consumed-capacity/single-use classification where applicable → Plex/context/confirmation/revision revalidation → storage/internal classification. Therefore active busy overrides missing, expired, or used plan state. When no operation is active, plan lookup remains consumed → available body (expiring it first if due) → expired/evicted tombstone → not-found; operation lookup remains retained terminal → expired tombstone → not-found. Accepted asynchronous apply work resolves deterministic materialization terminal outcomes first, then replacement survival, then `channel-id-allocation`, then aggregate/barrier/persistence; allocation failure is retained only as the terminal operation error and is never a preaccept invoke error. Other accepted asynchronous work likewise reports later failures only through its terminal operation; a failure before acceptance is an invoke error. A reviewed plan is single-use: accepted `startApply` atomically removes its body from the available-plan store and creates `{ planId, applyOperationId, consumedAtMs, expiresAtMs }`. Another use returns `CHANNEL_PLAN_ALREADY_USED`. Repeating an IPC request ID has no idempotency meaning and cannot repeat a write; the caller retrieves the accepted operation by operation ID.

Main retains the latest four unconsumed reviewed plan bodies for ten minutes, sixteen terminal operations for ten minutes, sixteen consumed-plan records for ten minutes from consumption, and 32 expired/evicted ID-only tombstones for a further ten minutes. When idle, after resolving an available unexpired plan but before consuming it, a full set of sixteen unexpired consumed records makes `startApply` return exactly `{ code: 'CHANNEL_BUSY', message: 'Channel setup is retaining too many recently consumed reviews. Try again.', retryable: true, recoverable: true, operation: 'startApply' }` from source `consumed-plan-capacity` and leaves that plan available with its index still owned by the retained body. It is distinct from `active-operation`, which wins earlier and uses the different frozen message. An already-consumed ID returns `CHANNEL_PLAN_ALREADY_USED` for the full ten minutes even when consumed capacity is full because consumed lookup precedes capacity. Plan lookup precedence is consumed record → `CHANNEL_PLAN_ALREADY_USED`, available body (after first expiring it if due) → consumed-capacity check, expired/evicted tombstone → `CHANNEL_PLAN_EXPIRED`, otherwise `CHANNEL_PLAN_NOT_FOUND`. Operation lookup uses retained terminal operation, then expired tombstone, then not-found. Restart makes all prior IDs `NOT_FOUND`.

### Context invalidation and cancellation lifecycle

Package 1B extends existing `src/main/plex/library/librarySectionCountEnrichment.ts` with exact main-only `loadLibrarySectionRecordsWithCounts(input): Promise<readonly PlexLibrarySection[]>`. It performs the existing single transport fetch, parse, validation, and count-enrichment pass and returns ownership-safe UUID-bearing parsed records; it issues no second catalog request. Existing `loadLibrarySectionsWithCounts(input)` delegates to that record loader and maps the result through the unchanged renderer-safe summary mapper, preserving its public return shape and behavior.

Existing `DesktopPlexLibraryOperationExecutor` adds exact main-only `listSectionsForMain(context): Promise<Readonly<{ sections: readonly PlexLibrarySectionSummary[]; libraryPairs: readonly Readonly<{ libraryId: string; libraryUuid: string }>[] }>>`. It calls `loadLibrarySectionRecordsWithCounts` exactly once, derives `sections` from those records through the existing safe mapper, and derives `libraryPairs` from the same records' exact `id` and `uuid`. Both arrays are ownership-safe; pairs require nonempty values, unique IDs, unique exact pairs, and lexical `libraryId` then `libraryUuid` order, otherwise the whole call rejects through the existing safe internal failure path. Existing `listSections(context)` delegates to `listSectionsForMain(context)` and returns only `.sections`. Package 1B therefore remains independently buildable, preserves renderer-visible behavior, and adds no UUID to a public snapshot, contract, preload API, or IPC payload.

In Package 1C, existing `DesktopPlexRuntime.listLibrarySections` calls `listSectionsForMain` internally. A successful call atomically commits `.sections` to the existing renderer-safe library snapshot and `.libraryPairs` only to `desktopPlexContextNotifications` from that same result/revision; no later join or second fetch is allowed. Profile change, selected-server change, library-load start, or library-load failure synchronously clears the private authoritative pair catalog before publishing the corresponding context event, so no prior server/profile UUID can survive. Public renderer state continues to contain only `.sections`.

Package 1C implements `ChannelBuilderFacetAccessPort` through `channelBuilderContextEpochOwner` and one exact new main-only `DesktopPlexRuntime.withChannelBuilderFacetSession<T>(input, run): Promise<T>`. Input/run are the exact Package 1B types. Before privileged acquisition, the context owner rederives the expected four-field context and exact selected ID→UUID pairs; mismatch throws an internal typed context-changed sentinel. Runtime then obtains the active token and selected server connection internally, closure-captures both, constructs a bound session exposing only the four allowlisted methods above, and awaits `run(session)` without returning token, connection, session, or raw transport. Relevant profile/server/selected-library notification aborts the session controller. In a `finally`, runtime invalidates the session and releases all captured privileged references; any later method call fails safely. After callback resolution and before returning `T`, the context owner revalidates the same bindings/pairs. Missing/expired auth maps to `CHANNEL_PLEX_REQUIRED`, either context check or relevant notification to `CHANNEL_CONTEXT_CHANGED`, caller/deadline abort to canceled/timeout, and all other transport/parser failures to `CHANNEL_UNKNOWN`; raw exception/token/URI/header text is never retained. Public runtime IPC/methods are unchanged, and no generic main endpoint is added.

`src/main/plex/desktopPlexContextNotifications.ts` is the main-only builder-context API owner. Its exact exported data types are:

- `DesktopPlexBuilderLibraryPair = Readonly<{ libraryId: string; libraryUuid: string }>`;
- `DesktopPlexBuilderContextSnapshot = Readonly<{ activeProfileId: string; selectedServerId: string; libraryPairs: readonly DesktopPlexBuilderLibraryPair[] }>`;
- `DesktopPlexBuilderContextError = Readonly<{ code: 'profile-unavailable' | 'server-unavailable' | 'libraries-unavailable' }>`;
- `DesktopPlexBuilderContextResult = Readonly<{ ok: true; snapshot: DesktopPlexBuilderContextSnapshot }> | Readonly<{ ok: false; error: DesktopPlexBuilderContextError }> | null`, where null means the Plex runtime has not completed its initial main-owned restore/load;
- `DesktopPlexBuilderContextEvent = Readonly<{ kind: 'initial' | 'changed'; revision: number; result: DesktopPlexBuilderContextResult }>`;
- `DesktopPlexBuilderContextListener = (event: DesktopPlexBuilderContextEvent) => void`;
- `DesktopPlexBuilderContextUnsubscribe = () => void`.

`DesktopPlexRuntime` exposes exactly `getBuilderContextForMain(): DesktopPlexBuilderContextResult` and `subscribeBuilderContextForMain(listener: DesktopPlexBuilderContextListener): DesktopPlexBuilderContextUnsubscribe`; nothing is added to renderer-safe Plex IPC. Before initial main-owned restore/library-load disposition, the getter returns null. After initialization, missing profile/server uses its exact unavailable error, while a present profile/server with no current authoritative successful same-context pair catalog—including load start, load failure, clear, malformed UUIDs, or a successful sections result that could not validate pairs—returns `{ ok: false, error: { code: 'libraries-unavailable' } }`. Only an atomically committed same-call sections/pairs result returns `ok: true`. The getter returns a deep immutable clone and never throws. Subscription validates a function, synchronously invokes it exactly once before returning with `{ kind: 'initial', revision: currentRevision, result: getBuilderContextForMain() }`, then emits `{ kind: 'changed', revision, result }` only after a committed main Plex/context snapshot changes the result by exact value. `revision` starts at 0 and increases by one for each emitted changed result. Listener failures are isolated. The returned unsubscribe is synchronous and idempotent; after its first call no later event reaches that listener.

A successful snapshot requires nonempty loader-owned active-profile and stable selected-server IDs plus the complete current eligible library catalog projected as unique nonempty `{ libraryId: PlexLibrarySection.id, libraryUuid: PlexLibrarySection.uuid }` pairs, sorted lexically by `libraryId` then `libraryUuid`. Duplicate IDs, duplicate pairs, missing/empty UUIDs, or a catalog that cannot be authoritatively read produce `{ ok: false, error: { code: 'libraries-unavailable' } }`; profile/server absence uses its exact corresponding error. No token, credential, endpoint, URI, profile/server/library name, raw section object, or transport error crosses this main-only API.

`src/main/channel/channelBuilderContextEpochOwner.ts` subscribes in `channelComposition`. For each normalized review config it derives selected pairs by joining every distinct `selectedLibraryIds` entry to exactly one snapshot pair, preserving normalized selected-ID order for the stored plan context and sorting a separate copy only for `LibrarySetBindingV1`; a missing/ambiguous pair is `CHANNEL_CONTEXT_CHANGED`, and main never substitutes a renderer ID for UUID. It constructs only the exact Identity V1 bindings and stores the exact selected `{ libraryId, libraryUuid }` pairs beside each retained plan in the main-only owner.

The owner has one process-local `contextEpoch`, initialized to 0 and increased monotonically by one for every accepted `changed` event; overflow is a fatal/replan condition rather than wraparound. Epoch orders observation but equality alone never invalidates a retained plan. A profile or server value/result transition expires every retained plan and aborts every pre-commit builder operation. A library-catalog change evaluates each retained plan independently: it expires that plan, disposes its index, and aborts its pre-commit apply/review only if any stored selected library ID is now absent, ambiguous, or maps to a byte-different UUID. Additions and changes to unselected library IDs are irrelevant to that plan and do not expire it. Multiple retained plans with different selected sets therefore invalidate independently under the same event. `startApply` re-reads the API and requires the plan's exact profile/server bindings and stored selected pairs to rederive byte-equal; it accepts an older captured epoch when those values remain equal and rejects stale values with `CHANNEL_CONTEXT_CHANGED`. No alternate delimiter-concatenated binding scheme is allowed.

`startReview` validates and normalizes configuration, captures the current epoch, exact profile/server bindings, selected library pairs, and lineup revision, and performs abort/context-aware asynchronous discovery. Immediately before planning it checks the operation abort signal and rederives that review's selected context; a canceled operation or a profile/server/selected-pair change does not submit a planning job, while an unrelated library addition/change does not invalidate it. Package 1C then delegates the exact Package 1A pure input to the main-owned planning worker boundary frozen below. After a successful worker result, the operation owner repeats the abort and selected-context check before retaining or publishing any plan body or materialization index. Only a still-current, non-aborted result reaches `review-ready`. Discovery and apply materialization remain cancellable at their existing async boundaries.

#### Package 1A Proof Route R0 — non-product CI/test routing

The immutable Package 1A commits are `ca21ba1a5d641093e55b7c64b0910e317016ae37` (original) and `aa224e5bed28341600d9fa33bd2fe7ac305aa2e4` (the one authorized pure optimization). PR #19 uses existing branch `dev/ws1-channel-builder-1a`; it remains open and unmerged. Runs `30054263643` and `30055718852` measured the unchanged 50,000-candidate invocation at `8830.27 ms` and `8497.53 ms` respectively only inside the broad, contended Windows `Verify` command. In both runs the later `Channel Builder performance` step skipped because GitHub Actions applies implicit `success()` to the current `if: runner.os == 'Windows'` expression. Neither broad measurement is authoritative isolated proof.

Before R0, the deadlock was exact: `package.json` `test:contracts` globs `src/__tests__/**/*.test.ts`, so Windows `Verify` loaded `src/__tests__/domain/channelBuilderPlannerPerformance.test.ts` and enforced the 2,000 ms cap before the dedicated step. R0 was the then-authorized non-product CI/test routing unit; it did not authorize product optimization, Package 1B, PR merge, or release-state change. A1 and `WS1-PERF-01` now supersede that historical sequencing restriction.

R0 changes only `.github/workflows/ci.yml` and `src/__tests__/domain/channelBuilderPlannerPerformance.test.ts`; `package.json` and every product owner/test are unchanged. The performance test registers the unchanged benchmark/enforcement only when `process.env.npm_lifecycle_event` is byte-equal to `verify:channel-builder-performance`. Under the broad `test:contracts` lifecycle it must report skipped, run no warm/measured planner invocation, enforce no performance cap, and make no performance-proof claim. The exact existing npm script remains the only enabling lifecycle.

The dedicated Windows step retains its name, Node `22.19.0` setup, isolated command `npm run verify:channel-builder-performance`, exact fixture, 50,000 candidates, and 2,000 ms cap. Its guard becomes exactly `${{ !cancelled() && runner.os == 'Windows' }}` so it runs after earlier success or failure but not after cancellation. R0 sought same-SHA dual-pass evidence, but A1 now owns exact-head checkout and sequencing: ordinary Windows Verify must pass, the isolated command must execute exactly, and an above-cap exact-head result activates `WS1-PERF-01` rather than blocking Package 1B. A skipped, contended, misrouted, wrong-SHA, wrong-Node, or wrong-command result remains missing proof.

After local proof and the one required must-fix-only implementation review, commit R0 with subject `ci(channels): isolate builder performance gate` and publish that commit only to the existing `dev/ws1-channel-builder-1a` PR #19 branch. This push is explicitly authorized; merge, force-push, rebasing, amending either immutable commit, opening another PR, or changing any other branch/release state is not. A rollback is a new explicit revert/correction commit on that same branch; it never rewrites either immutable commit, and it restores missing exact-head observation until a reviewed route supplies it.

#### Package 1A Performance Architecture A1 — main-owned native identity hashing

External authority now authorizes one serial pre-1B architecture unit, A1, while preserving the performance test contract. Run `30057283496` remains diagnostic failure evidence: its isolated Windows Node `22.19.0` invocation measured `3320.85 ms`, and checkout used pull-request merge SHA `ce5f56532e7b12922382d4af43c5ea84e64aa9e4` rather than head SHA `d6a42a6e363ce32769f5b949ee5768b0cb438023`. The authoritative observation remains the unchanged deterministic 50,000-candidate fixture, one warm invocation followed by one measured invocation, and `<= 2,000 ms` target on isolated Windows Node `22.19.0`. Ordinary Windows Verify must pass on the asserted exact A1 head SHA. The isolated command must execute on that same head and its result must be recorded honestly, but a measured result above 2,000 ms becomes the explicit deferred performance debt below and does not block Package 1B or later WS1 implementation.

**Deferred performance TODO `WS1-PERF-01`:** if the exact-head isolated A1 run remains above 2,000 ms, record the run ID, exact head SHA, Windows runner, Node `22.19.0`, command, isolation status, and measured milliseconds in every subsequent WS1 handoff until resolved. Preserve the failing result and keep the fixture/cap/script/CI command unchanged. Revisit through a separately authorized performance architecture pass after the functional WS1 packages are underway or sooner if performance regresses further. The debt blocks only a claim that the 2,000 ms target passed; it does not block Package 1A functional acceptance, Package 1B–1F implementation, or honest WS1 progress. Skipped, contended, wrong-command, wrong-Node, merge-SHA, or otherwise non-exact-head execution is not a debt result: it is missing proof and must be corrected before Package 1B.

`src/domain/channelBuilder/planIdentity.ts` owns one synchronous `ChannelBuilderIdentityOperations` capability and its factory. The capability contains the existing canonicalizer and every Identity V1 operation used anywhere in the builder: `canonicalJsonV1`, `sha256HexV1`, `createPersistedStringV1`, profile/server/library-set/facet/source/mixed-source/tag-group/content-filter identity creation, candidate identity/preimage tuple lookup, candidate ID, plan identity, and deterministic shuffle seed. Its only replaceable primitive is a synchronous incremental SHA-256 factory with exact `updateUtf8(string)` and single-use lowercase-64-hex `digestHex()` behavior. The existing dependency-free `Sha256V1` remains the pure default. Every existing public identity function and `buildChannelSetupPlan(input)` keeps its current signature and delegates to the pure-default capability, so all current domain and future Package 1B call sites remain pure and source-compatible.

`planner.ts` additionally exports one factory-created planner bound to an explicit `ChannelBuilderIdentityOperations`. It passes that one capability through the entire call graph: `strategyBuilders.ts` uses it for canonical seed tuples, mixed-source identity, content-filter identity, and shuffle seed; `planner.ts` uses it for persisted-string projection, candidate identity/tuple matching, candidate ID, plan identity, and candidate content-filter-plan validation. `facets.ts` owns exact `isValidChannelBuilderCandidateContentFilterPlanWithIdentityOperations(identityOperations, plan, snapshot)` for that bound validation path. Existing public `isValidChannelBuilderCandidateContentFilterPlan(plan, snapshot)` retains its exact signature and delegates to the pure-default capability; no other facets behavior or API changes. The factory-created planner calls only the bound variant, so inline-decade construction and its later validation use the same injected capability. No identity call in these owners may bypass it. The five-field `ChannelBuilderPlannerInput`, `ChannelBuilderPlannerOutput`, ordering, validation result, collision byte-tuple guards, domain separators, prefixes, `canonicalJsonV1` bytes, and golden outputs remain byte-for-byte unchanged.

`src/main/channel/channelBuilderProductionPlanner.ts` is the sole Node backend and production planning entrypoint. It imports only `createHash` from `node:crypto`, implements the domain hash factory synchronously with `createHash('sha256')`, `update(value, 'utf8')` for each exact emitted chunk, and `digest('hex')`, exports the one readonly native capability as `channelBuilderProductionIdentityOperations`, and uses that same instance for exported `buildProductionChannelSetupPlan(input)`. It owns no Electron object, IPC, transport, persistence, time/randomness, cache, mutable global plan state, async work, or fallback selection. The relocated `src/__tests__/main/channelBuilderPlannerPerformance.test.ts` must call this exact production entrypoint for both warm and measured invocations. Later Package 1C's fixed Worker entry must import and call this same function; a benchmark-only or second Worker planner path is forbidden. `src/domain/**` gains no Node import, runtime global, conditional runtime detection, or native fallback.

Pure/native conformance is exhaustive rather than sampled. Existing `src/__tests__/domain/channelBuilderIdentity.test.ts` remains pure-only and imports no main owner. `src/__tests__/main/channelBuilderProductionPlanner.test.ts` imports `channelBuilderProductionIdentityOperations` from the production planner owner and compares it with the pure-default capability across every existing identity golden and hostile class, producing the same value or the same fixed value-free failure. The matrix explicitly includes empty/ASCII/astral/unpaired-surrogate hashing; NFC keys/values and collisions; numeric-like key order; finite-number extremes and negative infinity; undefined, symbol, bigint, and function rejection; sparse, cyclic, and non-plain rejection; persisted-string empty/control/astral/unpaired-surrogate boundaries; every existing invalid binding, facet, source, mixed-source, tag-group, content-filter, candidate, candidate-ID, plan, and shuffle class; raw transient inputs; library-filter magic keys; complete plan identity literals; and same-digest/unequal-byte candidate collision tuples. Planner parity explicitly includes an inline-decade fixture, a counting/bound-operations assertion proving both decade identity construction and `isValidChannelBuilderCandidateContentFilterPlanWithIdentityOperations` validation use the injected capability, and the existing same-digest/unequal-byte collision non-match path, in addition to ready/slow/blocked, append/merge/replace, alternate-replica, display-hostile, and deterministic repeat fixtures. No new shared test helper file or existing domain-test edit is authorized. The performance test additionally pins the unchanged golden plan identity before timing, but no pure/default work runs inside its measured interval.

This unit changes no dependency, lockfile, npm lifecycle command name, fixture cardinality, cap, Node version, planner DTO, public IPC, or package/release state. `package.json` changes only the existing `verify:channel-builder-performance` target path from the deleted/moved domain test to `src/__tests__/main/channelBuilderPlannerPerformance.test.ts`; `package-lock.json` remains byte-for-byte unchanged. `planIdentity.ts` (currently over 800 lines) requires the implementation architecture review; `strategyBuilders.ts` and `planner.ts` (both over 500 lines) keep their existing cohesive strategy/planner responsibilities and only receive/pass the narrow capability. The new main owner isolates the distinct Node trust/runtime boundary and must remain below 220 lines. If capability threading requires a generic service, option bag, Node import in domain, second canonicalizer, identity API overload, or another production entrypoint, stop and replan.

For exact-head proof, `.github/workflows/ci.yml` sets checkout `ref` to exact `${{ github.event.pull_request.head.sha || github.sha }}` while retaining `persist-credentials: false`, then runs a cross-platform `bash` assertion that `git rev-parse HEAD` is byte-equal to that same expected SHA before setup/install/verification. The ordinary Windows Verify and isolated performance step therefore execute in one job/worktree at the asserted head. The dedicated condition remains exactly `${{ !cancelled() && runner.os == 'Windows' }}`.

#### Package 1C planning process boundary

This decision belongs to later serial Package 1C, not Package 1A, and is not implementable until Package 1A closes and Package 1B completes. Package 1C uses Node `worker_threads`, not Electron `utilityProcess`, because the planner is trusted, pure, CPU-bound code and a Worker has lower startup/transfer overhead, is Node-testable without `app.ready`, and fits the existing one-active-operation invariant. `utilityProcess` offers stronger fault isolation, but that benefit does not justify its extra process/packaging overhead for this trusted kernel. The Worker protects Electron-main responsiveness and makes pre-commit cancellation observable; it does not make the pure planner faster and does not replace or weaken the unchanged Package 1A isolated kernel performance gate.

`src/main/channel/channelBuilderPlanningWorker.ts` owns one lazy, long-lived Worker with pool size one and at most one in-flight planning job. It owns monotonically increasing positive safe-integer job IDs; exhaustion is a fixed failure/replan condition, never wraparound. The closed structured-clone protocol is main-to-worker `{ kind: 'plan', jobId, input: ChannelBuilderPlannerInput }` and worker-to-main `{ kind: 'planned', jobId, output: ChannelBuilderPlannerOutput } | { kind: 'failed', jobId }`. Both sides reject unknown keys, variants, invalid IDs, and malformed values. No raw diagnostics, exception text, Plex credential/connection/session material, Electron object, path, function, handle, or arbitrary payload crosses this seam. The entry imports and invokes only A1's `buildProductionChannelSetupPlan`; there is no `eval`, code string, caller-selected module, caller-selected path, or second planner binding.

The Worker is created only from the fixed compiled URL `new URL('./channelBuilderPlanningWorkerEntry.js', import.meta.url)`. `tsconfig.electron.json` already emits `src/main/**/*.ts` into `dist/main/**`, and the internal package owner already copies the complete `dist` tree, so Package 1C changes neither build configuration nor packaging logic. It must prove the entry is emitted and the packaged `resources/app/dist/main/channel/channelBuilderPlanningWorkerEntry.js` exists, and that the same fixed URL resolves under development and packaged layouts.

An abort atomically detaches the current `{ worker, jobId }`, terminates that Worker, maps the owning review operation to its exact existing canceled outcome, and discards every late message from the detached worker/job. The next planning call lazily creates a fresh Worker. A protocol error, worker error, or unexpected exit clears the owner, maps only to the existing fixed safe `CHANNEL_UNKNOWN` planning failure without raw detail, and permits a later call to create a fresh Worker. A concurrent direct planning request is rejected as busy; the operation owner still enforces the stricter process-wide single-active-operation rule. Shutdown is synchronous-to-request, idempotent, clears the owner, rejects any pending job with the fixed safe failure, and terminates the Worker. `channelComposition` constructs/injects this owner, and its existing teardown path shuts it down exactly once; the operation owner owns job submission/abort mapping but not Worker creation policy. No public DTO, IPC channel, preload API, renderer state, planner input/output shape, Identity V1 byte, or persisted schema changes.

`startApply` accepts only an unconsumed reviewed plan, requires explicit replace confirmation, and revalidates profile/server bindings, the plan's exact stored selected library pairs, and lineup revision before materialization; a greater global context epoch caused only by unselected-library changes is not itself stale.

The operation owner has one abort controller for the active operation. Before the persistence barrier, the first accepted cancellation returns exactly `{ accepted: true, reason: null, operation }`, performs the sole abort/disposal initiation, transitions once to observable `canceling`, then once to terminal `canceled`, changes no persisted data, and does not refresh the guide. While the operation is observably `canceling`, every repeated `cancel` returns exactly `{ accepted: true, reason: null, operation }` and performs no second abort, dispose, or state transition. The same exact accepted/null response applies to every repeated cancel of terminal `canceled`. For every other terminal operation it returns exactly `{ accepted: false, reason: 'already-terminal', operation }`. After the barrier callback has returned `proceed`, including all `persist` and `refresh-guide` phases, it returns `{ accepted: false, reason: 'commit-started', operation }`.

The persistence barrier is decided by the exact `mutateChannelAggregate` handshake described below. From operation start through that handshake, preparation is strictly read/stat/compute/serialize/guard only. It may perform the required destination `lstat` and, for an existing destination, the policy-specific read-only destination open, handle-stat, read, and close; it contains no temporary-file open, exclusive/create/write-capable open, handle write, chmod, sync, `mkdir`, rename, unlink, repair write, or other filesystem mutation. The operation owner supplies a synchronous callback that returns `cancel` when its abort signal is already aborted; otherwise it sets its irreversible-barrier flag and returns `proceed`. If cancel wins that pre-barrier race, the store performs no write or mutation and the operation ends canceled. From a `proceed` return through rename and guide refresh, cancellation returns `{ accepted: false, reason: 'commit-started', operation }` and is a no-op. The apply never reports canceled after `proceed`.

After successful rename, `channelComposition` invokes the existing `guideRuntime.refreshActiveChannelSelection()` through a generic lineup-changed callback. Refresh is non-abortable and completes before the apply operation becomes terminal. A refresh failure leaves persistence committed, preserves the last complete scheduler state, finalizes `guideRefresh: 'failed'`, and includes the exact deduplicated `GUIDE_REFRESH_FAILED` record in the one immutable summary constructed after refresh settles. Success finalizes `guideRefresh: 'completed'` without that warning. `guideRuntime` and the scheduler remain unchanged and receive no builder configuration, strategy, facet, context, or diff.

### Atomic persistence and rollback

#### Pre-operation channel persistence bootstrap

Package 1C adds `src/main/persistence/channelPersistenceBootstrapOwner.ts` as the sole channel-destination directory initializer. Its exact injected filesystem port is `{ realpath, lstat, mkdir }`; the channel store's operation filesystem port has no `mkdir`. After validated smoke-capability parsing and successful acquisition of the process-wide single-instance lock, production/development calls this owner before channel persistence read/load, channel composition, IPC registration, `app.whenReady`, BrowserWindow construction, or creation/exposure of any builder, Custom Channels, or current-channel operation.

The owner resolves `resolveDesktopAppDataPaths(app).channelPersistenceFilePath`, requires its parent to be the exact `persistence` child of canonical `userData`, and invokes the sole channel-parent initialization call `mkdir(parent, { recursive: true })`. It then `lstat`s the resulting parent, requires a real directory rather than a symlink or other node, resolves its canonical path, and requires exact equality with `path.join(canonicalUserData, 'persistence')` plus separator-boundary containment under canonical userData. Wrong parent, symlink, non-directory, canonical mismatch, mkdir/lstat/realpath failure, or unavailable channel path returns exactly `{ status: 'failed', error: { code: 'CHANNEL_STORAGE_UNAVAILABLE', message: 'Channel storage is unavailable.' } }`; main records only that fixed redacted code/message, exits startup nonzero, and performs no persistence read, repair, composition, IPC registration, `app.whenReady`, or window creation. This private startup error has no public operation field, path, or raw filesystem detail.

Success returns `ChannelPersistenceReadyCapability`, an in-process opaque object carrying both the canonical parent and injected `ChannelPersistenceFileProtectionPolicy = 'posix-0600' | 'windows-inherited-userdata-acl'` behind a module-private `unique symbol`; only this owner can construct it. Production selects that policy from one injected platform value (`win32` selects the Windows policy; every supported POSIX platform selects the POSIX policy), never by probing chmod behavior. `DesktopChannelPersistenceStore` requires the capability, proves the configured destination's canonical parent equals its bound parent, and has no constructor overload or fallback without it. `channelComposition` receives either the capability-backed disk store or the already-frozen smoke-only in-memory port, never a raw unvalidated path choice. Valid smoke bypasses the disk bootstrap owner entirely after smoke-capability validation and lock acquisition: it does not resolve, canonicalize, `lstat`, or create a channel persistence parent and never constructs `DesktopChannelPersistenceStore`.

Package 1C splits Plex construction from IPC reachability in existing `src/main/plex/plexComposition.ts`. `createPlexComposition(options)` constructs and returns the persistence/auth/discovery/runtime composition without registering any IPC. `registerPlexCompositionIpc(composition, ipcOptions)` registers the existing Plex handlers exactly once and returns the registration/teardown owner. Duplicate registration is rejected. Composition teardown shuts down the runtime and removes any registered handlers exactly once whether startup later succeeds or fails; registration teardown is likewise idempotent and cannot double-shutdown the runtime. Focused `src/__tests__/main/plexComposition.test.ts` proves no handler registration during construction, exactly-once registration, duplicate rejection, and exactly-once handler removal/runtime shutdown.

Package 1C also adds `src/main/persistence/channelPersistenceStartupOwner.ts` as the sole startup repair-write owner. `ChannelPersistenceStartupOwner.loadAndRepair()` runs on the `DesktopChannelPersistenceStore` mutation chain, reads the complete outer file exactly once, normalizes the full aggregate—including lineup, both current-channel pointers, builder state/revision, and provenance markers—and, only when a present supported file changed during normalization, performs exactly one atomic full-file temp-and-rename repair under the bound ready capability and file-protection policy. This startup lifecycle has no user-cancel barrier or `onCommitBarrier`; it completes or fails before any operation is reachable. A missing file returns the normalized empty aggregate without writing. Corrupt JSON/schema shape or an unsupported schema version returns exactly `{ code: 'CHANNEL_STORAGE_CORRUPT', message: 'Channel storage could not be loaded.' }`; read or repair-write failure returns exactly `{ code: 'CHANNEL_STORAGE_UNAVAILABLE', message: 'Channel storage is unavailable.' }`. Both are private startup failures with no raw detail or operation field and prevent every composition/IPC/window step that follows. The startup owner may reuse pure repository/coordinator normalization, but it is the only owner allowed to persist that normalization.

Existing `ChannelPersistenceCoordinator.load()` is changed to read and return normalized data without saving `didMutate`; `loadNormalized()` remains pure/read-only from the caller's perspective. Existing `ChannelPersistenceStore` and `DesktopChannelPersistenceStore` reads likewise stop clearing, pointer-fixing, corrupt-file replacement, or any other read-triggered mutation. Ordinary builder, Custom Channels, guide, and current-channel reads never repair or migrate. There is no second repair writer: all startup repair flows through `ChannelPersistenceStartupOwner.loadAndRepair()`, while all operation-time invalid/corrupt/unsupported observations fail before the barrier with no write and wait for a reviewed next-start diagnosis rather than silently replacing bytes.

The exact main-process startup order is smoke-capability validation → successful single-instance lock → disk bootstrap for production/development or explicit in-memory bypass for valid smoke → `createPlexComposition` with no IPC → `ChannelPersistenceStartupOwner.loadAndRepair()` for disk or normalized in-memory load for smoke → channel composition using that loaded aggregate and Plex runtime → `registerPlexCompositionIpc` → channel IPC registration → remaining settings/diagnostics/player/shell IPC and playback composition → `app.whenReady`/BrowserWindow. No IPC handler, feature listener, protocol handler beyond the required pre-ready scheme declaration, or window is registered/created before startup repair succeeds. Directory bootstrap may create an absent parent before operations exist; startup repair completes before operations are registered. Neither bootstrap nor repair is inside an operation's cancellation window. Any failure tears down the unregistered Plex composition exactly once and exits nonzero.

`DesktopChannelPersistenceStore` remains the sole persisted lineup owner. Builder state is stored with the lineup, not in the general settings store, because review lineage and application must share one atomic boundary.

The existing outer file `schemaVersion: 1` remains unchanged and uses the exact optional-file/normalized-aggregate contracts above. The restored config may contain renderer-safe server/library IDs already present in the public setup contract, but never names, credentials, tokens, URIs, paths, raw payloads, or media metadata.

`ChannelPersistenceStoragePort` and `ChannelPersistenceStore` gain one aggregate operation owned concretely by `DesktopChannelPersistenceStore`:

- `readChannelAggregate()` returns the normalized aggregate;
- `mutateChannelAggregate(request: ChannelAggregateMutationRequest)` runs on the store's existing mutation chain, loads the latest aggregate once, performs the request-specific compare-and-swap rule, applies the synchronous mutation, validates the complete replacement, serializes the complete file, and uses the exclusive same-directory handle policy below; it has no directory-creation branch;
- result is `{ status: 'committed', aggregate }`, `{ status: 'conflict', actualLineupRevision }`, or `{ status: 'canceled' }`.

`DesktopChannelPersistenceFileSystem` becomes exactly `{ lstat, open, rename, unlink }`; `mkdir` exists only on the separate bootstrap port above. `open(path, flags, mode?)` returns `DesktopChannelPersistenceFileHandle`, exactly `{ readFile, writeFile, chmod, sync, stat, close }`. `chmod` remains present only so the POSIX policy can use it; the Windows policy must never invoke it or reject a numeric mode. Tests inject this port, the required ready capability/policy, and `randomHex128(): string`. The production generator uses `crypto.randomBytes(16).toString('hex')`, and every generated value must match `/^[a-f0-9]{32}$/u`.

The temp-file threat model is bounded to the app-owned Electron `userData` persistence directory under the process-wide single-instance owner. It prevents accidental/stale/cooperating-process name collisions and refuses pre-existing symlinks or non-regular nodes; it does not claim protection against a malicious same-user process that can concurrently replace directory entries inside that app-owned directory. Node path-based `lstat`/`rename`/`unlink` leave a residual time-of-check/time-of-use window. The checks below are required defense in depth within that stated model, not a hostile-directory or hostile-same-user guarantee.

Before reading or mutating, the capability-backed adapter `lstat`s the destination. Missing is allowed; a symbolic link or any non-regular existing node is rejected with `CHANNEL_STORAGE_UNAVAILABLE`. For `posix-0600`, a present destination is opened with exactly `O_RDONLY | O_NOFOLLOW`; before any read, handle `stat` must report a regular file with exact `(dev, ino)` equality to the prior `lstat`. For `windows-inherited-userdata-acl`, Node 22.19 has no `O_NOFOLLOW`: after the same prior regular/non-symlink `lstat`, the adapter opens with exactly `O_RDONLY`, then before any read requires handle `stat` to report a regular file with exact `(dev, ino)` equality to that prior `lstat`. Only then may either policy read through the owned handle and close it. Immediately before rename, both policies require the destination still be the same regular node, or still absent when originally absent. A changed, symlinked, non-regular, or pre-read identity-mismatched destination aborts. If the bound parent disappears after bootstrap, reads may observe a missing destination but the first post-proceed exclusive temporary-file open fails `CHANNEL_STORAGE_UNAVAILABLE`; the store never recreates the parent, and recreation waits for the next process bootstrap/startup.

After serialization, the adapter makes at most eight attempts in the destination directory using `${destinationPath}.${suffix}.tmp`, one new crypto-random 128-bit lowercase-hex suffix per attempt. Under `posix-0600`, it invokes exactly `open(temporaryPath, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, 0o600)`. Under `windows-inherited-userdata-acl`, it invokes exactly `open(temporaryPath, O_CREAT | O_EXCL | O_WRONLY)` with no `O_NOFOLLOW` and no numeric mode. On Windows, `O_EXCL` is the bounded guarantee that a pre-existing temporary node or symlink is not opened/followed. `EEXIST` retries without opening, truncating, following, or deleting that target; any other failure stops; eight collisions produce `CHANNEL_STORAGE_UNAVAILABLE`. A successfully opened handle is the only event that records conditional cleanup ownership of that exact path and the handle's `(dev, ino)` identity. Both policies immediately `stat` the handle, require a regular file, retain its identity, write the complete serialized bytes, call `sync()`, verify the same regular-file `(dev, ino)` identity through the handle, and close; after close they `lstat` the temporary path and require the same regular non-symlink identity before the destination guard and rename.

`posix-0600` additionally calls `chmod(0o600)` before `sync`, requires `(mode & 0o777) === 0o600` in both the post-write handle `stat` and post-close `lstat`, and fails closed on either mismatch. `windows-inherited-userdata-acl` never calls `chmod`, never passes or compares a POSIX numeric mode, and relies on the inherited ACL of the canonical per-user Electron `userData/persistence` parent established by the bootstrap capability. This Windows boundary is valid only inside the existing single-instance, non-hostile-same-user threat model: it does not claim to defend against a hostile same-user process or an administrator that can rewrite the directory ACL. Both policies retain the same parent/capability binding, destination identity/type guard, collision, cleanup, sync/close, and rename requirements. Within that stated threat model, collisions and pre-existing symlink/non-regular targets are neither followed nor intentionally removed.

Node-level Windows `lstat`/open/handle-stat checks do not claim native reparse-point resistance against hostile concurrent substitution. If that resistance becomes a requirement, stop and replan to a reviewed native Win32 filesystem owner with explicit reparse-point/open-handle semantics rather than adding an unproved JavaScript flag or weakening this bounded contract.

`onCommitBarrier` retains its exact synchronous rule. The store calls it once after all awaited read/CAS/mutation/validation/serialization/stat/guard preparation, including any existing-destination policy-specific read-only open/handle-stat/read/close. If it returns `cancel`, the operation performs zero temporary-file opens, zero exclusive/create/write-capable opens, zero handle writes/chmods/syncs, and zero rename/unlink/`mkdir`/repair/other filesystem mutations; destination bytes, aggregate, revision, and guide remain unchanged. After `proceed`, the policy-specific first temporary `open(...O_CREAT | O_EXCL...)` promise is invoked in the same synchronous continuation—no await, promise continuation, queue handoff, microtask, timer, event, user callback, or `mkdir` intervenes. Collision retries and all handle writes occur after the irreversible flag, so cancel returns `commit-started`. Successful guarded rename is the sole persistence commit; there is no destination chmod or other fallible persistence step after rename.

Exclusive-open, handle write, policy-required POSIX chmod/mode verification, sync/stat/close, post-close temp-identity/policy check, destination guard, or rename failure before successful rename is terminal `CHANNEL_STORAGE_UNAVAILABLE`, never canceled, constructs no summary, does not refresh the guide, and leaves the original destination byte-identical. Best-effort cleanup first `lstat`s the temporary path and invokes `unlink` only when it is still a regular non-symlink node with the recorded `(dev, ino)`; missing is already clean. Identity/type mismatch leaves the path untouched and emits only the fixed redacted operational diagnostic code `CHANNEL_TEMP_CLEANUP_MISMATCH`, with no path, suffix, inode, or raw error. Cleanup lookup/unlink failure is likewise redacted and never replaces the primary error. This conditional check does not eliminate the acknowledged same-user TOCTOU window. After rename the operation proceeds to non-abortable refresh and immutable finalization.

Focused tests prove injected-suffix determinism; required ready-capability/policy construction and rejection of absent/forged/wrong-parent/wrong-policy capability; complete absence of `mkdir` from store/composition/operation source; exact POSIX destination/temp flags including `O_NOFOLLOW`; exact Windows destination/temp flags omitting `O_NOFOLLOW`; Windows destination handle identity/type verification before read; `posix-0600` exact creation/chmod/handle-mode/path-mode enforcement; `windows-inherited-userdata-acl` omits the numeric mode, never calls chmod, and never rejects a mode value while still enforcing every shared parent, prior/path/handle identity, symlink/type, collision, cleanup, sync/close, destination-guard, and rename rule; collision retry and exhaustion at exactly eight attempts; a precreated regular target is never truncated/deleted; a temp symlink to a victim is never followed/deleted and the victim is byte-identical; temp/destination directory/device/non-regular nodes are rejected; sync/close ordering; cleanup only after matching `lstat`; identity/type mismatch leaves the path untouched and emits the fixed redacted warning; destination identity recheck; and byte-identical destination on every pre-rename failure. For an existing destination, a cancel-before-barrier fixture must observe the exact policy-specific read-only destination open and its handle-stat/read/close completing before the callback, followed by zero temporary-file opens, zero exclusive/create/write-capable opens, zero handle writes/chmods/syncs, and zero rename/unlink/`mkdir`/repair/other filesystem mutations. A missing destination may have no read handle. Tests also prove the policy-specific first temporary exclusive create open is invoked only in the proceed continuation; deleted-after-bootstrap parent fails that first temporary exclusive open and is not recreated; cancel while temporary exclusive open/write/policy-check/sync/close/rename is pending returns commit-started; the callback runs once; successful rename has no destination chmod; and guide-refresh result construction remains one-time and immutable. A bootstrap fixture with an initially absent parent proves bootstrap may create it before operation availability, then a started-and-canceled operation performs no temporary-file/exclusive/create/write-capable open and no filesystem mutation while leaving aggregate/revision/destination/guide unchanged; it does not forbid the destination `lstat` or claim a read handle for the missing file. No test or acceptance claim asserts resistance to malicious same-user path replacement or Windows reparse-point substitution beyond this bounded contract.

`kind` is `builder-lineup`, `custom-lineup`, or `current-channel`. Builder and Custom Channels run only through the shared `ChannelLineupMutationCoordinator`. The builder supplies its reviewed revision; Custom Channels mutates the latest aggregate under the same queue. Both lineup kinds preserve unrelated aggregate metadata and increment `lineupRevision` by exactly one. `current-channel` validates against the latest stored lineup, changes only the outer and nested current-channel pointers, and does not increment revision or replace builder metadata.

This latest-aggregate callback is the interleaving rule: a tune queued before builder persistence is observed at commit and retained if that channel survives; otherwise builder mode selection chooses the first committed channel. A tune queued after the barrier runs after rename. No builder or Custom Channels path calls `saveStoredChannelData` followed by `saveCurrentChannelId`; `ChannelRepository.saveCurrentChannelId` delegates to the aggregate `current-channel` mutation so `guideRuntime` need not change. `CustomChannelRuntime.stateFromLoaded` must stop reconstructing a metadata-dropping snapshot, remove its private full-write queue, and preserve builder state/revision through the shared coordinator.

A legacy v1 file missing the new fields loads with revision `0` and unknown builder completion/configuration; existing channels are preserved and completion is never inferred. The directory bootstrap has already completed before this persistence read. A present but invalid `channelBuilderState` is dropped eagerly only by `ChannelPersistenceStartupOwner.loadAndRepair()` through the capability-backed store, preserving `storedChannelData`, both current-channel pointers, and a valid revision. A missing revision normalizes to `0`; an invalid present revision drops builder state and normalizes to `0` during the same single startup repair write. Bootstrap directory creation and startup repair both finish before channel operations exist and are outside the operation cancellation window. Because reviewed plans are process-local, no stale plan survives that startup repair. Corrupt or unsupported outer files are not rewritten to empty: startup fails redacted and leaves their bytes untouched for diagnosis/recovery.

Rollback uses the new fixture `src/__tests__/fixtures/channel-persistence-v1-legacy.json` and a test-local frozen legacy-reader procedure matching the pre-WS1 `{ schemaVersion, storedChannelData, currentChannelId }` reader. The test loads the legacy fixture with the new store, writes new builder metadata, reads and rewrites it through that legacy procedure while ignoring the additive fields, then reloads with the new store. It must prove channel/order/current preservation, builder state becoming unknown, revision returning to `0`, and no channel loss. An older binary may therefore discard builder metadata on a later write, but it cannot make the file unreadable or delete the lineup.

### Cross-workstream contribution and closure gates

Stable IDs remain registered exactly once. A contributor workstream supplies a required downstream consumer or proof surface but does not acquire duplicate registry ownership.

| Registry owner and IDs | Owner implementation gate | Required contributor gate | Final closure and authority update |
| --- | --- | --- | --- |
| WS2 — `PB-22`, `PB-23`, `PB-24` | Playback/profile/helper policy and focused tests for subtitle selection, audio fallback/passthrough, and HDR/fallback behavior | WS3 supplies the corresponding subtitle-language, audio/DTS, and HDR preference contracts, persistence, controls, and integration; any required native/Windows proof follows in its later owning gate | Keep all three rows open after WS2. Close each only after the WS3 contribution and any row-required native/Windows proof pass; the final contributing workstream updates the matrix while citing WS2 as unique owner. |
| WS3 — `ST-11`–`ST-16` | Settings contracts, normalization, persistence, restore/default behavior, and renderer controls | WS5 wires and proves the corresponding Guide/EPG consumers under `EPG-08`–`EPG-13` as applicable | Keep `ST-11`–`ST-16` open after WS3. WS5 is a contributor, not duplicate owner, and updates the matrix only when both the WS3 setting gate and its real Guide/EPG consumption proof pass. |
| WS8 — `WIN-04`; WS9 — `PB-27` | WS8 owns one shared main-owned power request plus sleep/resume lifecycle, cleanup/diagnostics, and local/non-packaged tests | WS9 consumes that reviewed gate; RD-27 owns packaged Windows sleep/wake recovery and soak observation for both rows | Keep both `WIN-04` and `PB-27` open after WS8. Close them only after WS9/RD-27 packaged Windows proof passes; WS8 and WS9 retain their unique registry IDs and the final authority update cites the contribution rather than registering either twice. |

`PB-07` and `WIN-07` likewise remain uniquely assigned to WS2. WS2 owns their playback/helper implementation and non-packaged integration gate. Passing that gate permits dependent WS3/WS4 implementation to proceed, but it does not mark either audit row complete. WS9 is the required proof contributor for packaged helper/libmpv redistribution and packaged replacement-helper recovery, carried specifically by its RD-28 package-lifecycle subphase after RD-27. The matrix keeps both rows open or partial until that evidence exists; WS9 cites them as contributor IDs without registering or counting them a second time. Program closeout requires both the WS2 implementation gate and the reviewed WS9/RD-28 packaged proof.

### Hotspot disposition

| Owner | Current responsibility | WS1 disposition and required evidence |
| --- | --- | --- |
| `src/preload/index.cts` (~1854 lines) | preload composition root | Wiring only; behavior stays in the guard/bridge modules. Fresh architecture review required before editing. |
| `src/domain/channel/channelManager.ts` (~1022 lines) | pure existing channel manager | Untouched and replan-only. It does not become a builder or persistence-policy owner. |
| `src/domain/channel/channelRepository.ts` (~769 lines) | normalized persisted-channel loading/saving boundary | Package 1C is surgical delegation only: aggregate/coordinator behavior remains extracted, provenance normalization delegates to the shared null-prototype own-record helper, no builder/plan/policy or new responsibility enters this file, and net line count is non-increasing from 769. Independent cohesion/lifecycle review is mandatory; any required expansion is a replan. |
| `src/renderer/index.ts` (~779 lines) | renderer composition/lifecycle | Lifecycle composition only. Builder state lives in focused modules. Fresh architecture/UI review required before editing. |
| `src/main/plex/desktopPlexRuntime.ts` (~551 lines) | authenticated main Plex runtime | Package 1C adds only the separate optional `channelBuilderFacetTransport` dependency, exact null/unavailable gate, narrow facet-source delegation, and main-only context publication; `libraryTransport` remains unchanged and distinct, and no planner, epoch, endpoint policy, cast, setter, or fallback enters this owner. Fresh security/Plex review required. |
| `src/main/plex/livePlexTransport.ts` and `desktopPlexLibraryOperationExecutor.ts` | authenticated typed Plex transport/library operation owners | Package 1B adds the separate narrow `LivePlexChannelBuilderFacetTransport`, implements it on the real `LivePlexTransport`, and adds the UUID-bearing record delegate and `listSectionsForMain`; the existing `LivePlexLibraryTransport` keys remain unchanged. The access adapter receives separately named `facetTransport` and narrow-`Pick` `itemTransport` fields and never intersects or combines them. No generic path/request/header primitive or renderer exposure. Fresh security/Plex review and exact URL/query tests required. |
| `src/main/channel/channelRuntime.ts` (~450 lines) | current fallback commit/status runtime | Remove fallback policy and retain narrow runtime/status delegation. New builder runtime owns the lifecycle. |
| `src/main/channel/channelIpc.ts` (~408 lines) | channel IPC registration | Wiring only; validation is extracted. Fresh IPC/security review required. |
| `src/main/index.ts` | Electron main composition root | Package 1C wires only the exact startup sequence: validated smoke capability, single-instance ownership, production/development channel-directory bootstrap capability/policy or explicit smoke bypass, Plex construction without IPC, sole-owner channel startup load/repair, channel composition, Plex IPC, channel IPC, remaining IPC, then app/window startup. No directory/repair policy, environment-derived smoke authority, builder policy, fixture data, or production/development fallback lives here. Fresh architecture/security review and source-order proof are required. |
| `src/main/plex/plexIpc.ts` (~422 lines) | renderer-safe Plex IPC | Untouched; builder facet access is main-only. |
| `src/main/channel/channelComposition.ts` | channel composition root | Wiring only; it must not acquire planning/persistence policy. |
| `src/main/smokeAssertions.ts` (~554 lines) | smoke orchestration/composition | Package 1C extracts Channel Builder-specific source/assertions into `src/main/smokeChannelBuilderAssertions.ts`; this file retains orchestration only, absorbs no builder state machine, and must finish below 554 lines. The extracted module is capped at 220 lines and receives a focused test. Independent architecture/maintainability review is mandatory. |
| `src/renderer/workflow.ts` (~504 lines) | renderer route/action workflow orchestration | May add only builder action delegation and lifecycle transitions; Package 1C's minimal config state and Package 1D's editable extension stay in `builderConfigState.ts`, while normalization/defaults remain in 1A. IPC parsing, DOM construction, and operation policy stay in focused modules. Packages 1C/1D/1E require fresh UI-composition, architecture, and maintainability review; policy growth or more than 40 net lines is a replan trigger. |
| `src/main/channel/guideRuntime.ts` and scheduler | guide/schedule owners | Untouched by WS1 policy; consume only a post-commit lineup-change signal. |

Crossing any of these dispositions is a replan trigger, not a local implementation choice.

### Audited upstream adaptation boundary

Only focused semantics from the local upstream Lineup checkout at audited commit `0258dbe` may be adapted. The input set is:

- `src/core/channel-setup/types.ts`
- `src/core/channel-setup/constants.ts`
- `src/core/channel-setup/config/normalizeChannelSetupConfig.ts`
- `src/core/channel-setup/planning/ChannelSetupPlanningTypes.ts`
- `src/core/channel-setup/planning/ChannelSetupFacetFamilies.ts`
- `src/core/channel-setup/planning/ChannelSetupNativeFacetEligibility.ts`
- `src/core/channel-setup/planning/ChannelSetupPeopleSeriesIndex.ts`
- `src/core/channel-setup/planning/ChannelSetupFacetLibraryExecutor.ts`
- `src/core/channel-setup/planning/ChannelSetupFacetSnapshotLoader.ts`
- `src/core/channel-setup/planning/ChannelSetupFacetSnapshotLoadSession.ts`
- `src/core/channel-setup/planning/ChannelSetupFacetSnapshotAbort.ts`
- `src/core/channel-setup/planning/ChannelSetupFacetCountRecoveryWorker.ts`
- `src/core/channel-setup/planning/ChannelSetupFacetCountRecoveryLimiter.ts`
- `src/core/channel-setup/planning/ChannelSetupFacetSnapshotFailures.ts`
- `src/core/channel-setup/planning/ChannelSetupPlanner.ts`
- `src/core/channel-setup/planning/ChannelSetupStrategyBuilders.ts`
- `src/core/channel-setup/planning/ChannelSetupTagFilters.ts`
- `src/core/channel-setup/build/ChannelSetupBuildCommitter.ts`
- `src/core/channel-setup/build/ChannelSetupBuildExecutor.ts`
- `src/core/channel-setup/shared/formatChannelSetupWarning.ts`
- `src/modules/ui/channel-setup/ChannelSetupSessionState.ts`
- `src/modules/ui/channel-setup/steps/StrategyStepControlDescriptors.ts`
- `src/modules/ui/channel-setup/steps/StrategyStepController.ts`
- `src/modules/ui/channel-setup/steps/StrategyStepInteractionController.ts`
- `src/modules/ui/channel-setup/steps/BuildReviewStepController.ts`
- `src/modules/ui/channel-setup/steps/BuildProgressStepController.ts`
- `src/modules/ui/channel-setup/styles.strategy.css`
- `src/modules/ui/channel-setup/styles.review-progress.css`
- `src/modules/plex/library/PlexLibrary.ts`
- `src/modules/plex/library/constants.ts`

These are adaptation references, not copy instructions. The newly listed Plex-library/facet loader/session/family/eligibility/count-recovery inputs were directly observed as present at audited `0258dbe`; execution preflight must still prove their pinned blobs and scoped cleanliness. Upstream browser storage, request-client implementation, general session/runtime owners, API clients, framework components, unrestricted metadata, and styling shell are excluded. Every copied or adapted slice is recorded in `docs/architecture/import-ledger.md` before or with its introduction.

Package 1F may additionally inspect and render these exact read-only visual-reference owners at the same `0258dbe` pin: `src/modules/ui/channel-setup/ChannelSetupScreen.ts`, `src/modules/ui/channel-setup/steps/LibraryStepController.ts`, `src/modules/ui/channel-setup/steps/ChannelSetupBuildStepPresenter.ts`, `src/modules/ui/channel-setup/styles.core.css`, and `src/modules/ui/channel-setup/styles.library.css`. They are not adaptation inputs and authorize no product-code copy; discovering that implementation must adapt one of them is a stop/review trigger.

## Files In Scope

Only WS1 has exact implementation files frozen. Later workstreams have bounded owner surfaces but no exact paths until their freshness gates.

### Package-owned directory scaffolding

Directory creation is non-product scaffolding and cannot broaden file scope. At this plan revision, direct filesystem validation observed `src/domain/`, `src/__tests__/`, `src/main/persistence/`, `src/__tests__/main/`, `docs/runs/`, and the tracked two-level WS1 run directory as existing; `src/domain/channelBuilder/` and `src/__tests__/fixtures/` were absent. The new bootstrap owner/test use those existing parents and authorize no source-directory creation. Ownership is exact:

- Package 1A creates only `src/domain/channelBuilder/` under existing `src/domain/`.
- Package 1C creates only `src/__tests__/fixtures/` under existing `src/__tests__/` if it remains absent.
- Package 1F's portable harness inputs are tracked at the exact `docs/runs/2026-07-22-tier3-parity-correction/channel-builder/` paths listed below and therefore exist after checkout. Evidence execution may create only the ignored output children/files declared below. If an ignored output parent is absent, 1F may create only the exact missing chain inside that tracked run root after resolving the repository root and rejecting symlink/non-directory components; it may not create a sibling run root or add any undeclared file. The already-frozen capture workflow may create only ignored `captures/upstream/` and `captures/desktop/` evidence-output children inside that exact run root; those children do not authorize another parent or sibling scope.

Before each package begins, a mechanical scope check must prove every path classified `Existing` for that package is a present file, every `New` file is absent or an explicitly reviewed resume artifact, and every new file's parent either already exists or is one of the package-owned directories above. A mismatch is a stop/replan condition, not permission to create an undeclared parent.

### Package 1A — pure DTO, config, and deterministic planner

Existing:

- `.github/workflows/ci.yml`
- `docs/architecture/import-ledger.md`
- `package.json`

New:

- `src/domain/channelBuilder/types.ts`
- `src/domain/channelBuilder/constants.ts`
- `src/domain/channelBuilder/config.ts`
- `src/domain/channelBuilder/facets.ts`
- `src/domain/channelBuilder/planIdentity.ts`
- `src/domain/channelBuilder/strategyBuilders.ts`
- `src/domain/channelBuilder/planner.ts`
- `src/domain/channelBuilder/persistence.ts`
- `src/domain/channelBuilder/index.ts`
- `src/__tests__/domain/channelBuilderContracts.test.ts`
- `src/__tests__/domain/channelBuilderIdentity.test.ts`
- `src/__tests__/domain/channelBuilderPlanner.test.ts`
- `src/__tests__/domain/channelBuilderPlannerPerformance.test.ts`

### Package 1A Proof Route R0 — completed historical unit

Existing and exact edit scope:

- `.github/workflows/ci.yml`
- `src/__tests__/domain/channelBuilderPlannerPerformance.test.ts`

No other file is in scope. In particular, `package.json`, Package 1A production
code and other tests, authority docs, workflows other than `ci.yml`, and every
Package 1B–1F file remain unchanged.

### Package 1A Performance Architecture A1 — current pre-1B unit

Existing and exact edit scope:

- `.github/workflows/ci.yml`
- `docs/architecture/import-ledger.md`
- `package.json`
- `src/domain/channelBuilder/facets.ts`
- `src/domain/channelBuilder/planIdentity.ts`
- `src/domain/channelBuilder/strategyBuilders.ts`
- `src/domain/channelBuilder/planner.ts`
- `src/__tests__/domain/channelBuilderPlannerPerformance.test.ts`

New:

- `src/main/channel/channelBuilderProductionPlanner.ts`
- `src/__tests__/main/channelBuilderProductionPlanner.test.ts`
- `src/__tests__/main/channelBuilderPlannerPerformance.test.ts`

The old domain performance-test path is deleted as the source side of the move;
the main performance-test path is the sole benchmark owner afterward.
`package.json` may change only the existing
`verify:channel-builder-performance` script's test path to that main file.
`package-lock.json`, `src/domain/channelBuilder/index.ts`, both existing domain
identity/planner tests, every other product/test/CI file, authority docs, and
Package 1B–1F files are out of scope. Before code, amend the existing Package 1A import-ledger row; in
the same checkpoint it must name the new main production planner destination,
retain the pure-domain default/no-Node boundary, record the Desktop-only native
hashing divergence, name pure/native identity and planner parity proof, and
retain the unchanged Windows gate/revisit trigger. No new upstream source or
dependency is claimed.

### Package 1B — safe Plex facets

Existing:

- `src/main/plex/livePlexTransport.ts`
- `src/main/plex/desktopPlexRuntime.ts`
- `src/main/plex/desktopPlexLibraryOperationExecutor.ts`
- `src/main/plex/library/librarySectionCountEnrichment.ts`
- `src/main/plex/library/constants.ts`
- `src/main/plex/library/libraryDomain.ts`
- `src/main/plex/library/libraryRuntimeValidation.ts`
- `src/main/plex/library/types.ts`
- `src/main/plex/library/parsing/libraryListingParser.ts`
- `src/main/plex/library/parsing/libraryResponsePayload.ts`
- `src/main/plex/library/parsing/index.ts`
- `src/main/plex/library/index.ts`
- `docs/architecture/import-ledger.md`
- `src/__tests__/main/plexLibrary.test.ts`
- `src/__tests__/main/plexRuntimeOperationOwners.test.ts`

New:

- `src/main/plex/desktopPlexChannelBuilderFacetSource.ts`
- `src/__tests__/main/channelBuilderFacetSource.test.ts`

`src/__tests__/main/plexRuntimeIpc.test.ts` and `src/__tests__/main/plexLibraryMinimalAdapter.test.ts` are explicitly unchanged and out of Package 1B scope. Their legacy `LivePlexLibraryTransport` mocks must not require edits because that interface's key set does not change.

### Package 1C — atomic application, lifecycle, cancellation, and IPC

Existing:

- `src/contracts/channel.ts`
- `src/contracts/ipc.ts`
- `src/contracts/shell.ts`
- `docs/architecture/import-ledger.md`
- `src/domain/channelBuilder/persistence.ts`
- `src/domain/channel/channelPersistenceCoordinator.ts`
- `src/domain/channel/channelPersistenceStore.ts`
- `src/domain/channel/channelDomainClone.ts`
- `src/domain/channel/channelRepository.ts`
- `src/main/persistence/desktopChannelPersistenceStore.ts`
- `src/main/plex/plexComposition.ts`
- `src/main/plex/desktopPlexRuntime.ts`
- `src/main/channel/channelRuntime.ts`
- `src/main/channel/customChannelRuntime.ts`
- `src/main/channel/channelIpc.ts`
- `src/main/channel/channelComposition.ts`
- `src/main/smokeAssertions.ts`
- `src/main/index.ts`
- `src/preload/channels.cts`
- `src/preload/channelBridgeGuards.cts`
- `src/preload/channelSetupBridge.cts`
- `src/preload/index.cts`
- `src/renderer/index.ts`
- `src/renderer/staticDom.ts`
- `src/renderer/channelRuntimeState.ts`
- `src/renderer/channelRuntimeActions.ts`
- `src/renderer/domBindings.ts`
- `src/renderer/rendererActionRegistration.ts`
- `src/renderer/channelSetup/viewModel.ts`
- `src/renderer/channelSetup/dom.ts`
- `src/renderer/focusDom.ts`
- `src/renderer/setup/stagedSetupController.ts`
- `src/renderer/workflow.ts`
- `src/__tests__/contracts/contracts.test.ts`
- `src/__tests__/domain/channelPersistence.test.ts`
- `src/__tests__/main/channelPersistenceAdapter.test.ts`
- `src/__tests__/main/channelRuntimeIpc.test.ts`
- `src/__tests__/main/channelComposition.test.ts`
- `src/__tests__/main/customChannelRuntime.test.ts`
- `src/__tests__/renderer/channelRuntimeActions.test.ts`
- `src/__tests__/renderer/rendererActionRegistration.test.ts`
- `src/__tests__/renderer/rendererRuntimeOwners.test.ts`
- `src/__tests__/renderer/routeDom.test.ts`
- `src/__tests__/renderer/focusDom.test.ts`
- `src/__tests__/renderer/plexRuntime.test.ts`
- `src/__tests__/renderer/playerOverlayPresentation.test.ts`
- `src/__tests__/renderer/workflow.test.ts`
- `src/__tests__/integration/preloadContractVocabulary.test.ts`
- `tools/copy-renderer-assets.mjs`
- `tools/smoke-electron.mjs`
- `tools/architecture-rules/buildEslintArchitectureRules.mjs`
- `tools/__tests__/copy-renderer-assets.test.mjs`
- `tools/__tests__/build-eslint-architecture-rules.test.mjs`
- `tools/__tests__/package-windows-internal.test.mjs`

New:

- `src/main/channel/channelPublicReferenceOwner.ts`
- `src/main/channel/channelBuilderOperationOwner.ts`
- `src/main/channel/channelBuilderPlanningWorker.ts`
- `src/main/channel/channelBuilderPlanningWorkerEntry.ts`
- `src/main/channel/channelBuilderRuntime.ts`
- `src/main/channel/channelBuilderContextEpochOwner.ts`
- `src/main/channel/channelLineupMutationCoordinator.ts`
- `src/main/channel/channelBuilderIpcValidation.ts`
- `src/main/channel/channelBuilderSmokeFixture.ts`
- `src/main/persistence/channelPersistenceBootstrapOwner.ts`
- `src/main/persistence/channelPersistenceStartupOwner.ts`
- `src/main/smokeBootstrapOwner.ts`
- `src/main/singleInstanceOwner.ts`
- `src/main/smokeChannelBuilderAssertions.ts`
- `src/main/plex/desktopPlexContextNotifications.ts`
- `src/renderer/channelSetup/builderConfigState.ts`
- `src/__tests__/fixtures/channel-persistence-v1-legacy.json`
- `src/__tests__/renderer/channelBuilderConfigState.test.ts`
- `src/__tests__/main/channelBuilderCommitBarrier.test.ts`
- `src/__tests__/main/channelBuilderContextEpochOwner.test.ts`
- `src/__tests__/main/desktopPlexChannelBuilderFacetRuntime.test.ts`
- `src/__tests__/main/channelBuilderSmokeFixture.test.ts`
- `src/__tests__/main/channelPersistenceBootstrapOwner.test.ts`
- `src/__tests__/main/channelPersistenceStartupOwner.test.ts`
- `src/__tests__/main/plexComposition.test.ts`
- `src/__tests__/main/channelBuilderOperationContracts.test.ts`
- `src/__tests__/main/channelBuilderPlanningWorker.test.ts`
- `src/__tests__/main/channelPublicReferenceOwner.test.ts`
- `src/__tests__/main/smokeBootstrapOwner.test.ts`
- `src/__tests__/main/singleInstanceOwner.test.ts`
- `src/__tests__/main/smokeChannelBuilderAssertions.test.ts`
- `src/__tests__/main/desktopPlexContextNotifications.test.ts`
- `tools/__tests__/smoke-electron.test.mjs`

Worker-thread-specific edits within this larger serial package are further
restricted to the two new planning-worker owners, their focused new test, the
already-declared new `channelBuilderOperationOwner.ts` and
`channelBuilderOperationContracts.test.ts`, existing
`channelComposition.ts`/`channelComposition.test.ts`, and existing
`tools/__tests__/package-windows-internal.test.mjs`. `src/main/index.ts`
continues to call only the composition teardown already required by Package 1C;
the worker boundary does not authorize an additional direct lifecycle owner or
any build/package configuration edit.

`src/domain/channelBuilder/persistence.ts` is a surgical existing Package 1C
owner only for the already-frozen persisted builder-state and
`channelProvenance` validation, normalization, current-lineup membership
filtering, marker-local repair, null-prototype clone, and startup-repair
integration responsibilities. It may call the existing config normalizer only
to validate/recover persisted `normalizedConfig`; it may not widen planner,
identity, config/default, persisted-schema, or public DTO behavior. This
amendment authorizes no additional production file or test file:
`src/__tests__/domain/channelPersistence.test.ts`,
`src/__tests__/main/channelPersistenceAdapter.test.ts`, and
`src/__tests__/main/channelPersistenceStartupOwner.test.ts` remain the declared
proof surfaces through the existing repository/adapter/startup seams.

`tools/architecture-rules/buildEslintArchitectureRules.mjs` and its existing
focused `tools/__tests__/build-eslint-architecture-rules.test.mjs` are a
surgical Package 1C verifier-correction seam only. The rule builder must
represent bare Node builtins such as `domain` as exact restricted imports
rather than glob patterns, so the frozen renderer owner may statically import
`../../domain/channelBuilder/config.js` without the bare builtin name matching
the relative `domain` segment. Exact bare `domain`, `node:domain`, `node:*`,
privileged main/preload/native-helper paths, non-literal dynamic imports, and
literal dynamic imports across every existing forbidden boundary remain
rejected. This changes no architecture policy, product scope, renderer
privilege, Package 1A config/default owner, IPC, or other package, and
authorizes no additional verifier or test file.

`tools/copy-renderer-assets.mjs` and its existing focused
`tools/__tests__/copy-renderer-assets.test.mjs` are the final surgical Package
1C runtime-build seam. After the existing `tsc` step, the owner copies exactly
emitted `dist/domain/channelBuilder/config.js` and `constants.js` byte-for-byte
to `dist/renderer/domain/channelBuilder/`, where the existing renderer-only
custom protocol can resolve the frozen canonical factory import. It copies no
source literal, source map, arbitrary directory, `index`, planner,
persistence, facets, or types artifact. Existing protocol root/containment,
CSP, `src/main/protocol.ts`, `src/main/index.ts`, package/build configuration,
public contracts, IPC, and Package 1A config/default ownership remain
unchanged. No additional asset owner or newly scoped test file is authorized;
the existing in-scope internal-package test remains its package proof surface.

`src/__tests__/renderer/playerOverlayPresentation.test.ts` is an existing
Package 1C compile-fixture conformance owner only. Its sole authorized change
adds exact `lineupRevision: 1` and exact `builder` value
`{ completion: 'unknown', normalizedConfig: null, completedAtMs: null }` to the
existing `channelSummary` fixture required by the frozen public Channel Setup
summary shape. It adds or changes no player/overlay/presentation behavior,
expectation, assertion, scenario, or owner.

### Package 1D — renderer configuration and review

Existing:

- `src/renderer/channelRuntimeState.ts`
- `src/renderer/channelRuntimeActions.ts`
- `src/renderer/channelSetup/viewModel.ts`
- `src/renderer/channelSetup/dom.ts`
- `src/renderer/channelSetup/builderConfigState.ts`
- `src/renderer/setup/stagedSetupController.ts`
- `src/renderer/setup/stagedSetupDom.ts`
- `src/renderer/setup/stagedSetupFocus.ts`
- `src/renderer/setup/setupComposition.ts`
- `src/renderer/staticDom.ts`
- `src/renderer/domBindings.ts`
- `src/renderer/rendererActionRegistration.ts`
- `src/renderer/workflow.ts`
- `src/renderer/styles/setup-workflow.css`
- `docs/architecture/import-ledger.md`
- `src/__tests__/renderer/channelRuntimeActions.test.ts`
- `src/__tests__/renderer/workflow.test.ts`
- `src/__tests__/renderer/rendererActionRegistration.test.ts`
- `src/__tests__/renderer/routeDom.test.ts`
- `src/__tests__/renderer/focusDom.test.ts`
- `src/__tests__/renderer/channelBuilderConfigState.test.ts`

New:

- `src/__tests__/renderer/channelSetupDom.test.ts`

### Package 1E — result, recovery, and onboarding integration

Existing:

- `src/renderer/setup/setupRuntimeCoordinator.ts`
- `src/renderer/onboarding/plexOnboardingFlow.ts`
- `src/renderer/index.ts`
- `src/renderer/routeDom.ts`
- `src/renderer/channelRuntimeActions.ts`
- `src/renderer/setup/stagedSetupController.ts`
- `src/renderer/setup/setupComposition.ts`
- `src/renderer/workflow.ts`
- `src/renderer/staticDom.ts`
- `src/main/smokeAssertions.ts`
- `src/main/smokeChannelBuilderAssertions.ts`
- `src/__tests__/renderer/setupRuntimeCoordinator.test.ts`
- `src/__tests__/renderer/plexRuntime.test.ts`
- `src/__tests__/renderer/rendererRuntimeOwners.test.ts`
- `src/__tests__/renderer/channelRuntimeActions.test.ts`
- `src/__tests__/renderer/workflow.test.ts`
- `src/__tests__/renderer/routeDom.test.ts`

`src/main/smokeChannelBuilderAssertions.ts` is an expected-existing output of the committed Package 1C checkpoint and must pass the normal preflight existing-path check before Package 1E starts.

New: none.

### Package 1F — proof and authority closeout

Tracked portable harness inputs:

- `docs/runs/2026-07-22-tier3-parity-correction/channel-builder/states.mjs`
- `docs/runs/2026-07-22-tier3-parity-correction/channel-builder/capture-upstream.mjs`
- `docs/runs/2026-07-22-tier3-parity-correction/channel-builder/capture.mjs`
- `docs/runs/2026-07-22-tier3-parity-correction/channel-builder/verify.mjs`
- `docs/runs/2026-07-22-tier3-parity-correction/channel-builder/visual-evidence-contract.test.mjs`
- `docs/runs/2026-07-22-tier3-parity-correction/channel-builder/windows-checklist.template.md`

Ignored session evidence outputs:

- `docs/runs/2026-07-22-tier3-parity-correction/channel-builder/upstream-reference-manifest.json`
- `docs/runs/2026-07-22-tier3-parity-correction/channel-builder/visual-comparison.json`
- `docs/runs/2026-07-22-tier3-parity-correction/channel-builder/windows-checklist.md`
- `docs/runs/2026-07-22-tier3-parity-correction/channel-builder/captures/**`
- `docs/runs/2026-07-22-tier3-parity-correction/channel-builder/.cb-manifest-*.tmp`

Tracked authority/evidence summaries:

- `docs/product/lineup-product-parity-matrix.md`
- `docs/architecture/CURRENT_STATE.md`
- `docs/roadmap/desktop-port-roadmap.md`
- `docs/architecture/import-ledger.md`
- `docs/development/windows-ui-proof-plan.md`
- `docs/plans/2026-07-22-tier3-parity-correction-plan.md`

## Files Out Of Scope

For WS1, all product files not explicitly named above are out of scope. In particular:

- `src/domain/channel/channelManager.ts`
- `src/domain/channel/channelAuthoringService.ts`
- `src/main/channel/guideRuntime.ts`
- `src/domain/scheduler/channelScheduler.ts`
- `src/main/plex/plexIpc.ts`
- `src/__tests__/main/plexRuntimeIpc.test.ts`
- `src/__tests__/main/plexLibraryMinimalAdapter.test.ts`
- Custom Channels UI and policy files
- player, settings, guide, navigation, packaging, updater, and unrelated lifecycle files
- upstream Lineup files outside the audited adaptation list
- the user-owned in-progress edits already present in `docs/architecture/CURRENT_STATE.md`, `docs/product/lineup-product-parity-matrix.md`, and `docs/roadmap/desktop-port-roadmap.md`, except when Package 1F deliberately refreshes them from verified evidence

For WS2–WS9, exact product files are deliberately out of scope until the applicable workstream freshness review freezes them. Their current owner surfaces are playback; settings/persistence; input/navigation/overlay; guide/scheduler; Custom Channels; renderer visual surfaces; Plex credentials/lifecycle/onboarding; and packaging/update/Windows proof, respectively.

## Execution Packages

### Controller gates applying to every package

Before each package, reread its exact source owners, contracts, focused tests, applicable stable-ID rows, `CURRENT_STATE.md`, and the relevant audited upstream paths. Confirm the worktree, preserve unrelated user changes, and obtain the required architecture/security/Plex/UI/persistence/test review for that package. A worker receives only the decisions, frozen files, and acceptance criteria in this plan; Package 1C is not authorized to redesign or “freeze” the IPC, persistence, context, or cancellation policy during implementation.

After focused tests, update only rows supported by observed evidence and retain live/Windows/visual qualifiers. Update `CURRENT_STATE.md` when ownership changes. Update the roadmap only at workstream close. Each adapting package—1A, 1B, 1C, and 1D—must add its own source-to-destination import-ledger entry before or in the same commit as the first adaptation. Packages 1A–1F are serial, and every local checkpoint must pass its focused tests, `npm run typecheck`, and `npm run build:electron` before its commit; no checkpoint may depend on an uncommitted later package. Package 1A additionally follows the provisional-checkpoint/acceptance sequence below: its local checkpoint commit is permitted after the named local gates, but is not an accepted/closed Package 1A checkpoint until authoritative isolated Windows proof passes against that exact commit SHA. Change the Windows proof plan when its reusable rule/scenario set or stale authority preamble changes.

### Package 1A Proof Route R0 — completed gate isolation

**IMPLEMENTER_ROLE_ELIGIBILITY:** `worker_sol_low`

This is the current, mechanical, non-product exception to the Package 1A hard
stop and the only implementation authorized immediately after the amended plan
passes one must-fix-only review. Change only the two R0 files. Make the broad
contract lifecycle skip the benchmark and make no performance-proof claim;
make the exact performance lifecycle execute the unchanged warm/measured
fixture and enforcement; and replace only the dedicated step's condition with
`${{ !cancelled() && runner.os == 'Windows' }}`.

Run the focused/local commands below, inspect the two-file diff, and obtain one
fresh must-fix-only implementation review. Correct at most one bounded cycle
for a genuine invariant violation; do not enter a nit/style loop. Commit
exactly `ci(channels): isolate builder performance gate`, then push only that
new commit to the existing `dev/ws1-channel-builder-1a` PR #19 branch. Do not
merge PR #19. Acceptance waits for the same exact pushed SHA's Windows
ordinary Verify and dedicated isolated performance results. Any failed,
skipped, contended, misrouted, or different-SHA evidence stops and returns to a
reviewed replan under R0. A1 and `WS1-PERF-01` supersede that historical
pass-before-1B rule.

### Package 1A Performance Architecture A1 — accelerate the production planner

**IMPLEMENTER_ROLE_ELIGIBILITY:** `worker`

A1 is architecture-heavy and remains one serial unit because the hash factory,
identity capability, strategy/planner threading, main production entrypoint,
conformance tests, benchmark relocation/script retarget, performance route,
import-ledger disposition, and exact-head
CI assertion form one atomic parity boundary. Do not split it gratuitously.
`worker_sol_low` is eligible only if a controller first extracts a genuinely
mechanical disjoint edit with frozen files and direct proof; no such slice is
currently justified.

The one independent must-fix-only A1 plan review is complete, and the first
implementation review produced the two accepted findings frozen above: bound
inline-filter validation and exhaustive main conformance. Do not reopen
architecture or request another broad plan/implementation review. Run one
in-scope implementation fix cycle limited to the corrected A1 file list,
including only the new `facets.ts` bound variant, the `planner.ts` call-site
substitution, and the main production-planner test expansion required by those
findings. Then rerun the affected focused
commands plus `npm run verify` and obtain one targeted reviewer recheck of those
two findings only. A recheck contradiction to the frozen seam, files, canonical
bytes, gate, or proof route stops for replan; do not enter a nit/style loop.

Preserve the user's pre-existing edits in
`docs/architecture/CURRENT_STATE.md`,
`docs/product/lineup-product-parity-matrix.md`, and
`docs/roadmap/desktop-port-roadmap.md`, plus this local active plan. Never use
`git add -A`, `git add .`, amend, rebase, force-push, or stage an authority doc.
Stage only the exact eleven A1 path-owned entries listed above and require
`git diff --cached --name-only` to equal that set before committing. Use the one
follow-up subject `perf(channels): use native planner identity hashing`.
Existing commits `ca21ba1a5d641093e55b7c64b0910e317016ae37`,
`aa224e5bed28341600d9fa33bd2fe7ac305aa2e4`, and
`d6a42a6e363ce32769f5b949ee5768b0cb438023` are immutable.

Before push, require
`git ls-remote --heads origin refs/heads/dev/ws1-channel-builder-1a` to resolve
exactly to `d6a42a6e363ce32769f5b949ee5768b0cb438023`; any absent or moved remote
head stops without push. Push the new descendant with the explicit non-force
refspec `git push origin HEAD:refs/heads/dev/ws1-channel-builder-1a`, then
require the remote ref to equal the new local `HEAD`. This existing branch/PR
push is authorized. Branch switching, another PR, merge, release, tag, signing,
force-with-lease, and any other remote state change are not.

After push, accept only a pull-request run whose checkout assertion, ordinary
Windows Verify step, and isolated `Channel Builder performance` step all name
the exact new head SHA; the latter must execute rather than skip and report the
unchanged measured invocation and target. Ordinary Windows Verify must pass.
If the asserted exact-head isolated result is above 2,000 ms, activate and
carry `WS1-PERF-01`, do not rerun for a favorable sample, and continue to
Package 1B only after the result is preserved in the next handoff. Do not tune
again without separate authority, merge, or alter the fixture/cap.

### Package 1A — pure DTO, config, and deterministic planner

**IMPLEMENTER_ROLE_ELIGIBILITY:** `worker`

Create the exact package-owned `src/domain/channelBuilder/` directory, then land the complete domain-owned DTO/config surface before any main consumer. Adapt the audited normalization, planning, strategy, eligibility, tag, people/series indexing, warning, diff, and plan-identity semantics. `types.ts` owns exact `PersistedStringV1`, the raw-free tag-facet/content-filter-plan types, and the sole `projectChannelBuilderSafeDisplayString`; `config.ts` owns the immutable behavior defaults, pure default factory, and one normalization seam; `planIdentity.ts` owns `canonicalJsonV1`, every Identity V1 constructor including tag-group/content-filter identities, the total library-filter dictionary exception, and no alternate serializer. Those typed constructors may synchronously receive main-validated raw inputs only under the frozen transient no-retention/value-free-failure contract; no planner or strategy function accepts them. Prove the exact `ChannelSetupConfig`, default/normalization return union, five-field `ChannelBuilderPlannerInput`, item-facet-free `ChannelBuilderFacetSnapshot`, presence-preserving raw-filter-free `ChannelBuilderExistingLineupEntry`, lossless total existing ID/name projection through `PersistedStringV1`, byte-level binding/facet/tag-group/content-filter/source/candidate/plan identities and golden vectors—including numeric-like ordinary key order `"10"` before `"2"`, all finite-number serialization, arbitrary/NFC-colliding library-filter cases, and exact facet-warning arrays/counts—warning/apply-summary shapes, all strategies and controls, deterministic same-input output, explicit clock/seed handling, append/replace/merge review diffs whose names all use the sole display helper before ordering/concatenation/capping, facet/reference-only output, and absence of Electron/Node/transport/filesystem/global-time dependencies from `src/domain/**`; A1's reviewed `node:crypto` adapter exists only in its named main owner.

`channelBuilderPlanner.test.ts` proves safe semantic completeness with unequal `tagValue`/`displayTitle` fixtures: per-library genre uses the tag source; cross-library genre/director and combined/cross-library actor/studio group only by equal `semanticGroupIdentity`; same displayed title with unequal group identities stays separate; unequal displayed titles with equal group identity combine; group seeds/skip counts do not change when display projection changes; per-library director emits the unfiltered library source plus exact `main-index-reference` content-filter plan; actor/studio source references retain their audited main-only fastKey/key filter semantics without planner strings; and decade count/filter construction uses only numeric `yearValue`, including null/invalid, case/display-hostile, and boundary fixtures. It rejects raw key, `tagValue`, and raw filter strings in every planner/safe DTO, missing/wrong-family semantic identities, a string-bearing inline plan, a digest used as a runtime value, and every use of `displayTitle` for identity/query/group/year/filter/seed/order/cap semantics. Identity tests invoke the typed constructors directly with validated raw key/tag/filter/runtime-source/persisted-filter values and prove synchronous opaque-only results, fixed value-free failures, and no retention in returned values, state, logs, diagnostics, or exceptions. Redaction, truncation, collision, and raw/display-divergence fixture pairs straddle the configured capacity boundary and prove identical semantic facet/group/member/candidate order, cap survivors, seeds, and identities despite different `displayTitle` output. It includes an explicit `alternateLineupCopies = 3` fixture proving the base emits `lineupReplicaIndex: 0` and its three alternates emit exact indices `1`, `2`, and `3` without clamping or omission; it also proves hostile existing IDs/names remain raw in the main-only ledger, raw existing filters are replaced by opaque content-filter identity, those values never affect source disposition except when the typed identity cannot be formed, and review samples remain helper-projected. Helper fixtures pin the exact complete-string credential redaction vectors plus overlength, controls, astral/surrogate edges, NFC-equivalent raw-distinct strings, innocent URL-only/angle text, exact fallbacks, and surrogate-safe limits. Facet-warning fixtures prove the exact seven-code union, deeply immutable unique lexical ordering, cap/count consistency, exact discovery-warning conversion, identity/golden-vector participation, deterministic output, and rejection of unknown/duplicate/unsorted/over-cap or inconsistent shapes. Manual-source fixtures are existing-projection-only and prove no item facet, item-facet identity, index entry, or new manual-producing candidate. All-disabled, all-ineligible, and all-skipped pure fixtures prove only the sole `PLAN_EMPTY` warning, blocked status, empty `applyCandidateIds`, empty `retainedMaterializationCandidateIds`, and absence of any apply-capable pure output or materialization request. Package 1A also lands the exact isolated npm performance script and guarded Windows CI step above. Package 1A owns no raw tag/filter acquisition, runtime plan ID, reviewed body/index retention, apply owner, or persistence access; its tests must not claim public `planId: null`, runtime rejection, body/index retention, persisted-lineup nonmutation, or materialized raw filter values. Its import-ledger entry records the explicit display-free semantic tie-break/cap divergence and post-admission display projection without raw examples.

Package 1A has no Electron-composed runtime consumer and is independently
buildable. A1 adds the main-owned synchronous production planning entrypoint
used by the isolated performance test and reserved unchanged for Package 1C's
Worker entry. Original
commit `ca21ba1a5d641093e55b7c64b0910e317016ae37` and its sole optimization
follow-up `aa224e5bed28341600d9fa33bd2fe7ac305aa2e4` are immutable evidence; do
not amend, rebase away, replace, or present either as accepted. R0 adds only
the immutable proof-route commit on top. A1's reviewed follow-up commit becomes
the sole Package 1A acceptance candidate and remains provisional until both
exact-head Windows steps are observed.

Package 1A becomes accepted/closed, and only then may Package 1B start, when
the same exact A1 SHA passes the ordinary Windows `Verify` step and then runs the
dedicated Windows Node `22.19.0` `Channel Builder performance` step. The latter
must execute exactly `npm run verify:channel-builder-performance` without a
concurrent npm/Node test workload and measure the unchanged deterministic
50,000-candidate fixture against the unchanged 2,000 ms target. Proof binds the exact SHA,
Windows runner, Node version, command, isolation statement, measured
invocation, and both step results. A skipped dedicated step is missing proof; a
dedicated result does not mask any Verify failure. An exact-head above-target
result activates `WS1-PERF-01` but permits Package 1B. Local performance runs
and the two broad contended measurements are diagnostic only.

Observed R0 evidence at commit
`d6a42a6e363ce32769f5b949ee5768b0cb438023` is terminal and does not satisfy
acceptance. Pull-request run `30057283496` passed ordinary Windows `Verify`, then
executed the dedicated Node `22.19.0`
`npm run verify:channel-builder-performance` command without another npm/Node
test command running. The unchanged fixture measured `3320.85 ms` and failed the
unchanged 2,000 ms cap. The checkout was GitHub's pull-request merge ref
`ce5f56532e7b12922382d4af43c5ea84e64aa9e4`, not the byte-exact R0 head SHA, so
the run also cannot serve as the plan's exact-head-SHA acceptance proof even if
the cap had passed. R0 successfully made the isolated step reachable; it did
not close Package 1A. The plan's single pure-optimization allowance is already
exhausted, and the deferred Package 1C Worker boundary protects responsiveness
but cannot make or substitute for the kernel gate. External authority now
authorizes only A1's main-owned native hashing architecture under the unchanged
test contract. No Package 1B–1F implementation is authorized before ordinary
Windows Verify passes and the exact-head isolated A1 result is observed and
either passes or is preserved as `WS1-PERF-01`.

Rollback removes the unconsumed pure domain modules, including `PersistedStringV1`, the transient-input/no-retention tag-group/content-filter/source identity constructors, raw-free content-filter plan, sole display helper, exact display-free semantic ordering/cap contract, and the exact facet-warning and pure blocked-output contracts; it preserves the import-ledger disposition documenting the attempted Desktop ordering divergence, removes only the exact `verify:channel-builder-performance` script and guarded Windows CI step, and restores the prior `package.json`/`.github/workflows/ci.yml` content without disturbing unrelated workflow changes. There is no runtime plan ID/body/index state to unwind because those were never in Package 1A's ownership. If rollback is chosen while the checkpoint remains provisional, use a new explicit rollback commit rather than rewriting the preserved provisional SHA.

### Package 1B — safe Plex facet source

**IMPLEMENTER_ROLE_ELIGIBILITY:** `worker`

Import the accepted 1A DTOs and implement the exact main-only item-facet-free snapshot/materialization-index contract, `ChannelBuilderFacetAccessPort`/callback-scoped allowlisted session, the separate narrow `LivePlexChannelBuilderFacetTransport`, fixed typed transport/parser methods, and the single-fetch UUID-bearing catalog seam frozen above. `librarySectionCountEnrichment.ts` owns the record loader; `DesktopPlexLibraryOperationExecutor` owns `listSectionsForMain`; existing safe summary methods delegate without public change. The real `LivePlexTransport` satisfies both the unchanged `LivePlexLibraryTransport` and the new narrow discovery interface. The Package 1B access adapter accepts only the exact separately named `{ facetTransport, itemTransport }` dependency object frozen above: `facetTransport` has the new interface, `itemTransport` has only `Pick<LivePlexLibraryTransport, 'listLibraryItems'>`, and no intersection/combined parameter exists. Package 1B tests discovery with a fake access port and is independently buildable before production privilege wiring. Every non-tag raw Plex facet title passes through the sole 1A helper with `{ fallback: 'Untitled facet', maxUtf16Units: 160 }` before safe snapshot construction and any display-only sample operation. For each tag, 1B first derives unprojected main-only `tagValue`; synchronously invokes the Package 1A typed constructors with validated raw key/tagValue/fastKey-derived filter/runtime-source inputs under the no-retention/value-free-failure rule to obtain the exact source, family-scoped `semanticGroupIdentity`, and director-only `contentFilterIdentity`; derives year-only safe numeric `yearValue`; applies the frozen display-free semantic tuples and all family/global cap admission; and only then independently derives `displayTitle` through that same helper/options call on the original raw title for admitted entries. Raw identity/query/filter work may use `tagValue` but never `displayTitle`; grouping uses only `semanticGroupIdentity`; decade construction uses only `yearValue`; `displayTitle` supplies only the attached label. Package 1B has no second sanitizer and never exposes or retains raw key/value/filter strings outside its main-only acquisition/index/call stack. Keep authentication and transport ownership in main; do not add renderer Plex operations or a generic endpoint.

`channelBuilderFacetSource.test.ts` uses the real `LivePlexTransport` with fake fetch for fixed URL/query proof and focused independently supplied `facetTransport` and `itemTransport` fakes for access/session behavior. Source/type assertions pin the exact two-field dependency object, reject an intersection/combined transport parameter, prove each of the three facet methods touches only the facet fake and item listing touches only the item fake, and prove one fake cannot satisfy or substitute for the other. They also prove the legacy interface key set is unchanged, the real class satisfies both interfaces, no generic method exists, and the out-of-scope `plexRuntimeIpc.test.ts` and `plexLibraryMinimalAdapter.test.ts` mocks require no edits. Unit fixtures prove exact encoded fixed URLs/query sets; the exact recently-added, tv-people-index, and facet-count discriminated item queries including tag-directory movie/show 1/2/4 media-type mapping, fixed recently-added sort, no-filter TV index, and unequal raw-key/raw-title cases. Genre/director/year fixtures prove exact `tagValue` filters derived before display projection; actor/studio fixtures prove valid allowlisted fastKey parsing plus malformed, missing-family, empty-family, credential-key, header-key, and container-key invalidation, exact raw-key fallback, exact `type = mediaType` override, and no `tagValue`/`displayTitle`/digest fallback.

Safe-semantic fixtures prove the exact family/null discriminants; equal case-folded raw semantics across libraries produce equal family-scoped `semanticGroupIdentity`; different families or semantic values do not; `displayTitle` collisions/divergence do not change grouping; director `contentFilterIdentity` recomputes from exact raw equality filters; and year `yearValue` follows exact finite `Number.parseInt(tagValue, 10)` behavior without retaining its input. Materialization fixtures prove per-library director references resolve to exact raw filters only inside `ChannelCreateInput`, inline decade filters remain numeric, source/filter/group digests are never used as runtime values, and missing/wrong-family/mismatched references fail closed. Hostile title fixtures prove facet identity and runtime queries use the unprojected semantic `tagValue`, the safe snapshot contains only the closed independently derived safe projection fields, and display projection occurs only after semantic order and cap admission without altering identity/query/group/filter/year/order/cap bytes. Redaction, truncation, collision, and raw/display-divergence pairs placed on both sides of the family/global capacity boundary prove identical semantic order, admitted facets, downstream candidate identities, and seeds. Constructor call-site fixtures prove validated raw values exist only for the synchronous call and neither they nor a value-bearing failure reaches returned DTOs, retained state, IPC, log, error, or diagnostic. Further fixtures cover rejection of caller sort/filter dictionaries, unknown query keys, path/header/query extension, and invalid media-type/family combinations; Metadata-versus-Directory parsing; totalSize/offset/empty/short-page termination; five-page/global/family caps; malformed payloads; 401/403/network/abort/deadline mapping; session invalidation/no escape; absence of a generic method; `id !== uuid`; one transport/record-loader call; same-record summary/pair derivation; exact sorting; duplicate/missing UUID rejection; existing `listSections` behavior; every audited family/field; absence/rejection of item facets and new manual sources; complete-string credential redaction and innocent URL projection; cross-package helper byte equality; SHA-256 identity stability; partial/blocked/slow projection; context binding; index expiry; cancellation propagation; and absence of UUID/privileged public fields. Playlist and collection fixtures deliberately set `ratingKey !== key` and prove the raw-to-safe locator retains both while the materialized endpoint source uses only `playlistKey = ratingKey` or `collectionKey = ratingKey`; restart recomputation remains identical. Add the Package 1B import-ledger entry covering these audited facet acquisition semantics and the explicit display-free ordering/cap divergence before or with adaptation.

Package 1B is serial after 1A and consumes only its committed domain exports. It does not edit `desktopPlexRuntime.ts`, `plexComposition.ts`, contracts, preload, channel runtime, or renderer files and is independently buildable while the current fallback builder remains active. Production constructor/composition injection of its new narrow interface belongs only to Package 1C.

Checkpoint commit after focused Plex/transport/parser/access-port tests, typecheck, build, redaction verification, architecture/security review, and the Package 1B import-ledger entry: `feat(plex): add safe channel-builder facets`. Rollback removes the unused main facet source, access/session contracts, the exact separately named `facetTransport`/`itemTransport` adapter dependency object, the separate `LivePlexChannelBuilderFacetTransport`, its real-class implementations/request types/parser extractors, `listSectionsForMain`, and the UUID-bearing record-loader export; restores the real class declaration and `loadLibrarySectionsWithCounts`/`listSections` plus transport/parser exports to prior behavior; and leaves the existing `LivePlexLibraryTransport`, its key set, its mocks, the 1A pure domain, and the current fallback runtime intact. It never leaves an intersection/combined transport parameter, generic endpoint, privileged session, second fetch, or UUID in the renderer-safe path.

### Package 1C — atomic cancellable application

**IMPLEMENTER_ROLE_ELIGIBILITY:** `worker`

Serial integration package using the standard `worker` role because
concurrency, abort, restart, and lifecycle ownership are high risk. Create only
the declared `src/__tests__/fixtures/` directory if absent, then implement the
exact public unions/caps, total existing-source projection, single-active
operation owner, frozen `worker_threads` planning boundary, production
`ChannelBuilderFacetAccessPort` callback wiring, authoritative same-call
library-pair catalog commit/clear lifecycle, context epoch owner,
platform-bound channel persistence ready capability, startup-only aggregate
repair owner, split Plex construction/IPC registration, aggregate CAS
mutation/barrier handshake, non-abortable refresh, and legacy behavior frozen
above. The main-only existing-lineup projection validates each runtime source
and persisted content-filter conjunction, passes it transiently to the owning
Package 1A source/content-filter constructor, and retains only the resulting
opaque identities in the raw-free planner DTO; focused tests prove the raw
values and value-bearing failures do not survive the synchronous constructor
call in DTOs, state, logs, diagnostics, or exceptions.

Within existing `src/domain/channelBuilder/persistence.ts`, limit the change to
descriptor-safe persisted-state/provenance validation, empty null-prototype
normalization for an invalid provenance container, marker-local removal,
current-lineup membership filtering including persisted IDs `__proto__`,
`constructor`, and `prototype`, and provenance cloning through the shared
`cloneOwnEnumerableStringRecordWithNullPrototype` helper for startup repair and
the already-frozen aggregate paths. Reuse the existing config normalizer only
for persisted-state validation/recovery. Do not add planner, identity,
config/default, new schema, public DTO, or unrelated persistence policy, and do
not add a file or test outside the existing Package 1C registry.

Correct only the existing architecture-rule builder's representation of Node
builtin restrictions: keep `node:*` and privileged path globs as patterns, but
emit every bare builtin, including `domain`, through exact restricted-import
paths so a relative segment cannot collide. Preserve the existing literal and
computed dynamic-import rejection. Extend only
`build-eslint-architecture-rules.test.mjs` with the focused renderer-boundary
regression: static
`../../domain/channelBuilder/config.js` is allowed, while bare `domain`,
`node:domain`, privileged main/preload/native-helper imports, and literal or
computed forbidden dynamic imports remain rejected. Do not edit
`desktopArchitectureRules.mjs`, add an exception for `builderConfigState.ts`,
weaken a boundary message/pattern, or change product code, defaults, contracts,
or IPC under this verifier correction.

Extend only the existing renderer asset-copy owner so its already-ordered
post-`tsc` invocation copies the exact two-file emitted runtime closure from
`dist/domain/channelBuilder/` into
`dist/renderer/domain/channelBuilder/`. Preserve bytes and relative file names;
create only that exact target chain. The focused copy test pins source/target
SHA-256 equality for both files and proves source maps plus
`index.js`, `planner.js`, `persistence.js`, `facets.js`, and `types.js` are
absent from the target even when present beside the emitted sources. The
already-scoped internal-package test proves the two copied files reach the
matching `resources/app/dist/renderer/domain/channelBuilder/` paths
byte-for-byte and the excluded siblings do not. Do not copy `src/**`, recurse
over `dist/domain`, duplicate config/default literals, change the current build
script/order, widen protocol resolution, alter CSP, or edit protocol/main/package
configuration.

Update the existing `playerOverlayPresentation.test.ts` `channelSummary`
fixture only with the exact required `lineupRevision` and unknown-builder
fields above so it conforms to the already-frozen public summary contract. Do
not change its player/presentation inputs, assertions, behavior, or coverage.

Implement `channelBuilderPlanningWorker.ts` and its fixed compiled entry exactly
as the Package 1C planning process boundary specifies. The operation owner
checks abort/context before job submission and after a successful result;
abort/context invalidation during planning terminates the current Worker,
discards late output, and yields the exact canceled/stale operation result with
no retained body or index. `channelComposition` injects the one planning owner
and includes its idempotent termination in composition teardown. Focused tests
cover success, deterministic byte-for-byte parity with direct
`buildChannelSetupPlan`, abort plus late-result discard, worker error,
unexpected exit, lazy restart, idempotent shutdown, single-flight busy
behavior, fixed compiled entry URL, protocol rejection, and absence of unsafe
diagnostic propagation. Build proof requires the emitted entry, and the
existing internal-package test must prove the complete-dist copy includes the
entry. Do not add a fallback that executes planning synchronously in Electron
main.

In `desktopPlexRuntime.ts`, add only the exact optional
`channelBuilderFacetTransport` option and dedicated nullable field frozen
above; existing `libraryTransport` stays required and unchanged. In
`plexComposition.ts`, pass the same real `LivePlexTransport` explicitly to the
two separately typed named runtime options without intersection, cast, setter,
overload, detection, or fallback.
`DesktopPlexRuntime.withChannelBuilderFacetSession` fails with the exact
nonretryable safe unavailable result before context/auth/connection/callback
work when the new option is omitted; when injected, it closure-captures
token/connection and constructs Package 1B's exact adapter dependencies as
`{ facetTransport: this.channelBuilderFacetTransport, itemTransport:
this.libraryTransport }`, with the latter statically narrowed to the named
`Pick`. Facet methods route only through `facetTransport`, item listing only
through `itemTransport`, and the allowlisted session exists only for callback
lifetime before context-owner revalidation. No public runtime/IPC method
changes. `DesktopPlexRuntime.listLibrarySections` alone bridges Package 1B's
same-result sections/pairs into the existing public snapshot and new private
notification owner; profile/server/load-start/failure clearing is atomic and no
UUID enters public state. New focused
`desktopPlexChannelBuilderFacetRuntime.test.ts` uses distinct facet and
legacy-library fakes to prove the exact two-field dependency
construction/routing, omission/explicit-undefined source compatibility and
zero-work unavailable behavior, callback lifetime, and no fallback.
`plexComposition.test.ts` pins the unchanged production two-option runtime
wiring and absence of a cast/intersection/setter. Full typecheck compiles the
unchanged out-of-scope `plexRuntimeIpc.test.ts` constructor and
`plexLibraryMinimalAdapter.test.ts` old-interface fake without edits. Other
focused integration fixtures cover profile/server/selected-library churn
before/during/after callback, abort/deadline, exact error mapping, session
use-after-settlement rejection, and source inspection/runtime assertions
proving no token/URI/header/session escape or generic method. In the same
checkpoint, remove the public `commit` channel with no shim and migrate the
complete buildable consumer chain. That chain includes
`src/preload/channels.cts`, bridge guards/API, `channelRuntimeState`,
`channelRuntimeActions`, `stagedSetupController`, and `workflow`, plus the
current legacy renderer branch in `src/renderer/index.ts`,
`src/renderer/rendererActionRegistration.ts`, `src/renderer/domBindings.ts`,
`src/renderer/channelSetup/viewModel.ts`, `src/renderer/channelSetup/dom.ts`,
and `src/renderer/focusDom.ts` and their named focused tests.

Before or with the first adaptation of pinned `ChannelSetupBuildCommitter`, `ChannelSetupBuildExecutor`, build-mode, or application semantics, Package 1C adds its own serialized `docs/architecture/import-ledger.md` entry with source pin/path, destination owners, adapted semantics, and verification. Independent reimplementation does not waive this semantic-provenance entry. The checkpoint cannot pass without it.

Removal/rewiring is exact: delete `ChannelCommitActionId` and `readChannelCommitActionId`; delete the `channelCommitButtons` DOM binding/query; delete `RendererActionHandlers.applyChannelCommitAction` and its standalone registration loop; delete the `index.ts` composition handler; delete commit-button labeling/disabled-state and focus registration; and update the action-registration, route-DOM, focus-DOM, runtime-owner, and smoke expectations that currently preserve `[data-channel-commit-action]`. Rewire the existing staged `[data-setup-flow-action="buildConfirm"]` route through a five-operation `reviewAndApply` orchestration: start review, poll it, reject blocked review, start apply, poll terminal state, and project safe status. Build mode remains normalized configuration state. No contract, preload, controller, registration, DOM data attribute, renderer branch, or smoke vocabulary named `commit` remains, and no compatibility shim is introduced.

Package 1C creates `src/renderer/channelSetup/builderConfigState.ts` and its focused test as the minimal renderer config owner required by that staged route. It exports exact immutable `ChannelBuilderConfigState = { config: NormalizedChannelSetupConfig }`, `createChannelBuilderConfigState(context): { ok: true, state } | { ok: false }`, and `readChannelBuilderConfigRequest(state): NormalizedChannelSetupConfig`. Creation delegates to Package 1A `createDefaultChannelSetupConfig`, freezes the returned state, and rejects invalid current `{ serverId, selectedLibraryIds }`; reading returns a deep clone suitable for the exact `startReview` request. The 1C owner has no editable fields, reducer, presentation copy, controller/action policy, persistence, or duplicate defaults. A changed server/library selection creates a new default state; the staged build-confirm route cannot invoke review without an `ok` complete request.

Package 1C also creates `src/main/channel/channelPublicReferenceOwner.ts` and its focused test, then constructs exactly one instance in `channelComposition` and injects it into existing `channelRuntime` and `channelIpc`. Existing `channelRuntime` adds the exact full-aggregate generation loader. This owner implements full-generation channel/library allocation, program-reference projection, imports and calls the sole Package 1A display helper with the frozen field-specific options, projects the current triple, and resolves current-generation tune references in main; it defines no local sanitizer or normalization variant. `channelPublicReferenceOwner.test.ts` reuses the hostile Package 1A vector table and proves byte-equal helper output across packages for every public field and option. `channelIpc` owns the exact three-attempt A/raw-presentation/B consistency sequence and never allocates from or lets a cache override the full generation; tune independently loads the latest full generation and passes only the resolved raw ID to unchanged guide runtime behavior. Existing safe/new builder channel IDs remain byte-identical; unsafe legacy IDs become stable aliases. No overlay, renderer, preload, guide-runtime, persistence-schema, or public-contract file is added for this correction.

The same Package 1C builder runtime constructs its injected `ChannelBuilderChannelIdAllocator`, performs the frozen eight-attempt ledger-ordered allocation before the barrier, and supplies the preallocated-ID closure to an apply-local existing `ChannelAuthoringService`. No edit to `channelAuthoringService.ts` is authorized.

In `channelSetup/viewModel.ts`, delete `ChannelSetupCommitAvailabilityViewModel` and `createChannelSetupCommitAvailability`; delete the workflow's `channelSetupCommitAvailability` field and call; and remove `commitMode`-based progress copy plus the legacy `ChannelRuntimeRendererState.commitMode` branch. Replace them with one minimal `ChannelSetupOperationProgressViewModel` exactly `{ kind: 'idle' | 'review' | 'apply', state: 'idle' | ChannelSetupOperation['state'], phase: ChannelSetupOperation['phase'] | null, progress: { completed, total }, pending, statusText, canCancel }`. The view model derives status text only from the main operation's kind/state/phase/progress, and `workflow` consumes this one field for the staged route; build mode remains config state, not progress state. Package 1C updates the existing `workflow.test.ts` and `routeDom.test.ts` coverage because there is no dedicated view-model test. Both must prove the removed exports/field/copy are absent and the five-operation progress model covers review, apply, canceled, failed, and succeeded states. Package 1D may reopen this file for full config/review presentation, but its committed 1C baseline contains no legacy commit vocabulary and is independently buildable.

Package 1C also replaces the current view-only cancellation with genuine operation cancellation. `src/renderer/staticDom.ts`, `stagedSetupController`, `workflow`, and the exact tests `workflow.test.ts`, `routeDom.test.ts`, and `plexRuntime.test.ts` are part of this atomic rewrite. While review or apply is still before the persistence barrier, the visible action is labeled exactly `Cancel build` and dispatches the public `channelSetup.cancel({ requestId, operationId })` for the currently polled operation. An accepted cancellation immediately projects the pending label `Canceling…`, continues polling that same operation, and transitions to the canceled result only when main reports terminal `canceled`. Back, Escape, window close, and route changes may hide or leave the view, but they neither call cancellation nor report a canceled operation.

Once main returns `reason: 'commit-started'` or the polled apply reaches phase `persist`/`refresh-guide`, the cancel action is removed from focus and disabled or hidden, and the progress status reads exactly `Saving channels—cancel is no longer available.` A late cancellation response must not project cancellation, reopen review, or conceal committed progress. Remove the literal `Cancel build view`, `cancelCommitView`, and every test that treats view invalidation as operation cancellation. Focus and DOM tests prove the real control is reachable only while `canCancel`, accepted → `Canceling…` → canceled is driven by main states, commit-started makes the action unavailable with the exact copy, and Back/close never falsely claims cancellation.

Package 1C extracts all Channel Builder smoke source/assertion logic from `src/main/smokeAssertions.ts` into new `src/main/smokeChannelBuilderAssertions.ts`. The extracted owner requires exactly `getStatus`, `startReview`, `startApply`, `getOperation`, and `cancel`; requires the real `[data-setup-flow-action="buildConfirm"]` entry into the minimal five-operation route; asserts `[data-channel-commit-action]` and legacy `commit` absent; and owns no production builder state. Remove the legacy commit container/button bookkeeping and `channelCommitActionCount === 3` diagnostics. `smokeAssertions.ts` only composes/invokes this focused owner and remains below its 554-line baseline; the extracted owner remains at or below 220 lines. `smokeChannelBuilderAssertions.test.ts` pins the exact bridge/route/vocabulary contract and `smokeAssertions` orchestration test proves delegation without duplicated builder logic.

Package 1C establishes one process-wide Electron owner before any persistence read, application composition, IPC registration, or BrowserWindow construction. New `src/main/singleInstanceOwner.ts` is the sole owner of `app.requestSingleInstanceLock()`, the `second-instance` listener, and lock-lifetime teardown. `src/main/index.ts` requests the lock once after smoke-capability validation and, on a true result, immediately chooses the exact disk-bootstrap or valid-smoke-bypass branch before constructing feature controllers or entering Plex/channel composition. A false result calls `app.quit()`, returns from startup with a non-primary disposition, performs no directory bootstrap or persistence read, registers no IPC/protocol handler/listener beyond Electron's required pre-ready scheme declaration, and creates no window or feature composition. The primary process holds the lock until quit. Its `second-instance` handler only restores, shows, and focuses the existing shell window when available; it never creates another window, reruns bootstrap/composition, or rereads persistence. Production, development, and smoke all traverse this owner; smoke's isolated user-data root is not a lock bypass and does not weaken the production default-user-data single-instance rule. `singleInstanceOwner.test.ts`, `channelPersistenceBootstrapOwner.test.ts`, `channelPersistenceStartupOwner.test.ts`, `plexComposition.test.ts`, `channelComposition.test.ts`, and `index.ts` source-order assertions prove smoke validation → lock → disk-bootstrap-or-smoke-bypass → Plex construction without IPC → channel startup load/repair → channel composition → Plex IPC → channel IPC → remaining IPC/app/window ordering, false-result no-bootstrap/no-start behavior, repair failure no-registration/no-window behavior, focus-only second-instance handling, one acquisition, and lock retention through quit.

The 1C Electron smoke is deterministic, capability-gated, fail-closed, and isolated:

- `tools/smoke-electron.mjs` obtains the canonical OS temporary root, creates a unique child with `mkdtemp`, obtains its canonical real path, and generates a cryptographically random 32-byte lowercase-hex nonce. Inside that unique canonical child it exclusively creates the exact regular file `.lineup-desktop-smoke-sentinel` with exact JSON content `{ "mode": "lineup-desktop-smoke-v1", "nonce": "<nonce>" }`. Under `posix-0600` it creates/chmods the sentinel to `0o600` and verifies exact mode; under `windows-inherited-userdata-acl` it uses an exclusive regular-file create with no chmod or numeric mode-equality check and records the root/sentinel ACL result required by the Windows proof below. It launches Electron with both `--user-data-dir=<canonical-root>` and the dedicated `--lineup-smoke-root=<canonical-root>` argument plus `LINEUP_DESKTOP_SMOKE=1`, `LINEUP_DESKTOP_SMOKE_NONCE=<nonce>`, and production `NODE_ENV`. Cleanup recursively removes that one validated child on normal success, nonzero exit, spawn error, and handled signal before returning final status; it never accepts, deletes, reuses, or falls back to the OS temporary root itself or normal Electron user data.
- New `src/main/smokeBootstrapOwner.ts` synchronously parses all smoke markers before `requestSingleInstanceLock`, controller construction, `app.whenReady`, persistence access, IPC registration, channel composition, or window creation. If any smoke marker is present, smoke mode is granted only when the dedicated argument root, `--user-data-dir` root, and canonical `app.getPath('userData')` are the same canonical path; that path is a unique nonce-bound strict child of canonical `os.tmpdir()` and is not the separately derived normal user-data path `path.resolve(realpath(app.getPath('appData')), app.getName())`; neither the root, sentinel, nor any component below the temporary root is a symbolic link; and the sentinel is the exclusively created regular file with the exact mode string and nonce while the environment nonce matches `/^[a-f0-9]{64}$/u`. Under `posix-0600`, validation additionally requires sentinel mode exactly `0o600`. Under `windows-inherited-userdata-acl`, validation performs no chmod or numeric mode comparison; it requires the same canonical root/nonce/identity/type guarantees, and packaged Windows proof separately records the inherited ACL. Root equality uses canonical real paths and separator-boundary containment, not string prefixes.
- `LINEUP_DESKTOP_SMOKE=1` alone is never authority. Any environment-only, argument-only, missing-root, missing-sentinel, malformed-sentinel, nonce-missing/mismatch, symlinked root/sentinel/component, root outside the OS temporary directory, root equal to the normal canonical user-data directory, or POSIX sentinel mode mismatch fails startup nonzero before the single-instance owner or any persistence/composition/IPC/window startup. Windows has no numeric-mode rejection branch. With no smoke marker at all, normal production/development startup remains unchanged.
- After a valid grant and successful single-instance lock, `src/main/index.ts` receives the returned smoke capability rather than rereading environment state. It takes the explicit in-memory branch, never calls `channelPersistenceBootstrapOwner`, never resolves a channel persistence path/parent, and injects the main-only `channelBuilderSmokeFixture` into `registerChannelComposition`; no renderer/preload fixture switch exists. Production and development cannot construct or fall back to it.
- `src/main/channel/channelBuilderSmokeFixture.ts` supplies deterministic safe context, facet, clock/seed, existing-lineup, and materialization inputs plus a smoke-only in-memory `ChannelPersistenceStoragePort` backed by one in-memory aggregate. Smoke channel composition must use that injected port and must not construct `DesktopChannelPersistenceStore` or resolve/read/write a channel persistence path. The sentinel is the only smoke-capability filesystem surface; after validation, the channel builder performs no filesystem or network I/O and cannot read or mutate normal user state. The fixture contains no token, path, endpoint, URI, header, raw Plex payload, real account/server/library/media identity, or privileged field, never crosses renderer/preload, and does not alter the public five-operation contract.
- Smoke `buildConfirm` performs `startReview` → poll to review-ready → `startApply` → poll to terminal success and proves a committed in-memory result, guide-refresh finalization, the exact five-method bridge, and absence of legacy commit vocabulary.
- `smokeBootstrapOwner.test.ts` proves valid capability derivation and every fail-closed negative case above, including environment-only smoke, missing/mismatched roots, normal-user-data roots, symlinked root/component/sentinel, missing/mismatched nonce, POSIX mode mismatch, and asserts that single-instance acquisition, disk directory bootstrap, persistence reads, composition, IPC registration, and window creation never start on failure. `channelBuilderSmokeFixture.test.ts` proves deterministic non-empty output, in-memory aggregate commit/nonmutation behavior, safe-field/redaction constraints, and selection only from a validated capability; `channelPersistenceBootstrapOwner.test.ts` and `channelComposition.test.ts` prove valid smoke never resolves/creates a channel parent or constructs the disk store, while production/development require the ready capability and cannot fall back to memory; `tools/__tests__/smoke-electron.test.mjs` proves canonical unique arguments, random nonce/sentinel creation, POSIX-only chmod/mode enforcement, Windows no-chmod/no-mode branch, and safe cleanup on success, nonzero exit, spawn error, and signal.

Package 1D adds the full configuration/review UI by reopening and extending this already-committed config owner in place; it does not move, replace, or interpose a second config/controller owner. Package 1C must already pass its focused tests, typecheck, Electron build, and Electron smoke run and keep the existing staged route functional against the five-operation contract using a complete 1A-defaulted request. It may not rely on a 1D or 1E file state.

Tests must cover:

- all five IPC channels and request/result discriminants, exhaustive config fields/defaults/caps, warning/apply-summary shapes including the exact `EXISTING_SOURCE_UNMATCHABLE` phase/null/count-only record and renderer copy, the exact review-diff DTO and mode normalization, unknown-key/size validation, request-ID/operation-ID separation, forbidden-field rejection, every valid phase-local progress value, every phase's cancel/fail terminal normalization including unknown-total discovery, monotonic-within-phase progress, and `updatedAtMs` advancement;
- canonicalJsonV1 byte rules plus literal golden binding/facet/tag-group/content-filter/source/candidate/candidate-ID/plan-identity vectors; ordinary numeric-like object keys serialize by Unicode code-point order with exact `"10"` before `"2"` bytes, never engine integer-index order; finite fractional/exponent/`Number.MAX_VALUE`/`-0` emission and all three non-finite rejections; arbitrary non-forbidden library-filter keys/values, NFC-equivalent raw-key multiplicity, exact-key preservation, and outer-object exactness; direct validated-raw typed-constructor calls with opaque-only return, fixed value-free failure, and no raw retention in DTOs/state/logs/diagnostics/exceptions; exact helper vectors for `Authorization: Bearer secret`, bare Bearer, token assignment, singular/plural/mixed-case header markers, innocent URL-only, controls, angles, astral and surrogate-boundary truncation, proving complete-string credential redaction with no suffix; Package 1B non-tag-title projection before display-only sample operations, raw-main-only `tagValue` derivation and typed-constructor calls before safe projection, exact safe group/filter/year projection, exact display-free semantic ordering and cap admission before tag-`displayTitle` projection with `Untitled facet`/160 options, capacity-boundary redaction/truncation/collision/divergence fixtures, runtime-query use only of raw main-only values, grouping/filter equality/year construction only of their owning safe fields, label use only of `displayTitle`, and cross-package helper byte equality; `src/__tests__/domain/channelPersistence.test.ts` fixtures for library-filter keys `__proto__`, `constructor`, and `prototype` alone and together through repository normalization, startup repair, append/merge, serialization, the first and repeated `cloneChannelForOwnership`/`cloneContentSource` ownership clones, identity, and restart with exact own enumerable entries, null prototype after every clone, and no global/`Object.prototype` pollution; separate provenance fixtures use persisted channel IDs exactly equal to each of those three names alone and together and prove exact own-property descriptor validation, null-prototype construction, valid-marker survival, invalid-marker-local removal, inherited/accessor/symbol/non-enumerable/container rejection to an empty null-prototype record without channel loss, append/merge/update/delete/repeated ownership clone, JSON serialization, startup repair, and restart round trip without prototype pollution; exact current Plex field mapping including playlist/collection `ratingKey !== key` locator/linkage/materialization/restart behavior; opaque ID issuance/collision exhaustion; restart stability, plan self-exclusion, and digest-collision tuple inequality;
- the exact planner input including the matchable/retained-unmatchable existing-lineup discriminated union, raw-filter-free `contentFilterIdentity`, and null rules; complete recursive source-reference trees for matchable rows; order-preserving existing `manual.items` and sequential/interleave `mixed.sources`; reversed-order non-equivalence; explicit absence/rejection of item facets, item-facet identities/index entries, and all new manual/manual-child candidate production without losing existing manual-source matching; lineage-bound shared identity normalization; exact `contentFilterPlan` union validation and candidate-identity use of only its digest; valid-marker-only one-to-one duplicate matching; retained-unmatchable never-match behavior; malformed/legacy/different-lineage rejection; same-key cross-server non-match; one original-order existing-ledger row per persisted channel; unequal raw/group/display vectors across genre/director/actor/studio grouping, director reference materialization, and numeric-only decade derivation; the exact seven-code deeply immutable facet-warning array; `omittedMalformedCount` validation and the exact `omittedCappedCount` zero/positive/null states across single- and multi-library/family cap fixtures, unknown remainders, exact aggregate over 50,000, malformed values, and proof that no extra page is fetched merely to count; identity/golden/determinism participation for all three cap states; exact aggregate-to-CB-21 discovery-warning conversion and numeric/null dedup behavior; exact count-only `EXISTING_SOURCE_UNMATCHABLE` warning/copy; and pure `PLAN_EMPTY` blocked/empty-apply-ID-arrays/no-apply-capable-pure-output behavior without a runtime plan-ID assertion;
- Package 1C public `planId: null`, no reviewed body/index retention, and `startApply` rejection for every append/merge/replace `PLAN_EMPTY` review plus a byte-identical persisted lineup and unchanged revision in each mode;
- the 1C minimal builder-config state delegates to the 1A factory, contains one complete exact default request, deep-clones on read, reinitializes on server/library context change, rejects invalid context, contains no duplicated literal/editable reducer/presentation/controller policy, and drives the staged build-confirm call without a 1D owner;
- `src/preload/channels.cts`, `src/contracts/ipc.ts`, the preload bridge, and vocabulary tests contain the same five channels and no commit constant/method;
- minimal renderer `reviewAndApply`, exact review-diff projection/validation, state projection, poll/terminal/error paths, real `Cancel build` dispatch and accepted → `Canceling…` → canceled lifecycle, exact commit-started copy/control removal, Back/close non-cancellation, staged-route call site, exact removal/rewiring of the legacy commit-button branch across the named renderer owners, and absence of a commit shim or `[data-channel-commit-action]`;
- smoke assertions require exactly the five channelSetup methods, exercise the minimal staged build-confirm route, and reject the legacy `commit` method, three-button requirement, selector, fields, and diagnostics;
- single-active busy-before-plan-lookup behavior including busy overriding missing/expired/used plans; the complete invoke precedence; four available bodies, sixteen consumed records, exact idle seventeenth-record `CHANNEL_BUSY`/`consumed-plan-capacity` message/flags/operation with the available plan/index retained, distinct active-operation copy, consumed-ID precedence, consumed → available/expiry/capacity → tombstone → not-found plan lookup when idle, operation lookup precedence, repeated-request non-idempotency, accepted-async terminal failure versus preaccept invoke failure, and stable retained CB-21/CB-25 results;
- legacy v1 migration without inferred completion or inferred channel provenance;
- invalid nested builder-state/revision repair without lineup loss, including marker-local repair for malformed, unknown-version, missing-channel, source-mismatched, recomputation-mismatched, cross-lineage, and retained-unmatchable provenance; plus legacy persisted cases with arbitrary non-forbidden filter keys, fractional/exponent/maximum-finite values, and distinct NFC-equivalent raw keys proving normal matchable projection; hostile current-valid existing IDs/names over 512 units, with C0/C1 controls, astral/surrogate edges, NFC-equivalent raw-distinct spellings, URLs, credential assignments, and angle text proving exact raw main-ledger retention, lossless `PersistedStringV1` identity, one row per persisted input, disposition independence from ID/name safety, restart stability, and no omission; and current-valid retained-unmatchable fixtures covering over-512/control-bearing source identifiers/keys, positive finite integers outside the safe range, manual/mixed arrays or total leaves above 500, source depth 9–25, and any other typed-constructor rejection, proving original ledger position, exact raw-source retention, warning count, append/merge byte preservation, confirmed successful replace removal, PLAN_EMPTY/failed/canceled/conflicted non-removal, stable restart disposition, marker drop, and no channel omission;
- the frozen legacy-reader fixture/procedure and older-reader rewrite;
- builder/custom/current-channel aggregate mutation, required unforgeable channel-parent ready capability, CAS conflict, metadata preservation, exact revision increments, and tune/apply interleavings;
- deterministic plan/context/revision revalidation;
- append, replace, and merge application, including complete non-manual composite-child resolution; exact ready `ChannelCreateInput` own-key projection with five required keys, contentFilters present only after valid inline numeric or main-index director-reference resolution, conditional seven direct generated optionals, permanent `number`/all-other-optional omission, and rejection of extra/missing/present-null/raw/digest/wrong-family/mismatched keys or values; every exhaustive materialization row and every non-materialization `(code, operation, source)` expansion—including exact `channel-id-allocation` and `consumed-plan-capacity` copy/flags—with rejection of extra or altered tuples; ordinal-over-settlement-time precedence and abort/no-write behavior; canceled non-error projection; all-unavailable replace rejection; mixed-success replace commit; explicit append/merge zero-new-success metadata behavior; post-materialization committed-lineup summary equations; per-strategy reconciliation; mode-specific identity retention/removal; restart-stable versioned provenance; exact configured/channel-number capacity and `reachedMaxChannels`; append/merge hole filling, replace numbering from 1, materialization skips consuming no number, 500-number boundary; and the injected allocator across append/merge/replace, matched merge ID retention, invalid output, repeated collision then success, eight-collision exhaustion, every-`B` occupied reservation even in replace, proposed/`F` uniqueness, safe watch ID, byte-identical failure, and no barrier/write/refresh/summary;
- merge candidate/existing ledger mapping, deterministic serial mixed retained/new processing against the evolving set, exact retained-ID update field replacement/removal and metadata preservation, matched `id`/`number`/`createdAt` retention, lowest-unused create numbering independent of promise settlement, matched-failure pre-barrier abort, new-candidate skip continuation, and unchanged-by-ID accounting;
- replace confirmation;
- Package 1B fake-access-port discovery plus exact allowlisted session shape/lifetime, exact separately named `{ facetTransport, itemTransport }` adapter dependencies with no intersection/combined parameter, three facet methods proven to use only the facet dependency and item listing proven to use only the narrow-`Pick` item dependency, fixed encoded collection/playlist/tag/item transport requests, closed request/query/header/path rules, Metadata/Directory parsers, totalSize/offset/five-page/cap termination, malformed/auth/network/abort/deadline mappings, and no generic method; UUID-bearing record loader and `listSectionsForMain` with `id !== uuid`, exactly one transport/loader call, safe sections and pairs derived from the same records, lexical pair sorting, duplicate ID/pair and missing/empty UUID rejection, existing delegate behavior, independent build, and no UUID public leak; Package 1C's exact optional `channelBuilderFacetTransport` constructor seam, null default, unchanged explicit production two-name runtime composition wiring, omitted/explicit-undefined source compatibility, exact construction of the Package 1B two-field adapter dependencies, no intersection/cast/setter/detection/fallback, exact nonretryable safe unavailable result before any context/auth/connection/callback/legacy-library work, distinct facet-versus-item transport routing, callback-scoped privilege acquisition with pre/post selected-context validation, relevant-notification abort, token/connection closure capture, session invalidation, exact safe throw/result mappings, and no token/URI/header/session escape; unchanged out-of-scope `plexRuntimeIpc.test.ts` and `plexLibraryMinimalAdapter.test.ts` compiling without edits; same-call atomic public-sections/private-pairs commit, null-before-initialization, libraries-unavailable without an authoritative current catalog, and pair clearing on profile/server change plus load start/failure with no stale UUID; exact main-only Plex builder-context getter/result-error-null union, immutable snapshot and initial/changed listener payloads, monotonic revisions, synchronous initial callback, isolated listener failure, idempotent unsubscribe, selected-pair derivation, and secret absence; profile/server changes invalidating all retained plans; library changes independently invalidating multiple retained plans only for removed/changed selected ID→UUID pairs while additions/unselected changes remain irrelevant; monotonic context epoch, exact startReview/startApply rederivation, pre-commit abort/disposal, and process restart behavior;
- cancellation during asynchronous discovery, Worker planning, and materialization with no write or guide refresh; pre-job abort/selected-context checks that submit no planning job; exact direct-planner parity; abort termination and late-message discard with no retained plan body/index while an unselected-library addition remains non-invalidating; fixed safe error/exit mapping, fresh-worker restart, single-flight busy behavior, idempotent shutdown, composition cleanup, fixed compiled entry resolution, closed protocol/no unsafe diagnostic propagation, emitted/package entry proof, and post-result stale/canceled terminal projection; repeated cancel during observable `canceling` and terminal `canceled` returning accepted/null with exactly one abort/dispose/transition sequence; other-terminal and commit-started exact responses; and the named isolated `npm run verify:channel-builder-performance` Windows Node 22.19 route executing the unchanged exact 50,000-candidate fixture without contention at the asserted exact A1 head SHA that passes ordinary Windows Verify, with an above-2,000-ms result preserved as `WS1-PERF-01` rather than hidden or used to block functional WS1 work;
- exact bootstrap owner/capability/file-protection policy, absent-parent creation, wrong-parent/symlink/non-directory/canonical-mismatch/failure rejection, smoke no-resolve/no-create bypass, and startup source order; complete absence of operation/store `mkdir` and ordinary-read repair/migration writes; exact POSIX destination/temp open flags with `O_NOFOLLOW`; exact Windows destination/temp flags without `O_NOFOLLOW`, no chmod/numeric mode, and handle identity/type validation before destination read; every shared destination guard and temp-handle identity/type/collision/cleanup/sync/close/rename behavior; POSIX-only `0o600` create/chmod/handle-mode/path-mode enforcement; injected 128-bit suffix/eight-attempt collision behavior; every named barrier race; existing-destination read-only open/handle-stat/read/close before a cancel callback followed by zero temporary/exclusive/create/write-capable opens and zero filesystem mutations; missing-destination cancel with optional no-read-handle behavior; absent-parent bootstrap then cancel under the same exact read-versus-write contract; deleted-after-bootstrap no-recreation failure; post-start invalid state no-repair failure; rejection/no-op after proceed; byte-identical destination/aggregate/revision and unchanged guide; matching-identity-only cleanup; mismatch-no-unlink with redacted warning; no destination chmod; and successful rename as the commit boundary, within the explicitly bounded app-owned-directory/single-instance/non-hostile-same-user threat model;
- startup repair ownership over one mutation-chain read and at most one full-file atomic repair write, jointly normalizing lineup/current pointers/builder state/revision/provenance; missing-file normalized empty/no-write; corrupt/unsupported/read/repair-write redacted failure with byte preservation and no composition/IPC/window; `ChannelPersistenceCoordinator.load()` and ordinary store/repository reads performing no repair; Plex composition construction with no handlers, exactly-once later Plex registration, duplicate rejection, and exactly-once shutdown/handler removal;
- non-abortable refresh success/failure and one-time immutable result finalization: success omits `GUIDE_REFRESH_FAILED`, failure includes exactly the frozen safe record, and repeated polls return the retained final summary;
- exact `loadPublicReferenceGeneration` one-aggregate tuple/fingerprint behavior; full-generation allocation before status/Guide subsets; hidden safe-ID reservation; status-first/Guide-first byte equality; cache non-override; imported sole credential predicate with `token-secret`, `Bearer-secret`, `authorization-secret`, and header variants aliasing while `mytoken` passes through under the exact boundary rule; hostile overlength/control-bearing channel/library IDs and labels; byte-equal cross-package output from the shared Package 1A display-helper vector table with no local sanitizer/predicate duplicate; fractional finite `itemCount`; injected channel/library digest collisions and safe-alias retries through attempt 500; duplicate-channel-ID corruption; current triple consistency; A/presentation/B success, one/two transient mismatch retries, three-attempt stale exhaustion with exact error, hidden/missing/mismatched Guide references, and no mixed generation;
- total program projection with a 120-character safe channel ID, repeated byte-equal base tuples and occurrence numbering, canonical tuple/digest golden vectors, injected unequal-tuple digest collisions and ordinal order, duplicate-final-ref rejection, invalid tuple, exact 50,000 success and 50,001 whole-presentation failure; every hostile Guide channel/program/now-watching display field through NFC/control/whitespace/angle/URL/assignment redaction and surrogate-safe 2,000/160-unit limits; quality/genre order and first-20 cap; and preload-safe validation proving no raw URL, authorization/token/header phrase, angle bracket, overflow, or omitted-program fallback crosses the bridge;
- tune latest-generation reload and raw-ID delegation, stale/unknown validation, mutation/deletion/runtime failure between resolution and call mapping only to exact `GUIDE_TUNE_FAILED`, fixed diagnostics with no raw legacy ID, 500-row deterministic restart, and no persistence mutation, row drop, renderer/preload/guide-runtime edit, or call-order dependence;
- startup smoke-validation → single-instance → disk-bootstrap-or-smoke-bypass → Plex construction without IPC → channel startup load/repair → channel composition → Plex IPC → channel IPC → remaining IPC/app/window ordering, fixed redacted bootstrap/repair failure with no reachable handler or window, secondary no-bootstrap/no-start behavior, focus-only handling, and lock lifetime in every mode;
- the smoke capability validator, smoke-only in-memory persistence/fixture/composition/launcher seam, deterministic safe review/apply, environment-only and every named negative rejection before startup, production/development exclusion, canonical unique nonce-bound temporary roots, sentinel identity/type and symlink checks, POSIX sentinel `0o600`, Windows no-chmod/no-mode branch plus separately recorded ACL proof, cleanup on every child termination path, normal-user-state isolation, and redaction;
- preload validation and vocabulary.

No full renderer UI package begins until this atomic migration passes focused contract/domain/main/preload/renderer tests, typecheck, build, `npm run smoke:electron`, redaction, architecture, maintainability verification, independent repository/smoke hotspot cohesion review, and the serialized Package 1C import-ledger entry. The checkpoint records `channelRepository.ts <= 769`, `smokeAssertions.ts < 554`, and `smokeChannelBuilderAssertions.ts <= 220` from observed line counts. The 1C checkpoint is independently buildable and smokeable and cannot depend on any 1D/1E result, recovery, or route extension. Checkpoint commit: `feat(channels): add atomic cancellable builder apply`.

Rollback removes the new public methods/runtime plan-ID/body/index projection, the `ChannelRuntime.loadPublicReferenceGeneration` seam, `channelPublicReferenceOwner.ts`, its import/use of the sole Package 1A display helper and credential predicate, and its channel/library/program projection plus focused test/wiring, `DesktopPlexRuntime.withChannelBuilderFacetSession`, the optional `channelBuilderFacetTransport` option/dedicated field/unavailable sentinel, the explicit second production composition argument, `desktopPlexChannelBuilderFacetRuntime.test.ts`, and the context-owner production access adapter, plus the same-call public-sections/private-library-pairs runtime commit and clear lifecycle, the three-attempt Guide consistency/tune failure mapping, the injected builder channel-ID allocator, the runtime-local validated-update/owned-clone/delete projection, the final number-sort/Watch derivation, canceling lifecycle, runtime wiring, minimal `builderConfigState.ts`/focused test, extracted smoke owner, `channelPersistenceBootstrapOwner.ts`, `channelPersistenceStartupOwner.ts`, their focused tests, and ready-capability/policy-specific open/store wiring together at the Package 1C boundary; it aborts/invalidates any active session, clears captured privileged closures/private pair catalogs, restores the pre-WS1 disk-store constructor/directory behavior, `ChannelPersistenceCoordinator.load()` behavior, and single-phase Plex composition API in the same rollback commit before restoring old startup composition. It must not leave a privileged callback seam without its context owner, a stale token/connection/session/UUID catalog, predicate duplicate, public UUID field, second option without a consumer, or implicit fallback from `libraryTransport`. Rollback must remove the matched-update deletion path and number-sorted final-order behavior together with the builder runtime; it must not leave either partially active, and it never edits or rolls back `channelAuthoringService.ts`. No Package 1C-local display sanitizer may remain after rollback. The shared null-prototype helper correction in existing `channelDomainClone.ts`, both library-filter and provenance call sites, repository/startup/CAS ownership rules, and their `channelPersistence.test.ts`/`channelPersistenceAdapter.test.ts` coverage roll back only if the entire Package 1C contract rolls back; none may be left half-applied, and no rollback conversion may copy magic-key provenance through a normal `{}`. It must restore prior status/guide/tune wiring as one unit and must not leave projected aliases/program IDs accepted without generation validation/resolution, builder-authored IDs without the allocator, mixed POSIX/Windows flag branches, both old read-trigger repair and the startup repair owner active, split Plex construction with old callers, or a public null-plan/cancel response contract without its owning runtime. It never deletes the app-owned persistence parent created by bootstrap, a channel file, or an unmatched temp file. It updates the 1C ledger entry with the rollback disposition rather than erasing semantic provenance. Persisted v1 channels—including channels with IDs `__proto__`, `constructor`, and `prototype`—remain readable; public aliases/program references were never persisted; only additive builder metadata may be ignored or later dropped by the old binary, causing setup to become unknown rather than losing channels.

The Package 1C rollback boundary explicitly includes the persisted-state and
provenance validator, normalizer, current-lineup membership filter, and
shared-clone integration in existing
`src/domain/channelBuilder/persistence.ts`, proved through the already-declared
domain, adapter, and startup-repair tests. It rolls back only with the complete
Package 1C persistence/provenance contract; no half-applied normal-object copy,
startup repair path, or magic-key marker conversion may remain.

The two architecture-verifier files roll back together with their exact
builtin-path representation and focused regression. A rollback must not leave
bare `domain` as a glob collision while the Package 1C renderer delegates to
the Package 1A default owner, and it must not preserve an allowlist exception
or weakened Node/privileged/dynamic-import ban. Full Package 1C rollback
restores the prior renderer path together with the verifier behavior; no
standalone architecture-policy divergence survives.

The asset-copy owner, its focused test, and the already-scoped package-test
assertions roll back together; a clean rebuild removes the generated
`dist/renderer/domain/channelBuilder/config.js` and `constants.js` artifacts.
Rollback never compensates by widening the protocol root, adding a fallback,
retaining copied source/sibling artifacts, or changing CSP/package
configuration. Full Package 1C rollback also restores the renderer path that
required this closure, leaving the pre-1C renderer-only protocol boundary
intact.

The two `playerOverlayPresentation.test.ts` fixture fields roll back only with
the public Channel Setup summary contract that requires them. No
player/presentation expectation or behavior participates in that rollback.

### Package 1D — configuration and review UI

**IMPLEMENTER_ROLE_ELIGIBILITY:** `worker`

Begin only after 1C's minimal five-operation consumer and config state are committed. Reopen `channelRuntimeState`, `channelRuntimeActions`, `stagedSetupController`, and `workflow`, extend the existing `channelSetup/viewModel` and `channelSetup/dom` owners, and extend the existing `builderConfigState.ts`/test in place with pure normalized editable form state. Implement restored configuration, all strategy/scope/priority/maximum-channel/minimum-item/mode controls, warning/cap presentation, deterministic review counts, blocked/slow states, replace confirmation, keyboard/D-pad/mouse/gamepad interaction, text-entry shortcut bypass, focus ownership/restoration, reduced motion, forced colors, high contrast, zoom, and responsive layout. The 1A default/normalization owner remains the only literal/default authority; there is no interim controller/action policy and no later file move. Add the Package 1D import-ledger entry before or with the UI adaptation.

The renderer polls operation state; it does not simulate progress or cancellation. No visible control may ship unless it invokes a real reviewed contract and has focused behavior coverage.

Checkpoint commit after focused renderer tests, typecheck, build, architecture, and maintainability verification: `feat(renderer): add channel builder config review`. Rollback restores the prior staged setup UI while leaving the main contract dormant and persisted data compatible.

### Package 1E — result, recovery, and onboarding integration

**IMPLEMENTER_ROLE_ELIGIBILITY:** `worker`

Serial after 1D because it reopens shared renderer composition owners. Complete first-run routing, prior-config restore, review-to-progress-to-result transitions, committed counts/warnings, cancellation result, retry/review-again behavior, safe recovery messages, Watch handoff, restart behavior, and renderer/main shutdown cleanup. Composition roots receive wiring/lifecycle changes only.

Package 1E may reopen `src/main/smokeChannelBuilderAssertions.ts` for focused result/recovery assertions and `src/main/smokeAssertions.ts` only for orchestration wiring. It must preserve the exact five-method bridge, hotspot caps, and absence of legacy `commit`/`[data-channel-commit-action]` vocabulary; it does not supply any behavior required for the 1C checkpoint.

Checkpoint commit after focused renderer/runtime/smoke tests, typecheck, build, redaction, architecture, and maintainability verification: `feat(renderer): complete builder result recovery`. Rollback returns routing to the prior setup state without deleting channels or builder metadata.

### Package 1F — integrated proof and authority refresh

**IMPLEMENTER_ROLE_ELIGIBILITY:** `worker`

At Package 1F opening, reread `docs/development/windows-ui-proof-plan.md`. Its current opening says Packages 0–8 are complete and RD-27 is next; once WS1 evidence changes authority, that preamble is stale. Update it before recording WS1 proof conclusions while preserving its redaction and Package 6 blocking rules.

Package 1F must create fresh current-upstream and Desktop visual proof for `UI-17`, `UI-18`, `UI-19`, `UI-21`, `UI-22`, `UI-23`, and `UI-24`. The old 138-capture bundle and source inspection alone are explicitly insufficient. After Package 1E is committed and immediately before capture preflight, Package 1F recomputes each Desktop row's transitive product-source closure from the mapped entry owners by following static imports and recording every direct runtime product-file read used to render that state. The table below is the frozen minimum seed list, not permission to omit a discovered owner. A reviewer must approve the resulting row-scoped closure; if another renderer/controller/DOM/style owner influences a mapped state, capture stops and this mapping plus the evidence contract are amended through review before proceeding. Every resulting source is tracked in that row's manifest and must pass blob, SHA-256, and scoped-clean proof. Before capture collection starts, `verify.mjs` resolves the upstream root from nonempty absolute `LINEUP_WS1_UPSTREAM_ROOT` when set, otherwise from the `Lineup` sibling of the resolved Desktop root; it rejects missing, relative, symlinked, non-directory, non-Git, wrong-top-level, or wrong-pinned-HEAD roots with fixed path-free failures and never logs or records the root. The operator launches `capture.mjs` with an explicit `--wait-ms` value from 1 through 3,600,000; collector launch fixes the session start, completes source preflight, then waits for the operator to generate every approved upstream and Desktop PNG during that same bounded process. A PNG whose mtime predates collector launch remains rejected. After all captures arrive, the collector rechecks source identity and Desktop `HEAD` before publication. Dirty, untracked, replaced, hash-mismatched, prior-session, or unavailable source/capture state blocks collection and keeps the rows open. Raw PNGs remain ignored under local `captures/upstream/` and `captures/desktop/` directories.

The tracked safe harness source and checklist template exist after checkout at the declared `docs/runs/2026-07-22-tier3-parity-correction/channel-builder/` path. Before writing local evidence, Package 1F validates that exact repository-root ancestry and may create only the declared ignored output children/files within it. Manifest publication writes collision-resistant `.cb-manifest-*.tmp` files in that validated evidence directory and renames them in place, so publication does not cross filesystem volumes; success and failure clean every owned transient, and an existing manifest prevents overwrite. The transient pattern remains ignored. The operation must reject symlink/non-directory components; it does not authorize another run directory, another tracked artifact, or any undeclared output.

The two ignored safe output manifests are exact. For both, `evidenceSessionId` matches `/^cb-evidence-[a-f0-9]{32}$/u`; every `capturedAtUtc`/`observedAtUtc` is exact UTC `YYYY-MM-DDTHH:mm:ss.sssZ`; every commit/Git blob is 40 lowercase hex; every SHA-256 is 64 lowercase hex; every state/capture/scenario/package ID matches `/^[A-Za-z0-9._-]{1,120}$/u`; and every path is a non-empty repository-relative POSIX path with no leading slash, backslash, or empty/`.`/`..` segment. Arrays contain unique values/records and appear in the frozen table order or the reviewed source-closure order as applicable. Each `rows` object has exactly the insertion-ordered keys `UI-17`, `UI-18`, `UI-19`, `UI-21`, `UI-22`, `UI-23`, `UI-24`. Every named object rejects unknown keys.

- `upstream-reference-manifest.json` is exactly `{ schemaVersion: 1, evidenceSessionId, capturedAtUtc, upstreamCommit, rows }`. `upstreamCommit` is the full SHA resolving `0258dbe`. Each row is exactly `{ sources, states }`; `sources` is the exact frozen row source list, each entry exactly `{ path, gitBlob, sha256 }`; `states` is the exact frozen row state order, each entry exactly `{ stateId, captureId, sha256 }`. No field or array entry is nullable.
- `visual-comparison.json` is exactly `{ schemaVersion: 1, evidenceSessionId, capturedAtUtc, upstreamCommit, desktopCommit, windowsAclProof, rows }`. Each row is exactly `{ desktopSources, upstreamCaptureIds, desktopScenarioId, desktopCaptures, status, blocker, decision, dimensions }`. `desktopSources` is the exact reviewed post-1E closure order, each entry exactly `{ path, gitBlob, sha256 }`; `upstreamCaptureIds` is the exact row/table order; `desktopScenarioId` is the named scenario; and `desktopCaptures` is the exact row/table order, each entry exactly `{ captureId, sha256 }`. `status` is exactly `'match' | 'adaptation' | 'divergence' | 'blocked'`. `blocker` is null unless status is blocked; blocked requires exactly `{ code, message: 'Evidence row is blocked.' }`, where code is `'source-dirty' | 'source-missing' | 'source-hash-mismatch' | 'capture-unavailable' | 'render-unavailable' | 'comparison-incomplete'`. `decision` is null for match and blocked; adaptation requires exactly `{ kind: 'electron-adaptation', rationaleCode }` with rationale code `'input-model' | 'platform-layout' | 'accessibility' | 'native-shell'`; divergence requires exactly `{ kind: 'approved-divergence', rationaleCode: 'desktop-product-decision' }`. `dimensions` is exactly `{ contentDipWidth, contentDipHeight, cssViewportWidth, cssViewportHeight, windowsScalePercent, devicePixelRatio, zoomPercent }`; every value is finite and positive and must equal the named scenario's recorded values.

`verify.mjs` loads these two manifests as one indivisible evidence session before validating any row conclusion or authority-doc update. It requires byte-equal `evidenceSessionId`; byte-equal full `upstreamCommit` values, both resolving the audited `0258dbe`; and, for each exact UI row, byte-for-byte array equality between `visual-comparison.json` `upstreamCaptureIds` and the paired upstream row's `states.map((state) => state.captureId)`, including order and multiplicity. Every referenced capture SHA-256 must validate against that paired upstream state and its capture file. `desktopCommit` must be the exact captured `HEAD` as 40 lowercase hex and must pass the source/capture preflight and post-capture checks below. A session-ID, upstream-commit, row-reference, ordering, multiplicity, pairing, capture-hash, or Desktop-commit mismatch blocks the entire evidence session and all seven rows before any row-local conclusion or tracked authority update; no valid row may be salvaged from a mismatched pair.

`windowsAclProof` is the sole safe ACL conclusion location and is exactly `{ scope, status, packageIdentity, observedAtUtc, currentUserControl, broadWriteAbsent, inheritsFromValidatedParent }`. `scope` is exactly `'not-run' | 'unpackaged-preliminary' | 'packaged'`; `status` is exactly `'pending' | 'passed' | 'blocked'`. Each of `currentUserControl`, `broadWriteAbsent`, and `inheritsFromValidatedParent` is an exact four-key object `{ persistenceParent, channelFile, smokeRoot, smokeSentinel }`, whose values are boolean or null:

- `not-run` requires `packageIdentity: null`, `observedAtUtc: null`, status `pending`, and all 12 result values null;
- `unpackaged-preliminary` requires a safe non-null package identity, non-null exact UTC observation, all 12 result values boolean, and status `pending | blocked`; it can never pass;
- `packaged` requires a safe non-null package identity, non-null exact UTC observation, and all 12 result values boolean; status is `passed` if and only if all 12 values are true, otherwise `blocked`.

Package 1F may record `not-run` or `unpackaged-preliminary`. WS9 packaged repetition must update or produce the reviewed `packaged` safe conclusion before any relevant Windows/package row closes. Raw ACL output, account/principal names, SIDs, and paths are forbidden from both manifests and remain only in ignored `windows-checklist.md`. Unknown keys, wrong key/array order, duplicates, nulls outside the exact ACL rules, invalid patterns, absolute/unsafe paths, account/server/library/media names or identifiers, URLs, diagnostics, and raw metadata fail verification.

For each upstream source, `git cat-file -e <full-pin>:<path>`, its Git blob OID, and SHA-256 of the pinned blob must equal the manifest, the worktree file SHA-256 must equal that pinned blob, `git diff --quiet <full-pin> -- <path>` must pass, and scoped untracked-file enumeration must be empty. For each Desktop source, the same checks use recorded full `desktopCommit`/`HEAD`, including `git diff --quiet HEAD -- <path>` and no scoped untracked file. A missing/replaced path, staged or unstaged difference, untracked mapped substitute, blob mismatch, or byte-hash mismatch prevents capture. After capture, verifier rechecks all source identities and capture SHA-256 values so a source cannot change between preflight and evidence acceptance. Pin/HEAD strings without per-file blob and SHA-256 proof are insufficient.

The row mapping freezes exact upstream sources and minimum Desktop source-closure seeds:

| Row | Exact upstream sources | Frozen minimum Desktop product sources | Upstream state IDs → capture IDs | Desktop scenario and capture IDs |
| --- | --- | --- | --- | --- |
| `UI-17` | `src/modules/ui/channel-setup/ChannelSetupScreen.ts`; `src/modules/ui/channel-setup/steps/LibraryStepController.ts`; `src/modules/ui/channel-setup/styles.core.css`; `src/modules/ui/channel-setup/styles.library.css` | `src/renderer/staticDom.ts`; `src/renderer/setup/stagedSetupDom.ts`; `src/renderer/styles/setup-workflow.css` | `library-selected` → `upstream-ui-17-library-selected`; `library-empty` → `upstream-ui-17-library-empty` | `CB-UI-05-NARROW-BREAKPOINT`: `desktop-ui-17-library-selected`, `desktop-ui-17-library-empty` |
| `UI-18` | `src/modules/ui/channel-setup/ChannelSetupSessionState.ts`; `src/modules/ui/channel-setup/steps/StrategyStepController.ts`; `src/modules/ui/channel-setup/styles.strategy.css` | `src/renderer/staticDom.ts`; `src/renderer/setup/stagedSetupDom.ts`; `src/renderer/channelSetup/dom.ts`; `src/renderer/channelSetup/viewModel.ts`; `src/renderer/styles/setup-workflow.css` | `strategy-preview-expanded` → `upstream-ui-18-preview-expanded`; `strategy-preview-unavailable` → `upstream-ui-18-preview-unavailable` | `CB-UI-02-BASELINE-REVIEW`: `desktop-ui-18-preview-expanded`, `desktop-ui-18-preview-unavailable` |
| `UI-19` | `src/modules/ui/channel-setup/ChannelSetupSessionState.ts`; `src/modules/ui/channel-setup/steps/StrategyStepControlDescriptors.ts`; `src/modules/ui/channel-setup/steps/StrategyStepController.ts`; `src/modules/ui/channel-setup/steps/StrategyStepInteractionController.ts`; `src/modules/ui/channel-setup/styles.strategy.css` | `src/renderer/staticDom.ts`; `src/renderer/setup/stagedSetupDom.ts`; `src/renderer/channelSetup/builderConfigState.ts`; `src/renderer/channelSetup/dom.ts`; `src/renderer/styles/setup-workflow.css` | `strategy-all-controls` → `upstream-ui-19-all-controls`; `strategy-disabled-boundaries` → `upstream-ui-19-disabled-boundaries` | `CB-UI-01-WIDE-CONFIG`: `desktop-ui-19-all-controls`, `desktop-ui-19-disabled-boundaries` |
| `UI-21` | `src/modules/ui/channel-setup/steps/BuildReviewStepController.ts`; `src/modules/ui/channel-setup/styles.review-progress.css` | `src/renderer/staticDom.ts`; `src/renderer/setup/stagedSetupDom.ts`; `src/renderer/channelSetup/dom.ts`; `src/renderer/workflow.ts`; `src/renderer/styles/setup-workflow.css` | `review-replace-required` → `upstream-ui-21-replace-required`; `review-replace-confirmed` → `upstream-ui-21-replace-confirmed` | `CB-UI-02-BASELINE-REVIEW`: `desktop-ui-21-replace-required`, `desktop-ui-21-replace-confirmed` |
| `UI-22` | `src/modules/ui/channel-setup/steps/BuildProgressStepController.ts`; `src/modules/ui/channel-setup/steps/ChannelSetupBuildStepPresenter.ts`; `src/modules/ui/channel-setup/styles.review-progress.css` | `src/renderer/staticDom.ts`; `src/renderer/setup/stagedSetupDom.ts`; `src/renderer/channelSetup/viewModel.ts`; `src/renderer/channelSetup/dom.ts`; `src/renderer/workflow.ts`; `src/renderer/styles/setup-workflow.css` | `progress-running` → `upstream-ui-22-progress-running`; `progress-canceling` → `upstream-ui-22-progress-canceling`; `progress-canceled` → `upstream-ui-22-progress-canceled` | `CB-UI-04-STACK-BREAKPOINT`: `desktop-ui-22-progress-running`, `desktop-ui-22-progress-canceling`, `desktop-ui-22-progress-canceled`, `desktop-ui-22-progress-commit-started` |
| `UI-23` | `src/modules/ui/channel-setup/steps/ChannelSetupBuildStepPresenter.ts`; `src/modules/ui/channel-setup/styles.review-progress.css` | `src/renderer/staticDom.ts`; `src/renderer/setup/stagedSetupDom.ts`; `src/renderer/channelSetup/dom.ts`; `src/renderer/workflow.ts`; `src/renderer/styles/setup-workflow.css` | `result-success` → `upstream-ui-23-result-success`; `result-warning` → `upstream-ui-23-result-warning` | `CB-UI-07-REDUCED-MOTION-ZOOM`: `desktop-ui-23-result-success`, `desktop-ui-23-result-warning` |
| `UI-24` | `src/modules/ui/channel-setup/ChannelSetupSessionState.ts`; `src/modules/ui/channel-setup/steps/ChannelSetupBuildStepPresenter.ts`; `src/modules/ui/channel-setup/styles.review-progress.css` | `src/renderer/staticDom.ts`; `src/renderer/setup/stagedSetupDom.ts`; `src/renderer/setup/setupRuntimeCoordinator.ts`; `src/renderer/workflow.ts`; `src/renderer/styles/setup-workflow.css` | `recovery-blocked` → `upstream-ui-24-recovery-blocked`; `recovery-error` → `upstream-ui-24-recovery-error` | `CB-UI-07-REDUCED-MOTION-ZOOM`: `desktop-ui-24-recovery-blocked`, `desktop-ui-24-recovery-error` |

For every mapped state, render upstream and Desktop afresh and compare typography, color, spacing, artwork/icon treatment, clipping/overflow, focus visibility/order/restoration, motion/reduced-motion behavior, state communication, and interaction disposition. `match` means the observed Desktop behavior/presentation is materially equivalent; `adaptation` means an intentional Electron/input/platform adjustment preserves the product intent; `divergence` means the observed difference remains and must carry a rationale plus an explicit decision in the row conclusion. If a mapped source fails cleanliness/blob/hash proof, the pinned upstream state cannot be rendered, a current Desktop state/capture is unavailable, or any comparison cannot be completed, that manifest row is `blocked` with the exact safe blocker and the parity row remains open. `visual-evidence-contract.test.mjs` enumerates both exact top-level/row/nested schemas and proves every regex, UTC timestamp, key order, row order, array uniqueness/order, path rule, status/blocker/decision cross-product, scenario-dimension match, ACL scope/status/null/12-boolean truth table, and unknown-key rejection. It also proves rejection when a frozen minimum seed or reviewed closure member is omitted, when the manifest differs from the approved closure, and for staged/unstaged dirt, untracked substitutes, replaced files, wrong blob/SHA-256, between-preflight-and-capture mutation, missing captures, unsafe/raw ACL material, and row-scoped blocking. Cross-manifest fixtures separately reject different individually valid session IDs, different individually valid upstream commits, cross-row capture substitution, missing/extra/reordered/duplicate upstream capture references, a paired state/capture SHA mismatch, and a Desktop commit other than the captured preflight/post-capture `HEAD`; each proves whole-session rejection before any row conclusion. `verify.mjs` must validate the same individual and paired contracts before and after capture and exits nonzero without updating any conclusion on any violation. Only redacted conclusions—not either local manifest or raw capture—may flow into tracked authority docs.

Run the complete verification surface and the following bounded manual UI manifest:

Every named width/height below is the `BrowserWindow` **content area in device-independent pixels (DIPs)**, not outer-window bounds or physical pixels. At Chromium zoom 100%, `window.innerWidth/innerHeight` in CSS pixels must equal the named content-DIP dimensions. Expected Windows scale/DPR pairs are 100% → 1, 125% → 1.25, and 150% → 1.5. Record the observed DPR in local evidence; a mismatch with the selected Windows scale fails the scenario and triggers replan before comparison. The 900px and 600px breakpoints are CSS-pixel media-query thresholds and therefore equal the named DIPs only at zoom 100%.

| Scenario | Exact content DIPs/scaling/DPR | State and actions | Pass criteria |
| --- | --- | --- | --- |
| `CB-UI-01-WIDE-CONFIG` | 1920×1080 DIPs, Windows 100%, DPR 1 | Restored config; visit every strategy, scope, priority, min/max, Expand, alternate, sequential/block, and mode control | CSS viewport is 1920×1080; wide layout uses intended columns; every control/value/focus ring is visible; no horizontal scroll, overlap, required-text truncation, or dead control. |
| `CB-UI-02-BASELINE-REVIEW` | 1280×720 DIPs, Windows 100%, DPR 1 | Ready, blocked, and slow review; warnings/caps; append/merge; open/cancel/confirm replace | CSS viewport is 1280×720; counts/status are unambiguous; modal traps then restores focus to its invoker; Escape never applies; no content or action is clipped. |
| `CB-UI-03-ORDINARY-WIDTH` | 1024×720 DIPs, Windows 125%, DPR 1.25 | Config through review at an ordinary resizable width above the 900px breakpoint | CSS viewport is 1024×720; columns remain usable with keyboard and pointer; focused controls scroll fully into view; no horizontal document scroll or occluded primary action. |
| `CB-UI-04-STACK-BREAKPOINT` | 900×700 DIPs, Windows 150%, DPR 1.5 | Config, review, and progress at the exact stack breakpoint | CSS viewport is 900×700 and the `max-width: 900px` rule matches; layouts are single-column; reading/focus order matches DOM order; no overlap, unreachable content, or offscreen status. |
| `CB-UI-05-NARROW-BREAKPOINT` | 600×700 DIPs, Windows 125%, DPR 1.25 | Library selection, config, and replace modal at the exact narrow breakpoint | CSS viewport is 600×700 and the `max-width: 600px` rule matches; library list is one column; dialog fits/scrolls internally; actions remain reachable; no two-dimensional scrolling. |
| `CB-UI-06-INPUT-FOCUS` | 1280×720 DIPs, Windows 100%, DPR 1 | Complete one review/cancel/review/apply path separately with Tab/Shift+Tab/arrows, D-pad/Enter/Escape, mouse, and gamepad mapping; type in text/number inputs | CSS viewport is 1280×720; one visible focus owner; disabled/pending controls are skipped; activation occurs once; text input suppresses global shortcuts; transitions restore the exact invoker. |
| `CB-UI-07-REDUCED-MOTION-ZOOM` | 1280×720 DIPs, Windows 100%; baseline zoom 100%/DPR 1, then zoom 200%/effective DPR 2 | Verify baseline CSS viewport 1280×720, then zoom to 200% where expected CSS viewport is 640×360; review every progress phase, canceled, result, recovery with reduced motion | Both measured viewport/DPR pairs match; status remains understandable without animation; no focus theft, overlap, clipped warnings, or unreachable action at zoom. |
| `CB-UI-08-FORCED-COLORS` | 900×700 DIPs, Windows 150%, DPR 1.5, forced colors/high contrast | Config, focused review, modal, progress, failure/result | CSS viewport is 900×700; focus, boundaries, selected/disabled/error states remain distinguishable without color alone; accessible names/states are present; announcements do not move focus. |

Automated responsive assertions additionally set BrowserWindow content widths/CSS viewports to 901/900 and 601/600 DIPs/CSS pixels at Windows 100%, DPR 1, zoom 100%, so each side of both `setup-workflow.css` breakpoints is covered without multiplying the manual manifest.

All eight manual scenarios fail on any horizontal document scroll, overlapping interactive targets, clipped required label/count/warning, invisible focus ring, focus outside an open modal, unreachable primary/back/cancel action, color-only state, duplicate activation, or focused element remaining outside the visible scrollport.

With a live multi-library Plex account, prove safe facet discovery, review and all apply modes, pre-barrier cancellation with no persisted change, commit-barrier cancellation rejection, restart restoration, and guide refresh only after commit. Run the separate packaged WS9 contribution before closing `PB-07`/`WIN-07`.

The packaged Windows proof must launch the packaged executable through one validated smoke run and one production-data persistence run, then inspect the actual canonical smoke root/sentinel and canonical per-user `userData/persistence` parent/channel file before cleanup. `Get-Acl` and `icacls` are both required. Raw commands/output, account names, SIDs, and paths stay only in the ignored `windows-checklist.md`; the safe visual manifest records only the exact `currentUserControl`, `broadWriteAbsent`, and `inheritsFromValidatedParent` four-target boolean objects. “Current-user control” means an effective Allow entry that permits the packaged app's current Windows user to create/replace/read the tested file; a broad-principal Allow containing Write, Modify, or FullControl fails. The smoke root/sentinel ACL result is part of the Windows smoke proof even though Windows performs no chmod or numeric mode comparison.

Any missing `Get-Acl`/`icacls` observation, unresolved/ambiguous ACL, current-user-control failure, broad-principal write/modify/full-control grant, ACL differing from the canonical parent inheritance assumption, or inability to open and replace through the packaged app keeps the Windows security proof open and triggers replan before acceptance. An unpackaged Package 1F run may collect preliminary ACL evidence but cannot substitute for the packaged WS9/RD-28 repetition; WS9 must carry this exact ACL gate into its refreshed package and cannot close the relevant Windows/package proof without it.

Raw captures, environment-specific paths, server/library/media names, and diagnostics remain ignored locally. The tracked summary may record only platform family, package identity, scenario, status, safe aggregate counts, and redacted conclusions.

Only after evidence exists and the Windows proof-plan preamble is current may Package 1F update matrix rows, current architecture, roadmap gates, and Windows proof conclusions. Checkpoint commit: `docs(parity): close channel builder workstream`. The canonical plan remains active for WS2. Package 1F rollback removes only its ignored run artifacts and reverts its tracked authority conclusions as one reviewed evidence unit; it never preserves a row or partial conclusion derived from a schema-invalid, cross-session, cross-commit, cross-row-substituted, or hash-mismatched manifest pair, never promotes raw ACL material, and never downgrades a packaged blocked result to unpackaged/not-run. Earlier implementation commits and persisted channel data remain untouched.

### Later workstream promotion

**IMPLEMENTER_ROLE_ELIGIBILITY:** `none` until the applicable workstream has been refreshed, replanned with exact files, and re-reviewed; the expected default after approval is `worker`.

At each WS1 close and subsequent workstream boundary:

1. Recompute the remaining registry from the parity matrix.
2. Confirm the preceding dependency gates and observed authority-doc state.
3. Use Codanna if useful, then direct source/test reads.
4. Freeze exact ownership, files, packages, rollback, proof, and safe parallelism for only the next workstream.
5. Route the refreshed plan to adversarial feature review before implementation.

WS2–WS9 do not inherit guessed files or stale upstream comparisons from this document. No two packages may concurrently edit a shared contract, composition root, persisted schema, runtime lifecycle, or authority document. Documentation/evidence preparation may overlap product work only when it does not assert unobserved completion or edit a shared owner.

For `PB-07`/`WIN-07`, “WS2 complete” means the implementation/non-packaged integration dependency gate is satisfied, not audit-row closure. WS9 must carry the named contributor proof into its refreshed package; neither row becomes complete before that packaged evidence passes.

The same rule applies to the frozen contribution table: WS2 does not close `PB-22`–`PB-24` before WS3/native proof, WS3 does not close `ST-11`–`ST-16` before WS5 consumption proof, and WS8 does not close `WIN-04` before WS9/RD-27 proves it alongside WS9-owned `PB-27`. The final contributing workstream updates the matrix with evidence while preserving each ID's unique registry owner.

## Verification Commands

Focused package commands use explicit test files from that package, for example:

```sh
test -f src/domain/channel/channelDomainClone.ts
test -f src/__tests__/domain/channelPersistence.test.ts
node --import tsx --test src/__tests__/domain/channelBuilderContracts.test.ts src/__tests__/domain/channelBuilderIdentity.test.ts src/__tests__/domain/channelBuilderPlanner.test.ts
npm run test:contracts
npm run verify:channel-builder-performance
node --import tsx --test src/__tests__/main/channelBuilderFacetSource.test.ts src/__tests__/main/plexLibrary.test.ts src/__tests__/main/plexRuntimeOperationOwners.test.ts
node --import tsx --test src/__tests__/contracts/contracts.test.ts src/__tests__/domain/channelPersistence.test.ts src/__tests__/main/channelPersistenceAdapter.test.ts src/__tests__/main/channelPersistenceBootstrapOwner.test.ts src/__tests__/main/channelPersistenceStartupOwner.test.ts src/__tests__/main/plexComposition.test.ts src/__tests__/main/desktopPlexChannelBuilderFacetRuntime.test.ts src/__tests__/main/channelRuntimeIpc.test.ts src/__tests__/main/channelComposition.test.ts src/__tests__/main/customChannelRuntime.test.ts src/__tests__/main/channelBuilderCommitBarrier.test.ts src/__tests__/main/channelBuilderContextEpochOwner.test.ts src/__tests__/main/channelBuilderOperationContracts.test.ts src/__tests__/main/channelBuilderPlanningWorker.test.ts src/__tests__/main/channelPublicReferenceOwner.test.ts src/__tests__/main/channelBuilderSmokeFixture.test.ts src/__tests__/main/smokeChannelBuilderAssertions.test.ts src/__tests__/main/smokeBootstrapOwner.test.ts src/__tests__/main/singleInstanceOwner.test.ts src/__tests__/main/desktopPlexContextNotifications.test.ts src/__tests__/renderer/channelBuilderConfigState.test.ts src/__tests__/renderer/channelRuntimeActions.test.ts src/__tests__/renderer/rendererActionRegistration.test.ts src/__tests__/renderer/rendererRuntimeOwners.test.ts src/__tests__/renderer/routeDom.test.ts src/__tests__/renderer/focusDom.test.ts src/__tests__/renderer/plexRuntime.test.ts src/__tests__/renderer/workflow.test.ts src/__tests__/integration/preloadContractVocabulary.test.ts
node --test tools/__tests__/package-windows-internal.test.mjs tools/__tests__/smoke-electron.test.mjs
npm run smoke:electron
node --import tsx --test src/__tests__/renderer/channelBuilderConfigState.test.ts src/__tests__/renderer/channelSetupDom.test.ts src/__tests__/renderer/channelRuntimeActions.test.ts src/__tests__/renderer/workflow.test.ts src/__tests__/renderer/rendererActionRegistration.test.ts src/__tests__/renderer/routeDom.test.ts src/__tests__/renderer/focusDom.test.ts
node --import tsx --test src/__tests__/renderer/setupRuntimeCoordinator.test.ts src/__tests__/renderer/plexRuntime.test.ts src/__tests__/renderer/rendererRuntimeOwners.test.ts src/__tests__/renderer/channelRuntimeActions.test.ts src/__tests__/renderer/workflow.test.ts src/__tests__/renderer/routeDom.test.ts
```

Required package/program gates as applicable:

```sh
npm run typecheck
npm run verify:architecture
npm run verify:maintainability
wc -l src/domain/channel/channelRepository.ts src/main/smokeAssertions.ts src/main/smokeChannelBuilderAssertions.ts src/renderer/workflow.ts
npm run verify:redaction
npm run build:electron
npm run smoke:electron
npm run verify
npm run verify:docs
git diff --check
```

For current Package 1A Proof Route R0, run `npm run test:contracts` and observe the performance row skipped with no benchmark diagnostic, then run `npm run verify:channel-builder-performance` and observe that same row execute. Also run `npm run typecheck`, `npm run build:electron`, `npm run verify`, `npm run verify:docs`, `git diff --check`, and `git diff --name-only -- .github/workflows/ci.yml src/__tests__/domain/channelBuilderPlannerPerformance.test.ts package.json`; the final scope audit must list only the first two paths and `package.json` must be unchanged. CI evidence must show Node `22.19.0`, the exact R0 SHA, ordinary Windows Verify passed, the dedicated step executed rather than skipped, its sole test command was `npm run verify:channel-builder-performance`, and the measured invocation passed at no more than 2,000 ms without a concurrent npm/Node test command.

For current A1, run exactly:

```sh
node --import tsx --test src/__tests__/domain/channelBuilderIdentity.test.ts src/__tests__/domain/channelBuilderPlanner.test.ts src/__tests__/main/channelBuilderProductionPlanner.test.ts
npm run test:contracts
npm run verify:channel-builder-performance
npm run typecheck
npm run verify:architecture
npm run verify:maintainability
wc -l src/domain/channelBuilder/planIdentity.ts src/domain/channelBuilder/strategyBuilders.ts src/domain/channelBuilder/planner.ts src/main/channel/channelBuilderProductionPlanner.ts
npm run build:electron
npm run verify
npm run verify:docs
git diff --check
```

The domain identity/planner tests remain pure and import no main owner. The
main production-planner test must import the sole
`channelBuilderProductionIdentityOperations` capability from the production
planner owner and run the exhaustive classes named in A1, including negative
infinity; undefined/symbol/bigint/function; persisted-string
empty/control/astral/unpaired-surrogate boundaries; every existing invalid
facet/source/filter class; and unequal-byte collision tuples. It must prove
all operation/error parity, deep planner output parity, default
`buildChannelSetupPlan` purity, and production-entrypoint use. Its inline-decade
fixture must use counting/bound operations to prove both construction and
`isValidChannelBuilderCandidateContentFilterPlanWithIdentityOperations`
validation call the injected capability, and its existing-collision fixture
must preserve same-digest/unequal-byte non-match behavior. Broad
`test:contracts` must discover the relocated main performance test, skip its
performance invocation, and make no performance claim. The isolated command
must call only
`buildProductionChannelSetupPlan` for warm/measured work, preserve the exact
50,000-item fixture and golden plan identity, and use its local non-Windows
timing only as diagnostic evidence. Source/diff review must prove `node:crypto`
occurs only in the new main owner, no Node/runtime import or global enters
`src/domain/**`, all identity calls in `strategyBuilders.ts`, `facets.ts`, and
`planner.ts` route through the bound capability, the existing two-argument
facets validator delegates to the pure default, no other facets API/behavior or
existing domain test changes, the old domain benchmark path is absent,
the main benchmark path is present, `package.json` changes only that script
path, and `package-lock.json` is unchanged.

Before commit, compare `git status --short` with the recorded pre-existing
state, stage only the eleven A1 path-owned diff entries—including `facets.ts`, the deleted
domain benchmark path, new main benchmark path, and `package.json`—and verify
`git diff --cached --name-only` exactly matches the A1 list. After the safe explicit push, the CI
log must show the checkout expected-SHA assertion passed and printed/resolved
the same A1 head SHA used by ordinary Windows Verify and the dedicated Windows
Node `22.19.0` command. Ordinary Windows Verify must pass; the isolated command
must execute and its result must be observed against the unchanged
`<= 2,000 ms` target. Different-SHA, merge-SHA,
skipped, contended, wrong-command, or wrong-Node evidence is missing proof.
Above-cap exact-head evidence activates `WS1-PERF-01` and does not block 1B.

For later Package 1C, the focused main command includes `channelBuilderPlanningWorker.test.ts`, `channelBuilderOperationContracts.test.ts`, and `channelComposition.test.ts`; the already-declared `channelPersistence.test.ts`, `channelPersistenceAdapter.test.ts`, and `channelPersistenceStartupOwner.test.ts` exercise the surgical `src/domain/channelBuilder/persistence.ts` responsibility through repository normalization, adapter round trip, marker-local/current-lineup repair, shared null-prototype cloning, and startup repair without adding a test file; `npm run build:electron` must emit `dist/main/channel/channelBuilderPlanningWorkerEntry.js`; and `tools/__tests__/package-windows-internal.test.mjs` must prove the staged package contains `resources/app/dist/main/channel/channelBuilderPlanningWorkerEntry.js`. These are in addition to Package 1C's existing focused, typecheck, architecture, maintainability, smoke, redaction, full-verify, and review gates.

Package 1C also runs
`node --test tools/__tests__/build-eslint-architecture-rules.test.mjs` and
`npm run verify:architecture`. The focused regression must prove a renderer
static import of `../../domain/channelBuilder/config.js` passes while exact
bare `domain`, `node:domain`, privileged main/preload/native-helper imports,
and literal or computed forbidden dynamic imports still fail with the existing
boundary rule. The full architecture gate must then accept the frozen
`builderConfigState.ts` static imports of Package 1A config/types without
weakening any domain/runtime-global or privileged dependency-direction rule.

Package 1C additionally runs
`node --test tools/__tests__/copy-renderer-assets.test.mjs
tools/__tests__/package-windows-internal.test.mjs`, then
`npm run build:electron` and `npm run smoke:electron`. The focused test and
build-output audit require exact source/target hashes and exact paths for only
`config.js` and `constants.js`, reject every named sibling/source-map/arbitrary
copy, and leave protocol/CSP sources byte-unchanged. The package test requires
the matching two packaged renderer-domain paths and excluded siblings without
changing package staging logic. Electron smoke must load the minimal staged
builder route without `net::ERR_FILE_NOT_FOUND` while the existing containment,
navigation, CSP, and bridge assertions remain green.

The reconciled renderer fixture runs through the focused
`node --import tsx --test src/__tests__/renderer/playerOverlayPresentation.test.ts`,
`npm run typecheck`, and the existing `npm run verify` Package 1C gate. Its
diff/proof must contain only the two required summary fields and no changed
player/presentation assertion or behavior.

Reproducible WS1 visual capture:

```sh
npm run build:electron
node docs/runs/2026-07-22-tier3-parity-correction/channel-builder/capture.mjs --wait-ms=3600000
# While the collector is running, generate every approved upstream and Desktop PNG.
node docs/runs/2026-07-22-tier3-parity-correction/channel-builder/verify.mjs
node --test docs/runs/2026-07-22-tier3-parity-correction/channel-builder/visual-evidence-contract.test.mjs
```

On the packaged Windows proof host, after resolving the four exact validated paths from the running packaged app into task-specific PowerShell variables:

```powershell
Get-Acl -LiteralPath $lineupPersistenceParent | Format-List Owner,AreAccessRulesProtected,Access
Get-Acl -LiteralPath $lineupChannelFile | Format-List Owner,AreAccessRulesProtected,Access
Get-Acl -LiteralPath $lineupSmokeRoot | Format-List Owner,AreAccessRulesProtected,Access
Get-Acl -LiteralPath $lineupSmokeSentinel | Format-List Owner,AreAccessRulesProtected,Access
icacls.exe $lineupPersistenceParent
icacls.exe $lineupChannelFile
icacls.exe $lineupSmokeRoot
icacls.exe $lineupSmokeSentinel
```

The final WS1 evidence must distinguish deterministic local fixture proof, live Plex proof, source inspection, visual capture, and packaged Windows proof. A passing automated suite cannot satisfy a live or visual row by implication.

**Verification classification:** broader integration/manual proof required

## Acceptance Criteria

- The registry contains all 227 audit stable IDs exactly once, and each later matrix update traces to its owning workstream and observed evidence.
- Package scope classifies `.github/workflows/ci.yml`, `package.json`, and `docs/architecture/import-ledger.md` as existing in 1A, classifies existing `src/domain/channelBuilder/persistence.ts`, `src/domain/channel/channelDomainClone.ts`, and `src/__tests__/domain/channelPersistence.test.ts` in Package 1C, creates only the three exact package-owned directory chains, places both persistence startup owners and their tests under already-existing `src/main/persistence/` and `src/__tests__/main/`, classifies `src/main/smokeChannelBuilderAssertions.ts` as expected-existing in 1E with `New: none`, and passes mechanical existing-path/new-parent validation before execution.
- Package 1C classifies existing
  `tools/architecture-rules/buildEslintArchitectureRules.mjs` and
  `tools/__tests__/build-eslint-architecture-rules.test.mjs` in its exact scope.
  Bare Node builtins are exact restricted imports rather than globs, the
  renderer's static Package 1A config/types imports pass, and bare `domain`,
  `node:domain`, every existing privileged path, and forbidden dynamic imports
  remain rejected. No product/default/IPC or architecture-policy exception,
  additional verifier/test file, or other package scope is introduced.
- Package 1C classifies existing `tools/copy-renderer-assets.mjs` and
  `tools/__tests__/copy-renderer-assets.test.mjs` in its exact scope. The
  existing post-`tsc` build copies only emitted `config.js` and `constants.js`
  from the pure Package 1A runtime closure into the exact renderer-domain
  target with byte-equal hashes; all named siblings, source maps, source
  literals, and arbitrary directory contents stay absent. Build, focused copy
  proof, internal-package proof, and Electron smoke pass without a protocol,
  CSP, index/main, package configuration, public contract, IPC, or default-owner
  change.
- Package 1C classifies existing
  `src/__tests__/renderer/playerOverlayPresentation.test.ts` in exact scope
  solely to add `lineupRevision: 1` and the exact unknown-builder value to its
  existing `channelSummary` fixture. Focused test, typecheck, and full verify
  pass with every player/presentation input, assertion, scenario, and behavior
  unchanged.
- Packages 1A–1F execute serially; every local checkpoint passes focused tests, typecheck, and Electron build without an uncommitted later package. Immutable commits `ca21ba1a5d641093e55b7c64b0910e317016ae37`, `aa224e5bed28341600d9fa33bd2fe7ac305aa2e4`, and `d6a42a6e363ce32769f5b949ee5768b0cb438023` remain unchanged. A1 lands as the one reviewed follow-up `perf(channels): use native planner identity hashing` on the existing unmerged PR #19 branch; no merge or further optimization is inferred. Package 1B may start after the exact A1 head passes ordinary Windows Verify and the unchanged isolated Windows Node 22.19 command executes on that same asserted head. A result at or below 2,000 ms closes the target; an above-cap result activates and carries `WS1-PERF-01` without blocking functional WS1 implementation.
- 1A lands the shared pure DTO/config/planner owner, exact immutable defaults/factory/normalizer, sole `PersistedStringV1`/Identity V1 canonical/golden-vector surface including `"10"`-before-`"2"` ordinary-key bytes, raw-free tag/content-filter planner contracts, and sole total no-suffix-leak display helper. A1 preserves every public pure default and golden output while routing the complete strategy/planner identity call graph through one injected capability and the sole main-owned synchronous `node:crypto` production entrypoint. Its typed identity constructors accept validated raw main values only as synchronous transient inputs and return only an opaque digest or fixed value-free failure, with no retention, logging, diagnostics, state, exception text, planner input/output, or safe/public DTO exposure. Broad `test:contracts` skips the benchmark; only the exact performance lifecycle runs the unchanged 50,000-candidate/2,000 ms gate, and `${{ !cancelled() && runner.os == 'Windows' }}` remains exact. Ordinary Windows Verify must pass on the asserted exact A1 head, and the isolated result on that head is either a passing target result or recorded honestly as `WS1-PERF-01`; it never masks Verify failure. 1B keeps raw main-only `tagValue` separate from all safe projections: facet/runtime queries use only the raw main-only value; grouping uses only `semanticGroupIdentity`; director filter equality/reference uses only `contentFilterIdentity`; decade construction uses only numeric `yearValue`; the exact display-free semantic tuples drive facet/group/member/candidate order, seeds, and cap admission; independently projected `displayTitle` is attached only after admission and supplies copy only. 1C atomically removes the public commit surface plus the complete legacy renderer commit-button branch, lands the minimal default-backed config state, rewires the staged build-confirm route through the five-operation flow with no shim, imports the shared display helper without a local sanitizer, and independently passes focused tests/typecheck/Electron build/`npm run smoke:electron` before 1D.
- A1 pure/native tests exercise every identity operation and every frozen hostile/golden class with byte-equal values or equal fixed failures, explicitly including negative infinity; undefined/symbol/bigint/function; persisted-string empty/control/astral/unpaired-surrogate boundaries; all existing invalid facet/source/filter classes; and unequal-byte collision tuples. Domain identity/planner tests remain pure-only and unchanged, while `channelBuilderProductionPlanner.test.ts` imports the sole main-native capability for conformance. Its inline-decade counting fixture proves construction and validation both use the bound capability, and its existing-collision fixture proves same-digest/unequal-byte non-match; all production-planner fixtures are deep-equal to pure-default output. `facets.ts` adds only the exact bound validator, the existing validator delegates to pure default, and the production planner never calls the pure validator. The relocated main performance test and later Package 1C Worker both use `buildProductionChannelSetupPlan`; `canonicalJsonV1`, all domains/prefixes, tuple collision guards, planner DTOs, npm lifecycle command name, fixture, cap, and Node version remain unchanged; `package.json` changes only the benchmark test path, `package-lock.json` is unchanged, the old domain benchmark path is absent, and no Node import/runtime global enters `src/domain/**`.
- Package 1C deletes the commit-availability type/factory/workflow field and `commitMode` progress copy from `channelSetup/viewModel.ts`, uses only the exact operation progress model, updates workflow/route-DOM proof, and leaves a buildable vocabulary-clean baseline for 1D.
- The 1C smoke owner asserts exactly `getStatus`, `startReview`, `startApply`, `getOperation`, and `cancel`, exercises a deterministic safe non-empty review/apply through the minimal staged build-confirm route, and contains no legacy `commit` method, three-commit-button requirement, `[data-channel-commit-action]` selector, or related diagnostics; its unique temporary user-data directory is passed to Electron and removed on every exit path, production/development cannot select the fixture, normal user state is unreachable, and 1E only extends this passing baseline for result/recovery states.
- Every process requests and retains the single-instance lock before directory bootstrap/persistence/composition/IPC/window startup; a secondary exits without directory creation, reads, or registration and can only ask the primary to restore/focus its existing window. Production/development then require the exact channel-parent ready capability/file-protection policy before persistence load, while smoke does not bypass the lock.
- Smoke mode is granted only by the exact canonical unique temporary-root/user-data/sentinel/nonce capability. Environment-only, missing/mismatched, symlinked, outside-temp, normal-user-data, and POSIX-mode-mismatch cases exit nonzero before startup; Windows has no chmod/numeric-mode branch. Valid smoke channel persistence is an injected in-memory aggregate that never resolves/creates a channel persistence parent or constructs the disk store.
- WS1 provides all audited builder strategies and controls through a pure deterministic planner fed by exactly normalized config, the capped item-facet-free safe facet DTO, the raw-filter-free domain-only existing-lineup projection, explicit clock value, and seed. Every binding/facet/tag-group/content-filter/source/candidate/candidate-ID/plan-identity preimage uses the one byte-level Identity V1 serializer and exact domain; validated raw main-only values may enter only the synchronous typed constructor that owns that preimage and must leave only an opaque identity or fixed value-free failure, never retained raw data. Golden vectors pin current raw fields, exact lossless `PersistedStringV1` records for total hostile existing IDs/names, exact numeric-like ordinary-key ordering, the exact complete-string credential-marker display vectors, the exact seven-code facet-warning array/count state, ECMAScript finite-number serialization, typed integer constraints, the total arbitrary-key/NFC-collision-safe library-filter entry representation, self-exclusion, restart stability, and collision-tuple rejection. Per-library and cross-library director/genre plus separate/combined actor/studio semantics are driven only by safe facet/source references and family-scoped semantic digests; decades are driven only by numeric `yearValue`; per-library raw director equality is represented only by the opaque main-index content-filter reference and resolved at materialization. After pinned count/eligibility rules, the exact family/group/member tuples frozen in this plan drive source/candidate order, mixed child order, seeds, skip counts, identities, and family/global/candidate cap admission. `displayTitle` is projected and attached only after semantic admission and is never a comparator, tie-breaker, group key, seed, identity, or cap input. Capacity-boundary redaction/truncation/collision/divergence fixtures preserve the same semantic order, survivors, and identities. Raw key/`tagValue`/director-filter strings never enter a safe/planner/public DTO, retained state, log, diagnostic, or exception. Facet warning codes are unique, lexical, deeply immutable, capped at seven; `omittedMalformedCount` follows its positive-iff-code rule, while `omittedCappedCount` is exactly zero for no cap, exact positive 1–50,000 for a completely known bounded remainder, or null for any unknown/over-50,000 remainder, with the cap code present exactly for positive/null and no count-only fetches. Conversion preserves exact affected counts/nulls; main dedup uses numeric sum only when every member is numeric and null if any member is null. Existing valid library filters with any non-forbidden own enumerable string keys and string/finite-number values—including exact own `__proto__`, `constructor`, and `prototype`—survive projection/migration/serialization and every repeated ownership clone with a null prototype, then identity/restart, without alteration or prototype pollution and remain eligible for exact provenance matching. The persisted `channelProvenance` record uses the same shared null-prototype own-record helper and exact descriptor validation: valid channel IDs `__proto__`, `constructor`, and `prototype` survive construction, marker repair, clone, mutation, JSON serialization, startup repair, and restart as ordinary own entries; invalid/inherited/accessor/symbol/non-enumerable containers cannot create provenance, and no path pollutes a prototype or loses a channel. Existing `manual.items` and all `mixed.sources` remain ordered/matchable when safe, but every planned/materialized tree is non-manual; privileged materialization identities stay main-only and expire with the plan.
- With valid `alternateLineupCopies = 3`, the planner accepts `ChannelBuilderCandidateDraft.lineupReplicaIndex` through integer `3`: the base is `0` and the three alternates are exactly `1`, `2`, and `3`; no candidate, identity, materialization, or merge projection clamps the third alternate to `2` or rejects it.
- Existing-lineup projection is total over the complete current loader/validator/persistence domain without widening builder-safe source/filter caps: every persisted row remains in original order, its exact raw ID/name is retained main-only without the new 512/control/display restrictions, its ID/name identity is losslessly typed through `PersistedStringV1`, raw nonempty content filters are replaced in the pure DTO by their opaque `contentFilterIdentity`, and it is exactly matchable with non-null safe source/filter identity or retained-unmatchable with null source/provenance solely by typed matchability. All current-valid hostile IDs/names remain rows; all overlength/control-bearing source/filter fields, positive finite out-of-safe-range values, over-500-array/leaf cases, depth-9–25 sources, and other Identity-V1-inexpressible cases remain byte-preserved and unmatched with one count-only warning. Append/merge retain them unchanged; only a reviewed, confirmed, non-empty, successfully committed replace may remove them; PLAN_EMPTY and every failed/canceled/conflicted path cannot.
- Packages 1A, 1B, and 1C compile independently against the exact exported planner output/candidate/ledger/review body, recursive safe source identity, facet source/index, operation/status, aggregate mutation, and coordinator contracts. Matchable existing and planned sources compare only through a valid versioned per-channel marker plus the same domain-separated lineage/source/candidate identity; retained-unmatchable, legacy, malformed, recomputation-mismatched, collision, and cross-server cases do not match. Index ownership transfers once and disposes on every terminal path; contract/preload/main tests reject every extra field/variant/null rule and privileged leak.
- Every zero-candidate pure result after enablement/eligibility/skips emits the sole `PLAN_EMPTY` warning, is blocked, has empty `applyCandidateIds` and `retainedMaterializationCandidateIds`, and exposes no apply-capable pure output/materialization request. Package 1C alone projects public `planId: null`, retains no body/index, rejects `startApply`, and proves append/merge/replace cannot delete or mutate the lineup.
- The five-operation public IPC matches the exhaustive nested config/defaults, exact identifier regex, warning/apply-summary equations and per-mode/per-strategy reconciliation, the exact closed review-diff DTO with six-name caps and replace/append/merge normalization, caps, ID semantics, phase-local progress values and terminal normalization, single-active busy-before-plan-lookup policy, retention/tombstone precedence, single-use plan behavior, and every exact materialization and non-materialization `(code, operation, source)` error row—including distinct `active-operation`, `consumed-plan-capacity`, and `channel-id-allocation` tuples—with no extra tuple. Every review sample is projected by the sole Package 1A helper before ordering/concatenation/capping, and cross-package hostile-vector tests prove Packages 1B/1C return byte-equal results for the same options.
- Package 1B defines an independently buildable fakeable `withSession` access boundary and a separate exact three-method `LivePlexChannelBuilderFacetTransport`; the real `LivePlexTransport` satisfies that interface and the byte-for-byte unchanged `LivePlexLibraryTransport`. The access adapter accepts exactly `{ facetTransport: LivePlexChannelBuilderFacetTransport, itemTransport: Pick<LivePlexLibraryTransport, 'listLibraryItems'> }`, routes collection/playlist/tag only through the former and item listing only through the latter, and has no intersection/combined transport parameter. `channelBuilderFacetSource.test.ts` uses real transport plus fake fetch and independently supplied narrow fakes; type/source and call-routing proof fixes the two-field dependency shape, old interface key set, both real-class relationships, absence of a generic method, and zero edits required in the out-of-scope `plexRuntimeIpc.test.ts` and `plexLibraryMinimalAdapter.test.ts` mocks. Every `facet-count` request retains the validated nonempty raw tag `key` and raw-main-only semantic `tagValue`: genre/director/year use exact `{ type: mediaType, [family]: tagValue }`; actor/studio accept only an allowlisted fastKey with a nonempty requested-family entry and force exact `type = mediaType`, otherwise fall back exactly to `{ type: mediaType, [family]: key }` with no `tagValue`, `displayTitle`, or digest fallback. The closed safe tag union contains independently derived `displayTitle`, family-scoped `semanticGroupIdentity`, director-only `contentFilterIdentity`, and year-only numeric `yearValue` under exact null rules; hostile/unequal raw/group/display/year fixtures prove display projection cannot change identity/runtime query/group/filter/year semantics and neither raw key, `tagValue`, nor raw director filter reaches safe/public output or diagnostics. Package 1C adds only the separate optional `channelBuilderFacetTransport` constructor option with exact null default, explicitly passes the production real transport under both separately typed runtime option names, and proves omitted/explicit-undefined old constructors remain source-compatible. Missing injection returns the exact nonretryable safe unavailable result before context/auth/connection/callback or old-library work; present injection constructs the exact Package 1B `facetTransport`/`itemTransport` dependencies, with no intersection, cast, setter, detection, or fallback. Package 1C alone acquires active token/connection inside `withChannelBuilderFacetSession`, closure-binds the allowlisted callback-scoped session, aborts on relevant context churn, and revalidates before/after. No token, connection, URI, header, endpoint string, session object, unrestricted request, caller-defined path/query, or generic Plex method crosses the callback or enters renderer/preload/contracts/IPC.
- Review and application are distinct; the exact main-only Plex getter/result/error/null/subscription API exposes no secrets, profile/server changes invalidate all retained plans, library changes invalidate each plan only when its selected ID→UUID pairs differ, unselected additions remain irrelevant despite monotonic epoch advancement, application rederives exact selected context and rejects stale lineage/context, and replace requires confirmation.
- Playlist and collection facet identity retains both current `ratingKey` and `.key`, but raw-to-safe linkage and every materialized runtime source assign only `playlistKey = PlexPlaylist.ratingKey` or `collectionKey = PlexCollection.ratingKey`; unequal-key fixtures and restart proof prevent `.key` substitution.
- Every materialization result/rejection/contract-invalid shape follows the exhaustive table's exact code/message/retryable/recoverable/`startApply` or non-error disposition. Lowest candidate-ledger ordinal wins among settled terminal outcomes, remaining pre-barrier work is stopped/aborted where supported, and no terminal failure writes, summarizes, or refreshes. Only genuinely unavailable new candidates may skip; canceled remains the exact canceled operation; a non-empty replace with zero ready replacements returns exact `CHANNEL_REPLACEMENT_EMPTY` without barrier/write/revision/summary/refresh, while mixed-success replace and explicit append/merge metadata-only outcomes follow the frozen accounting.
- The main-only builder channel-ID allocator processes surviving `new-apply` rows in ledger order, accepts only exact 128-bit lowercase random hex, reserves every `B` ID even for replace, retries collisions exactly eight times, and keeps every proposed/committed new ID safe, unique, and outside `B`; matched merge rows retain their ID. Invalid output or eighth-collision exhaustion returns the exact `channel-id-allocation` terminal error before barrier/write/refresh/summary and leaves aggregate/revision bytes unchanged; the apply-local authoring service consumes the preallocated closure without an edit to `channelAuthoringService.ts`.
- The materializer emits exactly the five required create keys; emits `contentFilters` only after validating an inline numeric plan or resolving a byte-equal main-index director reference; emits only non-null members of the other seven generated optionals; always omits `number` and every other create optional; and rejects any raw/digest/wrong-family/mismatched deviation. The apply owner calls unchanged authoring semantics serially in candidate-ledger order: append/merge fill the evolving lineup's lowest unused 1–500 numbers, replace numbers surviving rows from 1 against an empty create aggregate while IDs still reserve `B`, and skips consume no number. Merge matched rows use the runtime-local unchanged-`updateChannel` then ownership-clone/delete sequence: `contentFilterPlan.kind = 'none'` removes filters, inline/reference plans replace them, the other seven nulls delete only their owned optionals, invalid plans/non-null values fail, current/validated inputs are never mutated, and exact `id`/`number`/`createdAt` plus every unlisted field survive. Every mode persists the complete `F` sorted ascending by unique channel number; Watch is the first `F \\ B` member in that committed order, and status/Guide observe the same order.
- The bootstrap owner performs the sole channel-parent `mkdir` after smoke validation/lock and before persistence read, validates exact canonical non-symlink ownership, and returns the unforgeable platform-policy capability required by the disk store; fixed redacted failure stops startup. Operation/store code has no `mkdir` or parent recreation. An absent-parent bootstrap followed by operation cancel may perform destination `lstat` but performs zero temporary-file/exclusive/create/write-capable opens and zero filesystem mutations, while a parent deleted after bootstrap fails the first post-proceed temporary exclusive create open as storage-unavailable until next startup.
- `ChannelPersistenceStartupOwner.loadAndRepair()` is the sole repair-write owner: one mutation-chain full-file read, full aggregate normalization, and at most one atomic complete-file repair. Missing returns empty without write; corrupt/unsupported/read/write failure is redacted, preserves bytes where present, and blocks Plex/channel IPC and the window. `ChannelPersistenceCoordinator.load()` and every ordinary read perform no repair. Plex construction occurs without IPC before this load; Plex IPC, then channel IPC, register only after it succeeds, and shutdown/handler removal is exactly once.
- Package 1C invokes the unchanged pure planner only in the fixed `worker_threads` entry through the closed job-ID protocol. One lazy long-lived Worker/pool-size-one owner enforces single flight; abort terminates and detaches the Worker, discards late output, returns the exact canceled operation outcome, and lazily recreates on the next call; error/unexpected exit clears the owner and maps to fixed safe failure; shutdown is idempotent and composition-owned. Direct pure-planner parity, protocol/diagnostic safety, restart, fixed dev/package entry resolution, emitted entry, and packaged entry all pass. This responsiveness/cancellation boundary neither makes the kernel faster nor substitutes for Package 1A's unchanged isolated gate. Repeated cancel during observable `canceling` or terminal `canceled` returns exact accepted/null and causes no second abort, dispose, or transition; every other terminal returns already-terminal, and post-`proceed` returns commit-started.
- Cancellation is operation-scoped and leaves destination/aggregate/revision/guide unchanged when the exact synchronous barrier returns cancel. Before it, `mutateChannelAggregate` may complete destination `lstat`, the policy-specific read-only destination open/handle-stat/read/close for an existing file, and other read/stat/compute/serialize/guard work; cancel then guarantees zero temporary-file opens, zero exclusive/create/write-capable opens, zero handle writes/chmods/syncs, and zero rename/unlink/`mkdir`/repair/other filesystem mutations. Proceed invokes the policy-specific first temporary exclusive create open in the same continuation with no intervening await/microtask/`mkdir`. POSIX uses exact destination `O_RDONLY | O_NOFOLLOW` and temp `O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW` with `0o600`. Windows Node 22.19 uses destination `O_RDONLY` and temp `O_CREAT | O_EXCL | O_WRONLY`, never `O_NOFOLLOW`, chmod, or numeric mode, and requires prior `lstat` plus exact regular handle `(dev, ino)` equality before destination read; `O_EXCL` rejects pre-existing temp nodes/symlinks. Within the explicit app-owned `userData`/single-instance/non-hostile-same-user threat model, both policies enforce random 128-bit suffixes, eight collision attempts, shared handle/path identity and regular-file checks, sync/close, guarded rename, matching-identity-only cleanup, mismatch-no-unlink/redacted warning, and destination symlink/non-regular/identity rejection. The plan acknowledges residual path-based TOCTOU and no hostile same-user/native Windows reparse-point guarantee; every observed pre-rename failure preserves destination bytes, and rename commits before non-abortable refresh.
- Renderer cancellation is genuine: `Cancel build` invokes the active operation, accepted cancellation projects `Canceling…` until terminal canceled, commit-started removes/disables cancellation and shows `Saving channels—cancel is no longer available.`, and Back/close never masquerades as cancellation.
- Builder and Custom Channels serialize full lineup mutations without conflating feature behavior.
- The aggregate CAS owner preserves metadata and tune interleavings; lineup, current-channel pointer, builder completion/configuration/bindings, exact per-channel provenance ledger, and revision commit atomically.
- Legacy, invalid nested state/revision/provenance, retained-unmatchable marker repair, and the frozen old-reader rewrite procedure recover without channel loss; directory bootstrap precedes startup read/repair, neither belongs to an operation cancellation window, and an old rewrite may only make builder completion/provenance unknown.
- Post-commit guide refresh exposes no builder policy to guide/scheduler owners and preserves the last complete schedule on failure. The public summary is constructed exactly once only after refresh settles; success omits `GUIDE_REFRESH_FAILED`, failure includes exactly one frozen safe record and `guideRefresh: 'failed'`, and retained results are immutable across polls.
- One shared main public-reference owner allocates from the complete fingerprinted aggregate generation before projecting either status or Guide, so hidden safe IDs reserve passthrough values and status/Guide call order is byte-identical. A unique persisted raw ID passes through byte-for-byte only after the exact safe regex check; hostile/unsafe values alias deterministically and duplicate generation IDs reject, so no unvalidated raw ID crosses. Guide accepts only an A/raw/B-consistent full generation within three attempts, projects every program to the exact occurrence/canonical-digest/collision ID, fails rather than omitting over 50,000/invalid/duplicate programs, and total-projects every display field through the exhaustive field/fallback/max-UTF-16 table. Required channel/program labels use only the table's named nonempty fallbacks; status `name` remains 1–160 units; non-null status `sourceLibraryName` is 0–160 units and therefore preserves present empty; source-library null remains null; other optional empty metadata remains empty; and quality/genre entries project before the 20-entry cap. Tune reloads the latest full generation and maps every post-resolution race/runtime failure to fixed `GUIDE_TUNE_FAILED` with no raw diagnostics. Projection never persists aliases, mutates storage, drops accepted rows/programs, or requires renderer/preload/guide-runtime/public-contract changes.
- Composition roots and named hotspots retain the dispositions/review caps in this plan. `channelRepository.ts` is surgical/non-increasing at no more than 769 lines with no new responsibility; `smokeAssertions.ts` decreases below 554 lines and only orchestrates the at-most-220-line focused smoke Channel Builder owner; independent cohesion/maintainability reviews pass.
- Imported/adapted upstream code is limited to the audited inputs, and 1A/1B/1C/1D each records its own serialized import-ledger entry before or with adaptation. The 1A and 1B entries explicitly record the Desktop security/determinism divergence from upstream title-based tie-breaks, the exact display-free semantic ordering/cap owner, and post-admission label projection without raw examples. Package 1C records BuildCommitter/BuildExecutor/mode/application semantic provenance even when independently reimplemented, and rollback preserves every ledger disposition.
- All eight exact content-DIP/CSS-viewport/DPR manual UI scenarios, four automated CSS-breakpoint sides, live Plex/restart/cancellation, and packaged Windows evidence pass with redacted proof. The exact `windowsAclProof` scope/status/package/time/three-four-key-result schema is the only safe manifest location: not-run is all-null/pending, unpackaged is boolean/pending-or-blocked and never passing, and packaged passes if and only if all 12 booleans are true. Packaged Windows `Get-Acl` plus `icacls` evidence proves those booleans; any missing/failed/ambiguous result keeps proof blocked, raw ACL material remains only in ignored `windows-checklist.md`, and relevant closure waits for reviewed WS9 packaged repetition.
- `UI-17`, `UI-18`, `UI-19`, `UI-21`, `UI-22`, `UI-23`, and `UI-24` have same-session fresh upstream-at-`0258dbe` and Desktop renders. Both manifests satisfy the exact top-level/row/nested schemas, patterns, UTC/hex lengths, repo-relative paths, insertion/key/array ordering, uniqueness, status/blocker/decision cross-products, scenario dimensions, ACL truth table, and unknown-key rejection. The verifier accepts them only as one pair with byte-equal session IDs and full upstream commits, exact per-row upstream capture-reference equality in order/multiplicity, paired capture SHA proof, and the exact captured Desktop `HEAD`; any mismatch rejects the whole session before all row conclusions and authority updates. After 1E, the reviewed import/direct-read closure starts from the frozen minimum list—including `src/renderer/setup/stagedSetupDom.ts` in every row it controls—and every resulting owner has per-file Git blob/SHA-256 and scoped-clean proof, capture hashes, and completed typography/color/spacing/artwork/clipping/focus/motion/state/interaction dispositions. A newly discovered owner stops capture until reviewed amendment; dirty/untracked/replaced/mutated sources, invalid or cross-session manifests, or unavailable capture/blocker keeps every affected conclusion open; pin/HEAD strings, stale 138 captures, and source inspection are never substitutes.
- `PB-22`–`PB-24` remain open after their WS2 playback/profile/helper policy gate until WS3 preference/control integration and any required native/Windows proof pass; IDs remain registered only to WS2.
- `ST-11`–`ST-16` remain open after WS3 contracts/persistence/controls until WS5 proves their `EPG-08`–`EPG-13` consumers as applicable; WS5 contributes without duplicate registry ownership.
- `ST-23` remains WS3-owned and must implement and verify the persistent Settings “Switch Profile” affordance before WS8 begins `ON-08` closure proof. `ON-08` remains open until that WS3 contribution and WS8's live/profile-switch lifecycle proof both pass; neither workstream duplicates the other's registry ownership.
- WS8 owns the shared main power-request and sleep/resume implementation/local-test gate for `WIN-04`; WS9 consumes it for `PB-27`, and both rows remain open until RD-27 packaged Windows sleep/wake/soak proof passes. WS9 creates no second lifecycle owner and repairs only a freshness-confirmed prerequisite gap through a reviewed gate.
- `PB-07` and `WIN-07` remain open after the WS2 implementation gate until the WS9 packaged redistribution/replacement-recovery contribution passes.
- Package 1F corrects a stale Windows proof-plan authority preamble before using it for new conclusions.
- Authority docs are updated only from observed evidence and open proof qualifiers remain open. At WS9 freshness opening, a reviewed roadmap update records the wrapper mapping and unblock sequence before product/proof execution. RD-27 stays blocked until WS1–WS8 and WS9 prerequisite implementation/hardening are complete/reviewed and the current Windows proof plan is refreshed; RD-27 then runs as WS9's observation phase, followed only after review by RD-28 package lifecycle proof.
- Before `PKG-03` work, WS9 records reviewed Alternative A private-MVP divergence/defer authority plus internal lifecycle acceptance, or an Alternative B public installer/signing/updater release plan and its acceptance. RD-28 alone cannot close the broad row; without the chosen decision and all associated acceptance, `PKG-03`, WS9, and program closeout remain blocked.
- WS9 preserves the roadmap's RD-27 and RD-28 owners and closes only after its prerequisite hardening, RD-27, and RD-28 subphases close serially; program closeout follows only after WS9/RD-27/RD-28 all close.
- Every later workstream is freshness-read, exact-file scoped, and adversarially reviewed before implementation.
- Full `npm run verify` and the relevant platform/manual gates pass at each workstream close, with no unrelated user changes overwritten.

## Replan Triggers

Stop the active package and return to planning if any of the following occurs:

- The exact package requires a product file outside its frozen list, or a named out-of-scope/hotspot disposition must change.
- A path classified Existing is absent/non-file, a New path already exists without reviewed resume ownership, a New parent is absent outside the three declared package-owned chains, or directory creation would traverse a symlink/non-directory or create any sibling/undeclared artifact.
- Any checkpoint cannot pass focused tests, typecheck, and Electron build without a later package, or a commit compatibility shim appears necessary.
- Plex facet needs cannot be expressed within the frozen item-facet-free families, complete ordered non-manual planned source trees, fields, lineage-bound identities, caps, partial-failure rules, callback-scoped `withSession` access port, four-method allowlisted session, exact discriminated item queries, separate three-method `LivePlexChannelBuilderFacetTransport`, separately named `facetTransport` and narrow-`Pick` `itemTransport` adapter dependencies, fixed typed transport/parser methods, and main-only all-leaf/filter materialization index without exposing privileged data. Replan if the adapter requires an intersection/combined transport parameter; either named dependency can substitute for the other; collection, playlist, or tag calls can touch `itemTransport`; item listing can touch `facetTransport`; `facet-count` cannot retain the validated nonempty raw tag `key` main-only beside raw-main-only semantic `tagValue`; genre/director/year cannot map exactly to that unprojected semantic value; or actor/studio requires a `tagValue`/`displayTitle`/digest fallback rather than exact raw-key fallback. Replan if the safe tag union cannot carry exact family-scoped `semanticGroupIdentity`, director-only `contentFilterIdentity`, and year-only numeric `yearValue` under the frozen null rules; equal raw group semantics across libraries do not produce equal family-scoped group digests; different families/semantics collide at the typed-preimage level; per-library or cross-library genre/director or combined/cross-library actor/studio groups, seeds, skip counts, or equality use anything except the group digest; year/decade parsing uses anything except `yearValue`; per-library director cannot use the unfiltered library source plus exact main-index content-filter reference; or a digest is substituted for a runtime value. Also replan if a typed Identity V1 constructor cannot remain synchronous, pure, no-retention, opaque-returning, and value-free on failure; main cannot invoke it directly with validated raw input; raw input enters any Package 1A planner/strategy/safe DTO or survives the constructor stack; tag identity/runtime query would use projected `displayTitle`; display projection would occur before semantic ordering/cap admission; any facet/group/member/candidate tuple, mixed-child order, seed, skip count, identity, or cap admission would depend on `displayTitle`; the exact family tuples cannot be used consistently by 1B and 1A; a safe projection would be derived from another safe projection; a malformed, credential/header/container-bearing, missing-family, or empty-family fastKey would be accepted; or raw key/`tagValue`/director filter text would cross a safe/planner/public/retained/diagnostic boundary. Replan if the 1A/1B import-ledger entries cannot record the explicit display-free tie-break divergence and post-admission label projection. Replan if the existing `LivePlexLibraryTransport` key set must change; `plexRuntimeIpc.test.ts` or `plexLibraryMinimalAdapter.test.ts` requires an edit; the real transport cannot satisfy both interfaces; `DesktopPlexRuntimeOptions` cannot add the separate optional `channelBuilderFacetTransport` while old constructors compile unchanged; production composition cannot pass the real transport explicitly under both separately typed runtime option names; missing injection does anything except the exact pre-acquisition nonretryable safe unavailable result; or implementation requires a cast, overload, setter, runtime method detection, or fallback from `libraryTransport`. Also replan if the Package 1C bound session cannot construct the Package 1B adapter with the dedicated facet field and existing library `Pick`, or if implementation proposes an item facet, item-facet identity/index entry, new manual source candidate, caller-controlled path/query/header/sort/filter/media type, generic Plex request, token/connection/session escape, session retention after callback, a second catalog fetch, or silently stops matching current-valid existing manual sources.
- The pure planner needs any input beyond normalized config, safe facet snapshot, exact raw-filter-free existing-lineup projection, explicit clock value, and seed; needs Electron, filesystem, transport, raw Plex/filter strings, global time/randomness, renderer state, or a Node/runtime hashing import; cannot share the sole canonicalJsonV1 Identity V1 owner across binding/facet/tag-group/content-filter/source/candidate/plan identities; serializes numeric-like ordinary object keys by engine integer-index order instead of exact Unicode code-point order (`"10"` before `"2"`); cannot validate the exact `contentFilterPlan` union or candidate identity from its digest alone; rejects or clamps valid `alternateLineupCopies = 3`, fails to emit base replica `0` plus alternates `1`, `2`, and `3`, or requires a `lineupReplicaIndex` outside integer 0–3 or null. Replan A1 if it touches outside its exact eleven-file list; changes `package.json` beyond the one existing script's domain-to-main test-path retarget; changes `package-lock.json`, the lifecycle command name, fixture/cap/Node version/isolated command; leaves the old domain benchmark path present; lets a domain test import main or edits an existing domain test; lets broad `test:contracts` run or claim the benchmark; changes `${{ !cancelled() && runner.os == 'Windows' }}`; cannot assert exact PR-head checkout; lets planner validation call the pure two-argument facets validator or otherwise bypasses the one identity capability; changes another facets API/behavior; changes canonical bytes/golden outputs; adds Node to domain; creates a second production entrypoint/native capability or test helper; omits any named hostile/golden class, inline-decade construction/validation counting proof, or same-digest/unequal-byte non-match fixture; or cannot preserve pure/native exhaustive parity. Missing/skipped/contended/wrong-SHA/wrong-Node/wrong-command evidence blocks Package 1B until corrected; an exact-head above-cap result activates `WS1-PERF-01` and is not a replan or Package 1B stop. Preserve all three immutable commits and the unmerged PR state.
- Replan Package 1C if the fixed compiled Worker entry cannot resolve in both development and packaged layouts without `eval`, code strings, a caller-controlled/arbitrary path, or build/package weakening; the structured clone changes planner semantics, identity bytes, ordering, or output parity; Worker termination cannot provide the exact canceled operation outcome and late-result discard; one-active/single-flight ownership, error/exit restart, or idempotent composition shutdown conflicts with another lifecycle owner; any raw diagnostic, secret, privileged object, or exception detail would cross the protocol; or implementation requires a public DTO/IPC/preload/renderer/persistence contract expansion. Do not fall back to synchronous Electron-main planning or `utilityProcess` locally; return to reviewed architecture planning.
- Facet `warningCodes` requires a value outside the exact seven discovery codes; is mutable, duplicate, unsorted, or over seven; `omittedMalformedCount` is not a safe integer 0–50,000 or violates its positive-iff-code rule; `omittedCappedCount` cannot use exact zero/no-code, exact positive bounded remainder, or null unknown/over-bound semantics; discovery would fetch extra pages merely to count, or aggregate a multi-source cap despite an unknown remainder or total above 50,000; conversion changes array order/phase/null strategy/count mapping; a strategy-specific warning is smuggled through the aggregate codes; any zero/positive/null state is absent from identity/golden/determinism proof; or warning dedup sums a group containing null, fails to sum an all-numeric group safely, sorts before dedup, or exceeds the 50-record cap.
- A newly planned or matchable raw binding/facet/source/filter field cannot fit the exact V1 preimage table; tag-group/content-filter identity cannot remain one-way, family/lineage bound, and independently recomputable; Identity V1 cannot serialize every finite JavaScript number with exact ECMAScript `JSON.stringify` semantics while preserving typed integer constraints; `PersistedStringV1` cannot preserve the complete raw existing ID/name through both NFC and exact UTF-16 code-unit sequence, NFC-equivalent raw-distinct values collapse, or any raw existing ID crosses a public DTO; the library-filter exception cannot accept every current non-forbidden own enumerable string key and string/finite-number value, preserve NFC-equivalent raw-key multiplicity without altering the runtime source, preserve exact own `__proto__`/`constructor`/`prototype` through null-prototype repository normalization/serialization/restart and every repeated `channelDomainClone` ownership clone without prototype pollution, or project/restart-match eligible legacy valid channels without lineup loss; `channelProvenance` cannot validate only own enumerable data properties, normalize to a null-prototype record, preserve valid persisted IDs exactly equal to `__proto__`/`constructor`/`prototype`, remove invalid markers locally, reject inherited/accessor/symbol/non-enumerable container state without channel loss, or round-trip valid markers through repeated clone/repair/CAS/JSON/restart without prototype pollution; the shared `cloneOwnEnumerableStringRecordWithNullPrototype` helper cannot serve both libraryFilter and provenance, any ownership clone regains a prototype, or safe handling requires widening Package 1C beyond the named repository/builder/clone/persistence owners; any identity requires delimiter concatenation outside its named domain; candidate/plan identity becomes circular; or a golden vector/collision tuple guard cannot pass.
- Replan Package 1C if the surgical
  `src/domain/channelBuilder/persistence.ts` responsibility requires planner,
  identity, config/default, new persisted-schema, public DTO, or unrelated
  persistence-policy behavior; cannot stay within persisted-state/provenance
  validation, normalization, current-lineup membership filtering, marker-local
  repair, shared null-prototype cloning, and startup-repair integration; or
  requires a production/test file outside the declared Package 1C registry.
- Replan Package 1C if the bare-builtin correction cannot stay within
  `buildEslintArchitectureRules.mjs` and its existing focused test; requires an
  edit to `desktopArchitectureRules.mjs`, a renderer file exception, product
  code, another verifier/test file, or another package; treats bare builtins as
  globs; permits bare `domain` or `node:domain`; weakens `node:*`, privileged
  main/preload/native-helper, non-literal dynamic, or literal forbidden dynamic
  import rejection; or changes the architecture policy rather than correcting
  its representation.
- Replan Package 1C if the emitted canonical factory runtime closure is not
  exactly `config.js` plus `constants.js`; either file cannot be copied
  byte-for-byte after the existing `tsc` step to the exact renderer-domain
  target; a source literal, source map, sibling, arbitrary directory, fallback,
  or compatibility wrapper is proposed; the copy requires build/package
  configuration, `src/main/protocol.ts`, `src/main/index.ts`, CSP, public
  contract, IPC, or default-owner changes; packaged proof cannot preserve the
  same two-file/excluded-sibling contract; or smoke still cannot resolve the
  canonical factory import through the unchanged contained protocol.
- Replan Package 1C if `playerOverlayPresentation.test.ts` needs any change
  beyond the exact `lineupRevision` and unknown-builder fixture fields; if a
  player/presentation input, assertion, scenario, behavior, or owner changes;
  or if another outside-registry path appears in the controller scope audit.
- Existing-lineup projection would subject a current-valid persisted ID/name to the new 512/control/display restriction, truncate/reject/alias it, accept a domain narrower than exact loader output, omit its raw main-ledger mapping, expose raw persisted content-filter values beyond the transient owning Package 1A constructor call or retain them instead of only the opaque identity, or let ID/name display safety change source disposition; would omit, block, truncate, alter, or reorder any current-valid persisted channel; widen the depth-8/500-leaf/512-character builder-safe source/filter constraints; fail to emit exactly one ledger row and the count-only warning; expose raw source/filter/reason; let retained-unmatchable match/update; fail to retain it byte-for-byte in append/merge and every unsuccessful path; remove it without confirmed successful non-empty replace; or silently narrow the current depth-25 validator.
- Any Package 1A/1B/1C exported seam requires an invented field/variant/null rule/overload, raw persisted content/Plex key would be compared with a hashed reference, a marker could match without exact valid version/lineage/source/content-filter/candidate recomputation, the materialization index cannot resolve every ordered source leaf plus inline/reference filter plan, a missing/wrong-family/mismatched director reference does not fail closed, or the index cannot follow the exact single-transfer/disposal lifecycle.
- Any zero-candidate pure append/merge/replace result could produce non-empty apply/materialization ID arrays, omit the sole `PLAN_EMPTY`, or expose runtime plan-ID/body/index behavior from Package 1A; or Package 1C could assign a non-null public plan ID, retain a body/index, accept `startApply`, or change the lineup.
- The closed review-diff DTO cannot represent the exact replace comparison or append/merge retained-entry reclassification within the frozen count/name caps and forbidden-field boundary; any raw review name or non-tag facet title is ordered, concatenated, capped, or snapshotted before the sole Package 1A helper; tag `displayTitle` is projected before semantic order/cap admission, is missing from an admitted safe snapshot, or affects any comparator/tie-break/cap; a credential-marker string retains any prefix/suffix or maps to anything other than complete `[redacted]`; the helper is duplicated outside `types.ts`; a consumer returns different output for the same options; Package 1C cannot use every exact per-public-field fallback/max pair while preserving nullable and optional-empty semantics; or an undefined alternate display-processing rule is introduced.
- The five IPC operations cannot implement the frozen exhaustive config/warning/apply unions, exact phase-local progress/terminal normalization, busy-before-plan-lookup and idle lookup precedence, exact sixteen-record `consumed-plan-capacity` tuple/available-plan retention, consumed precedence, single-use policy, or every exact materialization/non-materialization `(code, operation, source)` tuple without a new public operation or extra error mapping.
- `ChannelRuntime` cannot build the exact full repaired aggregate generation/fingerprint in one read; the shared public-reference owner allocates from Guide subsets/cache/call order instead of the complete generation, fails to reserve hidden safe IDs, or status/Guide call order differs; Guide cannot complete the exact A/presentation/B visibility/fingerprint check within the frozen three-attempt policy, returns partial/mixed data, or changes the exact stale error; any program passes through, is omitted, exceeds the exact 50,000/collision rules, or cannot use the frozen occurrence/canonical tuple identity; any named display string bypasses the sole Package 1A helper with its exact field options, differs from the pure helper's hostile-vector output, or leaks a raw capped entry; status `name` accepts empty or non-null `sourceLibraryName` rejects/rewrites present empty instead of honoring its exact safe 0–160-unit contract; tune does not reload the latest generation, exposes exception/raw-ID diagnostics, or changes the exact failure; channel/library alias allocation exhausts its frozen 500-ordinal/501-attempt range; the correction requires persistence, renderer, preload, guide-runtime, overlay, or public-contract edits; or it cannot fit entirely within the declared Package 1C owners/tests.
- Builder persisted-ID allocation cannot remain injected/main-only in existing `channelBuilderRuntime.ts`; does not reserve every `B` ID in every mode; accepts a value outside exact 32-lowercase-hex, uses anything other than eight attempts per new row, allocates out of ledger order, reassigns a matched merge ID, permits duplicate/`B`-occupied proposed or `F` IDs, edits `channelAuthoringService.ts`, or cannot fail with exact `channel-id-allocation` copy/flags before barrier/write/refresh/summary with byte-identical aggregate/revision.
- Builder review and application cannot use the frozen main-only Plex getter/result-error-null/subscription API, deep immutable initial/changed payload, idempotent unsubscribe, selected library-pair derivation, production `withChannelBuilderFacetSession` pre/post revalidation, relevant-notification abort, closure-captured token/connection, terminal session invalidation, exact safe failure mapping, monotonic context epoch, domain-separated bindings, per-plan selected-pair invalidation, single-use plan identity, and monotonic lineup lineage; a profile/server change does not expire all plans, an unselected library addition expires a plan, selected UUID removal/change does not expire only affected plans, or raw secrets/names/errors cross the seam.
- Existing storage cannot provide the frozen aggregate CAS/interleaving behavior, invalid-nested repair, or legacy-reader rollback without channel loss.
- Playlist/collection runtime materialization would use `.key` rather than exact `ratingKey`, or unequal-key identity/linkage/materialization/restart fixtures cannot pass.
- Any materialization status/reason, malformed ready shape, or unexpected rejection lacks the exact exhaustive table mapping; ready create input differs from the exact five required keys plus contentFilters only after valid inline/reference resolution and present-only seven direct generated optionals, includes a raw/digest/wrong-family/mismatched filter, `number`, another optional, null, or is later enriched; flags/copy/operation differ; settlement timing can override candidate-ledger ordinal precedence; canceled becomes an error; an invalid result could be downgraded to a skip; unavailable matched-retained materialization could continue; or replace could reach the barrier without at least one ready replacement and the exact byte-identical `CHANNEL_REPLACEMENT_EMPTY` failure.
- The apply owner cannot process successful rows serially in candidate-ledger order through unchanged authoring semantics; append/merge fail to fill the evolving set's lowest unused number, replace does not begin create numbering at 1, a materialization skip consumes a number, channel-number/configured capacity differs from the frozen order, or promise settlement changes numbering. Merge cannot materialize every matched-retained candidate before the barrier, map it to the exact retained ID, reproduce the pinned update/remove/preserve field projection while preserving `id`/`number`/`createdAt`, evolve the existing set, or abort without persistence on a matched materialization failure.
- Custom Channels cannot preserve builder metadata and serialize through the shared coordinator without acquiring builder policy.
- The bootstrap owner cannot run only after validated smoke state and successful lock but before persistence read/composition/IPC/app/window; cannot be bypassed exclusively for valid in-memory smoke; cannot validate/create only the exact canonical non-symlink channel parent and return the unforgeable parent/policy-bound capability; cannot fail startup with fixed redacted `CHANNEL_STORAGE_UNAVAILABLE`; or store/composition/operation code retains `mkdir`, accepts a missing/forged/wrong-parent/wrong-policy capability, or recreates a deleted parent.
- Startup repair cannot be the sole repair-write owner on the store mutation chain with exactly one full-file read and at most one complete atomic repair write; a missing file writes; corrupt/unsupported/read/repair failure can proceed or overwrite evidence; `ChannelPersistenceCoordinator.load()` or another ordinary read still repairs; Plex construction registers IPC; Plex/channel IPC or a window becomes reachable before repair succeeds; or Plex runtime/handler teardown cannot be exactly once.
- Within the bounded app-owned `userData`/single-instance/non-hostile-same-user threat model, an existing-destination cancel test cannot observe the required read-only destination open/handle-stat/read/close before the callback, or any cancel path performs a temporary-file open, exclusive/create/write-capable open, handle write/chmod/sync, rename/unlink/`mkdir`/repair/other filesystem mutation, or changes destination/aggregate/revision/guide; the store cannot invoke the policy-specific first temporary exclusive create open only in the proceed continuation without an intervening await/microtask/`mkdir`; POSIX differs from exact destination `O_RDONLY | O_NOFOLLOW` or temp `O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW` plus `0o600`; Windows uses `O_NOFOLLOW`, chmod, or a numeric mode, differs from exact destination `O_RDONLY` or temp `O_CREAT | O_EXCL | O_WRONLY`, reads before exact prior-`lstat`/handle-`stat` regular `(dev, ino)` equality, or does not inherit from the canonical per-user parent; either platform cannot enforce the shared 128-bit/eight-retry/handle-path-identity/type/collision/cleanup/sync-close/guarded-rename policy; cleanup identity/type mismatch is unlinked or not redacted; or an observed pre-rename failure cannot preserve destination bytes and terminal/no-guide-refresh rules. A requirement for hostile same-user or stronger Windows reparse-point resistance triggers a reviewed native Win32 owner replan, not an unproved Node flag.
- Repeated cancel while state is observable `canceling` or terminal `canceled` returns anything other than accepted/null, triggers a second abort/dispose/transition, another terminal state returns anything other than already-terminal, or any post-`proceed` cancel returns anything other than commit-started.
- Operation progress cannot remain monotonic within a phase, cannot advance `updatedAtMs` with each phase/progress change, fabricates a discovery total, differs from the frozen review-plan/materialize/persist/refresh values, or cannot normalize every canceled/failed terminal to exact `{ completed: 1, total: 1 }` without implying success.
- Apply result finalization would construct or expose summary before guide refresh settles, mutate it afterward, or cannot deterministically include/omit the exact `GUIDE_REFRESH_FAILED` record.
- Guide/scheduler changes beyond a generic post-commit lineup-change hook become necessary.
- A composition root must absorb feature policy, `renderer/workflow.ts` needs config/IPC/DOM/operation policy or more than 40 net lines, or another hotspot grows beyond its stated role.
- Package 1C cannot build its minimal staged request from the 1A default factory inside the declared `builderConfigState.ts`, duplicates default literals, requires editable/presentation/controller policy before 1D, or Package 1D would move/replace rather than extend that owner in place.
- `channelRepository.ts` would grow beyond 769 lines or acquire builder/aggregate/coordinator policy; `smokeAssertions.ts` would not decrease below 554 lines or would retain builder state logic; or `smokeChannelBuilderAssertions.ts` would exceed 220 lines or lack independent focused proof.
- Package 1C cannot record its serialized semantic-provenance ledger entry before/with BuildCommitter/BuildExecutor/mode/application adaptation, including independent reimplementation.
- Current upstream differs materially from the audited `0258dbe` semantics needed by a copied/adapted slice.
- Post-1E import/direct-read closure discovery finds a mapped-state owner outside the frozen minimum Desktop list and capture would proceed without reviewed amendment, or any approved `UI-17`/`UI-18`/`UI-19`/`UI-21`/`UI-22`/`UI-23`/`UI-24` upstream/Desktop product source is dirty, untracked, replaced, byte-different from its recorded blob, changes between preflight and capture, or cannot support a fresh render/comparison under the exact manifest contract; that row remains blocked rather than inheriting pin/HEAD strings or old captures.
- Either Package 1F manifest cannot enforce its exact top-level/row/nested keys, insertion/array order, uniqueness, patterns, UTC/hex/path rules, status/blocker/decision cross-products, scenario dimensions, or unknown-key rejection; the verifier cannot bind both manifests to byte-equal session/upstream commits, exact row-local upstream capture IDs in order/multiplicity, paired capture hashes, and the captured Desktop `HEAD`, or cannot reject any pair mismatch as a whole session before every row conclusion/authority update; `windowsAclProof` cannot enforce the exact not-run/unpackaged/packaged null/boolean/status truth table; raw ACL output, names, SIDs, or paths would enter a manifest/tracked conclusion; unpackaged proof would pass or substitute for WS9 packaged repetition; or verifier/contract tests do not reject the malformed case before authority updates.
- A workstream dependency, stable-ID owner, missing/partial/proof classification, exact manual UI scenario, breakpoint/scaling combination, or `PB-07`/`WIN-07` proof contribution changes.
- The `PB-22`–`PB-24`, `ST-11`–`ST-16`, `WIN-04`, or `PB-27` contribution/closure gates cannot be preserved without duplicate registry ownership, or WS9 would require an independent second power-lifecycle implementation.
- WS9 cannot record its wrapper/unblock mapping in the roadmap before execution, prerequisite implementation remains when RD-27 would begin, RD-27 observation discovers a required runtime/package correction, or RD-28 would begin before reviewed RD-27 completion.
- WS9 cannot obtain and record the explicit reviewed Alternative A or B `PKG-03` release-posture decision before implementation/proof, or RD-28 internal lifecycle evidence is being used to silently narrow/close the broad row.
- Electron startup cannot preserve smoke validation → single-instance lock → disk-bootstrap-or-smoke-bypass → Plex construction without IPC → channel startup load/repair → channel composition → Plex IPC → channel IPC → remaining IPC/app/window ordering, or a secondary process would bootstrap/read/register/create rather than exit and focus only the primary window.
- Electron smoke cannot validate the exact unique temporary-root/user-data/sentinel/nonce capability before startup; accepts environment-only, missing, mismatched, symlinked, outside-temp, or normal-user-data input; applies a Windows chmod/numeric-mode requirement or omits POSIX `0o600`; cannot use injected in-memory channel persistence; cannot guarantee validated-root cleanup; requires renderer/preload fixture access; or can touch normal user state.
- Packaged Windows proof lacks either `Get-Acl` or `icacls` for the canonical persistence parent/file and smoke root/sentinel; cannot prove current-user control; observes an Allow Write/Modify/FullControl grant for `Everyone`, `BUILTIN\Users`, or `Authenticated Users`; contradicts inherited-parent ACL ownership; or the packaged app cannot open/replace the channel file. The proof remains open and implementation/security policy must be replanned rather than waived.
- A named BrowserWindow content-DIP size does not produce the specified CSS viewport/DPR at the selected Windows scale and zoom.
- Repository state or authority docs change materially before a package begins, including overlapping user edits.
- A test would need to assert an implementation detail rather than the required observable contract, or live/visual proof is being substituted with fixtures.
- Review produces a must-fix finding that changes ownership, security, persistence, public contract, package boundaries, or rollback.

After this planning artifact passes docs verification, route it to an independent adversarial feature-plan review before any WS1 implementation.

NEXT_SESSION_HANDOFF
NEXT_SESSION_LAUNCHER: lineup-desktop-feature-plan
TASK: Complete 2026-07-22 Tier 3 Parity Correction Through Quality Loop
TASK_FAMILY: feature/design
TIER: Tier 3
PLAN: docs/plans/2026-07-22-tier3-parity-correction-plan.md
ARTIFACT: revised active Tier 3 parity-correction plan
FILES:
- docs/plans/2026-07-22-tier3-parity-correction-plan.md
BLOCKERS: none for Package 1B entry; A1 commit `335a13acfcee3f5450c104ed3fc48e45e461264a` completed its reviewed implementation/review, exact-head Windows Verify passed, and the isolated Windows Node 22.19 result was observed at 2,690.61 ms, activating non-blocking deferred debt `WS1-PERF-01`
MESSAGE:
ACTIVE_A1_HANDOFF_OVERRIDE: This paragraph supersedes every earlier conflicting pass-before-1B, provisional-A1, or pure-TS-only performance assertion retained as historical context. Preserve immutable commits `ca21ba1a5d641093e55b7c64b0910e317016ae37`, `aa224e5bed28341600d9fa33bd2fe7ac305aa2e4`, `d6a42a6e363ce32769f5b949ee5768b0cb438023`, and reviewed A1 commit `335a13acfcee3f5450c104ed3fc48e45e461264a`, the unmerged PR #19, and the user's unrelated authority-document edits. A1 received explicit implementation approval with no unresolved must-fix findings and was published by safe non-force push to `dev/ws1-channel-builder-1a`. Pull-request workflow run `30074270895` checked out and asserted exact head `335a13acfcee3f5450c104ed3fc48e45e461264a`; Ubuntu job `89421508459` passed; Windows Server 2025 job `89421508431` used Node `22.19.0`, passed ordinary `npm run verify`, and then executed the isolated `npm run verify:channel-builder-performance` command sequentially with no concurrent npm/Node test workload. The unchanged 50,000-candidate fixture measured `2,690.61 ms` and failed the unchanged 2,000 ms target. This exact-head above-cap result activates `WS1-PERF-01`; carry the run ID, head SHA, Windows runner, Node version, command, isolation statement, and measured milliseconds in every later WS1 handoff until separately resolved, without rerunning for a favorable sample or weakening the fixture/cap. It does not block Package 1B–1F implementation or honest WS1 progress. Package 1B may begin after its own freshness audit. Do not merge or change release state.

ACTIVE_PACKAGE_1C_SCOPE_AMENDMENT: Package 1C product implementation is paused
with its partial worktree preserved. The exact-file replan adds existing
`src/domain/channelBuilder/persistence.ts` only for the frozen
persisted-state/provenance validation, normalization, membership filtering,
shared null-prototype cloning, and startup-repair integration responsibility;
it adds no planner/identity/config/default/public DTO behavior and no new
file/test scope. Resume the preserved partial work only after one independent
must-fix-only plan review approves this amendment. Preserved code is trigger
evidence only, not evidence of correctness or implementation approval.

ACTIVE_PACKAGE_1C_VERIFIER_SCOPE_AMENDMENT: Package 1C product and verifier
implementation remain paused with the partial worktree preserved. The second
exact-file replan adds only existing
`tools/architecture-rules/buildEslintArchitectureRules.mjs` and
`tools/__tests__/build-eslint-architecture-rules.test.mjs` to correct the bare
Node builtin `domain` glob collision while preserving `node:*`, exact bare
builtin, privileged path, and forbidden dynamic-import rejection. It changes
no architecture policy, product/default/IPC scope, or other package. Resume
only after one independent must-fix-only plan review approves both Package 1C
scope amendments. The successful typecheck/build and collision probe are
trigger evidence only, not proof that the verifier correction or preserved
product implementation is correct.

ACTIVE_PACKAGE_1C_RUNTIME_CLOSURE_AMENDMENT: This is the third and final
material Package 1C seam decision. Product, verifier, and build-tool
implementation remain paused with the partial worktree preserved. The replan
adds only existing `tools/copy-renderer-assets.mjs` and
`tools/__tests__/copy-renderer-assets.test.mjs`; it copies exactly emitted
`config.js` and `constants.js` into the contained renderer-domain build path
after `tsc`, with byte-equal focused/build/package proof and Electron smoke. It
does not widen protocol/CSP, copy source or sibling modules, change
index/main/package configuration, or alter a public contract, IPC, or default
owner. Resume only after one independent must-fix-only plan review approves all
three Package 1C scope amendments. The smoke failure and prior passing
typecheck/build/focused/architecture gates are trigger evidence only, not proof
that the chosen artifact closure or preserved implementation is correct. Do
not request or add optional refinements after the material review is clean.

ACTIVE_PACKAGE_1C_REGISTRY_RECONCILIATION: The controller's final mechanical
scope audit adds only existing
`src/__tests__/renderer/playerOverlayPresentation.test.ts` for compile-fixture
conformance to the frozen public summary shape. Its complete authorized diff is
the exact `lineupRevision: 1` and unknown-builder fields; no player or
presentation behavior/assertion is reopened. The prior three material seam
decisions remain unchanged. Resume only after the independent must-fix-only
plan review confirms this exact-file reconciliation and no other outside path.

For the Package 1B adapter phrase above, review the now-frozen exact meaning: one closed dependency object has separately named `facetTransport: LivePlexChannelBuilderFacetTransport` and `itemTransport: Pick<LivePlexLibraryTransport, 'listLibraryItems'>` fields; no intersection or combined transport parameter exists, the three facet methods can call only the former, and item listing can call only the latter.

For Package 1C status projection, also verify required channel `name` remains a safe nonempty 1–160-unit display string while non-null `sourceLibraryName` is a safe 0–160-unit display string: present empty remains `''`, null remains null, and the focused contract/preload/public-reference tests pin both cases.

For the two corrected tag-semantics findings, review the complete raw/safe boundary and display-free order as one coherent contract. Main-owned Package 1B/1C call sites may pass validated raw `key`, `tagValue`, fastKey-derived filters, runtime source values, and persisted filter strings transiently into the owning synchronous pure Package 1A typed constructor solely to canonicalize/hash and receive an opaque identity; the constructor cannot retain, log, diagnose, stringify into an exception, cache, asynchronously capture, or return raw data, and no raw value enters a planner/safe/public DTO or retained state. Then verify the exact frozen count-plus-family facet tuples, group tuple, mixed-member tuple, decade order, and seed tuples drive source/candidate order, skip counts, identities, and every cap admission; `displayTitle` is projected only for admitted entries, then attached as copy, and never acts as comparator, tie-breaker, group key, seed, identity, or cap input. Capacity-boundary redaction, truncation, collision, and raw/display-divergence fixtures must preserve semantic order, survivors, seeds, and identities. Verify `ChannelBuilderTagSemanticGroupIdentity` alone drives per-family cross-library/combined grouping; `ChannelBuilderContentFilterIdentity` alone represents normalized filter equality; director-only `main-index-reference` plans resolve raw equality filters only during main materialization; exact numeric `yearValue` alone drives decade construction; and the Package 1A/1B ledger entries record the explicit Desktop security/determinism divergence from upstream title tie-breaks without raw examples. Also verify canonical JSON ordinary numeric-like keys serialize in Unicode code-point order with exact `"10"` before `"2"`. Treat the current partial Package 1A code and tests as non-authoritative evidence: do not edit, accept, checkpoint, or use their present `displayTitle`-driven grouping/filter/year/order/cap behavior to weaken this plan.

For Package 1A candidate/planner review, preserve the approved config range `alternateLineupCopies = 1..3` and verify the candidate contract accepts `lineupReplicaIndex` integer 0–3 or null: base is `0`, configured alternates are exactly `1..N`, and the explicit `N = 3` fixture emits `1`, `2`, and `3` without clamping, rejection, or omission.

The review must also reclose the prior blockers: Package 1C's separately named optional `channelBuilderFacetTransport` constructor option, exact null/unavailable result, explicit production two-option wiring, distinct facet-versus-item dependency routing, no intersection/cast/setter/detection/fallback, and unchanged out-of-scope old constructors/fakes; plus null-prototype `channelProvenance` construction, descriptor-based own-property validation, shared dictionary-safe cloning, magic persisted-ID repair/mutation/serialization/restart proof, rollback, and replan coverage.

For the verifier amendment, review only the material seam: bare builtins are
exact restricted imports rather than glob patterns; the frozen renderer static
Package 1A config/types imports are allowed; and bare `domain`, `node:domain`,
privileged main/preload/native-helper paths, and forbidden dynamic imports stay
rejected without an exception, policy change, or extra file.

For the final runtime-closure amendment, review only the material seam: the
existing post-`tsc` asset owner copies exact emitted `config.js` and
`constants.js` byte-for-byte to the exact renderer-domain path; focused,
build-output, package, and smoke proof exclude every named sibling/source-map
and preserve protocol containment/CSP. Any protocol, source-copy,
index/main/package-configuration, contract/IPC/default-owner, additional-file,
or optional-refinement proposal is out of scope.

For the mechanical registry reconciliation, confirm the entire
`playerOverlayPresentation.test.ts` diff is only the exact two required
`channelSummary` fields and that no player/presentation assertion, behavior, or
coverage changed.

ACTIVE_WS1_PACKAGE_1F_HANDOFF_2026_07_28: This paragraph supersedes the stale
Package 1F cancellation-race blocker and is the current cross-machine
continuation boundary. Preserve commits `027e674` (`test(ws1): harden channel
builder evidence contract`) and `e9da53d` (`fix(ws1): make channel builder
commit transition atomic`). The fix makes the abort decision and commit-barrier
publication one synchronous owner transition, publishes exact
`running`/`persist` state only after commit is irrevocable, and removes the
runtime's earlier pre-barrier persist publication. Focused main/preload
contracts passed 42/42, the exact visual-evidence contract passed 94/94, and an
independent implementation rereview reported no findings.

On a fresh Electron build of exact commit `e9da53d`, after operator-owned Plex
linking and selected-server restoration through the safe public bridge, the
repaired live cancellation boundary passed without recording account, server,
library, media, credential, endpoint, or machine-path material. A pre-barrier
live merge cancel was accepted while apply was in `materialize`; the operation
ended `canceled`, lineup revision remained 4, and channel count remained 401.
A separate post-barrier live merge apply was observed at
`running`/`persist`; cancel was rejected with exact reason `commit-started`,
the operation ended `succeeded`, guide refresh completed, revision advanced
from 4 to 5, and channel count remained 401. After a complete app close and
restart, safe status reported revision 5, 401 channels, and `configured`.
Therefore the cancellation race is resolved and is no longer a Package 1F
blocker.

WS1 and Package 1F are not closed. No approved paired capture manifests yet
close `UI-17`, `UI-18`, `UI-19`, `UI-21`, `UI-22`, `UI-23`, or `UI-24`.
The repaired exact-HEAD live run exercised merge cancellation only; live safe
facet discovery across multiple eligible libraries, the complete supported
filter surface, and live append and replace review/apply proof remain open.
The named manual Windows scale/zoom, contrast/reduced-motion, D-pad/gamepad,
slow/blocked-state, and packaged ACL obligations remain open. Full
`npm run verify` is not currently a green closeout claim: one observed run
passed the 939-contract surface with 937 passed and 2 skipped but later failed
two unrelated packaging-harness environment assertions; another observed an
intermittent unrelated concurrent first-run Plex-client-identity failure that
passed 3/3 in isolation. `npm run verify:redaction` is also obstructed on this
Windows worktree only by the unrelated untracked
`src/native-helper/Lineup.NativePlayerHost/obj/` generated tree, which must not
be committed as WS1 evidence.

Carry `WS1-PERF-01` unchanged: workflow run `30074270895`, job `89421508431`,
exact head `335a13acfcee3f5450c104ed3fc48e45e461264a`, Windows Server 2025,
Node `22.19.0`, unchanged deterministic 50,000-candidate fixture, and isolated
command `npm run verify:channel-builder-performance`, executed sequentially
with no concurrent npm/Node test workload. It measured 2,690.61 ms against the
unchanged 2,000 ms cap. The above-cap result remains honest deferred debt and
is not resolved by a later non-authoritative local sample.

ACTIVE_WS1_PROOF_DEFERRAL_AND_WS2_ENTRY_OVERRIDE_2026_07_28: This is an
explicit user-approved sequencing amendment and supersedes the earlier rule
that WS2 cannot start while WS1 is active. The decision is **accept with
modification**: unavailable screenshots and broader manual testing are
deferred, not waived, passed, or converted into implementation evidence. The
same disposition applies to the other still-open Package 1F proof-only gates
listed above so they cannot indirectly block playback development. WS1 remains
open, its stable IDs and evidence classifications do not advance, and its
deferred proof debt must be completed before any claim that WS1 or the full
parity-correction program is closed.

The exception is justified by observed implementation state rather than an
assumed pass. WS1's shared lineup persistence/mutation boundary is implemented,
the cancellation race is repaired and reviewed, focused contracts pass, and
live merge proof plus restart persistence establish a usable channel lineup for
playback development. The remaining WS1 blockers are evidence/closeout work and
do not currently identify a product defect in the shared playback dependency.
`WS1-PERF-01` is separate from unavailable proof: it remains an observed
2,690.61 ms failure against the unchanged 2,000 ms target under its existing
non-blocking deferred-debt disposition. This amendment neither passes nor
weakens that target. The result does not identify a WS2 playback dependency,
but it remains open and must be carried until separately resolved or reviewed
under the plan's existing performance-debt policy. If later proof contradicts
the sequencing assumption or exposes a lineup, persistence, guide-refresh, or
mutation defect, stop immediately before any further WS2 product edit, commit,
or workstream advancement and route the smallest reviewed WS1 repair.

This amendment authorizes exactly WS2 freshness, plan review, and—only after
that reviewed plan is implementation-ready—WS2 product implementation. It does
not authorize WS3 through WS9, mark any WS1 row complete, weaken a future
Windows/manual or packaged gate, or let WS2 edit Package 1F evidence owners to
manufacture closure. WS2 must treat the 24 registered playback IDs as audit
inputs rather than assume the older RD-25/RD-26 “code complete” statement means
current parity. Its freshness pass must reread those rows, current player,
Plex-stream, native-helper, preload, renderer, persistence/cleanup, and test
owners, plus current upstream behavior, then classify what is already correct,
what is partial, and what is missing before freezing exact files.

MacBook entry conditions are:

- fetch the published `initial-build` branch and begin from this reviewed
  amendment;
- run a fresh clean-checkout baseline, including `npm run verify`, before WS2
  implementation; resolve every failure or record a reviewed exact
  pre-existing/non-WS2 disposition before any product edit rather than merely
  noting or weakening it;
- keep renderer custody unprivileged and retain credentials, headers, tokenized
  URLs, native handles, raw Plex payloads, helper internals, and native logs in
  privileged owners only;
- preserve all WS1 product, evidence-harness, manifest, checklist, and
  authority-document owners unless a reviewed cross-workstream replan names the
  exact shared edit;
- keep Windows native-playback, video-surface, fullscreen, recovery,
  track-selection, HDR, and packaged-helper observations open when the MacBook
  cannot prove them; and
- exclude `src/native-helper/Lineup.NativePlayerHost/**` from MacBook product
  edits unless the reviewed WS2 plan names and successfully runs at minimum
  `dotnet build src/native-helper/Lineup.NativePlayerHost/Lineup.NativePlayerHost.csproj --configuration Release`
  plus the relevant protocol/factory contract tests; if that proof is
  unavailable, route any helper change to a separately reviewed Windows-capable
  unit; and
- stop before implementation if freshness cannot isolate a bounded WS2 unit,
  requires a new dependency/package policy, or contradicts the current
  helper-hosted native-libmpv architecture.

Codanna semantic search was attempted for the playback owner sweep but the
current index reported that embeddings were unavailable. Discovery therefore
fell back to direct reads of `docs/architecture/CURRENT_STATE.md`,
`docs/architecture/playback-architecture.md`,
`docs/product/lineup-product-parity-matrix.md`, the roadmap, and `rg` inventory
of the current player/Plex/native-helper/renderer/test surfaces. No WS2 exact
file list is frozen by this sequencing amendment.

NEXT_SESSION_HANDOFF
NEXT_SESSION_LAUNCHER: lineup-desktop-feature-plan
TASK: Complete WS2 Playback Through Quality Loop
TASK_FAMILY: feature/design
TIER: Tier 3
PLAN: docs/plans/2026-07-22-tier3-parity-correction-plan.md
ARTIFACT: reviewed WS1 proof-deferral and WS2-entry sequencing amendment
FILES:
- docs/plans/2026-07-22-tier3-parity-correction-plan.md
- docs/architecture/CURRENT_STATE.md
- docs/architecture/playback-architecture.md
- docs/product/lineup-product-parity-matrix.md
- docs/roadmap/desktop-port-roadmap.md
BLOCKERS: none for WS2 freshness and planning; product edits remain blocked
until the WS2 plan freezes exact files, verification, acceptance, and replan
triggers and passes adversarial review
MESSAGE:
Start the reviewed Tier 3 WS2 freshness pass from the active sequencing
amendment. Audit all 24 WS2 IDs against current playback code, tests,
architecture, and current upstream behavior; reconcile the older RD-25/RD-26
code-complete claim with the reopened parity requirements; freeze the smallest
vertical playback unit that produces real user value; and route the
decision-complete exact-file plan to lineup-desktop-feature-review before any
product edit. Carry all deferred WS1 and Windows-native proof as open debt.

---

ACTIVE_WS2_EXECUTION_AMENDMENT_2026_07_28: This is the current whole-WS2
execution authority. It supplements the plan's existing required headings and
supersedes only the stale implication that RD-25/RD-26 code-complete wording
established current playback parity. The task remains Tier 3 feature/design
work. Product edits remain blocked until an independent
`lineup-desktop-feature-review` approves this amendment and explicitly approves
Package 2A with no unresolved material finding.

**ACTIVE_WS2_MAC_COMPLETION_OVERRIDE_2026_07_28:** the user's latest explicit
direction supersedes every conflicting Windows-machine, `.NET` Release-build,
native-helper build, live libmpv ERROR/EOF-path, Windows soak/manual, or Windows
capability-proof requirement anywhere in this canonical plan solely to the
extent that requirement would gate WS2 work, Package 2A–2E progression,
WS2 checkpoint/commit/publishing, or WS2 closeout. This plan-wide-as-applied-to-
WS2 precedence explicitly includes the earlier “relevant platform/manual gates
pass at each workstream close” clause and the earlier MacBook entry condition
that required a `.NET` Release build before any native-helper edit. Those
earlier clauses retain full, unchanged force for WS1, WS3–WS9, RD-27, RD-28,
their own workstream gates, and overall parity-program closeout; this override
neither waives nor defers any non-WS2 obligation. The superseded WS2
observations are now one named post-WS2 validation debt,
`WS2-POST-VALIDATION-01`, and are not executable WS2 packages or acceptance
gates. Their absence cannot block Package 2A checkpoint/commit/publishing,
Packages 2B–2E, Package 2D's conservative no-op disposition, Package 2E
authority reconciliation, or honest WS2 closeout on this Mac. This override
does not convert missing proof into support: the production capability profile
stays conservative, every affected row remains partial/proof-open or
later-contribution as classified below, and no capability may be promoted until
the deferred proof is later obtained and independently reviewed. Preserve the
exact implemented Package 2A diff and all observed local review/verification
evidence; no Windows command is rerun or fabricated for WS2.

### WS2 freshness evidence and claim boundary

Desktop was independently observed at clean `initial-build` HEAD
`76b741caed85623671419b5dbc95e67b7c7714df`, tracking
`origin/initial-build`. The controller observed a clean full `npm run verify`
baseline at that checkpoint before this plan edit. This planner independently
observed the clean worktree and exact HEAD but did not rerun the already-green
full baseline. The sibling upstream checkout was observed at audited authority
`0258dbe15b04d2d141d0a4a44575fecb5bb72d41`; its tracked
`scorecard.png` modification and untracked local documents are unrelated and
must not be read as product authority, adapted, or committed.

Codanna reported a fresh index with semantic search enabled, but the broad
playback query returned sparse capability/contract matches and noisy unrelated
results. Exact discovery therefore fell back deterministically to `rg`,
`rg --files`, line-count inventory, and direct reads of the current Desktop
contracts, main/player and main/Plex owners, preload, renderer overlays, native
helper, focused tests, authority docs, and the scoped upstream player, recovery,
stream, navigation, settings, and error-recovery owners. This fallback is the
recorded discovery path for WS2.

RD-25/RD-26 remain valid historical implementation claims at their reviewed
scope: production-shaped Plex resolution, private descriptor handoff, native
helper process/protocol, renderer-safe events, track/quality state, and
renderer controls exist. They do not establish the reopened rows because
`getProductionCapabilityProfile()` still advertises only MP4/H.264/AAC direct
play, subtitle delivery `none`, and unsupported audio/subtitle switching, HDR,
Dolby Vision, direct stream, and every transcode family. Current Desktop also
has a manual same-channel Retry/Guide error surface but not the audited
upstream behavior of three bounded automatic retries plus explicit Retry and
Skip recovery actions. Current native-helper source maps every
`MPV_EVENT_END_FILE` to `ended` without reading
`mpv_event_end_file.reason` or `.error`; command timeouts settle command
dispatch and are not a production mid-playback trigger. Current `playerIpc.ts`
uses one `sendPlayerEvent` callback for synchronous command/cleanup result
arrays and asynchronous adapter events, while `bootstrapPlaybackRuntime()`
does not pass the composition's existing `onEvents` seam. Finally,
`ChannelScheduler.skipToNext()` synchronously emits `programStart`, while
`src/main/index.ts` observes its async runtime-start handler as `void`. Those
three facts are must-fix ownership inputs below. Windows production media,
hardware, video-surface, track, HDR, recovery, and packaged-helper observations
remain unproved.

The audited upstream behavior at `0258dbe` is a functionality target, not a
Desktop ownership template:

- `RetryManager.ts` caps automatic network retries at three with delays of
  1,000, 2,000, and 4,000 ms, cancels owned timers/listeners, and resets after
  successful playback;
- `PlaybackRuntimeController.ts` attempts the current supported fallback before
  surfacing a nonrecoverable playback failure and advances after ended media;
- `RecoveryActions.ts` exposes explicit Retry and Skip for playback failures;
- subtitle, audio, DTS, HDR/Dolby Vision, direct-stream, transcode, and fallback
  policy are driven by upstream settings and browser/webOS capability owners.

Desktop preserves those user-observable recovery semantics where approved
below but intentionally diverges in ownership: retry/skip orchestration stays
main-owned, renderer calls remain narrow and validated, helper/libmpv and Plex
details never cross the bridge, and Windows-observed facts rather than upstream
webOS constants decide the production capability profile.

### WS2 registry audit

Every WS2 ID has exactly one present classification from the approved
vocabulary. A classification is not closure.

| ID | Present classification | Observed Desktop/upstream reconciliation | WS2 disposition |
| --- | --- | --- | --- |
| `LIB-05` | implemented-but-proof-open | Main-owned stream parsing covers files, parts, streams, language, dynamic range, and track identity; live representative samples remain unobserved. | Local automated proof is sufficient for the WS2 implementation gate; representative native samples remain `WS2-POST-VALIDATION-01`. Do not change parser absent a demonstrated defect. |
| `PB-01` | implemented-but-proof-open | Guide/current-program tuning reaches the production-shaped runtime. | Local runtime/integration proof closes the WS2 implementation gate; production Windows media observation remains `WS2-POST-VALIDATION-01`. |
| `PB-02` | implemented-but-proof-open | Mini-guide tune and channel transition exist; Windows native-video/focus proof remains. | Local transition/focus tests close the WS2 implementation gate; native Windows observation remains `WS2-POST-VALIDATION-01`. |
| `PB-03` | implemented-but-proof-open | Three-digit entry, timeout, invalid result, and tune exist. | Local input/runtime tests close the WS2 implementation gate; keyboard/numpad observation remains `WS2-POST-VALIDATION-01`. |
| `PB-04` | partial | Direct Play exists, but production truth is deliberately MP4/H.264/AAC only. | Keep the current conservative literal profile; Package 2D is a no-op. Broader native observation/promotion is deferred to `WS2-POST-VALIDATION-01`. |
| `PB-05` | partial | Policy/resolver remux paths exist while production remux/audio conversion are disabled. | Keep unsupported in Package 2D; observation/promotion is post-WS2 debt. |
| `PB-06` | partial | PMS start/release and transcode setup paths exist while every production transcode family is disabled. | Keep unsupported in Package 2D; observation/promotion is post-WS2 debt. |
| `PB-07` | later-workstream contribution | WS2 source/non-packaged helper boundary exists; packaged helper/libmpv redistribution remains WS9/RD-28-owned. | Local static/protocol/integration proof completes the WS2 contribution; native build/live validation is `WS2-POST-VALIDATION-01`, and packaged proof remains WS9/RD-28. |
| `PB-08` | partial | Renderer/native presentation structure exists, but current production video plus mandatory three-row Windows audit is open. | Local presentation tests close the WS2 implementation gate; native three-row audit remains `WS2-POST-VALIDATION-01`. |
| `PB-12` | implemented-but-proof-open | Contract/helper/renderer states cover idle, loading, buffering, seeking, stalled, ended, and error. | Packages 2A/2B plus platform-neutral tests close the WS2 implementation gate; live native states remain post-WS2 debt. |
| `PB-13` | partial | Manual same-channel retry exists; bounded automatic retry and upstream Retry/Skip action parity are missing. libmpv may report interrupted/incomplete/corrupt playback as EOF as well as ERROR, so an ERROR-only helper seam cannot prove every interruption class. | Packages 2A/2B plus deterministic 1/2/4 and explicit-action tests close the WS2 implementation gate. Live ERROR/EOF classification remains `WS2-POST-VALIDATION-01`, so the row stays partial. |
| `PB-14` | implemented-but-proof-open | Crash detection, cleanup, safe diagnostics, and replacement-process behavior have automated/harness coverage. | Local lifecycle/order/replacement tests close the WS2 implementation gate; native soak remains post-WS2 and packaged soak remains later. |
| `PB-19` | partial | Renderer/helper track list and selection paths exist but production switching is disabled. | Package 2D keeps switching unsupported; native observation/promotion is post-WS2. |
| `PB-20` | partial | Subtitle Off/list/selection paths exist but production delivery is `none` and switching disabled. | Package 2D keeps delivery/switching unsupported; native observation/promotion is post-WS2. |
| `PB-21` | partial | Direct/conversion/burn-in policy and resolver tests exist; production conversion/transcode and Windows samples are disabled/unproved. | Package 2D remains conservative/no-op; native samples are post-WS2 debt and there is no renderer-side subtitle pipeline. |
| `PB-22` | later-workstream contribution | Forced/default selection policy exists; preferred-language contract/persistence/control belongs to WS3. | Preserve WS2 policy/tests and close the WS2 contribution; the row remains open through WS3 and any post-WS2 native proof. |
| `PB-23` | later-workstream contribution | Audio fallback policy exists; DTS preference/control belongs to WS3 and production support is unproved. | Preserve and close the WS2 contribution; the row remains open through WS3/post-WS2 native proof. |
| `PB-24` | later-workstream contribution | HDR10/HLG/Dolby Vision metadata, policy, and helper quality state exist; fallback preference/control belongs to WS3 and production support is unproved. | Preserve and close the WS2 contribution; the row remains open through WS3/post-WS2 native proof. |
| `WIN-01` | named Windows/native/package blocked | Current production breadth is conservative by design; Mac and upstream constants cannot establish Windows libmpv/hardware truth. | Remains open as `WS2-POST-VALIDATION-01`; it does not block WS2 and cannot enable Package 2D promotion. |
| `WIN-06` | named Windows/native/package blocked | Safe quality summaries exist, but actual GPU/display/media capability and fallback diagnostics are not observed. | Remains open as `WS2-POST-VALIDATION-01`; a future privileged diagnostic need requires its own reviewed replan. |
| `WIN-07` | later-workstream contribution | Process isolation, redaction, and support bundle exist; packaged replacement-helper recovery belongs to WS9/RD-28. | Local lifecycle proof completes the WS2 contribution; native validation is post-WS2 and packaged recovery remains WS9/RD-28. |
| `UI-41` | implemented-but-proof-open | Runtime-backed idle surface exists and has historical local-match evidence. | Local renderer/runtime proof closes the WS2 implementation gate; native observation remains post-WS2 debt. |
| `UI-42` | implemented-but-proof-open | Runtime-backed loading transition exists and has historical local-match evidence. | Local renderer/runtime proof closes the WS2 implementation gate; native observation remains post-WS2 debt. |
| `UI-43` | partial | Error surface exists, but it substitutes Guide for upstream Skip and lacks bounded automatic recovery presentation. | Packages 2A/2B implement and locally prove recovery actions; live native observation remains post-WS2 debt. |

No WS2 row is presently classified `already correct for present gate` or
`missing`: the former implementation-shaped rows still have named proof debt,
and the newly identified recovery gap is partial rather than absent.

### WS2 architecture, security, and lifecycle invariants

- Electron main owns scheduler selection, retry/skip orchestration, Plex stream
  resolution, PMS leases, privileged playback descriptors, helper lifecycle,
  and capability truth. Preload validates narrow closed requests/results.
  Renderer owns display, focus, and ephemeral pending-action state only.
- Renderer never receives credentials, headers, tokenized URLs, raw Plex
  payloads, server/connection details, native handles, helper internals, native
  logs, process details, app paths, engine track ids, or capability-probe raw
  output.
- Retry, skip, stop, teardown, schedule tick, channel switch, server/profile
  change, helper crash, and replacement playback each have one generation owner.
  Timers, async completions, PMS leases, helper processes, and player requests
  are canceled, released, or quarantined by that owner.
- Automatic recovery is limited to the current scheduled identity. A stale
  timer or completion cannot restart old media, revive a released PMS lease,
  overwrite a newer player snapshot, or consume a retry budget belonging to a
  replacement program.
- Asynchronous adapter events and synchronous renderer-command/cleanup result
  events have different named sinks. Adapter batches enter the runtime exactly
  once; runtime-emitted batches and synchronous IPC result batches each reach
  the renderer exactly once. No event is fed through both paths.
- One main-owned schedule-transition owner is the only `programStart`
  subscriber used for playback and the only recovery caller of
  `skipToNext()`. It installs skip settlement before the scheduler's
  synchronous emission and resolves only after the resulting runtime start.
- Production capabilities stay conservative until exact Windows observations
  pass. Policy branches, helper source, dev harnesses, upstream constants, or a
  successful .NET build do not by themselves enable a capability. Those
  observations now occur only under `WS2-POST-VALIDATION-01`; their absence
  does not block WS2 closeout.
- There is no new dependency, package/lockfile policy, persistent schema,
  credential/storage owner, renderer browser storage, compatibility shim,
  fallback API variant, broad RPC bridge, or duplicated public contract.
- No Package 2A/2B code touches WS1 product/evidence/manifest/checklist owners.
  If playback work exposes a lineup, persistence, guide-refresh, or mutation
  defect, stop before further WS2 product edit or commit and route the smallest
  reviewed WS1 repair.
- Package 2A is the reviewed exception for exactly
  `src/native-helper/Lineup.NativePlayerHost/Program.cs`. It adds the official
  `mpv_event_end_file` layout and reason branch; it does not add a helper
  envelope or expose raw mpv values. This macOS workspace has no `dotnet`
  executable. Package 2A therefore checkpoints from the named platform-neutral
  static/protocol/adapter/process/runtime/smoke/full gates plus independent
  review. Release build and live native validation are
  `WS2-POST-VALIDATION-01`, not commit or closeout blockers. A second helper
  file, P/Invoke signature, dependency, project, package, or envelope change
  still requires reviewed replan.
- Any copied or behaviorally adapted upstream recovery slice receives a
  serialized import-ledger row before or with its implementation checkpoint.
  No upstream dirty artifact is in scope.

### WS2 files out of scope for every package

- WS1 Channel Builder product, evidence harness, paired manifests, checklists,
  performance fixture/cap, and authority conclusions
- WS3–WS9 product or authority implementation, including Settings preference
  contracts/persistence/controls, input/media keys, Guide feature work, release
  packaging, signing, updater, installer, helper/libmpv redistribution, and
  RD-27/RD-28 execution
- `src/main/persistence/**`, Plex credentials/auth/discovery/library browsing,
  channel mutation/persistence, diagnostics schema, package/lockfile files, and
  public release configuration
- native-helper files other than Package 2A's exact `Program.cs` exception

### WS2 file-shape disposition

Observed attention owners are `src/contracts/player.ts` (726 lines),
`src/main/player/desktopPlayerAdapter.ts` (640, named hotspot),
`src/main/player/plexPlaybackRuntime.ts` (566),
`src/main/player/streamPolicy/desktopStreamPolicy.ts` (624),
`src/main/plex/streamResolver.ts` (666),
`src/renderer/playerOverlayController.ts` (797), and native-helper
`Program.cs` (1,414).

`plexPlaybackRuntime.ts` remains the main request/epoch/active-session
coordinator, but Package 2A extracts the distinct retry timer/budget lifecycle
into a focused owner rather than adding that lifecycle to the coordinator.
`Program.cs` may grow only for end-file constants, the exact sequential struct,
and focused branch/emitter. `playerIpc.ts` receives only the two named delivery
callbacks and their call-site split, not a new lifecycle.
Package 2B extracts the distinct renderer player-error recovery request,
generation, and settlement lifecycle into
`playerErrorRecoveryController.ts` and the schedule transition into
`playbackProgramTransitionOwner.ts`; `playerOverlayController.ts` remains the
overlay/timer/focus coordinator and must not grow to absorb either policy. The
new owners must perform meaningful request-generation and synchronous-event
settlement behavior rather than act as forwarding wrappers. Reaching 800 lines in
`playerOverlayController.ts`, needing a second unrelated recovery policy, or
making renderer state authoritative triggers replan and fresh architecture
review. Package 2D is now an explicit conservative no-op and edits no
capability-profile, policy, resolver, source, or test owner during WS2. Any
future post-validation promotion requires a new reviewed post-WS2 plan with
observed facts and a fresh cohesion disposition. The named adapter hotspot
stays no-touch. The 1,414-line helper
receives only the bounded exception above and otherwise stays no-touch. Every
production-source package runs `npm run verify:maintainability` and gets fresh
architecture review.

### WS2 serial execution packages

Parallel product edits are prohibited. Packages execute exactly
2A → 2B → 2D conservative no-op → 2E. Former Package 2C is removed from the
executable WS2 graph and retained only as
`WS2-POST-VALIDATION-01`. Package 2A has no Windows/.NET completion sub-gate:
its checkpoint, commit, and publication proceed after the complete Mac-runnable
automated/static/smoke/full verification and fresh independent review pass.
Package 2D completes by recording that the current conservative profile is
unchanged and that promotion is deferred; it performs no product/test edit,
needs no Package 2C input, and cannot infer support. Package 2E follows that
reviewed no-op disposition.

#### Package 2A — bounded current-program automatic recovery

**IMPLEMENTER_ROLE_ELIGIBILITY:** `worker`. The owner and behavioral boundary
are frozen, but integrating native event classification, a timer lifecycle,
and exact event provenance with existing epoch/cleanup ordering requires
bounded design judgment. `worker_sol_low` and `worker_luna` are not eligible.
The helper edit may be checkpointed, committed, and published on this Mac after
all named platform-neutral gates and fresh independent review pass. Deferred
Windows/native validation is recorded but is not Package 2A acceptance.

**Owned files:**

- `src/native-helper/Lineup.NativePlayerHost/Program.cs`
- new `src/main/player/plexPlaybackRecoveryOwner.ts`
- new `src/main/player/playbackEventRouter.ts`
- `src/main/player/playerIpc.ts`
- `src/main/player/plexPlaybackRuntime.ts`
- `src/main/player/plexPlaybackComposition.ts`
- `src/main/player/playbackRuntimeBootstrap.ts`
- composition-only callback wiring in `src/main/index.ts`
- new `src/__tests__/main/player/plexPlaybackRecoveryOwner.test.ts`
- new `src/__tests__/main/player/playbackEventRouter.test.ts`
- `src/__tests__/main/playerIpc.test.ts`
- `src/__tests__/main/player/plexPlaybackRuntime.test.ts`
- `src/__tests__/main/player/plexPlaybackComposition.test.ts`
- `src/__tests__/main/player/playbackRuntimeBootstrap.test.ts`
- `src/__tests__/main/player/desktopPlayerAdapter.test.ts`
- `src/__tests__/main/player/nativePlayerHostProcess.test.ts`
- `tools/__tests__/native-helper-program.test.mjs`
- `tools/__tests__/smoke-electron.test.mjs`
- `docs/architecture/import-ledger.md`

This exhaustive scope is 19 files, including two new production owners and two
new tests.

**PACKAGE_2A_IMPLEMENTATION_REMEDIATION_2026_07_28:** implementation review
rejected the then-current uncommitted Package 2A diff on four correctness grounds:
adapter acceptance was mistaken for successful load settlement; an eligible
failure during an unresolved retry was lost; same-turn asynchronous host events
could overtake older synchronous result events; and the main helper-lifecycle
listener invalidated runtime custody before the adapter's renderer-safe error
was delivered. Preserve the complete 19-file diff without reverting,
committing, or editing Package 2B. A `worker` may remediate only this 11-file
subset after fresh plan approval:

- `src/main/player/plexPlaybackComposition.ts`
- `src/main/player/plexPlaybackRecoveryOwner.ts`
- `src/main/player/playbackEventRouter.ts`
- `src/main/player/playerIpc.ts`
- `src/main/index.ts`
- `src/__tests__/main/player/plexPlaybackComposition.test.ts`
- `src/__tests__/main/player/plexPlaybackRecoveryOwner.test.ts`
- `src/__tests__/main/player/playbackEventRouter.test.ts`
- `src/__tests__/main/player/plexPlaybackRuntime.test.ts`
- `src/__tests__/main/playerIpc.test.ts`
- `tools/__tests__/smoke-electron.test.mjs`

The other eight Package 2A files remain preserved exactly as reviewed during
this remediation. If any fix requires `desktopPlayerAdapter.ts`,
`nativePlayerHostProcess.ts`, a public contract, preload, native helper,
Package 2B, or a twelfth file, stop before edit and return to plan review.

**Production-reachable trigger:** `Program.cs` defines the official sequential
`mpv_event_end_file` data layout exactly as reason `int`, error `int`,
playlist-entry id `long`, playlist-insert id `long`, and inserted-entry count
`int`, plus reason constants EOF `0`, STOP `2`, QUIT `3`, ERROR `4`, and
REDIRECT `5`. The `MPV_EVENT_END_FILE` branch must inspect non-null event data:

- EOF, STOP, and QUIT preserve a non-retry terminal `ended` event for the
  current request; STOP/QUIT never consume recovery budget;
- REDIRECT emits no terminal event because libmpv is continuing to another
  file;
- ERROR emits the existing helper `error` envelope with fixed safe code
  `PLAYER_HELPER_PLAYBACK_ENDED_WITH_ERROR`, category `engine-failure`, and
  `recoverable/retryable: true`;
- null data or an unknown reason emits the same fixed safe error category with
  `recoverable/retryable: false`.

No numeric mpv error/reason, source URL, native message, or helper detail crosses
the envelope. The ERROR classification is deliberately `engine-failure`, never
`network`: libmpv documents its error as approximate and
`MPV_ERROR_LOADING_FAILED` as generic. It is nevertheless a real
production-reachable mid-playback failure event, unlike a synthetic adapter
event or command timeout. libmpv also documents that interrupted/incomplete or
corrupt media may arrive as EOF; Package 2A must not relabel EOF, and therefore
does not close that interruption-class proof.

**Recovery and single-delivery seam:** add one main-owned recovery owner,
injected with a timer host and a callback that retries an exact stable schedule
identity `(channelId, programId, startedAtMs)`. Eligibility is exactly the
current request's normalized `PLAYER_HOST_ENGINE_FAILURE` event in category
`engine-failure` carrying both recovery flags. Other engine errors, plus source,
authentication, authorization, network, timeout, unsupported
media/capability, validation, track, render, helper, cleanup, aborted, stale,
and unknown failures remain manual. The owner allows three attempts for one
identity at exactly 1,000, 2,000, and 4,000 ms. The runtime re-resolves once per
attempt and must compare the exact identity before dispatch; mismatch cancels
without consuming the replacement program's budget. A current-request
authoritative `playing` event resets the budget. Eligible errors continue to
the renderer once while retry is pending; a successful retry's ordinary
loading/playing events clear the error, and exhaustion leaves the final error
visible for Package 2B actions.

The adapter runtime port interprets load success from command settlement, not
from `DesktopPlayerAdapterDispatchResult.accepted`. It returns `ok: true` only
when `accepted` is true and the event batch contains exactly one matching
`command.settled` for the dispatched request id and command with `ok: true`,
with no matching failed or conflicting settlement. Missing, mismatched,
duplicate/conflicting, or `ok: false` settlement returns `ok: false` while
preserving the complete renderer-safe event batch for runtime observation.
Thus the adapter's legitimate `accepted: true` plus host error and
`command.settled ok: false` means the recovery load failed and consumes the
current attempt; it can never be reported `started`.

The recovery owner retains one boolean failure latch scoped to the active
identity, owner generation, and in-flight attempt generation. An eligible
engine error observed while that attempt is unresolved sets the latch instead
of being discarded by the in-flight guard. Attempt settlement is
decision-complete:

- `stale`, identity replacement, or explicit cancel invalidates the generation,
  clears the latch, and schedules nothing;
- a current authoritative `playing` event is the only success reset: it clears
  the latch, marks the in-flight generation successful, resets the budget, and
  prevents that attempt's later promise settlement from scheduling;
- without an observed playing reset, `failed` or a latched eligible error
  schedules exactly the next remaining delay once, even if the callback result
  is `started`;
- `started` with no latch schedules nothing and waits for a later accepted
  playing/error event; after settlement such a later eligible error enters the
  ordinary next-attempt path.

The third attempt may latch or return failure but cannot create a fourth timer.
Timer cancellation, stale completion, cleanup, teardown, helper crash, schedule
replacement, and integer generation rollover clear all latch/settlement state.

`RegisterPlayerIpcHandlersOptions` replaces the ambiguous callback with two
required named sinks: `sendSynchronousPlayerEvent(event)` is used only for
renderer command/cleanup result arrays and local unsupported results;
`onAsynchronousAdapterEvents(events)` is passed only to
`DesktopPlayerAdapter.onEvents`. The focused `playbackEventRouter` owns only
the latter batch path, but it intentionally retains shallow-copied,
renderer-safe batches until a FIFO next-turn drain. Its injected scheduling
port has `schedule(callback)` and `cancel(handle)`; production uses
`setImmediate`/`clearImmediate`, not a microtask. This lets all promise
continuations from a native result, adapter dispatch, composition port, and
runtime synchronous result publication settle before a later event from the
same stdout turn is ingested. Multiple queued batches preserve arrival order.

Each queue entry captures the runtime object at enqueue. At drain it is
delivered exactly once only if that object is still the current runtime; a
replacement/null runtime drops it with a safe diagnostic. The unchanged
runtime request/epoch custody then rejects stale request ids. A batch arriving
when no runtime exists is dropped immediately. `flushCurrentRuntime()` cancels
the scheduled handle and synchronously drains the eligible FIFO under the same
current-runtime checks; `dispose()` is idempotent, cancels the handle, clears
all retained batches, advances the router generation, and prevents future
delivery. The router retains no batch after drain, replacement drop, or
dispose.

`bootstrapPlaybackRuntime()` continues to pass `onEvents` in both
development/smoke and production branches, so synchronous runtime results are
visible. `src/main/index.ts` sends those results directly to
`sendPlayerEvent`, sends renderer IPC command/cleanup results through the
separate synchronous sink, and routes only adapter-async batches through the
FIFO. No returned or emitted batch feeds a second source.

Helper lifecycle uses the same ordering owner. `playerIpc.ts` creates the native
host, constructs `DesktopPlayerAdapter` first (registering the adapter
lifecycle listener), and only then registers the optional main lifecycle
callback supplied in `RegisterPlayerIpcHandlersOptions`. It retains that
unsubscribe and invokes it exactly once at the beginning of registration
teardown, before adapter cleanup and handler removal. The production
composition passes the original native-host factory unchanged. When the later
main listener fires, it calls `flushCurrentRuntime()` first so the adapter's
already-queued helper error is accepted and published while custody is active;
only then does it invoke `runtime.handleHelperCrash()`. Cleanup never precedes
that flush. Main shutdown unregisters the lifecycle callback through player IPC
teardown, disposes the router, and only then tears down runtime/Plex/channel
owners; both quit paths and re-entry use the same idempotent order.

Manual/schedule channel replacement, changed scheduled identity, stop, cleanup,
teardown, helper crash, server/profile lifecycle cleanup, and dispose cancel the
timer and invalidate its generation. Candidate-resolution and load-dispatch
failures from a recovery attempt consume the same budget; stale failures consume
none. A callback result of `started` is provisional until accepted playing or
error observation; it does not erase a failure latched during that attempt.
After exhaustion, the existing renderer-safe terminal error remains
visible and manually actionable; the owner neither loops, skips automatically,
changes capabilities, nor fabricates success. PMS cleanup and current epoch
custody remain in the existing runtime/cleanup owners.

The import ledger records a focused behavioral adaptation of upstream
`src/modules/player/recovery/RetryManager.ts` and
`src/modules/player/core/ErrorHandler.ts` at audited pin `0258dbe`: Desktop
retains cap/backoff/cancellation semantics but moves ownership from
`HTMLVideoElement` to main runtime generations and does not copy browser source.

**Exact no-touch files and neighboring owners:** no public contract, preload,
renderer, stream policy/resolver, adapter, native-host process/port/protocol
TypeScript source, scheduler/channel, persistence, diagnostics schema, package,
roadmap, matrix, or current-state edit. In particular,
`nativeHelperProtocol.ts`, `nativeHelperProtocolCodec.ts`,
`hostEventProjection.ts`, `desktopPlayerAdapter.ts`, and
`nativePlayerHostProcess.ts` remain source no-touch because their existing
closed `error` event path already validates and normalizes the new safe helper
event. `src/main/index.ts` changes only event-router composition, post-adapter
lifecycle callback wiring, lifecycle flush-before-cleanup, and idempotent
router/registration/runtime teardown order. It does not absorb adapter,
process, retry, or event-validation policy. Stop if listener order cannot be
made deterministic without either no-touch owner, if causal ordering requires
changing native stdout parsing, or if a helper project/P/Invoke/envelope
change, public schema, scheduler mutation, fallback decision, raw native
diagnostic, or renderer state is needed.

**Verification classification:** `new regression/contract test required`.
Focused tests must prove exact delays/cap, one budget per scheduled identity,
success reset, cleanup cancellation, stale timer/completion quarantine,
candidate/load failure accounting, provisional-start latch reconciliation, no
automatic retry for unsafe/nonretryable errors, causal cross-sink order,
lifecycle error-before-cleanup, PMS/player cleanup ordering, and unchanged
terminal error.
`native-helper-program.test.mjs` statically asserts the exact struct field
order, reason constants/branches, fixed safe payload, no raw numeric emission,
and no blanket END_FILE-to-ended branch. Adapter/process tests inject the
helper ERROR envelope through the real validation/projection path.
`plexPlaybackComposition.test.ts` first proves the port maps an exact matching
successful settlement to `ok: true` and maps accepted host failure, missing,
mismatched, and conflicting settlement to `ok: false` without dropping events.
Its concrete regression composes a real `DesktopPlayerAdapter` with a host
rejection that the adapter represents as `accepted: true` plus failed
settlement, and proves the runtime schedules
exactly 1,000/2,000/4,000 ms, performs no fourth retry, and leaves the final
error visible.

`plexPlaybackRecoveryOwner.test.ts` holds a retry promise unresolved, injects
an eligible error, resolves the callback `started`, and proves the latch
schedules the next delay; companion cases prove later playing clears the latch,
failed-plus-latched schedules only once, and identity replacement, cancel,
cleanup/stale completion, and third-attempt exhaustion clear or cap it.

`playbackEventRouter.test.ts` injects its scheduler and reproduces one native
result plus a later async buffering/error batch in the same turn. It proves the
synchronous loading/result batch is emitted first, the queued batch is emitted
second exactly once, FIFO is stable, microtask draining is forbidden,
replacement runtime entries are dropped, current-runtime stale events remain
runtime-filtered, explicit lifecycle flush is synchronous, and dispose cancels
and empties the queue. `playerIpc.test.ts` retains the sink-separation case and
adds a Set-ordered production host regression proving adapter lifecycle
delivery is registered before the main callback, teardown unsubscribes main
before cleanup, and post-teardown failure cannot call main.
`plexPlaybackRuntime.test.ts` routes a helper lifecycle error, flushes it, then
calls crash cleanup and proves the renderer observes the helper error—not only
stale warnings—before custody invalidation. `smoke-electron.test.mjs` locks the
composition root to the original factory, post-adapter lifecycle callback,
flush-before-crash order, and router disposal before runtime teardown.
Router/runtime/composition/bootstrap tests continue to prove async ingest once,
stale rejection, recovery observation once, and visible synchronous runtime
emissions. Run locally:

```sh
node --test tools/__tests__/native-helper-program.test.mjs
node --import tsx --test src/__tests__/main/player/desktopPlayerAdapter.test.ts src/__tests__/main/player/nativePlayerHostProcess.test.ts src/__tests__/main/playerIpc.test.ts src/__tests__/main/player/plexPlaybackRecoveryOwner.test.ts src/__tests__/main/player/playbackEventRouter.test.ts src/__tests__/main/player/plexPlaybackRuntime.test.ts src/__tests__/main/player/plexPlaybackComposition.test.ts src/__tests__/main/player/playbackRuntimeBootstrap.test.ts
npm run typecheck
npm run build:electron
node --test tools/__tests__/smoke-electron.test.mjs
npm run smoke:electron
npm run verify:maintainability
npm run verify:architecture
npm run verify:redaction
npm run verify
git diff --check
```

The following commands are retained only as
`WS2-POST-VALIDATION-01`'s future Windows/.NET debt packet. They are not run,
required, or awaited by WS2:

```sh
dotnet build src/native-helper/Lineup.NativePlayerHost/Lineup.NativePlayerHost.csproj --configuration Release
node --test tools/__tests__/native-helper-program.test.mjs
node --import tsx --test src/__tests__/main/player/desktopPlayerAdapter.test.ts src/__tests__/main/player/nativePlayerHostProcess.test.ts src/__tests__/main/player/productionNativeHostFactory.test.ts src/__tests__/main/player/plexPlaybackLifecycleIntegration.test.ts
dotnet clean src/native-helper/Lineup.NativePlayerHost/Lineup.NativePlayerHost.csproj --configuration Release
npm run verify:redaction
git diff --check
```

When that post-WS2 validation is eventually authorized, inspect only the exact
helper `bin/` and `obj/` outputs after clean and remove only confirmed generated
remnants if they obstruct redaction. Missing/unrun/failed Windows/.NET build or
live ERROR projection remains honest open validation debt; it does not block
the Package 2A checkpoint, commit, publication, later WS2 package, or WS2
closeout. For current WS2 acceptance, a deterministic injected test must observe recovery
without a stale restart, leaked lease, extra fourth attempt, duplicate event,
or public contract change. All gates and independent implementation review
must pass. The remediation is accepted only when all four rejected
reproductions pass at their public seams, the preserved eight files have no
additional diff, the full 19-file Package 2A set is freshly reviewed, and no
material finding remains. If a remediation edit must be abandoned, revert only
that edit back to the preserved rejected 19-file state for replanning; do not
discard unrelated Package 2A work or partially commit a fix. Final rollback
after an accepted checkpoint remains the entire 19-file unit.
Checkpoint commit: `feat(player): add bounded playback recovery`. No partial
TypeScript-only or helper-only commit is allowed.

PACKAGE_2A_FIX_HANDOFF
STATUS: preserve the approved remediation plan, exact implemented 19-file diff,
and all existing local verification/independent-review evidence
NEXT_SESSION_LAUNCHER: lineup-desktop-feature-review
TASK: Review Package 2A Correctness Remediation Plan
TASK_FAMILY: feature/design
TIER: Tier 3
PLAN: docs/plans/2026-07-22-tier3-parity-correction-plan.md
ARTIFACT: PACKAGE_2A_IMPLEMENTATION_REMEDIATION_2026_07_28
PRESERVE: the exact implemented 19-file Package 2A product/test/import diff
EDIT_AFTER_APPROVAL: only the exact 11-file remediation subset
IMPLEMENTER_AFTER_APPROVAL: `worker`
BLOCKERS: only a failed required Mac-runnable gate or unresolved material
independent-review finding; no Windows-machine blocker applies because the
Release/live-native work is `WS2-POST-VALIDATION-01`
MESSAGE:
Freshly review the complete WS2 amendment and the exact
PACKAGE_2A_IMPLEMENTATION_REMEDIATION_2026_07_28 handoff. Reproduce and
adjudicate adapter settlement accounting, the in-flight failure latch,
same-turn cross-sink causal ordering, and adapter-error-before-helper-cleanup
lifecycle order. Confirm the fixes remain inside the 11-file subset of the
preserved 19-file Package 2A diff, tests fail on the rejected behavior and
prove the frozen outcomes, no-touch owners remain untouched, rollback and
post-WS2 validation debt remain honest, and Package 2B/proof debt are unchanged. Do not
authorize implementation until no material plan finding remains.

#### Package 2B — explicit Retry and Skip recovery actions

**IMPLEMENTER_ROLE_ELIGIBILITY:** `worker`. This is a reviewed cross-process
vertical slice and needs bounded judgment inside frozen contracts; lower roles
are ineligible.

**Owned owners/files:** `src/contracts/ipc.ts`, `src/contracts/shell.ts`, new
`src/preload/playerRecoveryBridge.cts`, `src/preload/channels.cts`,
`src/preload/index.cts`, new `src/main/player/playerRecoveryIpc.ts`,
new `src/main/player/playbackProgramTransitionOwner.ts`,
`src/main/player/plexPlaybackRuntime.ts`,
`src/main/player/plexPlaybackBridge.ts`,
`src/main/player/plexPlaybackComposition.ts`,
composition, owner teardown, and removal of the old program-start,
channel-tuned, and post-initialize playback starts in
`src/main/index.ts`, `src/renderer/playerOverlayController.ts`,
new `src/renderer/playerErrorRecoveryController.ts`,
`src/renderer/playerOverlayDom.ts`, `src/renderer/overlays.ts`,
`src/renderer/overlayViewModels.ts`, `src/renderer/domBindings.ts`,
`src/renderer/index.ts`, new
`src/__tests__/main/player/playerRecoveryIpc.test.ts`,
new `src/__tests__/main/player/playbackProgramTransitionOwner.test.ts`,
new
`src/__tests__/main/player/playbackProgramTransitionIntegration.test.ts`,
`src/__tests__/main/player/plexPlaybackRuntime.test.ts`,
`src/__tests__/main/player/plexPlaybackBridge.test.ts`,
`src/__tests__/main/player/plexPlaybackComposition.test.ts`,
`src/__tests__/domain/schedulerDomain.test.ts`,
`src/__tests__/main/guideRuntime.test.ts`,
`src/__tests__/contracts/contracts.test.ts`,
`src/__tests__/integration/preloadContractVocabulary.test.ts`,
new `src/__tests__/renderer/playerErrorRecoveryController.test.ts`,
`src/__tests__/renderer/playerOverlayController.test.ts`,
`src/__tests__/renderer/overlays.test.ts`,
`src/__tests__/renderer/routeDom.test.ts`,
`tools/__tests__/smoke-electron.test.mjs`, and
`docs/architecture/import-ledger.md`. This list is exhaustive.
The exhaustive scope is 34 files, including two new production owners and
four new tests.

**Accepted route-DOM test-authority correction:** the only newly permitted
Package 2B edit is the existing
`src/__tests__/renderer/routeDom.test.ts` player-error assertion block at or
around the stale Guide-visible assertion previously reported at line 677.
Replace the obsolete expectation that Guide remains visible while the selected
channel has playable current and next programs. Add or adjust only semantic DOM
assertions proving that this actionable error state projects Retry and Skip,
including their current visible/available or pending/busy state, while hiding
Guide; then prove an explicit no-current/no-next playable-program state hides
Retry and Skip and exposes Guide as the fallback. Reuse the existing route DOM
fixture and public DOM bindings. Do not refactor route-DOM setup, navigation,
focus, input, unrelated fixtures/assertions, selectors, static DOM, production
renderer owners, or any other Package 2B behavior to make this test pass. If
the frozen production behavior cannot pass through this test-only correction,
stop and return to plan review instead of widening scope.

The public API adds one closed player recovery operation with action exactly
`retry-current` or `skip-next`; request/result envelopes echo one opaque request
id and expose only accepted/failed status plus the current renderer-safe player
snapshot/error vocabulary. Retry resolves the currently authoritative scheduled
program through the runtime, resets Package 2A's exhausted manual budget, and
starts it once. Skip advances the main-owned scheduler exactly once and starts
the newly current program; it never accepts a renderer-supplied channel,
program, media, URL, or offset. Both reject absent/stale playback context
safely, are serialized against tune/cleanup generations, and cannot resurrect a
released session. Renderer replaces the error surface's Guide substitute with
upstream-shaped Retry and Skip actions, preserves deterministic focus/busy/error
state, and falls back to Guide only when no current/next playable program is
available. This is a reviewed Desktop process-boundary divergence from
upstream's in-process callbacks, not a behavior divergence.
The focused renderer recovery owner, not the 797-line overlay controller, owns
request generations, one in-flight action, bridge timeout/settlement, safe
failure text, and retry/skip completion. The overlay controller composes it
with existing presentation, render, and focus callbacks.

**Single skip transition owner and awaitable contract:** current
`ChannelScheduler.skipToNext()` calls `jumpToProgram()`, which updates
current/next state and synchronously emits exactly one `programStart`. The
existing `channelSchedulerProgramStartHandler` in `src/main/index.ts` returns a
promise to an event API typed `(program) => void`, so the emitter neither
awaits nor reports that playback transition. Package 2B removes that handler
and its teardown bookkeeping. `playbackProgramTransitionOwner` becomes the
sole playback `programStart` subscriber and the sole recovery caller of
`skipToNext()`; `playerRecoveryIpc` receives this owner, never the scheduler.

The owner is authoritative for every scheduler-emitted start, not only a
natural tick or skip. `ChannelScheduler.loadChannel()` synchronously emits
`programStart`; `GuideRuntime.tuneChannel()` then invokes `onChannelTuned`, and
`initializeActiveChannel()` calls that same tune path. Therefore
`src/main/index.ts` also removes `onChannelTunedCallback`, stops supplying the
`onChannelTuned` option to `createChannelComposition()`, and removes the
post-`initializeActiveChannel()` explicit
`startCurrentPlayback('startup')`. It creates/subscribes the transition owner
after runtime bootstrap and before calling `initializeActiveChannel()`.
Initialization retains only its existing safe rejection diagnostic.
`src/main/channel/channelComposition.ts` and
`src/main/channel/guideRuntime.ts` remain source no-touch: their optional
callback stays available to non-playback consumers, but the production
composition root supplies no playback callback.

Every `programStart`, whether caused by startup load, manual tune, channel
refresh, natural clock transition, or skip, invokes exactly one
`runtime.startCurrentPlayback('schedule-tick')`. Here `schedule-tick` means a
scheduler-authoritative program transition, not only a timer origin;
`startup` and `manual-switch` remain runtime vocabulary for non-scheduler
callers/tests but are not used by the production composition root. A non-skip
listener failure is caught and reported once through the owner's injected safe
diagnostic callback; it cannot become an unhandled rejection or trigger a
second start.

For `skip-next`, the owner freezes the current schedule identity, creates one
serialized transition generation and pending settlement, and registers that
pending generation before calling `skipToNext()` exactly once. The synchronous
`programStart(nextProgram)` listener must observe a different authoritative
identity, attach exactly one
`runtime.startCurrentPlayback('schedule-tick')` promise to the pending
settlement, and never start playback from the outer skip method. Skip resolves
`accepted` only after that runtime start settles and its `onEvents` callback
has synchronously published the result. It returns a safe failure if no
program event/change occurs, runtime start fails, cleanup/tune invalidates the
generation, or the event does not name the authoritative new current program.
A normal schedule event with no skip pending enters the same listener and
starts once with safe failure diagnostics. Concurrent recovery actions are
rejected busy; cleanup, teardown, manual tune, and a newer program event settle
or invalidate the old deferred once. No direct skip-start remains in
`playerRecoveryIpc` or `src/main/index.ts`.

`retry-current` enters the same transition owner without scheduler mutation:
it freezes the current identity, resets Package 2A's manual budget, and invokes
the runtime's exact-identity retry once. It settles only after runtime
completion/event publication under the same generation rules. A manual tune's
`loadChannel()` event is a newer program generation and invalidates a pending
recovery action before its single runtime start. The owner's idempotent
`dispose()` unsubscribes the listener, invalidates/settles any deferred, and is
called before runtime cleanup in both main shutdown paths; the removed legacy
handler/callback has no separate teardown.

The import ledger records the behavioral adaptation of upstream
`src/core/error-recovery/RecoveryActions.ts` and the playback action portion of
`PlaybackRuntimeController.ts` at `0258dbe`. No upstream UI framework,
`HTMLVideoElement`, browser storage, or webOS routing source is copied.

**No-touch boundary:** no scheduler interface/implementation/event-owner,
persistence, Settings, stream capability/policy, Plex transport,
adapter/native-host/helper, package, WS1 owner, or later workstream edit.
Specifically `src/domain/scheduler/interfaces.ts`,
`src/domain/scheduler/channelScheduler.ts`, including its local
`SchedulerEventOwner`, `src/main/channel/channelComposition.ts`, and
`src/main/channel/guideRuntime.ts` remain source no-touch; existing synchronous
load/tune behavior is locked by the named domain, guide, owner, and integration
tests.
The shared player contract gains no helper detail and the renderer gains no
scheduler port. Stop if one closed operation is insufficient, skip requires
channel mutation/persistence, a scheduler signature must become async, a new
owner would be a forwarding wrapper, or `playerOverlayController.ts` would
reach 800 lines.

**Verification classification:** `new regression/contract test required`.
The observed full `npm run verify` baseline after the reviewed Package 2B
implementation was 982 passing and one failing test, exactly
`src/__tests__/renderer/routeDom.test.ts` at the stale Guide-visible assertion;
the reviewed production behavior and the new in-scope overlay coverage already
agree that actionable current/next programs expose Retry/Skip and reserve Guide
for the no-playable-program fallback. Treat this as a test-authority mismatch,
not permission for a production change.
Tests cover exact payload/key rejection, sender/origin authorization, preload
invoke rejection, request-id echo, retry currentness, one-step skip, empty/end
cases, tune/cleanup races, stale completion, focus/busy/error recovery,
forbidden-field recursion, and unchanged existing player APIs. The scheduler
domain test locks one synchronous `programStart` per `skipToNext`, and the
guide test locks `loadChannel` emission before optional tune notification. The
owner test proves pending-before-emission, one runtime start, no outer-method
duplicate, await-through-runtime settlement, no-emission failure, concurrent
busy rejection, and tune/cleanup/dispose invalidation. The real
GuideRuntime/ChannelScheduler integration test proves exactly one runtime start
for initialize-active-channel, manual tune, natural clock transition, and
skip—never the former two/triple starts. The smoke test locks production
composition omission of both `onChannelTuned` playback wiring and the
post-initialize explicit start, and proves subscription precedes
initialization. The main IPC test proves an accepted result cannot precede the
runtime's observable event callback. Run:

```sh
npm run typecheck
npm run build:electron
node --import tsx --test src/__tests__/domain/schedulerDomain.test.ts src/__tests__/main/guideRuntime.test.ts src/__tests__/main/player/playerRecoveryIpc.test.ts src/__tests__/main/player/playbackProgramTransitionOwner.test.ts src/__tests__/main/player/playbackProgramTransitionIntegration.test.ts src/__tests__/main/player/plexPlaybackRuntime.test.ts src/__tests__/main/player/plexPlaybackBridge.test.ts src/__tests__/main/player/plexPlaybackComposition.test.ts src/__tests__/contracts/contracts.test.ts src/__tests__/integration/preloadContractVocabulary.test.ts src/__tests__/renderer/playerErrorRecoveryController.test.ts src/__tests__/renderer/playerOverlayController.test.ts src/__tests__/renderer/overlays.test.ts src/__tests__/renderer/routeDom.test.ts
node --test tools/__tests__/smoke-electron.test.mjs
npm run smoke:electron
npm run verify:maintainability
npm run verify:architecture
npm run verify:redaction
npm run verify
git diff --check
```

Rollback is the whole closed recovery API/action slice; never leave a contract,
channel, preload method, main handler, renderer control, or its corrected
route-DOM authority assertion unmatched. The route-DOM correction is not an
independent product change and must roll back with Package 2B.
Checkpoint commit: `feat(player): add retry and skip recovery actions`.

PACKAGE_2B_ROUTE_DOM_SCOPE_REVIEW_PACKET_2026_07_28
NEXT_SESSION_LAUNCHER: lineup-desktop-feature-review
TASK: Review Package 2B Route-DOM Scope Correction
TASK_FAMILY: feature/design
TIER: Tier 3
PLAN: docs/plans/2026-07-22-tier3-parity-correction-plan.md
ARTIFACT: PACKAGE_2B_ROUTE_DOM_SCOPE_REVIEW_PACKET_2026_07_28
FILES:
- docs/plans/2026-07-22-tier3-parity-correction-plan.md
SCOPE_DELTA:
- add exactly `src/__tests__/renderer/routeDom.test.ts` to Package 2B
- increase the exhaustive Package 2B count from 31 to 32 files
CURRENT_SUPERSEDING_SCOPE:
- the later `PACKAGE_2B_IMPLEMENTATION_REMEDIATION_2026_07_28` expands the
  active exhaustive boundary from 32 to 34 files solely for canonical playback
  identity projection and its existing bridge test; this does not broaden the
  approved route-DOM edit
PERMITTED_IMPLEMENTATION_EDIT:
- replace only the stale player-error Guide-always-visible assertion and add or
  adjust nearby semantic DOM assertions for Retry/Skip in the playable
  current/next state and Guide in the explicit no-current/no-next fallback
NON_GOALS:
- no production source, selector, static-DOM, route setup, navigation, focus,
  input, unrelated fixture/assertion, or broad route-DOM refactor
OBSERVED_CONTRADICTION:
- full verification reached 982 passing and one failing test, exactly the stale
  `src/__tests__/renderer/routeDom.test.ts` assertion reported at line 677
REQUIRED_REVIEW_ASSERTIONS:
- the reviewed route-DOM delta added no file other than the existing route-DOM
  test; the later 34-file remediation boundary is separately reviewed
- the permitted test edit aligns public DOM assertions with already frozen
  Package 2B Retry/Skip and Guide-fallback behavior without authorizing a
  production change
- the focused command includes the route-DOM test, full `npm run verify` must
  pass before Package 2B resumes or closes, and rollback remains the whole
  Package 2B slice
- every other Package 2B scope, invariant, no-touch boundary, stop condition,
  verification gate, and WS1/WS3–WS9/RD-27/RD-28 obligation remains unchanged
BLOCKERS:
- worker remains paused until fresh independent plan review reports no material
  finding
MESSAGE:
Adversarially review only the accepted Package 2B route-DOM scope correction.
Confirm it adds exactly one existing test file, changes the exhaustive count
from 31 to 32, limits implementation to replacing the stale Guide-visible
assertion plus nearby Retry/Skip and Guide-fallback DOM proof, forbids production
or broad route-DOM refactoring, adds the test to focused verification, preserves
whole-slice rollback and every other invariant, and keeps the worker paused
until explicit approval.

**PACKAGE_2B_IMPLEMENTATION_REMEDIATION_2026_07_28:** two independent
implementation reviews reproduced seven unique material defects in the current
uncommitted Package 2B diff. Accept all seven findings and the later P1 plan
review finding that item 5 lacked one implementable canonical identity owner.
Preserve the complete current diff and expand the exhaustive Package 2B
boundary from 32 to 34 files only for the existing playback bridge source and
test named below. Preserve the independently approved route-DOM correction
without reverting, committing, or starting Package 2D.
Accept the later P1 implementation-review finding that invalidation alone opens
a recovery/start window while asynchronous player/PMS cleanup drains. The
prior clean remediation-plan review is superseded for this lifecycle amendment.
The prior route-DOM plan approval does not authorize remediation implementation:
the worker remains paused until this complete amendment receives fresh
independent plan approval.

**IMPLEMENTER_ROLE_ELIGIBILITY:** `worker` only. The fixes span authorization,
main cleanup/transition generations, runtime retry custody, preload validation,
and renderer settlement/projection ordering; lower worker roles are ineligible.

The remediation edit subset is exactly these 20 files inside the revised
34-file Package 2B boundary:

- `src/main/player/playerRecoveryIpc.ts`
- `src/main/player/playbackProgramTransitionOwner.ts`
- `src/main/player/plexPlaybackRuntime.ts`
- `src/main/player/plexPlaybackBridge.ts`
- `src/main/index.ts`
- `src/preload/playerRecoveryBridge.cts`
- `src/preload/index.cts`
- `src/renderer/playerErrorRecoveryController.ts`
- `src/renderer/overlayViewModels.ts`
- `src/__tests__/main/player/playerRecoveryIpc.test.ts`
- `src/__tests__/main/player/playbackProgramTransitionOwner.test.ts`
- `src/__tests__/main/player/playbackProgramTransitionIntegration.test.ts`
- `src/__tests__/main/player/plexPlaybackRuntime.test.ts`
- `src/__tests__/main/player/plexPlaybackBridge.test.ts`
- `src/__tests__/main/player/plexPlaybackComposition.test.ts`
- `src/__tests__/integration/preloadContractVocabulary.test.ts`
- `src/__tests__/renderer/playerErrorRecoveryController.test.ts`
- `src/__tests__/renderer/overlays.test.ts`
- `src/__tests__/renderer/routeDom.test.ts`
- `tools/__tests__/smoke-electron.test.mjs`

Every other Package 2B file is preserve/no-touch during remediation. No new
file, public recovery action, renderer-supplied program identity, contract
field, IPC channel, scheduler interface/implementation, cleanup-owner edit,
dependency, native-helper change, or broader renderer refactor is authorized.
If any accepted fix cannot be completed inside this 20-file subset, stop before
editing a twenty-first file and return to plan review.

**Required composition-test signature correction:** the nonoptional
`retryCurrentPlayback(expectedSelection)` contract intentionally removes the
old zero-argument call. In
`src/__tests__/main/player/plexPlaybackComposition.test.ts`, edit only the
existing manual-retry composition test at or around the prior line 481 to
derive the expected selection through the same runtime-owned canonical
projector and pass it to `retryCurrentPlayback`. Preserve that test's exact
two-load behavior, repeated media id, player load-command count, one prior
request cleanup, and `switch` PMS-release assertions. Do not add an optional or
default identity, compatibility overload/fallback, local program-id encoder,
weaker equality, production change for this test, unrelated test refactor, or
another file.

**Accepted cleanup-custody lifecycle correction:** the existing 20-file
remediation boundary is sufficient; no count or file changes are authorized.
The current rejected implementation calls transition-owner `invalidate()` and
then immediately permits new actions while asynchronous PMS/player cleanup is
still draining. Preserve the complete current remediated diff, but replace that
open interval with complementary runtime and transition-owner cleanup custody:

The cleanup-custody correction may edit exactly this eight-file subset of the
approved 20-file remediation boundary:

- `src/main/player/plexPlaybackRuntime.ts`
- `src/main/player/playbackProgramTransitionOwner.ts`
- `src/main/index.ts`
- `src/__tests__/main/player/plexPlaybackRuntime.test.ts`
- `src/__tests__/main/player/playbackProgramTransitionOwner.test.ts`
- `src/__tests__/main/player/playbackProgramTransitionIntegration.test.ts`
- `src/__tests__/main/player/plexPlaybackComposition.test.ts`
- `tools/__tests__/smoke-electron.test.mjs`

The other 12 remediation files preserve their current reviewed fixes. If this
lifecycle correction requires a ninth file, a contract change, or
`plexPlaybackCleanupWiring.ts`, stop before edit and return to plan review.

The only cleanup-custody edit permitted in
`src/__tests__/main/player/plexPlaybackComposition.test.ts` is the existing
test `desktop adapter runtime port keeps a replacement session when prior stop
cleanup settles late`. Preserve its deferred native stop, request-A cleanup,
adapter snapshot, PMS/session, late-stop isolation, and teardown proof. While
the stop drain is pending, assert the manual-switch replacement fails closed,
does not consume or install request B, and performs no request-B
resolver/player/PMS work. After stop fully settles and custody releases, invoke
one fresh manual-switch start, assert it receives and keeps request B, and prove
the completed request-A stop output cannot clear, overwrite, or relabel that
replacement. Preserve final request-B adapter/PMS teardown cleanup. Do not
change production code for this test, weaken the stop hold, queue/replay the
rejected start, add an optional fallback, or refactor another composition test.
The test title may change only to state that replacement is blocked until the
prior stop cleanup settles.

- `PlexPlaybackRuntime` acquires cleanup custody synchronously at entry to every
  public asynchronous cleanup path that can drain or release player/PMS state,
  including `cleanup`, `stop`, `handleHelperCrash` through `cleanup`, and
  `teardown` through `cleanup`. Custody is a nested count, not a boolean:
  overlapping cleanup calls each acquire one hold and release exactly their own
  idempotent hold in `finally`; starts remain blocked until the last hold
  releases. Cleanup cancels automatic recovery, clears active selection,
  advances epoch, awaits the complete player/PMS drain, emits only that
  cleanup's renderer-safe events while custody is still held, and releases
  after emission/settlement.
- While runtime cleanup custody is nonzero,
  `startCurrentPlayback()` fails closed before scheduler/candidate resolution
  with `accepted: false`, the current epoch, `requestId: null`, and no new
  session event; `retryCurrentPlayback(expectedSelection)` returns `false`
  before resolving or installing a selection; and an automatic Package 2A retry
  returns stale without dispatch. Work that began before cleanup remains
  governed by the advanced epoch and may not install or publish a current
  session after cleanup acquisition. A second overlapping cleanup may finish
  first, but cannot reopen starts while any older hold remains.
- `PlaybackProgramTransitionOwner` exposes one bounded synchronous cleanup-hold
  acquisition that returns an idempotent release. Holds are nested. Main
  acquires the hold before calling `invalidate()`, so the pre-cleanup pending
  action settles stale but no new action can enter the opened generation.
  During any hold, Retry and Skip both reject exactly `busy`; Skip rejects
  before `skipToNext()` or any scheduler mutation. Releasing one of multiple
  holds does not reopen actions, and final release does not replay work.
  `dispose()` remains terminal and a later release cannot reopen a disposed
  owner.
- A scheduler `programStart` observed during transition cleanup custody is
  deliberately dropped, not queued, coalesced, or replayed. It advances
  generation, invokes no runtime start, and may report only a fixed safe
  diagnostic without program identity. The safe consequence is explicit:
  cleanup leaves playback idle/error rather than automatically starting media
  from a profile, server, or helper context being torn down. After final
  release, a later scheduler event/tune starts exactly once through the existing
  owner, or an explicit Retry reprojects and revalidates the latest exact
  authoritative canonical selection and starts once. Release alone never
  starts playback.
- In `src/main/index.ts`, the helper-crash callback acquires transition cleanup
  custody synchronously before flushing the already-routed safe adapter event,
  then invalidates, awaits `handleHelperCrash()` with safe rejection reporting,
  and releases only in `finally`. The profile/server facade supplied to
  `wirePlexPlaybackCleanup()` similarly acquires before invalidation, awaits the
  real runtime cleanup, and releases in `finally`. Existing quit ordering stays
  dispose-before-runtime-teardown and needs no reopenable hold. Do not edit
  `plexPlaybackCleanupWiring.ts` or add a new composition owner.
- Cleanup events and failures belong to the epoch/session being drained. Because
  runtime custody prevents any replacement session until all overlapping holds
  settle and emits cleanup events before release, late old cleanup output cannot
  overwrite, obscure, clean, or relabel a newer session. Existing stale-event
  quarantine remains in force after release; do not suppress cleanup failures
  by mutating a later snapshot.

The public regressions use deferred PMS release and player cleanup, not private
state probes. `plexPlaybackRuntime.test.ts` proves Retry and scheduled start
fail closed throughout a deferred cleanup, overlapping cleanup keeps the hold
until the oldest drain settles, no request-2 resolver/player/PMS work starts
early, old cleanup events settle before release, and exact-authoritative Retry
starts request-2 only afterward without later request-1 cleanup affecting it.
`playbackProgramTransitionOwner.test.ts` proves pending Retry and Skip settle
stale after hold-then-invalidate; new Retry/Skip reject busy during one or
nested holds; Skip never mutates the scheduler; programStart is dropped without
runtime dispatch or replay; partial and idempotent release do not reopen; final
release permits a later exact Retry and later programStart exactly once.
`playbackProgramTransitionIntegration.test.ts` uses the real public transition
owner and real `wirePlexPlaybackCleanup()` with a deferred cleanup facade to
prove the profile-change and server-change sequences, plus the helper-crash
sequence: custody precedes invalidation, pending action settles, concurrent
actions/events cannot start, and post-cleanup Retry succeeds without permanent
busy state. `tools/__tests__/smoke-electron.test.mjs` locks the main helper and
profile/server composition order—acquire, invalidate, await/catch, finally
release—without replacing those public-seam tests. No new test file is needed.

Run the focused cleanup-custody surface before the complete remediation command:

```sh
node --import tsx --test src/__tests__/main/player/plexPlaybackRuntime.test.ts src/__tests__/main/player/playbackProgramTransitionOwner.test.ts src/__tests__/main/player/playbackProgramTransitionIntegration.test.ts src/__tests__/main/player/plexPlaybackComposition.test.ts
node --test tools/__tests__/smoke-electron.test.mjs
```

The seven fixes are frozen as follows:

1. **Authorization failure is inert.** `playerRecoveryIpc.ts` returns one fixed
   idle renderer-safe snapshot for unauthorized recovery requests and does not
   call `getSnapshot()` on that branch. It must expose no live request id,
   media, position, duration, tracks, capability, quality detail, or last error.
   Payload validation and authorized accepted/failed results retain their
   existing behavior. The IPC regression supplies a live sentinel snapshot,
   proves the unauthorized result is exactly inert, and proves the live
   snapshot supplier was not read.
2. **Every composed cleanup invalidates transition custody first.**
   `src/main/index.ts` supplies `wirePlexPlaybackCleanup()` a narrow facade that
   calls `PlaybackProgramTransitionOwner.invalidate()` immediately before the
   real runtime cleanup for successful profile and server changes. The native
   host failure callback may first flush the already-routed safe adapter event,
   but must then invalidate the transition owner before
   `handleHelperCrash()`. Both quit branches preserve the existing
   owner-dispose-before-runtime-teardown order. Do not edit
   `plexPlaybackCleanupWiring.ts`. Public owner/integration regressions prove a
   pending Retry and a pending Skip each settle stale rather than remain busy,
   a later action is not permanently rejected busy, and profile-change,
   server-change, helper-crash, and teardown order invalidate before cleanup.
   The smoke source assertion locks the composition ordering without replacing
   the public-seam proof.
3. **Renderer settlements are terminal by generation.** Timeout, bridge
   failure result, invoke rejection, and accepted result each terminally advance
   the current action generation before projecting terminal state. A late
   settlement from a timed-out or otherwise failed action cannot clear its safe
   error, install a snapshot, reactivate transition state, change focus, or
   render. Focused controller tests settle both late accepted and late failed
   results after timeout and prove no resurrection.
4. **Busy projection is symmetric.** While either `retry-current` or
   `skip-next` is in flight, both visible recovery actions remain visible but
   project the existing focus-preserving busy/unavailable semantics:
   `aria-busy="true"`, `aria-disabled="true"`, and busy-focus-custody
   projection, with no second dispatch accepted. When settlement completes,
   both clear together. View-model, route-DOM, and recovery-controller tests
   cover both initiating actions and both controls. No
   `playerOverlayController.ts` or `playerOverlayDom.ts` production edit is
   authorized; the existing DOM projection consumes the corrected view model.
5. **Explicit Retry survives completed helper cleanup without weakening stale
   custody.** `plexPlaybackRuntime.ts`, which owns
   `PlexPlaybackScheduleSelection`, becomes the sole canonical projection and
   equality owner. It exports one narrow projector from
   `(channelId, ratingKey, scheduledStartTime, scheduledEndTime)` to the complete
   canonical selection `(channelId, programId, startedAtMs, endsAtMs)` and one
   exact selection equality guard. Move the existing `programId` construction,
   safe-id normalization, and full selection equality out of
   `plexPlaybackBridge.ts` without changing their behavior.
   `plexPlaybackBridge.ts` consumes those exports for both
   `getCurrentPlayback()` and stale-candidate comparison; it retains scheduler
   reading and resolver/candidate ownership and defines no second encoder or
   equality implementation. `PlaybackProgramTransitionOwner` uses the same
   runtime-owned projector over its authoritative scheduler state/program,
   freezes that complete canonical selection, and passes it to
   `retryCurrentPlayback(expectedSelection)`. No renderer identity or media
   locator is accepted.

   The runtime captures the current epoch, re-reads its main-owned scheduler
   selection, requires exact equality with `expectedSelection`, and only then
   installs that selection as the fresh retry candidate and starts it through
   the existing candidate/PMS resolution path. This permits Retry after
   completed helper-crash cleanup has cleared `activeSelection`, but rejects a
   changed rating key/program id, channel, start, end, tune/program replacement,
   concurrent cleanup, stale scheduler completion, and epoch change before
   installing or starting the selection. It never reuses a released session or
   resurrects an old request. Do not duplicate the bridge's former encoding,
   compare only channel/time, omit end time, accept a callback that hides
   identity comparison, or export scheduler/domain objects across the runtime
   port. Bridge tests lock byte-for-byte-equivalent canonical projection and
   stale comparison before/after the ownership move; runtime, owner, and real
   helper-crash-to-Retry integration regressions prove success after completed
   crash cleanup plus rejection for tune, cleanup, changed-program, and stale-
   identity races.
6. **Accepted snapshot precedes success render.** On an accepted renderer
   recovery result, the controller terminally closes the generation, clears
   pending state, installs the accepted snapshot through `acceptSnapshot`, and
   only then performs the render that projects successful transition state.
   There is no render of the old error snapshot between settlement and snapshot
   installation. A composed ordering regression records snapshot acceptance
   before the success render and proves the old error surface is not left
   projected when no later player event arrives.
7. **Preload recursively rejects forbidden recovery results.**
   `playerRecoveryBridge.cts` accepts an injected forbidden-field predicate in
   its existing validator bundle and rejects the entire invoke result before
   accepting either snapshot or error. `preload/index.cts` supplies its existing
   recursive player forbidden-key predicate and vocabulary; do not add a second
   list, broaden Plex vocabulary, or move privileged validation into renderer.
   Integration regressions submit both an accepted snapshot and a failed error
   containing nested `diagnostic.counts.nativeHandle` and prove fixed safe
   validation failure with no hostile value accepted.

Architecture dispositions remain bounded. `src/main/index.ts` stays a
composition/lifecycle owner and adds only invalidation-before-cleanup wiring.
The sandboxed `src/preload/index.cts` composition root only injects its existing
recursive predicate into the focused bridge; it gains no second validator
vocabulary. The 794-line `plexPlaybackRuntime.ts` cohesively owns the
canonical `PlexPlaybackScheduleSelection` projection/equality, main-scheduler
identity revalidation, epoch, candidate, PMS-session, retry, and nested cleanup
custody lifecycle. Crossing 800 lines still triggers the existing mandatory
fresh architecture review; it does not authorize a forwarding wrapper or
separate cleanup state owner without a distinct responsibility and reviewed
replan.
`plexPlaybackBridge.ts` remains the scheduler-to-runtime and resolver adapter
and consumes that canonical seam rather than retaining duplicate identity
policy; extracting a forwarding wrapper would weaken custody.
`playerOverlayController.ts` remains no-touch at 799 lines and must not cross
800. Fresh independent architecture review remains mandatory.

**Verification classification:** `new regression/contract test required`.
Each new regression must fail for its reproduced rejected behavior and pass for
the frozen public outcome. Run the focused remediation surface, then the
complete Package 2B and full gates:

```sh
node --import tsx --test src/__tests__/main/player/playerRecoveryIpc.test.ts src/__tests__/main/player/playbackProgramTransitionOwner.test.ts src/__tests__/main/player/playbackProgramTransitionIntegration.test.ts src/__tests__/main/player/plexPlaybackRuntime.test.ts src/__tests__/main/player/plexPlaybackBridge.test.ts src/__tests__/main/player/plexPlaybackComposition.test.ts src/__tests__/integration/preloadContractVocabulary.test.ts src/__tests__/renderer/playerErrorRecoveryController.test.ts src/__tests__/renderer/overlays.test.ts src/__tests__/renderer/routeDom.test.ts
node --test tools/__tests__/smoke-electron.test.mjs
npm run typecheck
npm run build:electron
node --import tsx --test src/__tests__/domain/schedulerDomain.test.ts src/__tests__/main/guideRuntime.test.ts src/__tests__/main/player/playerRecoveryIpc.test.ts src/__tests__/main/player/playbackProgramTransitionOwner.test.ts src/__tests__/main/player/playbackProgramTransitionIntegration.test.ts src/__tests__/main/player/plexPlaybackRuntime.test.ts src/__tests__/main/player/plexPlaybackBridge.test.ts src/__tests__/main/player/plexPlaybackComposition.test.ts src/__tests__/contracts/contracts.test.ts src/__tests__/integration/preloadContractVocabulary.test.ts src/__tests__/renderer/playerErrorRecoveryController.test.ts src/__tests__/renderer/playerOverlayController.test.ts src/__tests__/renderer/overlays.test.ts src/__tests__/renderer/routeDom.test.ts
npm run smoke:electron
npm run verify:maintainability
npm run verify:architecture
npm run verify:redaction
npm run verify
git diff --check
```

Acceptance requires all seven public regressions, every original Package 2B
focused test, all full gates, the unchanged 799-line overlay-controller cap,
exact 20-file remediation scope, and fresh independent implementation review
to pass. Any live-state authorization exposure, pending action after cleanup,
late renderer resurrection, asymmetric busy projection, Retry using
renderer-supplied or stale identity, old-error success render, nested forbidden
field acceptance, recovery/scheduled start during runtime or transition cleanup
custody, Skip mutation during a hold, replay of a cleanup-time program event,
premature nested-hold release, old cleanup output affecting a newer session,
permanent post-cleanup busy state, scope expansion, or material review finding
blocks the Package 2B checkpoint.

Rollback remains the entire 34-file Package 2B recovery API/action slice,
including the approved route-DOM correction and this remediation. Do not
partially roll back one trust boundary, generation owner, test authority, or
preload guard while leaving the public recovery method active.

PACKAGE_2B_IMPLEMENTATION_REMEDIATION_REVIEW_PACKET_2026_07_28
NEXT_SESSION_LAUNCHER: lineup-desktop-feature-review
TASK: Review Package 2B Seven-Finding Remediation Plan
TASK_FAMILY: feature/design
TIER: Tier 3
PLAN: docs/plans/2026-07-22-tier3-parity-correction-plan.md
ARTIFACT: PACKAGE_2B_IMPLEMENTATION_REMEDIATION_2026_07_28
FILES:
- docs/plans/2026-07-22-tier3-parity-correction-plan.md
PRESERVE:
- the complete current uncommitted Package 2B diff, revised 34-file boundary,
  and all passed verification evidence
- the independently approved route-DOM scope correction
EDIT_AFTER_APPROVAL:
- only the exact 20-file remediation subset named above
REQUIRED_REVIEW_ASSERTIONS:
- all seven reproduced findings have one decision-complete owner, invariant,
  public regression, and stop condition
- no finding requires a twenty-first file, cleanup-owner edit, contract expansion,
  renderer identity authority, duplicated identity encoding/equality, duplicated
  forbidden vocabulary, or broad renderer refactor
- `plexPlaybackRuntime.ts` is the sole canonical projector/equality owner,
  `plexPlaybackBridge.ts` only consumes it, and the bridge regression preserves
  the former program-id bytes and full stale-selection comparison
- the existing composition manual-retry test passes a required canonical
  selection while preserving its exact two-load and switch-cleanup assertions;
  no optional/default identity or compatibility fallback is authorized
- runtime and transition cleanup custody are acquired synchronously, nest
  correctly, release only in `finally` after full cleanup settlement, and block
  Retry, Skip, scheduled starts, and automatic retry without permanent busy
- cleanup-time `programStart` is intentionally dropped without scheduler
  mutation, runtime dispatch, coalescing, or release-time replay; a later event
  or exact-authoritative Retry is the only post-release start
- deferred public-seam regressions cover PMS/player drain, overlapping cleanup,
  helper crash, composed profile/server cleanup, late old cleanup output,
  post-cleanup Retry, and exactly-once later program transition
- helper-crash Retry re-resolves and revalidates exact main-owned current
  identity under epoch custody and never reuses a released session
- profile/server/helper/teardown cleanup invalidates transition custody first,
  terminal renderer generations cannot resurrect, both actions project
  symmetric busy state, and accepted snapshots render in the frozen order
- authorization failure is inert and preload rejects nested forbidden fields
  before accepting either snapshot or error
- original Package 2B semantics, no-touch boundaries, 799-line cap, full
  verification, whole-slice rollback, later-workstream obligations, and Mac
  completion override remain unchanged
BLOCKERS:
- worker remains paused until fresh independent plan review explicitly approves
  this complete remediation amendment
MESSAGE:
Adversarially review the complete
PACKAGE_2B_IMPLEMENTATION_REMEDIATION_2026_07_28 amendment against all seven
accepted implementation findings and the P1 identity-ownership plan finding.
Confirm the exact 20-file subset is sufficient and remains inside the revised
34-file boundary; the runtime-owned canonical projector/equality seam is
implementable without duplicate encoding or weaker comparison; nested runtime
and transition cleanup custody closes every pre-release start window; the
drop-without-replay programStart policy is safe and exactly-once; deferred
runtime/owner/helper/profile/server regressions prove no old cleanup can affect
a newer session and no permanent busy remains; every prior fix remains
decision-complete; and no original Package 2B or later obligation is weakened.
Report findings by severity and explicitly APPROVE or REJECT. Do not authorize
implementation while any material finding remains.

PACKAGE_2B_CLEANUP_CUSTODY_REVIEW_PACKET_2026_07_28
NEXT_SESSION_LAUNCHER: lineup-desktop-feature-review
TASK: Review Package 2B Cleanup-Custody Lifecycle Amendment
TASK_FAMILY: feature/design
TIER: Tier 3
PLAN: docs/plans/2026-07-22-tier3-parity-correction-plan.md
ARTIFACT: accepted cleanup-custody lifecycle correction within
PACKAGE_2B_IMPLEMENTATION_REMEDIATION_2026_07_28
FILES:
- docs/plans/2026-07-22-tier3-parity-correction-plan.md
IMPLEMENTATION_AFTER_APPROVAL:
- only the exact eight-file cleanup-custody subset
PRESERVE:
- the complete current remediated Package 2B diff and all seven prior fixes
- 34-file Package 2B scope, 20-file remediation scope, canonical identity,
  route-DOM authority, 799-line overlay-controller cap, rollback, and full gates
FROZEN_POLICY:
- runtime cleanup uses synchronous nested holds through full player/PMS
  settlement and event emission; starts/retries fail closed until final release
- transition cleanup uses nested idempotent holds acquired before invalidation
  and released in `finally`; Retry/Skip reject busy and Skip never mutates
- cleanup-time `programStart` is dropped with no runtime call, queue,
  coalescing, or replay; later exact Retry or later scheduler event is required
- old cleanup events cannot affect a replacement session, post-cleanup exact
  Retry succeeds, and overlapping cleanup cannot reopen early or remain busy
REQUIRED_REVIEW_ASSERTIONS:
- the eight existing files are sufficient and no cleanup-wiring/contract/new
  file edit is required
- runtime and transition holds close the reproduced request-2-during-request-1-
  cleanup race across helper, profile, server, stop, teardown, and overlapping
  cleanup paths
- drop-without-replay is a safe explicit scheduler policy and preserves honest
  exactly-once semantics
- deferred PMS/player public tests prove no early resolver/player/PMS work, no
  Skip mutation, no program-event dispatch/replay, release only after complete
  drain, stale old output quarantine, and successful later exact Retry/event
- the existing composition deferred-stop test rejects and does not install or
  consume request B during the hold, then starts and preserves request B only
  after release while retaining request-A and final request-B cleanup proof
- no previous remediation behavior, trust boundary, proof gate, or later
  workstream obligation is weakened
BLOCKERS:
- worker remains paused until fresh independent plan review explicitly approves
  this lifecycle amendment
MESSAGE:
Adversarially review only the accepted Package 2B cleanup-custody lifecycle
amendment in the canonical plan. Reproduce the open invalidation-to-cleanup-
settlement window conceptually, then confirm the nested runtime and transition
holds, main acquisition/finally ordering, fail-closed actions, explicit
drop-without-replay programStart policy, overlapping cleanup semantics,
late-event isolation, post-cleanup success, exact eight-file scope, regressions,
rollback, and stop conditions are decision-complete. Report findings by
severity and explicitly APPROVE or REJECT. Do not authorize implementation
while any material finding remains.

#### `WS2-POST-VALIDATION-01` — deferred native/Windows validation debt

This is not Package 2C, is not in the executable WS2 sequence, owns no current
edit/commit, and has no WS2 blocking power. A later separately reviewed task
may run the preserved Windows/.NET Release build/clean, live helper ERROR/EOF
projection, representative direct-play/remux/transcode media matrix,
windowed/fullscreen OSD/mini-guide/options focus audit, keyboard/numpad checks,
loading/buffering/seeking/stalled/ended/interruption recovery, Retry/Skip,
helper crash/replacement soak, audio/subtitle switching and delivery, HDR/HLG/
Dolby Vision/SDR fallback, and safe hardware/display capability observations.
It must use exact then-committed source, sanitized evidence, redaction checks,
and the existing no-private-data rules.

Unavailable, unrun, ambiguous, or failed observations remain debt and keep the
affected registry rows partial/proof-open; they do not reopen or invalidate an
honestly closed WS2 implementation gate. A discovered product defect returns
through a new reviewed remediation plan. Observed additional support may
propose a new post-WS2 capability-promotion plan, but never mutates capability
truth directly. Existing WS9/RD-27/RD-28 packaged Windows owners remain
separate and unchanged.

#### Package 2D — conservative capability no-op

**IMPLEMENTER_ROLE_ELIGIBILITY:** no implementation worker is delegated.
The controller records the reviewed disposition that
`getProductionCapabilityProfile()` remains byte-for-byte conservative:
MP4/H.264/AAC direct play only, subtitle delivery `none`, and unsupported
audio/subtitle switching, HDR/Dolby Vision, direct-stream, and transcode
families.

Package 2D owns no source, test, evidence, or capability edit; runs no
Windows/native command; creates no checkpoint commit; and is complete for WS2
when the no-op disposition is reviewed and handed to Package 2E. Any promotion
is deferred until `WS2-POST-VALIDATION-01` later supplies exact reviewed facts
under a new plan. Unobserved support remains unsupported.

**Verification classification:** `no new automated test needed`. Package 2A/2B
and full Mac verification already exercise the unchanged profile; Package 2E
records the conservative no-op. A changed profile, new support literal, or
attempt to infer capability from helper source/static tests is a stop/replan,
not Package 2D work.

#### Package 2E — WS2 authority reconciliation and implementation-gate closeout

**IMPLEMENTER_ROLE_ELIGIBILITY:** `worker_sol_low` only after the controller
freezes every row disposition from accepted commits and evidence. The mapped
role is eligible because it must perform an exact mechanical authority update
and must make no product, architecture, proof-depth, or classification decision.

**Exact owned files:** `docs/plans/2026-07-22-tier3-parity-correction-plan.md`,
`docs/architecture/CURRENT_STATE.md`,
`docs/architecture/playback-architecture.md`,
`docs/product/lineup-product-parity-matrix.md`,
`docs/roadmap/desktop-port-roadmap.md`, and
`docs/architecture/import-ledger.md` only if an accepted implementation import
row still needs its final evidence/commit reference. No source, test, tool,
run-harness, WS1 evidence/checklist, later-workstream authority, or package file
may be edited.

The worker updates only controller-supplied exact statuses/evidence links,
removes the stale unqualified RD-25/RD-26 parity implication, records commits
and observed commands, keeps all unavailable Windows claims open, and preserves
`PB-07`, `WIN-07`, and `PB-22`–`PB-24` as open through their named
contributors. It records `WS2-POST-VALIDATION-01` as nonblocking post-WS2 debt
and Package 2D as a conservative no-op. It must not decide whether a row
advances, paraphrase missing proof into a pass, alter WS1 debt, authorize
WS3–WS9, weaken a target, or invent a Windows result. Missing Windows evidence
is expected and does not stop closeout; a missing controller disposition,
conflicting authority, failed Mac-runnable verifier, or requested product edit
is an immediate stop/escalation.

**Verification classification:** `no new automated test needed`. Exact proof is
authority consistency plus:

```sh
npm run verify:docs
npm run verify:redaction
git diff --check
npm run verify
```

Rollback is the single docs-only closeout commit; accepted product commits and
ignored redacted evidence remain intact. Checkpoint:
`docs(parity): record ws2 playback implementation gate`.

**Package 2E closeout record (2026-07-28):** reviewed plan checkpoints
`9a66dd6` and `60c68f4`, reviewed Package 2A commit `8dc1057`, and reviewed
Package 2B commit `d2f1e97` are published on `initial-build`. Package 2B
observed 46/46 cleanup/runtime/composition, 114/114 remediation, 196/196
complete-package, 994 aggregate contract passes plus one intentional skip, and
179/179 harness/docs tests; typecheck, Electron build, static/live Electron
smoke, architecture, maintainability, redaction, docs, full `npm run verify`,
and `git diff --check` also passed. Its 794-line runtime and 799-line overlay
controller were reviewed as cohesive below the existing 800-line threshold
with no growth headroom.

Package 2D received independent approval as a conservative no-op at `d2f1e97`;
its focused production-profile test passed 2/2 and it made no source, test,
evidence, capability, or commit change. Production remains MP4/H.264/AAC
Direct Play only, with subtitle delivery `none` and switching, HDR/Dolby
Vision, Direct Stream/remux, and every transcode family unsupported.

This closes only WS2's platform-neutral implementation gate. Every unavailable
or unrun Windows/.NET Release/native build, live libmpv ERROR/EOF,
representative-media, Windows video/focus/input/manual/soak,
track-delivery/switching, HDR/display/hardware-capability, and helper-
replacement observation remains nonblocking post-WS2 debt under
`WS2-POST-VALIDATION-01`. No support or capability promotion follows. WS1
remains open unchanged; WS3–WS9 are not started or authorized, with WS3 only
the next unopened freshness-planning target; RD-27/RD-28 and WS9 packaged
proof ownership remain unchanged.

### WS2 acceptance, rollback, and replan rules

WS2's implementation gate is complete after 2A and 2B are committed/published
and cleanly reviewed, Package 2D's conservative no-op is reviewed, Package 2E
passes, all named platform-neutral static/contract/integration/smoke/
architecture/maintainability/redaction/full verification is green, imports are
ledgered, and active playback no longer relies on fake WS2-owned production
behavior. `WS2-POST-VALIDATION-01` is carried in closeout/handoffs but does not
keep WS2 active or closeout-pending and does not block commits or publishing.
Missing native/Windows proof never becomes a support claim.

Rollback is per checkpoint and must preserve one buildable/smokeable state.
Never roll back shared channel/persistence data, erase honest blocked evidence,
erase honest post-WS2 debt, or combine packages into one unreviewable commit.

Stop and replan before further product edit or commit when:

- a WS1 lineup, persistence, guide-refresh, or mutation defect appears;
- source/contract/owner freshness contradicts this amendment;
- recovery cannot remain main-owned and generation-safe;
- a public schema, IPC method, persisted setting, capability field, helper
  protocol, or exact file outside the active package is required;
- any native-helper source edit beyond Package 2A's exact `Program.cs`
  branch/struct/emitter, or any dependency/lockfile/package policy,
  redistribution, signing/updater, or new privileged diagnostic surface is
  required;
- Package 2D attempts any capability/profile edit or claims support without a
  future reviewed post-WS2 evidence package;
- a touched attention owner reaches its extraction/review trigger;
- required verification fails or evidence would contain private material; or
- current upstream changes materially beyond audited `0258dbe`.

Carry WS1 debt unchanged, including paired visual manifests, live multi-library
facet/filter proof, append/replace proof, manual accessibility/input/scale
proof, packaged ACL proof, and `WS1-PERF-01`: workflow `30074270895`, job
`89421508431`, exact head `335a13acfcee3f5450c104ed3fc48e45e461264a`,
Windows Server 2025, Node 22.19.0, unchanged 50,000-candidate fixture,
2,690.61 ms observed against the unchanged 2,000 ms cap.

MODEL_SUGGESTION
PLANNER: current tracked planner
IMPLEMENTER: tracked role selected per package
REVIEWER: current tracked reviewer
WHY: WS2 crosses main runtime lifecycle, typed IPC/security, renderer recovery,
native playback, conservative capability truth, deferred validation debt, and
later-workstream contribution gates.

WS2_MAC_COMPLETION_OVERRIDE_REVIEW_PACKET
NEXT_SESSION_LAUNCHER: lineup-desktop-feature-review
TASK: Review WS2 Mac Completion Override
TASK_FAMILY: feature/design
TIER: Tier 3
PLAN: docs/plans/2026-07-22-tier3-parity-correction-plan.md
ARTIFACT: ACTIVE_WS2_MAC_COMPLETION_OVERRIDE_2026_07_28 within
ACTIVE_WS2_EXECUTION_AMENDMENT_2026_07_28
FILES:
- docs/plans/2026-07-22-tier3-parity-correction-plan.md
PRESERVE:
- the exact implemented Package 2A diff and every observed local verification
  and independent-review result
- Package 2B scope/semantics and all existing WS1/WS3–WS9 contribution debt
EXECUTABLE_WS2_SEQUENCE:
- Package 2A
- Package 2B
- Package 2D conservative no-op
- Package 2E
POST_WS2_DEBT:
- `WS2-POST-VALIDATION-01` owns every Windows/.NET Release/native build, live
  libmpv ERROR/EOF, Windows native/manual/soak, and capability observation
BLOCKERS:
- failed platform-neutral Package 2A/2B focused or full verification
- unresolved material independent-review finding
- non-conservative Package 2D edit/claim
- inconsistent Package 2E authority reconciliation
NONBLOCKERS:
- unavailable/unrun/failed Windows machine, `.NET`, Release helper build, live
  libmpv path, Windows manual/soak, or capability proof
- absence of a former Package 2C execution
REQUIRED_REVIEW_ASSERTIONS:
- the override has plan-wide precedence over every conflicting Windows/.NET/
  native/manual/soak/capability requirement only as applied to WS2, including
  clauses earlier than the active amendment
- all such earlier requirements retain full force for WS1, WS3–WS9, RD-27,
  RD-28, their own gates, and parity-program closeout
- Mac-runnable static/contract/integration/smoke/typecheck/build/architecture/
  maintainability/redaction/full verification plus independent review remain
  mandatory
- no missing proof is converted to support and the production capability
  profile remains conservative
- Package 2C is absent from the executable graph, Package 2D is a reviewed
  no-op with no edit/commit, and Package 2E records the debt without blocking
  closeout
- Package 2A may checkpoint/commit/publish and WS2 may close while
  `WS2-POST-VALIDATION-01` remains open
MESSAGE:
Adversarially review only the planning override and its consistency across the
complete canonical plan, including clauses earlier than the active WS2
amendment. Confirm its plan-wide-as-applied-to-WS2 precedence permits honest Mac-only WS2
completion without weakening platform-neutral verification/review or promoting
unproved capabilities; carries all Windows/native/live/capability work under
the exact nonblocking debt ID; preserves the implemented Package 2A diff and
local evidence; removes Package 2C from execution; closes Package 2D as a
conservative no-op; and updates acceptance, rollback, closeout, and handoff
without altering Package 2B or weakening WS1, WS3–WS9, RD-27/RD-28, or program
closeout requirements. Report material findings or explicit approval.
