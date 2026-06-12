# Lineup Desktop UI Parity Implementation Plan

**Plan Status:** active  
**Task family:** feature/design  
**Target Desktop branch:** `TJZine/LineupDesktop@initial-build`  
**Reference WebOS branch:** `TJZine/Lineup@code-health`  
**Created:** 2026-06-12  
**Primary goal:** bring `LineupDesktop` Windows UI style, density, overlay choreography, focus language, artwork readiness, settings/onboarding composition, and EPG rendering into close parity with WebOS `Lineup`, without weakening Desktop's Electron, Plex, persistence, playback, diagnostics, redaction, or maintainability boundaries.

> This is a durable implementation plan intended to be saved as:
>
> `docs/plans/2026-06-12-ui-parity-implementation-plan.md`
>
> Keep it tracked only while active. After closeout, promote durable conclusions to the roadmap/current-state/import-ledger/docs as appropriate, then move the full plan body to the local ignored archive according to Desktop plan rules.

---

## Goal

Implement WebOS-style UI parity in `LineupDesktop@initial-build` through bounded, reviewable Codex execution units. The implementation must cover every surface identified by the attached audit:

1. Global visual tokens and 10-foot density.
2. App shell / route chrome.
3. OSD panel.
4. Now Playing panel.
5. Mini guide.
6. Channel number overlay.
7. Playback options.
8. Plex auth PIN/QR presentation.
9. Profile PIN modal/numpad.
10. Server selection polish.
11. Settings rail.
12. Guide / EPG time-math layout.
13. Channel setup staged composition.

The target visual language is WebOS Lineup's 10-foot media UI: immersive full-screen dark glass, high-contrast focus, large type, edge-attached overlays, cinematic artwork areas, remote/gamepad-first interaction, reduced desktop-card chrome, and time-proportional guide cells.

The implementation must preserve Desktop-specific product requirements: unprivileged renderer, main-owned Plex/auth/transport/credentials, main/helper-owned playback/native concerns, support-bundle diagnostics, redaction, Electron shell hardening, Windows focus/fullscreen behavior, mouse/keyboard accessibility, and maintainability/file-shape controls.

---

## Non-Goals

- Do not implement fake features merely to match WebOS labels. Specifically do not add fake Sleep Timer, fake latency, fake channel reorder, fake cast headshots, fake clear-logo/artwork from tokenized Plex URLs, or fake live health values.
- Do not import WebOS app architecture, old path barrels, class-name compatibility wrappers, or upstream source topology just to mirror file names.
- Do not expose raw Plex tokens, auth headers, tokenized media/image URLs, native handles, raw Electron APIs, Node APIs, raw Plex payloads, or native playback details to renderer-facing contracts.
- Do not widen preload into broad RPC. Any new preload/main surface requires a narrow typed contract, guard coverage, sender validation, redaction checks, and explicit plan review.
- Do not introduce new runtime dependencies for styling, visual proof, screenshots, QR generation, or image handling unless a reviewed replan names owner, lockfile impact, licensing/provenance/security posture, and rollback.
- Do not make EPG parity depend on aggressive virtualization, background schedule warming, or scheduler/runtime redesign unless performance evidence proves it necessary.
- Do not redesign channel setup interaction semantics to support drag/drop, channel reordering, or unsupported scheduler/channel contracts.
- Do not weaken CSP, navigation containment, permission denial, new-window denial, Electron sandboxing, context isolation, or renderer privilege denial to load artwork or run tests.

---

## Parent Architecture Alignment

This is Tier 3 UI/product work because it spans renderer composition, renderer CSS, Plex-safe view presentation, possible renderer-safe media/art descriptors, visual proof, and multiple active product surfaces. The active Desktop rules require explicit planning, feature-quality review, bounded implementation, implementation review, observed verification, and closeout memory updates.

Relevant repo-aligned decisions:

- **Renderer owns visual composition only.** Renderer code may own DOM, CSS, view-model projection, focus state, keyboard/remote presentation, timers/listeners, and accessibility. It must not own Plex transport, secret storage, token-bearing URL construction, app paths, native playback, packaging, or raw Electron APIs.
- **Contracts own renderer-safe shapes only.** Any new public shape for artwork, guide cell positioning, server status, or profile/auth UI state must be explicit, narrow, tested, and free of forbidden privileged fields.
- **Main/Plex owners retain credential and transport custody.** Plex auth, selected server, server health, library, artwork lookup, and tokenized media setup remain main-owned or use existing main-owned seams. Renderer receives safe summaries only.
- **Existing Desktop support/diagnostics remain valid.** Settings parity must preserve support-bundle export and diagnostics states even though they are not WebOS features.
- **Lineup WebOS is visual reference, not architecture authority.** Copy behavior intentionally where it fits; adapt or re-express visual patterns in Desktop-owned files. If any upstream code/CSS is copied or closely adapted, update `docs/architecture/import-ledger.md` before or with the import.
- **Electron security remains production baseline.** Official Electron security guidance emphasizes not loading/executing untrusted remote code with Node integration, enabling context isolation and process sandboxing, restrictive CSP, limited navigation/new windows, custom protocols over `file://`, and validating IPC senders. This plan must preserve those constraints.

---

## Required Reading

Read these in order before editing:

1. `AGENTS.md` on `LineupDesktop@initial-build`.
2. `docs/AGENTIC_DEV_WORKFLOW.md` on `LineupDesktop@initial-build`.
3. `docs/agentic/plan-authoring-standard.md` on `LineupDesktop@initial-build`.
4. `docs/architecture/CURRENT_STATE.md` on `LineupDesktop@initial-build`.
5. `docs/architecture/file-shape-guardrails.md` on `LineupDesktop@initial-build`.
6. `docs/architecture/import-ledger.md` on `LineupDesktop@initial-build`.
7. `docs/architecture/security-and-secret-flow.md`, `docs/architecture/playback-architecture.md`, and `docs/architecture/upstream-behavior-guardrails.md` if the implementation unit touches Plex, artwork, playback-derived data, or public contracts.
8. Attached audit: `ui_parity_audit_results.md`.
9. Desktop source evidence:
   - `src/renderer/staticDom.ts`
   - `src/renderer/routeDom.ts`
   - `src/renderer/overlayViewModels.ts`
   - `src/renderer/overlays.ts`
   - `src/renderer/epg.ts`
   - `src/renderer/plexRuntimeDom.ts`
   - `src/renderer/plexRuntimeRows.ts`
   - `src/renderer/channelSetup/**`
   - `src/renderer/styles/base.css`
   - `src/renderer/styles/player-overlays.css`
   - `src/renderer/styles/guide-epg.css`
   - `src/renderer/styles/workflow-screens.css`
   - `src/renderer/styles/plex-onboarding.css`
   - `src/main/smokeAssertions.ts`
   - existing renderer, contract, smoke, maintainability, docs, and redaction tests.
10. WebOS reference evidence:
   - `Lineup@code-health:src/styles/tokens.css`
   - `src/modules/ui/now-playing-info/**`
   - `src/modules/ui/player-osd/**`
   - `src/modules/ui/mini-guide/**`
   - `src/modules/ui/playback-options/**`
   - `src/modules/ui/auth/**`
   - `src/modules/ui/profile-select/**`
   - `src/modules/ui/server-select/**`
   - `src/modules/ui/settings/**`
   - `src/modules/ui/channel-setup/**`
   - `src/modules/ui/epg/**`
11. Official Electron security guidance for any change touching renderer privileges, protocols, CSP, remote content, or IPC.

Freshness gate: if any file above has materially changed after this plan was written, stop and update or re-review the plan before editing.

---

## Required Skills

Use these Lineup Desktop project skills:

- `execution-plan-authoring`: this is a durable Tier 3 plan with multiple Codex execution units and must be decision-complete.
- `ui-composition-patterns`: all units touch renderer UI, focus, keyboard/remote behavior, motion, accessibility, media presentation, or visual proof.
- `architecture-boundaries`: the plan touches module shape, renderer/main/preload boundaries, and possible public contracts.
- `plex-integration-boundaries`: auth, profile PIN, server rows, artwork, and library-driven presentation must remain Plex-safe and main-owned where applicable.
- `persistence-boundaries`: settings, selected server, support-bundle surfaces, and profile/session-related UI must not introduce renderer persistence or browser storage shortcuts.
- `verification-strategy`: visual parity requires automation plus manual/browser proof, not only type/lint/test checks.
- `review-request`: plan review and implementation review are required before closeout.
- `closeout-verification`: final work must record observed commands, screenshot/manual evidence, reviewed deviations, and memory updates.

---

## Evidence And Discovery

### Branch correction

All implementation evidence must be gathered from:

- `TJZine/LineupDesktop@initial-build`
- `TJZine/Lineup@code-health`

Do not rely on `LineupDesktop@main` or `Lineup@main` for this task unless a rebase/merge changes the target branch.

### Audit evidence summary

The attached audit found that Desktop is functionally broad but visually divergent: route card chrome, smaller tokens, simplified overlays, centered modals, inline/profile inputs, and fixed-column EPG remain visibly more desktop-like than the WebOS 10-foot media UI. The recommended implementation sequence is token foundation, overlay parity, onboarding input parity, settings rail parity, guide parity, and channel setup parity.

### Source evidence summary

- Desktop `initial-build` has the renderer surface the audit describes: static screen markup, player/guide/settings/channel setup routes, player overlays, mini guide, playback options, channel number overlay, Plex runtime panels, and guide rendering in renderer-owned DOM/CSS files.
- Desktop base CSS currently defines compact spacing and small-ish route chrome tokens such as `--space-2: 6px`, `--space-4: 10px`, `--space-8: 18px`, `--button-min-height: 42px`, plus topbar/rail/screen panel chrome.
- Desktop `player-overlays.css` currently places Now Playing as a bottom-right card, OSD as a bottom-right panel with a 5px progress bar, mini guide/playback options/channel-number as centered overlays, and playback options as two-column modal content.
- Desktop guide still uses CSS grid slot columns and `gridColumn` spans from renderer-projected program column data. WebOS computes real pixel positions from time and duration, then renders absolute cells with live/current/focus/progress/ticker/compact-tier presentation.
- Desktop current state and file-shape guardrails show several UI owners already over 500 lines, including `src/renderer/epg.ts`, `src/renderer/routeDom.ts`, `src/renderer/overlayViewModels.ts`, and `src/renderer/index.ts`. New parity work must decompose rather than grow these owners.
- WebOS tokens define the 10-foot text scale, spacing scale, focus ring, progress heights, panel/scrim vocabulary, radius vocabulary, and z-index semantics.
- WebOS Now Playing has backdrop/poster/clear-logo, metadata badges, playback summary, meta lines, autoscrolling description, actor/cast areas, and progress metadata.
- WebOS OSD has a title/clear-logo zone, action affordances, monospace tabular meta strip, and 10px progress bar.
- WebOS mini guide is a five-row edge-attached top shelf with channel number, branding slot, channel name, now title/start time, progress, next title, loading state, focus state, and footer hint.
- WebOS playback options is a right-side rail with one-column sections, selected/focused accent treatment, meta pills, and an animated selected-track equalizer.
- WebOS auth/profile screens use remote-first PIN boxes, QR/PIN card presentation, modal PIN slots, and on-screen numpad.
- WebOS settings use a left category rail, profile row, cardless detail pane, toggle/select controls, focus coordination, and pane transitions.
- Official Electron security guidance supports the existing Desktop posture: local/trusted content, no Node integration for remote content, context isolation, process sandboxing, restrictive CSP, limited navigation/new windows, IPC sender validation, and custom protocols.

### Discovery method expectation for implementer

Before each unit, run a fresh local evidence sweep:

```bash
git status --short --branch
rg "now-playing|player-osd|mini-guide|playback-options|channel-number|settings|epg|plex-runtime|profile-pin|auth-pin" src/renderer src/contracts src/main tools docs
rg "lineup-style-ready|verify:maintainability|file-shape|import-ledger" docs tools src/main package.json
```

Use Codanna if useful for symbol ownership; record any Codanna stale/noisy fallback in the implementation notes. Direct `rg`/source reads are acceptable for UI/CSS surfaces.

---

## Impact Snapshot

### Owners that may change

- Renderer UI composition and view-model projection.
- Renderer CSS/style tokens.
- Renderer DOM bindings.
- Renderer focus/action mapping only if required by overlay/profile/settings parity.
- Contract vocabulary only if renderer-safe artwork, guide presentation, or server/profile UI data needs a stable public shape.
- Main/Plex owners only if a safe artwork/status summary already exists or a narrow renderer-safe data seam is unavoidable; such work must be split into its own reviewed unit.
- Docs/import ledger/current-state/roadmap only for plan tracking, closeout, or copied/adapted upstream source.

### Owners that should not change without replan

- Native/helper playback internals.
- Secure credential storage.
- Plex token/auth-header transport.
- Packaging/signing/update pipeline.
- Broad preload bridge shape.
- Electron navigation/protocol/security policy.
- Scheduler/channel domain behavior, except renderer-safe guide presentation projection if needed.
- Public release artifacts or binary redistribution.

### Public contracts

Expected first-pass implementation should avoid public contract changes. If artwork, server latency/health, profile PIN state, or guide presentation data cannot be expressed from existing renderer-safe state, create a focused contract subplan. Do not broaden `src/contracts/player.ts` casually because it is already allowlisted and has a split trigger for new public player contract families.

### Dependencies

No dependency changes are expected. Use platform/Electron capabilities, existing test harnesses, and repo code. If QR generation, screenshot diffing, or visual regression tooling appears to require a package, stop and replan; first prefer static QR asset reuse, existing SVG, Electron `capturePage`, or manual screenshot proof.

### Commands/tests/docs likely to change

- Renderer unit/DOM tests under `src/__tests__/**`.
- Existing smoke assertions if style-ready marker changes.
- Maintainer docs/plan/import-ledger only as needed.
- Optional dev-only visual proof harness under `tools/**` if existing smoke harness cannot capture required evidence without fragile manual steps.

### User-visible behavior that must not regress

- Existing player playback behavior and commands.
- Existing route reachability: player, guide, settings, channel setup.
- Existing support-bundle export flow.
- Existing Plex runtime account/server/library workflows.
- Existing keyboard, mouse, remote/gamepad focus affordances.
- Existing fullscreen bridge behavior.
- Existing redaction and renderer-safe diagnostics.
- Existing no-secret renderer boundary.

### Local-only artifacts that must stay untracked

- `docs/runs/ui-parity-*/`
- screenshots, videos, visual comparison notes, temporary test data
- Codanna indexes/caches
- generated Electron build outputs
- local package outputs

---

## Files In Scope

Treat these as allowed scopes by unit, not a license to edit everything in one pass.

### Unit 0 - plan and freshness

- `docs/plans/2026-06-12-ui-parity-implementation-plan.md`
- `docs/architecture/import-ledger.md` only if copied/adapted upstream source is imported.
- `docs/architecture/CURRENT_STATE.md` and roadmap only at closeout if durable conclusions change.

### Unit 1 - token and shell parity foundation

- `src/renderer/styles/base.css`
- `src/main/smokeAssertions.ts`
- `src/renderer/staticDom.ts` only for shell/route chrome class hooks needed by CSS.
- `src/renderer/styles/workflow-screens.css`
- Node-safe renderer/style/smoke tests that assert route reachability and style marker behavior.

### Unit 2 - player overlay parity package

- `src/renderer/staticDom.ts`
- `src/renderer/domBindings.ts`
- `src/renderer/routeDom.ts` only if overlay rendering remains there; prefer extracting focused overlay DOM helpers.
- `src/renderer/overlays.ts`
- `src/renderer/overlayViewModels.ts` only if split first or modified narrowly.
- `src/renderer/styles/player-overlays.css`
- New focused renderer overlay helper files, if needed:
  - `src/renderer/overlays/nowPlayingDom.ts`
  - `src/renderer/overlays/osdDom.ts`
  - `src/renderer/overlays/miniGuideDom.ts`
  - `src/renderer/overlays/playbackOptionsDom.ts`
  - `src/renderer/overlays/channelNumberDom.ts`
- Renderer tests for overlay view models, DOM rendering, focus fallback, hidden/visible states, and keyboard/mouse action preservation.

### Unit 3 - onboarding/profile/server input parity

- `src/renderer/staticDom.ts`
- `src/renderer/plexRuntimeDom.ts`
- `src/renderer/plexRuntimeRows.ts`
- `src/renderer/styles/plex-onboarding.css`
- `src/renderer/styles/workflow-screens.css`
- `src/renderer/domBindings.ts`
- Focus/action tests for auth PIN, profile PIN fallback, server row selection, and no-secret presentation.
- Contract/main/preload files only if a separate reviewed subplan proves a renderer-safe data seam is unavoidable.

### Unit 4 - settings rail parity

- `src/renderer/staticDom.ts`
- `src/renderer/routeDom.ts`, but extract if file growth would exceed guardrails.
- `src/renderer/settings/**` if creating focused settings renderers is cleaner.
- `src/renderer/styles/workflow-screens.css`
- `src/renderer/styles/base.css` only for shared tokens/hooks.
- Existing settings/support-bundle action tests.

### Unit 5 - guide / EPG parity

- `src/renderer/epg.ts`
- `src/renderer/routeDom.ts`, preferably split guide rendering before adding behavior.
- `src/renderer/styles/guide-epg.css`
- New focused files if needed:
  - `src/renderer/epg/guidePresentation.ts`
  - `src/renderer/epg/guideCellPosition.ts`
  - `src/renderer/epg/guideCellDom.ts`
  - `src/renderer/epg/guideVisibleWindow.ts`
- Renderer EPG tests for time-to-pixel math, clipping, current/live state, width tiers, focus overflow, and no selectable empty state.

### Unit 6 - channel setup staged shell parity

- `src/renderer/staticDom.ts`
- `src/renderer/channelSetup/**`
- `src/renderer/styles/plex-onboarding.css`
- `src/renderer/styles/workflow-screens.css`
- `src/renderer/plexRuntimeDom.ts` only for markup/hooks reused by setup stages.
- Channel setup tests for staged shell, server/library/media detail preservation, and no unsupported drag/drop/reorder semantics.

### Unit 7 - proof and closeout

- `tools/smoke-electron.mjs` only if extending existing smoke proof without weakening it.
- `tools/__tests__/**` only for harness-shape tests.
- `docs/runs/ui-parity-*/` local ignored evidence.
- `docs/architecture/CURRENT_STATE.md`, `docs/roadmap/desktop-port-roadmap.md`, and `docs/architecture/import-ledger.md` only for durable closeout updates.

---

## Files Out Of Scope

Do not edit these without a reviewed replan:

- `src/main/player/**` native/helper playback behavior.
- `src/main/native/**` or native helper binaries.
- `src/main/persistence/**` unless a settings persistence bug is discovered and separately planned.
- `src/main/plex/**` transport/auth/stream setup unless an explicit renderer-safe artwork/status subplan is approved.
- `src/preload/index.cts` or preload bridge files unless a contract-approved narrow method is required and reviewed.
- `src/contracts/player.ts` unless adding a stable renderer-safe media/artwork contract is explicitly approved after checking file-shape guardrails.
- Packaging/signing/update files.
- Scheduler/channel domain files, except tests/fixtures only when EPG presentation needs pure view-model proof.
- External dependency lockfiles unless a replan approves a package.

---

## Architecture Health

Current `initial-build` guardrails already identify several affected hotspots:

- `src/renderer/epg.ts` is allowlisted at 725 lines and must split presentation normalization/bounds from cell projection before adding live scheduler-backed guide data, another guide state family, or more renderer route-specific behavior.
- `src/renderer/routeDom.ts` is allowlisted at 518 lines and must extract guide-dedicated rendering before adding additional route families, guide interaction families, or further parity-driven template branches.
- `src/renderer/overlayViewModels.ts` is allowlisted at 507 lines and must split view-model helpers or track conversion logic before adding more overlay view models or growing option row properties.
- `src/renderer/index.ts` is allowlisted at 511 lines and must extract input/listener/action routing helpers before adding more route families or onboarding steps.
- `src/preload/index.cts` is a hard hotspot and must not be touched for UI-only parity unless a separate reviewed contract/bridge plan approves it.

Architecture-health decision:

1. **Decompose before growth.** Units 2 and 5 should create focused renderer overlay/guide helper files before adding significant DOM/view-model complexity to `routeDom.ts`, `overlayViewModels.ts`, or `epg.ts`.
2. **CSS can grow only with focused ownership.** If `player-overlays.css`, `guide-epg.css`, `workflow-screens.css`, or `plex-onboarding.css` becomes hard to review, split by surface rather than appending monolithic rules.
3. **No guardrail baseline increases as a convenience.** A baseline may be raised only with an implementation diff that proves decomposition is worse for that unit and records a removal trigger.
4. **Contract additions require split consideration.** Do not add artwork or guide presentation contract families to `src/contracts/player.ts` by default. Prefer a small dedicated contract if a public seam is truly needed.
5. **Visual parity should remove fake/scaffold drag.** When a real product surface now exists, smoke-only fake panels or placeholder desktop cards should be removed from reachable product routes or moved into tests/dev fixtures.

Maintainability route:

```bash
npm run verify:maintainability
npm run verify:architecture
npm run verify
```

Run these after any production source shape change.

---

## Planner Self-Check

1. **Is any product, architecture, ownership, dependency, or verification decision unresolved?**  
   Yes for actual live artwork delivery and measured latency. The plan resolves this by allowing placeholder/artwork-ready UI only in the first parity pass and requiring replan for any tokenized-image proxy or measured latency data seam.

2. **Does the plan depend on adjacent files needing contract or type changes that are not in scope?**  
   No for token/shell/overlay/settings CSS parity. Possibly yes for live artwork and EPG presentation if current renderer-safe state lacks data; those are explicit stop/replan triggers.

3. **Did the plan freeze any file out of scope while relying on hidden wiring inside it?**  
   No. Main/Plex/preload/native owners are frozen unless a focused subplan approves a safe data seam.

4. **Did the plan record evidence path and fallback reads?**  
   Yes. Branch-qualified source reads and the audit are recorded. Implementer must refresh with local `rg`/Codanna before each unit.

5. **Is the work assigned to the repo-preferred owner, or is it growing a hotspot?**  
   Renderer UI owns visual composition. Hotspot growth is controlled by focused helper extraction and file-shape guardrails.

6. **Did Tier 3 work include Architecture Health evidence and a decomposition, avoidance, or allowlist decision for touched hotspots?**  
   Yes. Avoid/pre-split decisions are above.

7. **Would a fresh implementer need to invent security, IPC, playback, persistence, packaging, import, or verification policy?**  
   No. Security and boundary policy are explicit; IPC/preload/main changes require replan; verification commands and manual proof are named.

8. **Did the plan record exact verification commands, expected outcomes, and stop/replan triggers?**  
   Yes.

---

## Architecture Seam Decision Gate

Chosen seam:

- **Primary seam:** renderer-owned UI parity using existing renderer-safe state and Desktop-owned DOM/CSS/view-model helpers.
- **Secondary seam, only if approved:** narrowly scoped renderer-safe contract data for artwork/status/guide presentation, still main/Plex-owned for transport/credentials/tokenized URLs.
- **Visual source seam:** WebOS `Lineup@code-health` is visual/presentation reference. Any copied/adapted upstream code/CSS needs import-ledger provenance.

Forbidden shortcuts:

- No raw tokenized image/media URLs in renderer state or DOM.
- No renderer-side Plex fetches.
- No broad preload RPC.
- No `window.electron`, raw `ipcRenderer`, `require`, Node, filesystem, or native handle exposure in renderer.
- No old WebOS path shims or compatibility wrappers.
- No fake controls for missing Desktop features.
- No unreviewed CSP relaxation.
- No lockfile/dependency change for convenience.
- No line-count baseline increase to hide hotspot growth.
- No brittle screenshot snapshots as the only verification for behavior; use public seams and manual visual proof for layout.

Stop and replan when:

- A parity requirement cannot be satisfied without new main/preload IPC.
- Artwork needs a tokenized URL, auth header, image proxy, or CSP change.
- Server latency/status data is not measured or safely provided.
- EPG time-math needs scheduler/runtime contract changes beyond renderer projection.
- Channel setup parity would imply unsupported drag/drop/reorder semantics.
- Any touched production file crosses a file-shape guardrail without a split or reviewed allowlist update.
- `npm run verify`, `npm run smoke:electron`, redaction, or visual proof fails and the fix crosses a boundary not named by this plan.

---

## Verification Commands

Verification classification: broader integration/manual proof required

Run the following at minimum for each source-changing unit:

```bash
npm run typecheck
npm run verify:architecture
npm run test
npm run verify:docs
npm run verify:redaction
npm run verify
```

Run this after each UI/route/overlay unit:

```bash
npm run smoke:electron
```

Run this after file shape, source topology, or guardrail changes:

```bash
npm run verify:maintainability
```

Run this after docs/plan/import-ledger/current-state/roadmap-only edits:

```bash
npm run verify:docs
```

Expected outcomes:

- `npm run verify` passes without new redaction, architecture, maintainability, contract, docs, or test failures.
- `npm run smoke:electron` proves Electron boot, renderer privilege denial, style marker load, route reachability, navigation containment, permission/new-window denial, fullscreen bridge continuity, and no regressions in existing smoke assertions.
- Visual proof captures player, guide, settings, channel setup, all player overlays, profile/auth PIN states, server rows, and guide focus states at target viewport sizes.
- Manual proof records any intentional divergence in `docs/runs/ui-parity-*/summary.md`, with no secrets or tokenized URLs.
- Redaction proof passes after visual evidence, support-bundle changes, or diagnostics changes.

Recommended visual proof matrix:

| Surface | Proof states |
| --- | --- |
| Player shell | Windowed, fullscreen, route rail hidden/subordinate where intended, OSD closed/open, focus visible |
| Now Playing | No artwork, placeholder artwork, poster/backdrop/clear-logo-safe descriptors if available, long title/description |
| OSD | Playing, paused, buffering, audio/subtitle pills, timecode, buffer text, progress |
| Mini guide | Five rows, selected/focused row, loading row, long channel/program names, next title |
| Channel number | Digit entry, auto-commit pending, clear, invalid/no match, keyboard/mouse fallback |
| Playback options | Audio list, subtitle list, selected equalizer, disabled/blocked rows, empty sections |
| Auth | Idle, pending PIN, QR visible, expired/cancel/error |
| Profile PIN | Four empty/partial/full slots, numpad focus, backspace/cancel, error |
| Server selection | No servers/loading/ready/selected/unreachable/auth-required if safely represented |
| Settings | Category rail, profile row, detail pane, toggle/select states, support-bundle action |
| EPG | Current marker, time slots, absolute cell widths, clipped edges, live badge, narrow/tiny tiers, focused overflow/ticker, no selectable program |
| Channel setup | Staged shell, account/server/library/media detail, empty/loading/error states, Desktop-specific build/replacement semantics |
| Accessibility/motion | Keyboard-only, focus restoration, reduced motion, forced colors where supported |

Suggested local evidence folder:

```text
docs/runs/ui-parity-2026-06-12/
  summary.md
  screenshots/
    1280x720/
    1920x1080/
    fullscreen/
  command-output/
    verify.txt
    smoke-electron.txt
    redaction.txt
```

Keep the folder untracked unless repo policy explicitly requests a redacted summary file.

---

## Acceptance Criteria

### Global

- Every audit surface is either implemented to parity target or recorded as an intentional divergence with owner, reason, verification, and revisit trigger.
- Desktop retains Electron security posture, renderer unprivileged status, redaction, support bundle, and main-owned Plex/credentials/transport.
- No tokenized URL, auth header, native handle, raw Electron API, Node API, or raw Plex payload reaches renderer-facing state, DOM attributes, logs, screenshots, or test fixtures.
- No new dependency is added.
- No route becomes unreachable by keyboard, mouse, or Desktop remote/gamepad input.
- No introduced timer/listener/observer leaks across hide/destroy or route transitions.
- Reduced-motion and forced-colors behavior remains acceptable.
- `npm run verify` and `npm run smoke:electron` pass with observed output.
- Visual proof passes for the matrix above.
- Plan and implementation reviews are clean or all findings are adjudicated.

### Surface-by-surface acceptance

| Surface | Acceptance target |
| --- | --- |
| Global tokens | Desktop token scale uses WebOS-compatible 10-foot names and values where practical: text scale, spacing, radius, focus, scrim/panel, progress, z-index, and OSD pill vocabulary. Existing Desktop aliases can remain only as compatibility within Desktop-owned CSS, not as a divergent design system. |
| Route chrome | Player, guide, settings, onboarding, and overlay states read as immersive media surfaces. Desktop route rail/topbar may remain as a fallback but must not visually dominate media routes. |
| Now Playing | Artwork-ready left/bottom cinematic panel with backdrop/poster/clear-logo slots, badges, playback summary, metadata, description, cast/art placeholder states, and progress meta. Placeholder states must be honest and safe. |
| OSD | Bottom OSD visually matches WebOS proportions: title/clear-logo zone, first-class Audio/Subtitles actions, monospace/tabular meta strip, 10px progress, and WebOS-like focus treatment. Sleep is omitted unless real. |
| Mini guide | Top shelf, five rows, channel number/icon/name, now start/title, progress, next title, focused/selected/loading states, footer hints, mouse fallback subordinate to remote/key hints. |
| Channel number | WebOS-like auto-commit digit buffer with underscore/pending presentation; explicit Tune/Clear buttons are only fallback/dev/accessibility controls. |
| Playback options | Right-side rail, one-column sections, selected/focused accent, meta pills, equalizer for selected track, Desktop-only volume/rate controls retained only if backed by real commands and visually secondary. |
| Plex auth | QR/PIN-card presentation and per-character PIN boxes. No WebOS direct token/fetch behavior; Desktop main-owned auth remains intact. |
| Profile PIN | Modal four-slot PIN plus on-screen numpad and keyboard fallback. Inline numeric input is not primary visual language. |
| Server selection | WebOS-like status/health pills and selected/connected treatment. Latency appears only if measured and renderer-safe. |
| Settings | Left category rail, profile row, cardless detail pane, WebOS toggle/select controls, focus coordination, and support-bundle preservation. |
| Guide / EPG | Time-math layout: pixel widths/absolute positioning/visible clipping/current marker/live badge/edge masks/library tabs or pills only from safe state/tickers/compact tiers. Fixed six-column grid is gone from product EPG. |
| Channel setup | WebOS-like staged shell with side rail/category and detail flow, but Desktop build/replacement semantics remain visible. Unsupported drag/drop/reorder is not introduced. |

---

## Replan Triggers

Replan immediately when any of the following happens:

- The implementer discovers `initial-build` has diverged materially from this evidence.
- Existing tests or smoke prove a boundary assumption wrong.
- A UI parity requirement requires raw Plex token, tokenized image URL, auth header, native handle, or renderer fetch.
- CSP must change to load external artwork.
- Preload/main IPC must grow beyond existing typed APIs.
- Guide time-math requires domain/scheduler behavior changes instead of renderer presentation.
- Server latency is requested but no measured latency exists.
- Profile/auth PIN parity conflicts with current Plex runtime flow.
- Visual proof shows overlays unusable over native video/fullscreen.
- File-shape guardrails require decomposition not accounted for in the unit.
- A proposed unit cannot be verified by public seam tests, smoke proof, and visual evidence.
- A dependency addition seems necessary.
- Any redaction scan fails.

---

## Rollback Notes

- Use one focused commit per unit after review and verification.
- Every unit should be reversible by reverting its commit.
- Do not mix docs/workflow/plan edits with product implementation unless the unit explicitly requires it.
- If visual parity causes runtime behavior regressions, revert the current unit first; do not patch around with compatibility shims.
- If artwork/status/public contract work leaks privileged material, revert the contract and all downstream renderer usage immediately, then replan from main-owned safe view models.
- If EPG time-math causes unusable performance, revert Unit 5 and replan with measured performance data before adding virtualization or schedule warming.

---

## Commit Checkpoints

Suggested conventional commits:

1. `docs(plan): add desktop ui parity implementation plan`
2. `feat(renderer): align ui tokens and immersive route shells`
3. `feat(renderer): restyle player overlays for webos parity`
4. `feat(renderer): add remote-first auth and profile pin presentation`
5. `feat(renderer): align settings with webos rail layout`
6. `feat(renderer): implement time-math guide presentation`
7. `feat(renderer): recompose channel setup staged shell`
8. `test(renderer): add ui parity smoke and visual proof harness`
9. `docs: close ui parity implementation memory`

Use fewer commits only if a reviewed unit is smaller; use more commits if file-shape or boundary splits make it safer.

---

# Current-Unit Execution Packets

The implementation must not be done as one broad edit. Execute these packets in order. Each packet requires a clean plan/implementation review before moving to the next if the diff is non-trivial.

---

## Unit 0 - Freshness, plan landing, and source map

### Goal

Land the active plan, confirm current source state, and produce a local source map for the implementer.

### Files in scope

- `docs/plans/2026-06-12-ui-parity-implementation-plan.md`
- local ignored `docs/runs/ui-parity-2026-06-12/source-map.md`
- no production source files

### Steps

1. Confirm branch and worktree:
   ```bash
   git status --short --branch
   git branch --show-current
   ```
   Expected branch: `initial-build`.

2. Read required docs and confirm no newer active plan supersedes this one.

3. Save this plan to `docs/plans/2026-06-12-ui-parity-implementation-plan.md`.

4. Create a local ignored source map with:
   - Desktop files read.
   - WebOS reference files read.
   - Any Codanna fallback notes.
   - Any contradictions with attached audit.

5. Run:
   ```bash
   npm run verify:docs
   ```

### Acceptance

- Active plan file satisfies repo plan verifier.
- Source map exists locally and is not staged.
- No production source changed.

### Stop/replan

- Another active plan already owns UI parity.
- Branch is not `initial-build`.
- Required docs conflict with this plan.

### Codex goal

```text
Goal: In /Users/tristan/Software/LineupDesktop on branch initial-build, land the active UI parity plan as docs/plans/2026-06-12-ui-parity-implementation-plan.md, refresh evidence from LineupDesktop@initial-build and Lineup@code-health, record local ignored source-map notes under docs/runs/ui-parity-2026-06-12/, and run npm run verify:docs. Do not change production source. Stop if another active plan owns this work or if branch/source evidence contradicts the plan.
```

---

## Unit 1 - Visual token parity foundation and immersive shell

### Goal

Align Desktop's base visual system with WebOS 10-foot tokens and reduce desktop-card chrome so later surfaces inherit parity rather than re-solving density locally.

### Files in scope

- `src/renderer/styles/base.css`
- `src/renderer/styles/workflow-screens.css`
- `src/renderer/staticDom.ts` only for class/data hooks needed by shell CSS
- `src/main/smokeAssertions.ts`
- existing renderer/smoke tests

### Implementation requirements

1. Add/align token-vocabulary:
   - `--color-primary`, `--color-primary-rgb`, `--focus-color`, `--focus-ring-width`, `--focus-ring-offset`
   - `--text-xs` through `--text-2xl`
   - `--space-1`, `--space-2`, `--space-3`, `--space-4`, `--space-5`, `--space-6`, `--space-8`, `--space-10`, `--space-12`, `--space-16`
   - `--radius-sm`, `--radius-md`, `--radius-lg`, `--radius-xl`, `--radius-full`, `--panel-radius`
   - `--progress-height`, `--progress-height-sm`, `--progress-height-lg`
   - `--scrim-tint-rgb`, `--scrim-tint-rgb-legacy`
   - `--z-base`, `--z-dropdown`, `--z-modal`, `--z-overlay`, `--z-toast`, `--z-max`
   - OSD pill variables.
2. Preserve existing Desktop aliases if needed, but map them onto the new vocabulary.
3. Increase default font/density toward WebOS without breaking desktop minimum window support.
4. Restyle shell so player/guide/settings/channel setup are immersive screen surfaces:
   - route rail/topbar present only as fallback or visually subordinate chrome.
   - no generic bordered card look on media surfaces.
   - screen panels use full-screen dark glass/scrim language.
5. Preserve focus-visible and `.is-focused` behavior.
6. Preserve reduced-motion and forced-colors rules.
7. Update the style-ready smoke assertion marker only if required and update both CSS and smoke assertion together.

### Verification

```bash
npm run typecheck
npm run verify:maintainability
npm run smoke:electron
npm run verify
```

Manual visual proof:
- player, guide, settings, channel setup at 1280x720 and 1920x1080
- keyboard focus visible on route rail and route actions
- route rail not visually dominant on player route

### Acceptance

- Tokens match WebOS scale where practical.
- Existing UI remains reachable.
- Later overlay work can use shared token-names.
- `smoke:electron` style assertion passes.

### Stop/replan

- Base token changes break smoke style loading or route reachability.
- Visual density becomes unusable below 1280x720.
- Implementer needs to change preload/main to hide route chrome.

### Codex goal

```text
Goal: Implement Unit 1 of the active UI parity plan. Align src/renderer/styles/base.css and related shell CSS with WebOS 10-foot token-vocabulary from Lineup@code-health, reduce media-route desktop-card chrome, preserve existing renderer route/focus behavior, update smoke style markers if needed, and verify with npm run typecheck, npm run verify:maintainability, npm run smoke:electron, and npm run verify. Do not touch preload/main/plex/native owners except src/main/smokeAssertions.ts if the style marker changes. Stop if shell parity requires new IPC or renderer privileges.
```

---

## Unit 2 - Player overlay parity package

### Goal

Convert Desktop overlays from compact desktop cards/modals to WebOS-like media overlays while preserving real Desktop actions.

### Files in scope

- `src/renderer/staticDom.ts`
- `src/renderer/domBindings.ts`
- `src/renderer/overlays.ts`
- `src/renderer/overlayViewModels.ts`, preferably split first
- `src/renderer/routeDom.ts`, preferably split first
- `src/renderer/styles/player-overlays.css`
- new focused overlay helper files under `src/renderer/overlays/`
- overlay-related renderer tests

### Implementation requirements

#### 2A. Now Playing

- Replace bottom-right small card with cinematic, artwork-ready panel:
  - backdrop slot
  - poster slot
  - clear-logo slot with title fallback
  - title/subtitle
  - badges
  - playback summary
  - metadata lines
  - description area with overflow handling
  - actor/cast placeholder zones only when safe data exists
  - progress bar plus progress meta
- Use safe placeholders when artwork descriptors are unavailable.
- Do not expose tokenized Plex artwork URLs.
- Do not broaden CSP.
- If safe image descriptors are not already available, keep slots empty/placeholder and record a future main-owned image proxy subplan.

#### 2B. OSD

- Move toward WebOS bottom OSD:
  - title/clear-logo zone
  - direct Audio/Subtitles buttons if backed by existing overlay actions
  - Mini guide and Options retained as Desktop-specific real actions
  - numeric entry moved out of primary OSD chrome
  - monospace/tabular meta strip
  - 10px progress bar using shared token-variable
  - buffer/played progress preserved
- Omit Sleep Timer unless a real sleep-timer owner exists.

#### 2C. Mini guide

- Convert centered card into top shelf:
  - five rows
  - channel number
  - channel icon/branding placeholder slot
  - channel name
  - now start/title
  - progress
  - next title
  - loading row style
  - selected/focused treatment
  - footer key hint
- Keep mouse controls accessible but visually subordinate.

#### 2D. Channel number overlay

- Implement auto-commit digit buffer presentation:
  - large digits
  - underscores/pending slots
  - timeout/commit state
  - invalid/no-match state
- Keep explicit Tune/Clear buttons only as fallback/dev/accessibility controls.

#### 2E. Playback options

- Convert centered modal into right-side rail:
  - one-column section rhythm
  - subtitles and audio sections
  - selected/focused left accent
  - meta pills
  - selected equalizer
  - blocked/disabled state
  - Desktop-only volume/rate controls only if backed by existing player commands; otherwise remove or demote from parity target.

### Architecture health requirement

Before adding markup, split `routeDom.ts`/`overlayViewModels.ts` if the unit would grow them. Preferred split:
- route-specific overlay rendering helpers under `src/renderer/overlays/`
- overlay view-model conversion helpers by surface
- keep `routeDom.ts` as orchestration only

### Verification

```bash
npm run typecheck
npm run verify:maintainability
npm run test
npm run smoke:electron
npm run verify:redaction
npm run verify
```

Add/extend tests for:
- overlay visible/hidden state
- OSD action availability
- channel number buffer
- playback options selected/equalizer state
- mini guide five-row rendering
- no forbidden artwork/privileged fields

Manual visual proof:
- all overlay states windowed and fullscreen
- overlays over player presentation surface
- long text truncation/overflow
- reduced-motion behavior

### Acceptance

- Overlay surfaces match WebOS layout language.
- No fake controls.
- Existing Desktop actions still work.
- No secret or token-bearing data appears in DOM/logs/screenshots.
- File-shape guardrails satisfied.

### Stop/replan

- Artwork cannot be represented without tokenized URLs or CSP change.
- OSD Audio/Subtitles buttons are not backed by real commands.
- Playback options volume/rate controls are fake.
- Overlay work requires new preload/main IPC.

### Codex goal

```text
Goal: Implement Unit 2 of the active UI parity plan. Refactor renderer overlay DOM/view-model/style ownership as needed to avoid routeDom/overlayViewModels hotspot growth, then restyle Now Playing, OSD, mini guide, channel number, and playback options to WebOS parity using renderer-safe data only. Preserve real Desktop actions and accessibility fallbacks. Do not add fake Sleep Timer, fake artwork, tokenized URLs, CSP changes, dependencies, or preload/main IPC. Verify with npm run typecheck, npm run verify:maintainability, npm run test, npm run smoke:electron, npm run verify:redaction, and npm run verify. Capture local ignored visual proof for all overlay states.
```

---

## Unit 3 - Onboarding input parity: Plex auth, profile PIN, server rows

### Goal

Bring auth/profile/server selection presentation into WebOS remote-first parity while preserving Desktop main-owned Plex boundaries.

### Files in scope

- `src/renderer/staticDom.ts`
- `src/renderer/plexRuntimeDom.ts`
- `src/renderer/plexRuntimeRows.ts`
- `src/renderer/styles/plex-onboarding.css`
- `src/renderer/styles/workflow-screens.css`
- `src/renderer/domBindings.ts`
- related renderer/Plex UI tests

### Implementation requirements

#### Plex auth PIN/QR

- Replace single `strong` PIN display with WebOS-like card:
  - QR card area
  - per-character PIN boxes
  - state text for idle/pending/claimed/expired/error
  - countdown/expiry presentation if state exists
- If QR SVG/asset is not safely available in Desktop:
  - render QR placeholder card with `plex.tv/link` instruction and PIN boxes
  - do not add QR dependency
  - do not renderer-fetch Plex
  - document future main-owned QR/static asset subplan if needed

#### Profile PIN

- Replace inline profile PIN as primary UI with:
  - modal dialog
  - four PIN slots
  - on-screen numpad 0-9
  - backspace/cancel
  - keyboard numeric fallback
  - error state
- Keep any existing text input only as fallback if needed for accessibility/dev, not as the primary visual language.
- Clean up key handlers/listeners/timers on close/hide.

#### Server selection

- Polish existing server rows:
  - status/health pills
  - selected/connected treatment
  - ownership/local/remote/relay summary
  - unreachable/auth-required/access-denied states if already provided safely
  - auto-connect hint only if backed by real behavior
- Do not show latency without measured renderer-safe latency.

### Verification

```bash
npm run typecheck
npm run verify:maintainability
npm run test
npm run smoke:electron
npm run verify:redaction
npm run verify
```

Add/extend tests for:
- PIN boxes render safe code characters
- profile PIN modal focus trap/fallback
- numpad input/backspace/cancel
- server health/status rows
- no raw auth/token/connection details in renderer-visible strings

Manual visual proof:
- auth idle/pending/error
- profile PIN partial/full/error
- server list loading/ready/selected/unreachable if fixture exists

### Acceptance

- Auth/profile input looks remote-first.
- Plex auth and credential ownership remains main-owned.
- No direct token/fetch behavior copied from WebOS.
- Server data is honest and safe.

### Stop/replan

- PIN state needed for parity is not present in renderer-safe snapshot.
- QR requires generated dependency or token-bearing data.
- Profile PIN flow needs new IPC/main behavior.
- Server latency/status not available safely.

### Codex goal

```text
Goal: Implement Unit 3 of the active UI parity plan. Restyle Plex auth, profile PIN, and server selection in the renderer to match WebOS remote-first presentation while preserving Desktop main-owned Plex/auth/credential boundaries. Use QR/PIN placeholders only when safe QR assets are unavailable. Do not add renderer Plex fetches, token exposure, latency badges without measured data, dependencies, or preload/main IPC. Verify with npm run typecheck, npm run verify:maintainability, npm run test, npm run smoke:electron, npm run verify:redaction, and npm run verify.
```

---

## Unit 4 - Settings rail parity

### Goal

Replace Desktop's flat settings route with a WebOS-like left category rail, profile row, cardless detail pane, and TV-style controls, while preserving Desktop support/diagnostics actions.

### Files in scope

- `src/renderer/staticDom.ts`
- `src/renderer/routeDom.ts`, preferably split
- `src/renderer/styles/workflow-screens.css`
- `src/renderer/styles/base.css` only for shared tokens
- new `src/renderer/settings/**` helpers if needed
- settings route tests

### Implementation requirements

1. Create settings shell:
   - full-screen overlay/screen
   - left category rail
   - header/back hint
   - profile row
   - cardless detail pane
   - WebOS-style toggle/select rows
2. Preserve current settings values and actions:
   - startup surface
   - guide density
   - preview badges
   - setup reminder
   - support bundle export
   - channel setup/back to player
3. Make support-bundle action visually Desktop-specific but not visually dominant.
4. Keep focus coordination:
   - up/down category navigation
   - right into detail pane
   - left back to category rail
   - focus restoration after category changes
5. Avoid renderer persistence/browser storage shortcuts.

### Architecture health requirement

If `routeDom.ts` would grow, extract settings rendering to a focused `src/renderer/settings/settingsDom.ts` or similar.

### Verification

```bash
npm run typecheck
npm run verify:maintainability
npm run test
npm run smoke:electron
npm run verify:redaction
npm run verify
```

Manual visual proof:
- categories
- detail pane
- support bundle row/action
- focus movement
- long labels/descriptions

### Acceptance

- Settings reads as WebOS rail/detail UI.
- Existing Desktop diagnostics/support actions remain available.
- No persistence or IPC changes unless separately planned.

### Stop/replan

- Settings controls require actual persisted behavior changes.
- Support-bundle action breaks diagnostics contract.
- Focus behavior cannot be maintained without broader input changes.

### Codex goal

```text
Goal: Implement Unit 4 of the active UI parity plan. Recompose the settings route into a WebOS-like left rail plus cardless detail pane with profile row and TV-style controls, preserving Desktop support-bundle/export and current settings actions. Extract focused settings DOM helpers if routeDom would grow. Do not change persistence, preload, main diagnostics contracts, or browser storage. Verify with npm run typecheck, npm run verify:maintainability, npm run test, npm run smoke:electron, npm run verify:redaction, and npm run verify.
```

---

## Unit 5 - Guide / EPG time-math parity

### Goal

Replace fixed six-column guide rendering with WebOS-like time-math EPG presentation: absolute/pixel cell positions, clipping, current marker, live badge, compact tiers, edge masks, and focus overflow/ticker behavior.

### Files in scope

- `src/renderer/epg.ts`
- `src/renderer/routeDom.ts`, preferably split
- `src/renderer/styles/guide-epg.css`
- new focused guide files under `src/renderer/epg/`
- renderer EPG tests

### Implementation requirements

1. Split guide presentation:
   - `guideCellPosition`: start/end/duration to pixel left/width
   - `guideVisibleWindow`: clipping and visible width
   - `guideCellDom`: DOM element construction/update
   - `guidePresentation`: width tiers/live/current/focus/ticker state
2. Replace fixed `repeat(6, 1fr)` cell grid with a time track:
   - pixel width based on visible window minutes
   - absolute-positioned program cells
   - channel column fixed/sticky-like
   - time header ticks aligned to pixels
   - current-time marker
   - edge masks for clipped programs
3. Add safe library tabs/pills only if renderer-safe library state already exists.
4. Add cell presentation:
   - live badge
   - episode badge
   - time label
   - title/subtitle
   - progress fill
   - compact/tiny/sliver tiers
   - focused overflow/ticker respecting reduced motion
5. Preserve guide navigation:
   - earlier/later
   - channel up/down
   - previous/next program
   - selected detail panel
   - empty/loading/error states
6. Do not add virtualization unless measured performance requires it.

### Verification

```bash
npm run typecheck
npm run verify:maintainability
npm run test
npm run smoke:electron
npm run verify
```

Add/extend tests for:
- time-to-pixel math
- minimum width/clipping
- current/past/future classification
- visible window clipping
- compact tiers
- live/current marker
- selected/focused program
- no selectable-program empty state
- reduced-motion ticker behavior where testable without brittle layout snapshots

Manual visual proof:
- 1280x720 and 1920x1080
- narrow and long programs
- current program progress
- edge clipped program
- focus on tiny/narrow/wide cells
- window shift earlier/later
- route switch back to player

### Acceptance

- Product EPG no longer uses fixed six-column CSS grid for program widths.
- Program cell widths reflect actual schedule duration.
- Focus and current/live state are visually close to WebOS.
- Performance remains acceptable for current channel counts.
- File-shape guardrails are satisfied by splitting before growth.

### Stop/replan

- Current guide view-model lacks start/end times required for pixel math.
- Runtime scheduler data contract must change.
- Performance degrades materially and needs virtualization.
- Guide behavior requires preload/main or domain changes.

### Codex goal

```text
Goal: Implement Unit 5 of the active UI parity plan. Split renderer guide presentation out of epg.ts/routeDom.ts as needed, replace fixed six-column program layout with WebOS-style time-to-pixel absolute positioning, visible-window clipping, current marker, live/progress/compact tiers, edge masks, and focused overflow behavior. Preserve existing guide navigation and empty/loading states. Do not add virtualization, scheduler/domain changes, preload/main IPC, or unsafe data. Verify with npm run typecheck, npm run verify:maintainability, npm run test, npm run smoke:electron, and npm run verify. Capture local ignored visual proof for guide states.
```

---

## Unit 6 - Channel setup staged shell parity

### Goal

Recompose channel setup from a long sequential page into a WebOS-like staged shell after higher-priority surfaces are stable, while preserving Desktop setup behavior and avoiding unsupported interactions.

### Files in scope

- `src/renderer/staticDom.ts`
- `src/renderer/channelSetup/**`
- `src/renderer/plexRuntimeDom.ts` only for reused safe markup hooks
- `src/renderer/styles/plex-onboarding.css`
- `src/renderer/styles/workflow-screens.css`
- channel setup tests

### Implementation requirements

1. Create staged shell:
   - left stage/category rail
   - account/profile stage
   - server stage
   - library stage
   - media preview stage
   - build/review stage if current Desktop behavior supports it
2. Preserve current functional actions:
   - resume setup
   - request/poll/cancel PIN
   - choose profile
   - restore/refresh/clear server
   - list/search/clear library
   - preview metadata
   - create/build/update/replacement semantics currently present
3. Keep Desktop-specific setup copy honest.
4. Do not add drag/drop/reorder unless scheduler/channel contract already supports it.
5. Preserve loading/empty/error/pending states.
6. Keep mouse and keyboard accessibility; remote/gamepad visual language remains primary.

### Verification

```bash
npm run typecheck
npm run verify:maintainability
npm run test
npm run smoke:electron
npm run verify:redaction
npm run verify
```

Manual visual proof:
- stage rail and active stage
- auth/server/library/media details
- empty/loading/error states
- build/review if present
- focus movement between rail/detail/actions

### Acceptance

- Channel setup no longer reads as one long desktop form.
- Existing setup behavior remains intact.
- Unsupported WebOS drag/drop/reorder semantics are absent.
- Plex/credential boundaries remain intact.

### Stop/replan

- Current runtime/setup behavior is unstable or changing.
- Staged UI would hide required Desktop-specific setup details.
- Reordering/channel authoring semantics are needed but not supported.

### Codex goal

```text
Goal: Implement Unit 6 of the active UI parity plan. Recompose channel setup into a WebOS-like staged shell with side rail/category and detail panes while preserving all current Desktop Plex onboarding, library browse, metadata preview, and build/replacement semantics. Do not implement unsupported drag/drop or channel reorder behavior. Do not change Plex transport, persistence, preload/main IPC, or scheduler/channel domains. Verify with npm run typecheck, npm run verify:maintainability, npm run test, npm run smoke:electron, npm run verify:redaction, and npm run verify.
```

---

## Unit 7 - Visual proof, review, docs, and closeout

### Goal

Prove UI parity across surfaces, run all repo gates, complete reviews, update durable docs, and archive the active plan according to repo rules.

### Files in scope

- `tools/smoke-electron.mjs` only if a small harness enhancement is needed
- `tools/__tests__/**` only for harness-shape proof
- `docs/architecture/import-ledger.md` if copied/adapted upstream code landed
- `docs/architecture/CURRENT_STATE.md`
- `docs/roadmap/desktop-port-roadmap.md`
- local ignored `docs/runs/ui-parity-2026-06-12/**`
- active plan file while still active

### Steps

1. Run full command verification:
   ```bash
   npm run typecheck
   npm run verify:architecture
   npm run test
   npm run verify:docs
   npm run verify:redaction
   npm run smoke:electron
   npm run verify
   ```

2. Produce local ignored visual proof:
   - screenshot/video/manual notes for proof matrix
   - command outputs
   - redaction scan result
   - reviewed intentional divergences
   - no secrets, tokenized URLs, or local environment-sensitive paths beyond allowed redacted paths

3. Request read-only implementation review:
   - include changed files
   - include command output summary
   - include visual proof summary
   - include intentional divergences
   - include file-shape/maintainability notes
   - include import-ledger updates or no-import rationale

4. Adjudicate review findings before closeout.

5. Update durable memory:
   - `CURRENT_STATE.md` if ownership/status changed
   - roadmap if the UI parity slice is now complete or partially complete
   - import ledger for any copied/adapted upstream source
   - active plan with final status until archive step

6. Archive plan after closeout:
   - move completed full plan body to local ignored `docs/runs/archive/plans/`
   - keep only durable conclusions in tracked docs per repo policy

### Acceptance

- Full verify and smoke pass.
- Visual proof is complete and redacted.
- Review is clean or findings are resolved.
- Durable docs updated.
- Active plan is archived/removed from tracked docs after closeout per repo rules.

### Stop/replan

- Visual proof fails in fullscreen/native-video conditions.
- Redaction or security proof fails.
- Review finds a material architecture or parity blocker.
- Durable docs cannot be updated consistently with repo policy.

### Codex goal

```text
Goal: Close the active UI parity implementation plan. Run full verification including npm run smoke:electron and npm run verify, capture redacted local visual proof under docs/runs/ui-parity-2026-06-12/, request read-only implementation review, adjudicate findings, update CURRENT_STATE/roadmap/import-ledger as required, and archive the completed plan body according to docs/plans policy. Do not call the work complete without observed commands, visual proof, and clean/adjudicated review.
```

---

# Codex Master Goal

Use this goal to start the full work through the Desktop feature-quality loop:

```text
Goal: In /Users/tristan/Software/LineupDesktop on branch initial-build, implement the active UI parity plan for WebOS Lineup parity using Lineup@code-health as visual reference and the attached audit as preliminary evidence. Follow AGENTS.md, docs/AGENTIC_DEV_WORKFLOW.md, docs/agentic/plan-authoring-standard.md, docs/architecture/CURRENT_STATE.md, docs/architecture/file-shape-guardrails.md, and docs/architecture/import-ledger.md. Keep authoritative execution state in update_plan. Use Tier 3 feature-quality workflow: plan refresh, read-only plan review, one bounded implementation unit at a time, read-only implementation review, and closeout only after observed verification.

Implement in this order:
1. Unit 0 plan/freshness/source map.
2. Unit 1 WebOS token and immersive shell foundation.
3. Unit 2 player overlay parity: Now Playing, OSD, mini guide, channel number, playback options.
4. Unit 3 onboarding input parity: Plex auth QR/PIN, profile PIN modal/numpad, server row polish.
5. Unit 4 settings rail parity.
6. Unit 5 guide/EPG time-math parity.
7. Unit 6 channel setup staged shell parity.
8. Unit 7 visual proof, review, docs, closeout.

Hard constraints:
- Renderer remains unprivileged and display-focused.
- Main/Plex owns credentials, token-bearing transport, selected-server persistence, image/token setup, and diagnostics redaction.
- No raw Plex tokens, tokenized URLs, auth headers, native handles, raw Electron APIs, Node APIs, raw Plex payloads, or native playback details in renderer-facing contracts, DOM, logs, screenshots, docs, or fixtures.
- No webOS compatibility shims, old path barrels, broad preload RPC, fake features, unmeasured latency badges, fake artwork, or fake Sleep Timer.
- No new dependency unless a reviewed replan approves owner, lockfile impact, security/licensing/provenance, verification, and rollback.
- Decompose routeDom/epg/overlayViewModels/index or CSS hotspots before growing them beyond file-shape guardrails.
- Update import-ledger before or with any copied/adapted upstream Lineup source.
- Preserve Desktop support bundle, diagnostics, keyboard/mouse accessibility, remote/gamepad focus, reduced-motion, forced-colors, fullscreen, smoke, redaction, and verification behavior.

Required verification:
- npm run typecheck
- npm run verify:maintainability when source shape changes
- npm run verify:architecture
- npm run test
- npm run verify:docs
- npm run verify:redaction
- npm run smoke:electron after UI units
- npm run verify before any implementation closeout
- local ignored visual proof covering all surfaces in the plan

Stop and replan if any parity requirement needs new IPC/preload/main ownership, tokenized artwork, CSP relaxation, measured latency that does not exist, scheduler/domain changes, native playback changes, or file-shape guardrail exceptions not already approved.
```

---

# Review Checklist

Use this checklist during plan review, implementation review, and final closeout.

## Audit coverage

- [ ] Global token parity implemented.
- [ ] Route/app chrome parity implemented.
- [ ] Now Playing parity implemented.
- [ ] OSD parity implemented.
- [ ] Mini guide top shelf implemented.
- [ ] Channel number auto-commit buffer implemented.
- [ ] Playback options right rail implemented.
- [ ] Plex auth QR/PIN boxes implemented or honest QR placeholder recorded.
- [ ] Profile PIN modal/numpad implemented.
- [ ] Server selection polish implemented without fake latency.
- [ ] Settings rail implemented.
- [ ] Guide/EPG time-math implemented.
- [ ] Channel setup staged shell implemented after behavior stability.
- [ ] Intentional divergences documented.

## Security and boundaries

- [ ] Renderer unprivileged.
- [ ] No raw token/auth/header/native/Electron/Node data in renderer.
- [ ] No broad preload RPC.
- [ ] CSP not weakened.
- [ ] IPC sender validation unchanged or strengthened if touched.
- [ ] Main/Plex credential ownership preserved.
- [ ] Redaction proof passed.
- [ ] Electron security posture preserved.

## Production quality

- [ ] No fake controls.
- [ ] No unused abstractions.
- [ ] No unnecessary dependencies.
- [ ] File-shape guardrails satisfied.
- [ ] Focus behavior verified.
- [ ] Timers/listeners/observers cleanup verified.
- [ ] Reduced-motion and forced-colors verified where applicable.
- [ ] Keyboard/mouse/remote/gamepad paths preserved.
- [ ] Visual proof captured.
- [ ] Full repo verification passed.
- [ ] Read-only review clean or adjudicated.
- [ ] Durable docs/import ledger updated.
