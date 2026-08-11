# Guide Large-Lineup Performance And Parity Bug Report

## Record

- Issue: `WIN-TEST-010`
- Title: Guide is under-dense and not PC-scaled with a 459-channel lineup
- Type: Bug with functional, performance, and visual-parity sub-findings
- Severity: High
- Status: Under-density reproduced; performance hypotheses require instrumentation; implementation is not authorized by this report
- Area: Guide/EPG renderer, focus and paging, main Guide runtime, Electron composition, Settings
- Observed product checkpoint: `7e2af33585604b53ef2b16c72d7e741c9303e550`
- Observed upstream product baseline: `0258dbe15b04d2d141d0a4a44575fecb5bb72d41`
- Current upstream `code-health` head checked on 2026-08-10: `f5f587c93cbea74f6c23f2df86ddae15fcb40e65`
- Active remediation plan: [`docs/plans/2026-08-10-guide-continuous-lineup-visual-parity-plan.md`](../plans/2026-08-10-guide-continuous-lineup-visual-parity-plan.md)
- Date: 2026-08-10

This is a sanitized tracked conclusion from the Windows manual-audit session. Raw frames and operator-only notes remain outside tracked documentation. This report contains no Plex token, authentication header, tokenized URL, native handle, private path, or raw media identifier.

## Executive Summary

The Guide does not meet the product expectation for a Windows PC with a large lineup. In a maximized 3840 x 2160, 100%-scale Electron window backed by 459 persisted channels, only eleven complete channel rows and part of row twelve were visible. The operator further confirmed that ordinary vertical scrolling did not populate program content beyond those initial twelve channels. Source tracing corroborates the missing behavior: the virtual range is calculated only from the loaded `guidePresentation.channels` array, and the scroll callback rerenders that same presentation without requesting a later channel window. This is a reproduced functional content-coverage defect, not merely a preference about how many rows fit on screen.

The Guide also felt slow during the manual audit. A later Page Down injection exercise produced no visible channel-page settlement during the initial five-second observation window, but the starting focus and accepted-input path were not instrumented. That result remains an interaction symptom under `WIN-TEST-007`, not latency or root-cause proof for this issue.

The visible `12` is not an accidental rendering count. It is the default data-page limit. The current implementation requests only twelve channels, uses a 108 px row with an approximately 120 px outer stride, and spends substantial vertical space on the detail card, header, tabs, edit action, and time ruler. A 4K desktop therefore displays almost exactly one default data page. The existing `Guide Density` setting changes only the horizontal time window (two versus three hours); it does not change vertical row density.

The source trace exposes several credible performance hypotheses that current proof does not measure:

1. scroll and focus paths can rebuild the whole Guide subtree via `replaceChildren`;
2. one application render can recompute the Guide view multiple times;
3. page refresh scans and sorts the full lineup, resolves a twelve- or twenty-four-channel page, and the 15-second poll bypasses the renderer page cache;
4. the source-resolution cache holds only twenty-four canonical source identities, which could churn only when the lineup actually has more distinct source identities than that bound;
5. Electron is explicitly launched with GPU acceleration disabled, and the observed renderer used software GPU composition;
6. no Windows/Electron Guide benchmark, 400+ channel test, frame/heap profile, or long-running Guide soak exists.

The issue must not be fixed by simply raising caps. The first required action is an instrumented Windows/Electron baseline that separates input acceptance, renderer reconciliation, data resolution, cache behavior, and frame presentation. Only that evidence may authorize later changes such as a Guide-scoped incremental renderer, adaptive cache/request policy, or GPU-mode work. The product direction can still separate display density from performance policy: PC-tuned `Auto` should be the default, while a `Reduced resource` override should preserve functionality on lower-performance machines.

## Relationship To Existing Audit Findings

This report narrows but does not merge the existing findings:

- `WIN-TEST-007` remains the action-level Guide interaction and settlement concern.
- `WIN-TEST-008` remains the paired visual-parity concern.
- `WIN-TEST-010` owns the reproduced large-lineup/PC-scaling failure: fixed initial page size, no automatic content window beyond the loaded twelve during ordinary vertical scrolling, and insufficient vertical density. It also owns measurement of the candidate renderer and resource-policy bottlenecks, but does not presume their causal weight.

Visual parity and interaction correctness still need separate acceptance rows. A visually closer Guide can remain slow, and a fast Guide can remain visually wrong.

## Scope And Non-Goals

In scope:

- Guide row density and wide/high-resolution viewport use;
- large-lineup navigation, paging, focus reveal, pointer/keyboard/gamepad behavior;
- row/cell virtualization, DOM reconciliation, view-model work, caches, refresh cadence, cancellation, and resource budgets;
- current upstream WebOS Lineup Guide behavior and presentation hierarchy;
- justified Windows/Desktop divergences;
- a PC performance policy plus an explicit lower-resource setting;
- reproducible acceptance metrics and a risk-matched verification campaign.

Out of scope for this report:

- implementing the fix;
- changing playback, native-helper, IPC, or credential boundaries;
- declaring the later playback-diagnostic `EPIPE` modal a Guide bug;
- closing `EPG-10` through `EPG-13`, `UI-36`, WS5, or any Windows proof row;
- importing upstream code without a reviewed plan and import-ledger entry;
- treating raw screenshots, private lineup names, or local machine paths as tracked evidence.

## Environment And Reproduction

Observed environment:

- Windows 10 Home 10.0.19045;
- Electron 42 development runtime;
- product checkpoint `7e2af33585604b53ef2b16c72d7e741c9303e550`;
- maximized 4K window, Chromium device scale factor `1`;
- 459 persisted auto-generated channels;
- Guide default profile (`aggressiveGuidePreloadEnabled` defaults to `false`);
- Electron process command line included `--disable-gpu-compositing`; the GPU process used ANGLE `d3d11-warp-webgl`.

Reproduction:

1. Launch the existing product build and complete onboarding.
2. Open Guide with `G`/`F2`/Guide input.
3. Use the `All` library tab with the 459-channel lineup.
4. Observe the maximized 4K Guide.
5. Count fully visible channel rows.
6. Move focus through channels with arrows and Page Up/Page Down.
7. Observe focus settlement, page transitions, loading behavior, and resource use.

Expected:

- The default Windows profile uses the available PC viewport and resources.
- A 4K window presents materially more than one TV-sized page without clipping or unreadable text.
- Arrow, full-page, pointer, and gamepad navigation settle visibly within the defined latency budgets.
- Large-lineup browsing does not repeatedly reconstruct unrelated application UI or re-resolve recently visited pages.
- A lower-resource setting reduces preload/cache/overscan work without changing Guide correctness or hiding channels.
- Visual hierarchy and feature behavior match current upstream where compatible with Desktop security and native-video constraints.

Actual:

- Eleven complete rows and part of row twelve were visible.
- The twelfth row was clipped at the bottom of the scroll viewport.
- The default request profile contains twelve channels, matching the visible page.
- Ordinary vertical scrolling did not populate program content after the initial twelve channels.
- The scroll/virtualization source path uses only the currently loaded `presentation.channels`; `channelWindow.total` is not represented as a sparse total-height channel surface and scroll reconciliation does not request the next channel window.
- Twenty Page Down inputs sent at 250 ms intervals produced no visible channel-page movement in the first five-second observation window. The exercise did not record the initial focus ID, accepted paging actions, pending page target, request lifecycle, or first painted focus. It therefore remains a `WIN-TEST-007` interaction symptom and cannot establish Guide latency or implicate the cache, renderer, or GPU path.
- Renderer working set rose from 169.3 MiB to 191.0 MiB during that short exercise and later settled near 189.6 MiB. This is diagnostic evidence only; it is not sufficient to call a memory leak.
- A later `EPIPE: broken pipe` modal originated while writing a playback-transition diagnostic to the launch console. Its stack did not identify Guide owners, so it is excluded from this defect's root-cause claims.

Frequency:

- Under-density: 1/1 observed 4K Guide openings at this checkpoint.
- Page Down injection with no visible movement: 1/1 uninstrumented exercise; input acceptance was not established.
- Long-run latency, memory plateau, and route-exit cleanup: not yet measured.

Workaround:

- None established. Enabling the existing experimental aggressive preload can request twenty-four channels and warm adjacent pages, but it does not change the 108 px row height, full-subtree render strategy, global GPU-disabled mode, or missing production performance proof.

## Source-Traced Findings

### F1 — Ordinary scrolling is limited to the initially loaded twelve-channel presentation

Severity: High.

Evidence:

- `src/renderer/guideVirtualization.ts` defines `DEFAULT_GUIDE_PRELOAD_PROFILE.channelLimit = 12` and the aggressive limit as `24`.
- `src/contracts/settings.ts` defaults `aggressiveGuidePreloadEnabled` to `false`.
- `src/renderer/guidePresentationPolling.ts` passes the selected profile's channel limit into every presentation request.
- `src/main/channel/guideRuntime.ts` sorts eligible channels and slices only the requested page before resolution.
- `src/renderer/epg/guideDom.ts` calculates the virtual range from `view.guide.rows`, which contains only the current presentation page.
- the Guide scroll callback in `src/renderer/index.ts` schedules another application render but does not request a channel window.
- the current virtual grid does not use `channelWindow.total` to create a sparse absolute row surface or loading placeholders for unloaded channel indices.

Impact:

- A 459-channel lineup requires many page boundaries even before time navigation is considered.
- The default page is a conservative fixed constant, not derived from viewport height, memory, processor capability, or observed latency.
- A 4K window happens to expose approximately the same number of rows as the default page, making the Guide feel like a twelve-channel product even though `channelWindow.total` is correct.
- Wheel and scrollbar users cannot continuously reveal later populated channel rows because scrolling does not advance the data window.

Required direction:

- Represent the full eligible count as a bounded sparse absolute channel surface.
- Fetch the visible channel window automatically as wheel/scrollbar, boundary arrows, viewport-sized Page input, pointer, or gamepad movement crosses loaded pages.
- Use explicit inert loading rows for a fast jump into an unloaded window; never present silent blank rows or treat unloaded data as no-program data.
- Merge only current scope/revision/time/profile results, retain finite page/cache/DOM bounds, and preserve semantic focus across accepted window changes.

Rejected alternative:

- This is not an unbounded 459-row DOM mount. Renderer virtualization caps mounted rows at twenty-four and live program cells at four hundred.

### F2 — Horizontal `Guide Density` is mislabeled for the user's vertical-density need

Severity: High.

Evidence:

- `src/renderer/epg.ts` maps comfortable to four 30-minute slots/two hours and compact to six slots/three hours.
- `src/renderer/styles/guide-epg.css` keeps `--guide-row-height: 108px` for both settings.
- The DOM records the density value, but no production CSS rule changes vertical row height from it.
- The measured/fallback row stride is approximately 120 px after gaps.

Impact:

- Changing Guide Density does not show more channels.
- The label conflates horizontal time span with general information density.
- PC users have no supported way to trade artwork/metadata height and row height for more visible channels.

Required product decision:

- Separate `Time range` (Detailed 2h/Wide 3h) from `Row density` (Auto/Comfortable/Compact), or rename the existing setting and add a distinct vertical-density setting.

### F3 — Guide reconciliation is a high-priority measurement hypothesis

Severity: High.

Evidence:

- `src/renderer/epg/guideDom.ts` computes a virtual range but ends every Guide render with `epgGridElement.replaceChildren(shell)`.
- `src/renderer/index.ts` schedules `renderApp()` from Guide scroll via `requestAnimationFrame`.
- `renderApp()` recomputes route/workflow views and focusable elements; current call paths can create the Guide view multiple times per application render.
- `createEpgGuideView()` maps every channel in the current presentation page, filters buffered programs, builds cell view models, and then scans for selection.
- focus registration queries and rebuilds the focus graph from `[data-focus-id]` elements after render.

Possible impact requiring trace proof:

- DOM count is bounded, but nodes are still destroyed and recreated on scroll/focus renders.
- Focus registration, layout reads, view-model projection, and native-presentation reconciliation can repeat even when only a small visible range changed.
- Production traces must quantify their share of handler, reconciliation, style/layout, paint, and presentation time before a persistent row/cell pool is authorized.

Upstream comparison:

- Current upstream `EPGVirtualizer` owns a bounded persistent pool, stages visible and buffer cells, prunes to a DOM budget, reconciles existing cells, and protects the focused cell.
- Upstream `EPGGridRuntimeController` throttles grid work with `requestAnimationFrame` without routing every scroll through a whole-app subtree replacement.

Conditional direction if traces show this work dominates:

- Introduce a Guide-scoped lifecycle/reconciler that persists the shell, time ruler, channel rows, cells, and focus targets across range changes.
- Memoize or compute the Guide view once per accepted state generation.
- Keep `src/renderer/index.ts` a composition root; do not turn it into Guide policy.

### F4 — Main/data scaling and source-cache churn are unmeasured hypotheses

Severity: High.

Evidence:

- Every main Guide page request filters and sorts the full visible lineup before slicing the requested page.
- The page channels are resolved concurrently with `Promise.all`; the page is bounded at twelve or twenty-four, but there is no smaller per-page worker limit.
- each channel schedule is created for the requested buffered time range, capped at 200 programs per channel and 1,000 total programs.
- the domain source-resolution cache has a five-minute TTL and twenty-four entries keyed by canonical source identity, not by channel.
- the renderer polls every fifteen seconds. Only page and time-window changes are eligible for the renderer presentation cache; poll-start and poll-interval recompute the current page.

Possible impact requiring trace and cardinality proof:

- A lineup with more than twenty-four distinct canonical source identities could evict recently resolved sources; the observed lineup's distinct-source count and hit rate are not yet known.
- Returning to a recently viewed page may repeat resolution/schedule work only if relevant source entries missed or expired.
- The periodic poll could contend with input-triggered page work, even though one-active/one-trailing queues prevent an unbounded request storm.
- Request, cache, and worker-policy changes require measurements of sort cost, source cardinality, hit/clone rate, queue wait, source latency, and memory retention.

Rejected alternative:

- There is no evidence of an unbounded polling fan-out. Renderer work is one active plus one trailing request, and main IPC is also bounded.

### F5 — GPU-disabled composition is a cross-boundary A/B hypothesis

Severity: High, cross-boundary.

Evidence:

- `src/main/index.ts` unconditionally calls `app.commandLine.appendSwitch('disable-gpu')`.
- The observed renderer command line contained `--disable-gpu-compositing`.
- The observed GPU process used the WARP software D3D11 path.
- The active WS5 plan intentionally carries the same GPU-disabled setting into native child-window composition proof.

Possible impact requiring A/B proof:

- Chromium cannot use its normal hardware-accelerated composition path for the Guide.
- Large 4K surfaces, opacity, focus effects, scrolling, and subtree replacement may cost more under software composition, but the contribution has not been isolated.
- Hardware acceleration is a candidate Desktop optimization only if A/B traces show a material benefit and native child-window composition remains correct.

Constraint:

- Do not remove `disable-gpu` as a Guide-only patch. It is entangled with the unclosed native child-HWND/video composition proof (`EPG-10`, `UI-36`, WS5). A reviewed Tier 3 architecture decision must A/B prove native video, HTML overlay, focus, resize, fullscreen, DPI, multi-monitor, and teardown with hardware acceleration enabled and with a supported fallback.

### F6 — The current test suite proves bounds, not production performance

Severity: High verification gap.

Existing proof:

- 300 x 48 synthetic fixtures cover twelve/twenty-four request profiles, <=24 mounted rows, <=400 cells, <=200 programs per row, and <=1,000 programs per response.
- tests cover paging, focus retention, cache freshness, cancellation, one-active/one-trailing behavior, density settlement, past-window policy, tabs, and Play-to-now.
- a focused eight-file Guide suite passed 81/81 during this investigation.

Missing proof:

- no observed-lineup 459-channel or maximum-boundary 500-channel test;
- no Windows production Electron Guide benchmark or CI gate;
- no real scroll/input-to-paint measurement;
- no production DOM descendant/accessibility-node count;
- no heap plateau or listener/timer cleanup measurement;
- no real 15-second cadence soak through route, filter, density, server, and lineup churn;
- no paired current-upstream visual proof;
- no A/B GPU-mode proof.

## Upstream Parity Findings

The repository's audited baseline `0258dbe` remains valid for this issue. The remote `code-health` branch advanced twenty-one commits to `f5f587c` by 2026-08-10, but the following current Guide sources were byte-identical at both commits:

- `src/modules/ui/epg/constants.ts`;
- `src/modules/ui/epg/view/EPGVirtualizer.ts`;
- `src/modules/ui/epg/coordinator/EPGRefreshController.ts`;
- `src/modules/ui/epg/coordinator/EPGCoordinatorPolicies.ts`;
- `src/modules/ui/epg/styles.grid.css`;
- `src/modules/ui/epg/styles.info-panel.css`.

### Behaviors to preserve

- Guide opens from Guide/G/Green/F2-equivalent input.
- Rows are sorted by channel number.
- The ruler uses 30-minute columns and a current-time marker.
- The focused program exposes title, time, current/live state, metadata, and artwork hierarchy.
- The tuned/current channel rail remains visually distinct.
- arrows navigate channels/programs; page input advances a viewport-sized channel page; Back closes.
- pointer activation works.
- horizontal browsing can reach the full supported day/window.
- future programs show details but do not tune.
- All/per-library tabs are focusable and persist in the correct scope.
- current/past/selected program styling, loading/empty/error states, cancellation, and currentness remain explicit.
- classic/overlay presentation and Now Watching preference remain supported where native composition allows them.

### Visual hierarchy to match

Upstream and Desktop share some constants (approximately 108 px rows and a 48 px time header), but that is not visual parity. Current upstream additionally has a cohesive shell, persistent virtualized grid, rich info panel/backdrop/poster/clear-logo hierarchy, focused cell expansion, channel-rail provenance, current-time treatment, classic/overlay variants, and a bottom Now Watching/dashboard composition. Desktop currently presents a flatter large detail card, separate header/tabs/edit action, and full-width card rows.

Paired proof must evaluate hierarchy, typography, spacing, focus, selected/current/past states, artwork treatment, tabs, time ruler, empty/loading/error states, and both layouts. Historical macOS frames and matching individual constants cannot close this gap.

### Desktop divergences to retain

- Renderer stays unprivileged.
- Artwork uses opaque, self-owned, renderer-safe references; no raw Plex URL or token enters DOM.
- Settings persistence remains main-owned/versioned rather than upstream browser `localStorage`.
- Native video remains an app-owned main/helper concern.
- Desktop need not copy upstream WebOS worker counts, cache constants, blur cost, Magic Remote APIs, or hardware assumptions.
- Desktop may use larger PC caches, more concurrency, different overscan, denser rows, richer wide-screen layout, pointer/wheel affordances, and hardware composition after proof.

### Stale authority to reconcile before implementation closeout

The parity matrix still describes several already implemented features as missing or fixed to Classic. Current source/tests show Desktop implementations for Play-to-now, library tabs, Now Watching preference, past-items policy, and overlay/classic selection. A future implementation plan must reconcile those rows before using the matrix as a gap list. This report does not change their proof status; Windows/current-upstream evidence remains open.

## Candidate PC Performance Policy

Use two independent settings surfaces.

### Display density

Recommended shape:

- `Auto` (default): derive row height and detail layout from viewport size, DPI, input/readability constraints, and layout mode;
- `Comfortable`: preserve the TV-like 108 px presentation where desired;
- `Compact`: reduce row/detail height while preserving readable focus and metadata.

The existing Detailed/Wide control should be renamed `Time range` or otherwise made unambiguously horizontal.

Initial visual acceptance target:

- 3840 x 2160 at 100%: at least twenty complete schedule rows in Auto/Compact, with no clipped row;
- 1920 x 1080 at 100%: at least eight complete rows in Auto;
- 1280 x 720 and high-DPI/narrow windows: preserve upstream-like readability and a minimum usable five-row Guide;
- focus, forced colors, zoom, and reduced motion remain correct in every density.

These are acceptance floors, not hard-coded request sizes. The implementation should derive visible rows from actual grid geometry.

### Performance profile

Recommended shape:

- `Auto` (default): PC-tuned viewport-derived requests, bounded adaptive concurrency, cache sizing from lineup/viewport and a reviewed memory ceiling, idle warming only when input is quiet, and hardware acceleration when the native-composition gate allows it;
- `Reduced resource`: smaller overscan/cache/concurrency, no speculative background warming, and conservative artwork work while retaining complete navigation and the same visible-row density;
- an optional diagnostics-only `High performance` override may be considered only if Auto cannot reliably select the right profile.

The existing `Aggressive Guide Preload (Experimental)` toggle should be migrated or renamed. A low-performance option should not be implemented as “show fewer channels”; it should reduce speculative work and resource retention while leaving correctness, focus, and page semantics intact.

## Proposed Evidence And Conditional Remediation Packages

This report is evidence and historical planning input, not execution authority. Its Package 1-5 taxonomy predates and does not map one-to-one onto the Guide plan's G0-G6 execution packages. Use the active Guide plan for current sequencing; the package list below records the original evidence hypotheses only.

1. Measurement and authority correction
   - add a production Electron Guide performance harness plus observed-lineup 459-channel and maximum-boundary 500-channel fixtures;
   - reconcile stale matrix rows;
   - record baseline GPU-disabled and later A/B results;
   - freeze exact visual references and performance budgets.
2. Renderer incremental reconciliation, only if production traces show Guide projection/reconciliation/layout/presentation dominates
   - one Guide view computation per generation;
   - persistent shell/row/cell owners with keyed reuse/pooling;
   - range-local focus registration and no full application render on scroll;
   - keep renderer composition root wiring-only.
3. Adaptive data/cache policy, only if traces show distinct-source churn, queue contention, or request/cache miss cost
   - viewport-derived request size and full-page navigation semantics;
   - proportional bounded cache, recently visited page retention, and explicit foreground priority;
   - bounded per-channel resolution concurrency and poll/input scheduling;
   - cancellation/currentness preservation.
4. Desktop density and visual parity, after product review freezes responsive row and detail behavior
   - separate time range, row density, and performance settings;
   - responsive detail/shell composition for 720p, 1080p, 1440p, 4K, DPI, and resizable windows;
   - paired current-upstream visual and focus review.
5. GPU/native composition decision, only if GPU-mode A/B traces show material benefit
   - Tier 3 A/B Windows proof for hardware acceleration;
   - safe fallback/profile selection;
   - no parity or performance claim until native video/HTML composition passes.

Stop and replan if a package needs a new public contract, expands renderer privilege, exposes Plex/native details, changes native HWND ownership, adds a dependency/worker without measured need, or cannot meet the proof surface below.

## Acceptance And Verification

### Structural and contract proof

- Add an observed-lineup 459-channel fixture and one named maximum-boundary 500-channel fixture.
- Prove request offsets/totals/clamps and viewport-derived limits.
- Retain <=200 programs per channel and <=1,000 programs per main response unless a reviewed measurement changes those caps.
- Retain a documented DOM/cell budget and focused-row/cell protection.
- Prove one active foreground request plus one latest trailing intent; warm work never blocks input.
- Prove stale, cancelled, old-scope, old-density, and old-settings results cannot settle.
- Prove source/cache entries and public references are released on route/server/profile/lineup changes.

### Production Electron/Windows performance proof

The historical Package 1 proposal identified the following renderer marks plus one external presentation observation before any budget could be used as an implementation gate:

- `input-received`: trusted renderer event received, with input kind and starting focus ID;
- `input-accepted`: Guide owner accepts the action and records the intended focus/page target;
- `request-start` / `request-settled`: foreground Guide request identity, cache class, source-resolution class, and currentness result;
- `state-accepted`: the requested presentation/focus generation becomes eligible to render;
- `reconcile-start` / `reconcile-end`: Guide-scoped projection and DOM work;
- externally captured Chromium `frame-presented` trace evidence for the first frame containing the accepted target. This is not a renderer-emitted custom mark, and a lone `requestAnimationFrame` callback is not paint proof.

Run at least three repetitions after one discarded warm-up on the exact production build. Each repetition supplies its own 100-sample same-buffer scroll and arrow/D-pad cohorts; do not combine three undersized runs into one sample set. Record per-run and aggregate p50/p95/max, CPU/GPU/RAM, display/DPI, build, profile, source cardinality, cache state, request state, and distance from the next scheduled poll. Keep separate cohorts for:

- same-buffer work with no request;
- renderer page-cache hit;
- main/source-cache hit;
- cold live source resolution;
- quiet polling and input colliding with a scheduled refresh.

The active WS5 plan's existing timing values are candidate guardrails for baseline comparison, not frozen acceptance for every cohort. Package 1 may tighten or relax them only through a reviewed plan backed by the recorded baseline. The initial interpretation is:

- data-available (`state-accepted`) to `frame-presented`: candidate <=100 ms;
- same-buffer `input-accepted` to `reconcile-end`, 100 samples: candidate p95 <=50 ms and max <=100 ms;
- arrow/D-pad `input-accepted` to `reconcile-end`, 100 samples: candidate p95 <=16 ms, while `input-accepted` to `frame-presented` is measured separately with a candidate max <=32 ms;
- warm Page Up/Page Down and pointer `input-accepted` to `frame-presented`: candidate p95 <=100 ms with no lost or stale focus;
- cold live page requests: show the accepted loading/focus intent within the candidate 100 ms UI budget, report final data settlement separately, and freeze its budget only after source-latency baselines exist;
- steady scrolling on the reference capable-PC class should target 60 fps and must not sustain long tasks above 50 ms;
- renderer heap, working set, DOM nodes, accessibility targets, timers, listeners, and cached page count plateau during a >=100-cycle soak and return to the reviewed post-route baseline after Guide exit;
- no more than the reviewed row/cell/DOM budget is live at once;
- no clipped row or horizontal overflow at supported viewport/DPI rows.

### GPU/native proof

- capture sanitized A/B results for GPU-disabled and hardware-accelerated modes;
- prove Player full, Guide Overlay full, and Classic PIP native pixels beneath HTML;
- prove focus, pointer, resize, maximize, fullscreen, minimize/restore, 100/125/150% DPI, multi-monitor, crash recovery, and teardown;
- select a supported default/fallback from evidence, not device guessing.

### Visual and interaction parity proof

- pair current upstream and Desktop at 1280 x 720, 1920 x 1080, 2560 x 1440, 3840 x 2160, resizable widths, and 100/125/150% scaling;
- cover Detailed/Wide time ranges, Auto/Comfortable/Compact row density, Auto/Reduced performance, All/library tabs, Classic/Overlay, Now Watching on/off, current/past/future programs, loading/empty/error/retry, artwork unavailable, forced colors, reduced motion, keyboard, pointer, page keys, and gamepad;
- record expected and observed focus, visible-row count, response timing, resource profile, artifact locator, and redaction check for every row;
- do not close `EPG-10` through `EPG-13`, `UI-36`, or WS5 from synthetic tests alone.

### Commands expected for implementation closeout

- focused new Guide regression/performance tests;
- `npm run typecheck`;
- `npm run build:electron`;
- `npm run verify:architecture`;
- `npm run verify:maintainability`;
- `npm run verify:redaction`;
- `npm run verify`;
- `npm run verify:docs`;
- `git diff --check`;
- independent UI/performance/architecture review with no material finding.

## Ownership And Workflow

Likely owners:

- renderer Guide view/range/reconciliation: `src/renderer/epg.ts`, `src/renderer/epg/guideDom.ts`, `src/renderer/guideVirtualization.ts`, a new cohesive Guide lifecycle owner if approved;
- renderer polling/cache/input settlement: `src/renderer/guidePresentationPolling.ts`, Guide-specific focus/navigation owners;
- main page/schedule/cache policy: `src/main/channel/guideRuntime.ts` plus domain cache owners;
- settings/contracts/persistence: existing Settings contract and main persistence owners;
- GPU/native composition: Electron main shell/native-presentation owners and the WS5 Tier 3 proof plan;
- renderer and main `index.ts` files: wiring only.

The active worktree contains concurrent playback remediation changes and a user-modified active plan. This investigation deliberately did not edit those files. `WIN-TEST-006` remains the current playback blocker and its active amendment expressly does not authorize Guide appearance work. The Guide implementation should begin only after sequencing is reconciled through a reviewed plan; this report may be referenced as the evidence packet.

## Evidence Quality And Open Questions

Confirmed:

- 459 persisted channels at the observed checkpoint;
- 4K/100%-scale under-density with eleven complete plus one clipped row;
- default twelve-channel request profile and fixed 108/approximately 120 px row geometry;
- whole-subtree Guide replacement path;
- fixed twenty-four-entry source cache and fifteen-second poll;
- global GPU-disabled/software-composition mode;
- focused structural tests pass but no production Guide performance gate exists;
- current upstream Guide core sources are unchanged between audited baseline and remote `code-health` head for the compared files.

Not yet confirmed:

- exact input-to-paint p95/max on an uninterrupted production run;
- whether the Page Down injection reached the Guide paging owner at all and, for accepted actions, which dispatch/request/reconcile/presentation stage dominates;
- per-source cache hit rate and Plex latency in the 459-channel lineup;
- production heap plateau or leak;
- hardware-accelerated native child-window viability;
- final visual design choice for responsive detail placement and row density.

Those unknowns are explicit verification work. They are not reasons to weaken the reproduced defect or to guess at implementation.
