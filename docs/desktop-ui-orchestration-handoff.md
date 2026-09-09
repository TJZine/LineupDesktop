# Desktop UI orchestration workflow and new-session handoff

Status: preparation for a new implementation session. This file does not start
implementation in the design session. The user explicitly requested a stronger
orchestrator, `worker` and `worker_luna` execution chosen by task, grouped reviewer
passes, and review/fixes before proper commits. Preserve the entire approved scope;
usage savings come from appropriate assignment, concise context and shared checks.

## Start here

Read the [specification](desktop-ui-design-spec.md), [delivery plan](desktop-ui-implementation-plan.md),
and [visual manifest](design/desktop-ui/README.md). Also read repository AGENTS,
relevant Development/Architecture sections and the interface system. History is
reference only: read it only to resolve a specific provenance question. Do not
send the entire design conversation to every worker or repeat the original audit.

The stronger orchestrator owns implementation approach, data contracts, state and
input architecture, task decomposition, API designs, difficult production logic,
integration, visual acceptance and finding adjudication. Strong `worker` agents
may implement substantive logic using these contracts. Luna carries out bounded
implementation against concrete instructions; it does not invent missing product
behavior, architecture, APIs, migration rules or new visual direction.

## Role selection and availability

Inspect the new session's actual callable roles before dispatch. Prefer the named
`worker_luna` when provided; verify its configured model rather than inferring it
from its name. The repository now registers `worker` using `gpt-5.6-sol` / `medium` and
`worker_luna` using `gpt-5.6-luna` / `xhigh`. The configured reviewer remains
unchanged. Those are the user's worker-role choices; the orchestrator retains
responsibility for the stronger architectural/planning judgment. This already-open
preparation session may not hot-load new role registrations. Verify that the new
session actually exposes them; file presence is not runtime invocation proof.

If `worker_luna` is absent, use `worker` with explicit `gpt-5.6-luna` model override
and a bounded, self-contained context fork when the tool supports that combination.
For the current collaboration API that means `fork_turns: "none"` (or a bounded
positive turn count); full-history forks do not accept model overrides. This is
the user-authorized fallback, not permission to change global agent configuration.
Use `xhigh` reasoning for Luna, including the fallback. Record the actual
role/model/reasoning used in the dispatch ledger. If Luna cannot be called,
report that once and continue independent orchestrator work; do not repeatedly
attempt unavailable roles or silently bill strong workers as Luna savings. Obtain
a revised assignment preference if the unavailable role blocks planned delegation.
Use the explicitly configured strong worker role; do not silently replace its
model/reasoning. The strong orchestrator may keep the hardest logic itself. Do not use Luna as the independent correctness reviewer.

| Work type | Default owner | Boundary |
| --- | --- | --- |
| P0 contracts, migration/projection algorithm, API and ownership choices | Strong orchestrator | Record contract decisions/test cases in P0; implement tests/contracts with strong agents in P1 before dependent Luna work |
| Scheduling/filter semantics, serialized mutations, auth lifetimes, focus routing, asynchronous currentness | Strong worker or orchestrator | Includes algorithmic and integration tests |
| Guide geometry/time math, ticker lifecycle/RTL, native-video bounds, timer wake/stop, track confirmation, diagnostics redaction | Strong worker or orchestrator | “UI code” here is behaviorally high risk |
| Approved copy, static layout/spacing, existing control placement, simple read-only rows and state presentation | Luna after contract freeze | Exact files, API inputs, reference states and no-change boundaries required |
| Repetitive test fixture adaptation/docs after a settled implementation | Luna when judgment is bounded | Must not bless failing goldens, weaken tests or assert unsupported evidence |
| Cross-surface visual assessment and acceptance | Strong orchestrator | Compare actual Flutter renders with manifest refinements |
| Independent grouped review | Configured reviewer | Read-only; actual diff, contracts and targeted evidence |

Start with one strong worker and at most two Luna workers only when useful disjoint
work exists and the runtime permits it. Fewer agents are preferable to overlapping
edits or idle coordination. Do not parallelize simply to fill capacity. Reuse an
agent for related work while its context remains accurate; split fresh when stale
context would cost more than the brief. Give one corrective clarification when a
Luna result misses a bounded requirement; promote the task if it exposes an
unsolved contract or repeated misunderstanding. Do not burn usage on retry loops.

## Dispatch readiness and file ownership

Maintain one compact execution ledger in this document or an adjacent campaign
record: task/package, role/model, exclusive write files, prerequisite contracts,
status, test evidence, visual reference, review group/finding status and commit.
Do not create a tracking framework. Before dispatch, the orchestrator must finish
the concrete task card below. “Implement P5 from the spec” is not a Luna brief.

Only one active writer per file, including test fixtures, shared shell/controller
and goldens. A package boundary is not a file boundary. Hand off a shared file only
after the prior worker has finished and its edits have been inspected. Do not ask
Luna to extract components just to enable concurrency. Use existing boundaries,
serial work, or an orchestrator-approved extraction with a real cohesion benefit.
All workers receive: “You are not alone in this codebase. Preserve others' edits;
do not revert unrelated work. Stop and report an ownership conflict. Do not commit.”
Workers may read adjacent contracts, but request a file lease before modifying
anything outside the assigned set. Tests obey the same rule.

### Required task-card template

1. **Outcome and bounds:** one concrete result; exact exclusive files/symbols;
   forbidden neighboring changes; actual role/model and dependencies.
2. **Source grounding:** current methods/widgets and callers, current behavior,
   exact interfaces/callbacks to reuse, and the strong agent's implementation
   approach. Include types, null/unknown semantics and ownership of pending/error
   state. If this cannot be supplied, the task is not ready for Luna.
3. **Approved design:** exact spec heading and HTML filename, selected variant,
   later prose overrides, existing theme/type/spacing primitives and control order.
   Include a render or precise subtree geometry from the current Flutter baseline
   when layout work needs it. Do not let a mock's hardcoded CSS become Flutter policy.
4. **Behavior/state table:** normal, focused, disabled, pending, failed, empty,
   long-content and reduced-motion cases as applicable; name the existing state
   owner and what each action calls. Include dismissal and focus-return contracts.
5. **Responsive contract:** region order, width/height ownership, wrapping versus
   ticker rule, scroll owner, scale constraints and approved fallback. For Luna,
   supply the established responsive API/tokens or explicit formulas already
   selected by the strong agent; do not ask it to invent breakpoints.
6. **Acceptance examples:** input -> expected visible result and retained state;
   exact focused tests/fixtures and render configurations. Identify what existing
   coverage already proves; do not add mirror tests for static text changes.
7. **Return format:** changed files, concise decisions, commands/results, before/
   after render paths, omissions/conflicts, and any unresolved physical evidence.
   No commit, broad refactor, hidden feature, new dependency or invented fallback.

## Concrete Luna candidates and limits

These are task-card seeds. The orchestrator fills actual API signatures and exact
file leases after P0/core work; do not dispatch them verbatim as complete tickets.

| Seed | Required frozen contract | Visual/state requirements | Strong-agent ownership retained |
| --- | --- | --- | --- |
| L1: Settings row presentation | P2 categories, row value/pending/error API, Account callbacks, responsive tokens | `settings-layout-comparison.html` A; label/helper left, controls right; six-category order; final Account profile/server/signed-in account and sign-out; full names, quiet adjacent failure, no preview/Apply | Persistence migration, callbacks/sign-out, category routing and focus restoration |
| L2: Welcome/profile/server presentation | P3 attempt lifecycle and verified server/row-state API | Hybrid linking QR right, full code and explicit actions; profile full wrapping names; server row-local verified status. Use manifest's three corresponding files; no spontaneous browser open or Online label | PIN submission, auth/cancellation, discovery/reconnect, picker routing and keyboard handling |
| L3: Setup/result copy and structure | P4 exact count/view model and methods/actions; responsive source/rules layout | Two-column sources/rules, full-width source arrows, extras off default; `setup-result-states.html` minimal states; exact approved truthful copy | Candidate allocation, review comparison/counts, commit/rollback, lazy list and stale-review guard |
| L4: Studio passive presentation | P5 source/draft/recovery state API, approved geometry and schedule scroll owner | `studio-consolidated-review.html` and `studio-playback-space-refinement.html`; inline Mini-marathon options, persistent right preview, full titles, no duplicate actions | Source/filter semantics, all pickers/bulk operations, reorder, preview invalidation, Save/Tune/conflict state |
| L5: Diagnostic facts/event rendering | P7 typed allowlisted support view model and currentness/unknown rules | `diagnostics-refined.html`; Playback/Video/Media signal/Plex, technical disclosure, event-reading position, off/empty/error examples | Collection/redaction/copy snapshot, correlation/freshness, scroll/focus preservation logic |
| L6: Mechanical follow-through | Strong agent's accepted production diff | Update documented labels, removed-mode references and narrowly identified fixture plumbing; preserve historical evidence | Deletion scope, test assertions/coverage, golden acceptance and final documentation claims |

The same worker may handle related mechanical seeds sequentially. Separate core
behavior from presentation only at real existing/approved boundaries; do not
create a view-model framework for this campaign. Luna may write ordinary Flutter
widget code, but the strong agent supplies contracts and verifies its result.
Guide cells/tickers and Mini Guide gradients may include small bounded cosmetic
subtasks only after the stronger owner has fixed measurement, clipping, video
bounds, text scaling and lifecycle behavior. Never assign a complete Guide/Studio
redesign to Luna based solely on an HTML filename.

## Review batches and shared verification

Default to three grouped independent review gates, plus a narrowly scoped final
integration pass. These are bounded gates, not a rigid ceiling if concrete risk
requires another pass. No reviewer per text/spacing adjustment or Luna task.

| Gate | Integrated scope and timing | Focus |
| --- | --- | --- |
| R1 | P1 source/scheduling/persistence core, before downstream behavior builds on it | Schema round trips, migration continuity, occurrence identity, deterministic cycles, all projection consumers, corruption/rollback boundaries |
| R2 | P2–P4 navigation/Settings/onboarding/setup after strong integration and local checks | Retired preference safety, auth and input guards, accurate allocation/review/removals, responsive composition; group mechanical presentation changes here |
| R3 | P5–P7 Channels/Studio/Guide/player panels/Diagnostics after integration | Saved/draft/async races, batch operations, Guide/ticker focus, timer/tracks, privacy, shared state, visual consistency |
| R4 | Final net integration delta and evidence gaps after R1–R3 fixes | Cross-batch regressions, omissions, protected surfaces, docs/removed code and exact-commit Windows evidence; reuse earlier findings/evidence rather than fully rereviewing everything |

R3 is broad: provide a navigation map and split into at most cohesive subpackets
(e.g. Channels/Studio and Guide/Player/Diagnostics) when the actual diff would
prevent a careful review. Do not save usage by submitting an unreviewably large
diff. Likewise move a high-risk shared change forward to its prerequisite gate
instead of delaying its review merely to meet a package number. Reuse one reviewer
for follow-up fixes to its packet while context is valid. Request a targeted delta
recheck for substantive fixes; no fresh full reviewer for each mechanical repair.
The final pass may use that reviewer with a concise evidence index if practical.

Orchestrator first integrates worker output, reads the diff, runs relevant checks
and compares real Flutter visuals. Then provide the reviewer: exact immutable
base/target or frozen working-tree packet, file manifest INCLUDING untracked files,
spec sections and selected refs, tests/results, known baseline failures and prior
findings. Freeze writes to the packet until reviewed. `git diff` alone omits new
files; do not claim those were reviewed without including their contents. Never
stage unrelated user changes merely to generate a packet. If edits occur during
review, invalidate affected findings/approval and submit the changed delta.

Review output: severity, concrete location, failing scenario, evidence, requested
correction, and readiness verdict. Orchestrator accepts/modifies/rejects each with
reason, assigns repair at appropriate model level, verifies and records closure.
Do not accept speculative features or visual departures just because a reviewer
suggests them. Any material UX conflict returns to the user; routine fixes proceed.

Workers run focused checks for their changed behavior. The orchestrator runs one
shared integrated check per gate when appropriate and the required final checks;
do not run the full suite simultaneously for every worker or repeat an unchanged
passing run. Re-run affected checks after changes; reuse only when code, inputs and
toolchain match. Capture before/after renders using the same synthetic data/clock/
focus and agreed dimensions. An image update is not evidence until inspected.

After a portable review gate passes, create coherent conventional commits for its
distinct changes;
review batches and commit boundaries need not be identical. Only the orchestrator
commits, after repairs and verification. P8 audits the resulting net diff and
records exact tested commits. Sequence physical work as portable-reviewed candidate
-> coherent commit -> exact-commit package/Windows checks -> fix commit and affected
retest if needed. R4's portable code-review closure may precede physical results;
physical acceptance remains open until its actual evidence exists. Before executing
the Windows procedure, reconcile its active scenarios with the implemented PiP-only
target while preserving dated historical observations. If hardware is unavailable, finish portable work and
provide explicit physical acceptance steps/gaps; do not claim release/Windows
acceptance or leave unrelated authorized work undone.

## Copy/paste prompt for the new session

> Implement the approved Desktop UI refinement campaign in this repository.
> Act as the stronger orchestrator. Begin with AGENTS.md, then read the complete
> `docs/desktop-ui-design-spec.md`, `docs/desktop-ui-implementation-plan.md`,
> `docs/desktop-ui-orchestration-handoff.md` and `docs/design/desktop-ui/README.md`,
> plus the relevant Development, Architecture and interface-system contracts.
> Use the latest readiness-review record; do not treat historical proposals or
> illustrative mock behavior as active requirements.
>
> I authorize implementation through relevant tests, integrated visual checks,
> independent reviewer subagents, finding adjudication/repairs and coherent
> conventional commits. Use `worker` and `worker_luna` according to the handoff;
> if the named Luna role is unavailable, use the documented worker/Luna model
> override when supported and report actual assignments. Keep architecture,
> contracts and difficult logic with the stronger orchestrator/strong workers.
> Give Luna concrete bounded briefs after interfaces/behavior are settled.
> Group mechanical/UI tasks before independent review using the documented gates;
> do not launch a reviewer for each small task. Preserve completeness and quality.
>
> Recheck HEAD/status and preserve all existing changes, including uncommitted
> design documents. Complete P0 technical contracts before dependent implementation.
> Maintain exclusive file ownership, a concise dispatch/evidence ledger and honest
> progress. Follow the approved designs and later refinements, including all four
> resolutions/DPI/text-scale acceptance and protected Player boundaries. Do not
> recreate HTML as application UI, reopen resolved choices, or invent new features.
> Ask only about consequential new conflicts; resolve routine engineering details.
>
> Begin now with P0, then carry out the dependency-aware packages. Do not deploy,
> publish or push without a separate instruction. Physical Windows checks require
> real evidence at the tested commit; if unavailable, complete portable work and
> record the exact remaining checks without calling them passed. Do not create
> additional user-facing tasks as a substitute for worker subagents.

Paste the block above into a new session opened on this repository. Creating or
sending to that session is the user's next action; no new session is created by
this planning pass. The block is the explicit future execution instruction, not
an instruction to implement while preparing/reviewing these documents here.
