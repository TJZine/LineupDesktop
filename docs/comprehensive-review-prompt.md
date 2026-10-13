# Comprehensive Lineup Desktop review prompts

Use **Prompt 1** for the general review on the current host. It includes
repo-wide source review and every useful verification available here, including
static inspection of Windows code. It prepares a separate Windows handoff and
stops. Use **Prompt 2** only when starting the later Windows review. Neither
prompt authorizes implementation.

Grounding: inspected on October 10, 2026 at
`4fb7758034f4f47290fae13a4ea8275860ba1284`. The defect classes and journeys below
were approved for this prompt. Reconcile them against the actual review target;
this preparation SHA is not a request to check out an old revision. Docker is
excluded. Windows GPU, media runtime, and packaging remain in scope.

## Prompt 1 — General review on this host

Copy this entire block into Codex in the LineupDesktop checkout:

```text
Perform a deep, comprehensive production review of THIS Lineup Desktop repo.
Find real bugs, latent defects, and material code-quality problems before manual
testing finds them. Use repo-production-review as the backbone: repo census,
evidence ledger, specialist dimensions, wide scans, deep inspection, and evidence
calibration. Extend it with the history-derived defect classes, end-to-end
journeys, executable probes, and doc-versus-code checks below.

This invocation is the GENERAL REVIEW. Finish as much as this host can establish.
Review Windows source and contracts here; put Windows-only execution, GPU/media
runtime, physical input/display, and exact-package acceptance into a separate
WINDOWS_HANDOFF.md. Do not launch that Windows campaign or wait for it before
completing this review. Docker is out of scope.

1. AUTHORITY, TARGET, AND WRITE BOUNDARY

Read the actual applicable AGENTS.md files, CLAUDE.md, and .agents/project.md.
Root CLAUDE.md currently imports AGENTS.md. Use this repo's verification and
ownership contracts; do not import rules or platform requirements from another
repository. Locate and read the installed repo-production-review skill and its
relevant specialist rubrics. Apply review-code for review/adjudication and
verify-code for evidence selection. Use repo-production-remediation-plan after
calibration to produce the requested planning artifact.

Resolve repository root, branch, full SHA, requested target/base, dirty tracked
files, relevant untracked files, host, and toolchain before collecting evidence.
Unless I name another target, review the current checkout. Identify any local
deltas included in the review separately from HEAD. Preserve unrelated work,
including existing review documents and ignored artifacts. Record a source/input
fingerprint for checks; if concurrent changes affect a finding or check, reconcile
and repeat only the affected work. Do not attribute a mixed-tree result to a SHA.
Do not switch branches, reset, stash, commit, push, merge, publish, or message
others as part of this review.

This is review and planning only. Do not edit product code, permanent tests,
configuration, manifests, lockfiles, engine patches, security options, snapshots,
goldens, or existing product documentation. Do not apply fixes, generate patches,
install replacement tooling, update dependencies, or dispatch implementation.

I explicitly authorize these narrow write exceptions to the review/planning
skills' read-only defaults:
- New review artifacts under REVIEW_DIR, defined below.
- Disposable synthetic probe source, fixtures, and sanitized logs under
  build/review-probes/<review-date>-<short-sha>/, with unique names per run/owner.
- Normal ignored build/cache output and temporary files from safe, documented
  verification commands. Describe their output before execution.
These exceptions do not authorize product changes. Do not modify .gitignore.
Verify each probe destination with git check-ignore before writing; build/ is
ignored by the current root .gitignore. Preserve prior probes and outputs.
If a command needs writes beyond this scope, use a compliant alternative or
record the specific limitation; continue independent review work.

Use the review date in America/New_York for
docs/reviews/comprehensive-review-<YYYY-MM-DD>/. Call the exact path REVIEW_DIR.
If that directory already contains a completed review or unrelated work, preserve
it and choose a unique sibling with the date and short SHA (plus a suffix if
needed). Record that choice. Do not overwrite an earlier campaign.

Keep credentials, token-bearing URLs, authorization headers, private media titles
and paths, raw native messages, and unredacted diagnostics out of artifacts and
shared output. Use synthetic identities/media and bounded controlled failures.
Do not read credential stores or raw private logs to populate the review. Real
account actions, destructive fixtures, system setting changes, and physical
observations require their own appropriate authorization; queue unavailable ones.

2. REPO CENSUS AND CURRENT CONTRACTS

Build the census before delegating or drawing conclusions. Inventory tracked
files, entry points, owners, large/high-risk files, source/test/config/docs
surfaces, dependencies, CI jobs, build/package scripts, persistence, networking,
native transport, diagnostics, and platform boundaries. Use direct git/rg reads;
a missing or stale code index must not narrow coverage. Include release-relevant
vendor metadata and engine patches; exclude opaque assets/caches/generated output
from qualitative review unless they affect a concrete production obligation.

Starting authorities and evidence sources:
- README.md, docs/README.md, docs/user-guide.md, docs/architecture.md,
  docs/DEVELOPMENT.md, CONTRIBUTING.md, SECURITY.md.
- .interface-design/system.md and applicable approved design/decision records.
- docs/product-parity.md, docs/reviews/, relevant investigation and plan status.
- docs/windows-native-validation.md, docs/windows-runtime.md,
  docs/windows-collaborative-acceptance-handoff.md, tool/windows/,
  tool/flutter_engine/, third_party/libmpv/, .github/workflows/ci.yml,
  pubspec.yaml and pubspec.lock.
- docs/schedule-continuation-plan.md,
  docs/guide-freshness-collection-investigation.md,
  docs/libmpv-authenticated-reference-investigation.md,
  docs/plex-transcoding-implementation-plan.md,
  docs/fullscreen-hdr-spec.md and docs/fullscreen-hdr-implementation-plan.md.

Search for DECISIONS.md, TODO.md, CHANGELOG.md, docs/current-cli-contract.md,
and docs/current-architecture.md. At prompt preparation, none exists in the
current tree; all except CHANGELOG.md also have no history in available local
refs. CHANGELOG.md occurs only on upstream-lineup refs outside HEAD ancestry and
describes webOS. Recheck, record absent/nonapplicable sources, and use this repo's
actual equivalents rather than inventing contracts or importing upstream rules.

The actual command/API surfaces include lib/main.dart's --media= entry,
tool/windows/run.ps1 parameters and environment inputs, preparation/build/package
commands, Plex HTTP request/response boundaries, and Dart/native MethodChannel
messages. Inventory all current surfaces and consumers; do not assume this app
exposes a general-purpose CLI or a public server API.

Preserve distinctions between requirements and current implementation, and between
implemented, deterministically tested, platform-observed, and supported. Flutter
owns application and interaction policy; native code owns media/platform
mechanisms. macOS playback is intentionally unsupported. Electron is provenance,
not a compatibility target. Current approved decisions outrank old execution
prompts; historical worker rosters and approval/dispatch procedures are not new
task instructions.

Reconcile older findings against the actual target. In particular, many October 7
review findings were fixed October 8; scheduled continuation was implemented
October 10. At preparation, Plex transcoding and automatic fullscreen HDR matching
remain planned. Do not call planned features implemented, or turn acknowledged
unimplemented features into newly discovered regressions. Recheck if the target
has advanced. Preserve settled decisions; isolate genuinely unresolved ones.

3. DERIVE AND HUNT KNOWN DEFECT CLASSES

Read git log across the relevant history, especially fix/test and consequential
refactor commits, then inspect representative diffs, regression tests, review
reports, decision records, and release evidence. Do not stop at recent commits or
commit titles. Separate current Flutter lineage from older Electron/upstream
provenance; transfer a historical lesson only with a demonstrated current seam.

Use this approved seed list, refreshing and extending it from actual evidence:

C01 Stale async work and incomplete cancellation. Late results cross profile,
server, content, route, or authorization lifetimes; obsolete IO still consumes
resources. Seeds: 37416c1e, e3f36d00, 62bc8af1. Hunt controllers, Plex transport,
Guide/artwork caches, Studio tasks/navigation, and playback callers.

C02 Persistence, rollback, and recovery. Publication before durable save,
overlapping snapshots, failed settings revived later, migration/quarantine losing
original bytes. Seeds: 204e0648, c7c393aa, 3fc568d9. Hunt every mutation owner,
selection/save/credential barrier, legacy decoder, recovery and filesystem path.

C03 Credential isolation and containment. Account versus PMS credentials,
authorization retirement, redirects/nested media references, unsafe diagnostics.
Seeds: 5598005e, a061935a, 3d2014e6. Hunt request construction, artwork/portraits,
privileged native loads, option lifetime, stores, errors and support export.

C04 Incomplete/malformed external data. Missing data treated as authoritative
empty inventory, incomplete pagination, numeric identities, duplicated playlist
occurrences. Seeds: 7dd76763, f6bdae5b, 292fc815. Hunt every parser, inventory and
enrichment stream, bounded page reader, retry path and downstream durable filter.

C05 Generator/resolver/scheduler disagreement. Preview/apply succeeds but content
cannot air; specials, duplicates, source provenance, number exhaustion or refresh
damages preserved channels. Seeds: 85aa6452, c732f79f, 4f89dcad. Hunt all strategies,
build modes, allocation, Studio/Air Check, shared resolution and commit guards.

C06 Time and schedule instability. Input-order-dependent shuffle, DST folds,
midnight, stale caches, loaded-program versus wall-clock identity. Seeds:
7287db1c, 6a1ec4e3, db3978e3. Hunt scheduler/worker, seeds/anchors/migrations,
Guide geometry/live following, previews, Player metadata and continuation.

C07 Playback lifecycle and confirmation. Command accepted versus state observed,
stale load/stop/track events, cleanup ownership, multipart readiness, EOF versus
stop, premature endings and superseded continuation. Seeds: 51900b52, 4e01d438,
835ab431, db30c286, 91b66b7e, cd2c08f6. Hunt Dart/native producers and consumers,
every load/seek/retry/stop/dispose path, track requests and presentation state.

C08 Recovery exits and action eligibility. Wrong Back/Cancel origin, no usable
exit, invisible pending tasks, retrying the wrong dependency, enabled UI rejected
downstream. Seeds: 9534b282, 9aebd4c7, 64be4860, 62bc8af1. Hunt every stage/route,
dialog, picker, busy guard, save/tune/retry action and failure continuation.

C09 Overlay/focus/shortcut/timer interference. Frequent events restart deadlines,
pointer input becomes keyboard focus, text keys escape, context guards suppress
valid shortcuts. Seeds: 6b874f35, b86693d9, 01bda796, 0421c88e. Hunt shared controls,
shell key dispatch, all Player overlays, Guide editors, focus restoration and
mounted presentation lifetimes; test actual key events where that is the claim.

C10 Geometry and accessibility. Incidental sizing caps, clipped/unreachable
controls, inaccessible track choices, text scaling, focus and native aperture/DPI
disagreement. Seeds: 02330deb, 825070fd, 6a1ec4e3. Hunt shared layout primitives and
all consumers, scrolling/hit targets/semantics, root transforms and native bounds.

C11 Resource bounds and truthful progress. Sibling requests survive fatal failure,
collection budgets misclassified, repeated expensive resolution, misleading phase
or diagnostic projection. Seeds: 4d2470c5, d6019438, 79b1a6df. Hunt workers, queues,
caches, pagination/recovery budgets, notifications, timers, native telemetry and
support report vocabulary. Measure credible cost claims; bounded code alone does
not prove acceptable latency, and file size alone does not prove bad performance.

C12 Build/package identity and path failures. Stale engine/runtime outputs,
dirty-source acceptance, symlink/reparse escape, missing runtime requirements,
incorrect diagnostic identity. Seeds: d816b53b, 565bf0bd, ca56080a, 070ab1d6. Hunt
launcher/preparation/build/package/CI paths and provenance/license/hash checks.

C13 Weak or misleading verification. A positive control passes before a later
rejection, errors are overwritten by stop, negative contracts disappear, source
grep substitutes for behavior, CI/platform evidence is overstated. Seeds:
d6fff072, 29062716, 766ed05f, 9d30daa9. Hunt harnesses, fixtures, assertions, skips,
test tiers, job selection, report claims and evidence reuse across revisions.

For EACH class, record: historical trigger/root cause/fix with references; current
invariant; all candidate sibling surfaces; searches and deep inspections; controls
or protections found; confirmed siblings, rejected candidates, and unresolved
gaps. Search the whole relevant codebase, not just changed files or the original
fixed instance. A past fix is a search seed, not evidence of a present defect.

4. TRACE APP-SPECIFIC END-TO-END JOURNEYS

Trace UI/command entry -> policy/controller -> Plex/store/native boundary ->
observable result -> recovery/cleanup/relaunch. Include failure, cancellation,
supersession, repeated action and restart at consequential async boundaries.
Use current README/guides/source/tests to refine these approved journeys:

J01 First run: startup, PIN/QR link, expiry/cancel/retry, protected/unprotected Home
profiles, reachable/no server, scan, configure, review/apply, Guide. Include empty,
unsupported, partial and malformed inventory, and failed secure cancellation.

J02 Saved restoration: relaunch, profile-scoped server/lineup recovery, missing or
recreated collection/playlist references, enrichment failure, readiness retention,
restore cancellation/server switch and correct return/restart behavior.

J03 Setup re-entry: ready subset, new libraries, retry failed dependencies,
cancel/restart, all source strategies, per-library/grouped scope, playback modes,
specials/variants/minimum programs/channel limits, replace/add/refresh, custom
preservation, stale reviewed plans, missing sources and number exhaustion.

J04 Account/scope transitions: switch profile/server during discovery, scan, save
and playback; nested picker origins/PIN Back; same-scope refresh; failed persistence
and credential cleanup; logout, cancellation and relink without revived old work.

J05 Channel management/Studio: create/edit/duplicate/generated inspection,
library/hand-picked/retained playlist/mixed sources, unavailable retained items,
filters/browse/rundown, Air Check, conflicts/reconfirmation, reorder/delete,
save versus tune, dirty-draft exits and navigation while tune is pending.

J06 Guide: live following versus browsing/inspection, search with actual keys,
library filters, paging/Now, retries including offscreen rows, failed hours save,
midnight/DST/long-open sessions, large/empty lineups, geometry and Player/PiP
transitions with distinct focused/selected/tuned/airing identities.

J07 Playback/continuation: manual tune/live join, surfing/number entry, multipart
advance and repeated cross-part seeks, auth recovery, track request/confirmation,
EOF/stop/error distinction, premature end, next-program start, 30-second catch-up
boundary, unknown duration, failed continuation without automatic retry, and
tune/Stop/sleep/logout/content change superseding pending loads. Player follows
the loaded program while Guide remains wall-clock; verify current policy.

J08 Controls/settings: every overlay and documented shortcut context, text editing,
pointer/keyboard/remote semantics, DVR off/on, sleep deadlines, auto-hide, themes,
Guide hours/context/artwork, reduced motion, focus indicators, startup picker,
concurrent immediate saves, failure feedback and rollback in mounted surfaces.

J09 Diagnostics/support: enable, reproduce, inspect/refresh/copy, disable/clear;
bounded retention, truthful safe facts, redaction and current build/runtime identity.

J10 Persistence/upgrade: valid old state, compatible migration, edit/save/relaunch;
invalid encoding/JSON/schema, quarantine collision, transient IO, failed write or
rename, original-byte preservation, secure-store isolation and cleanup failure.

J11 Platform/native lifecycle: Windows local --media launch and Plex playback,
startup failure, replacement, resize/minimize/fullscreen/monitor/DPI transitions,
shutdown with work pending, hardware decode, representative codec/container/audio/
subtitle/HDR behavior; macOS explicitly unsupported playback. Inspect code and
portable seams here; defer actual Windows execution/physical observations.

J12 Build/release: pinned provisioning inputs, launcher parameters/environment,
paths with spaces/caller directory, stock compile versus patched engine, release
build/package, provenance/hashes/licenses/containment, complete package launch
outside the checkout and on clean Windows, including Vulkan-loader prerequisites.
Run portable policy checks here when available; defer Windows execution.

Use risk-driven combinations: owned/shared/managed/protected accounts; selected
direct/remote/relay routes; small/large/empty/partial sources; sequential/shuffle/
block; DVR off/on; Guide 2/3/4 hours; auto-hide settings; themes/motion/focus/text
scaling; viewport/DPI regimes. Do not invent an exhaustive Cartesian test matrix.
Record which combinations were actually inspected or exercised.

Build an action-eligibility ledger and navigation/input-context map. For every
important action trace visibility/enabled state, handler guard, mutation scope,
success, failure, retry and exit. Check shared keyboard/remote contracts in each
overlay/editor context rather than testing only the ordinary Player state.

5. SPECIALIST COVERAGE AND CALIBRATION

Cover every repo-production-review dimension with a wide scan and deep inspection:
architecture/ownership; correctness/failure modes; maintainability/AI debt;
tests/CI; security/privacy; build/release/supply chain; operations/configuration/
diagnostics; performance/concurrency/reliability; docs/DX. Use the installed
specialist rubrics and repo-review-evidence-calibration. State inspected surfaces
and limitations even where no material finding survives.

I authorize bounded read-only subagents when they improve distinct coverage or
settle an important uncertainty. The controller owns census, evidence, severity,
adjudication and artifacts. Supply actual discovered skill paths, repo context,
scope and evidence requirements; keep within host limits and avoid nested
delegation, fixed rosters, implementation roles or separate user-owned chats.
Assign disjoint probe paths and serialize shared runtime/build/cache resources.
If delegation is unavailable, perform the work inline and disclose any material
independence limitation; do not reduce inspection depth.

Material quality findings need a demonstrated maintenance/correctness burden:
duplicated policy with divergent consumers, confused ownership, invalid states,
misleading fallbacks, needless forwarding/frameworks, or brittle tests. Do not
promote personal style, a large file, or a necessary native interface as a defect.
Give a coherent corrective direction, not an unsolicited rewrite implementation.

For each material candidate, independently challenge reachability, caller guards,
valid inputs, product intent, mitigating tests, alternate interpretations,
severity and claimed evidence tier. Inspect decisive sources directly. Verify
external API/framework/platform claims against version-appropriate primary
documentation and cite the exact supporting source. Reviewer agreement alone is
not evidence. Deduplicate causes while preserving distinct effects/proof needs.

6. EXECUTABLE EVIDENCE ON THIS HOST

Inspect docs/DEVELOPMENT.md and actual scripts before running checks. Resolve the
SDK/runtime pins from their owners instead of assuming PATH is correct. Existing
documented portable commands are:
  flutter pub get
  dart format --output=none --set-exit-if-changed .
  flutter analyze
  TZ=America/New_York flutter test
  pwsh -File ./tool/windows/verify-release-policy.ps1

Use installed resolved dependencies and --no-pub where appropriate. Run dependency
preparation only when needed and compatible with the no-tracked-input-change
boundary; otherwise record the prerequisite and continue source review. Never
upgrade or silently change pins. Run the applicable baseline once on stable inputs,
then focused suites/probes for unresolved claims. Reuse valid results. Do not run
Flutter commands concurrently when they contend for shared caches/build state.

On macOS, the required Guide alpha suite is
  TZ=America/New_York flutter test test/app/guide_opacity_test.dart
Recognize when the full suite already executed it. Optional visual suites under
tool/visual/ are separate; use them for a concrete visual question, never update
goldens during review. A macOS build/run may add evidence for a specific portable
startup/platform question when prerequisites and safe isolated data exist; a
synthetic UI harness is not real-app E2E and does not prove native playback.

The broad formatter can see ignored Dart probes/capture scripts. Prefer baseline
checks before creating new probes. If pre-existing ignored files cause failure,
attribute it accurately and supplement with a read-only tracked-Dart check; do
not erase those files, format the repo, or describe the broad command as passed.

For a concrete unresolved mechanism, write the smallest useful probe only under
the verified ignored run directory. Import the real production owners and reuse
existing meaningful fixtures; do not duplicate the suspected algorithm or weaken
production access/security guards to make a demonstration work. For Dart probes:
  TZ=America/New_York flutter test --no-pub build/review-probes/<run>/<name>_test.dart
Resolve the placeholders to this run's actual path. Exercise the real event/input
or IO boundary relevant to the claim, with positive/negative controls as needed.
Repair probe-only setup errors there; they are not product defects. Characterizing
a bug with a green assertion is not a passing acceptance test. Retain enough
sanitized recipe/source detail in REPORT.md to reproduce evidence even though
ignored probes do not travel with Git; do not copy probes into permanent tests.

Log command, cwd, exact input identity, host/tool versions/timezone, exit status,
assertions/meaningful output, skipped cases, duration when known and evidence
limits. Distinguish new execution, attributed historical evidence, static trace,
mock/synthetic boundary evidence, native harness execution and physical acceptance.
Do not sum overlapping focused/full-suite counts as distinct tests.

Portable tests and C++ source review can establish specific Windows contract
defects here. They cannot establish physical media, GPU/HDR, composition, input,
filesystem/credential-store, shutdown or package behavior. Windows TZ alone does
not set Dart's Windows timezone. CI job definitions or a green aggregate badge do
not prove a particular native/package job ran. Keep all such claims precise.

7. DOC-VERSUS-CODE CONTRACT CHECK

Build a claim matrix: document/line -> promised behavior/default/command -> actual
entry/owner/caller -> test or executed observation -> disposition. Compare README,
user guide, current architecture/development docs and relevant approved records
against actual CLI/script parameters, Plex/native boundary validation, UI controls,
shortcuts, settings, failure/recovery behavior, platform support and release claims.

Classify agreement, documentation drift, implementation defect, ambiguous product
decision, intentional unsupported behavior, planned work and evidence overclaim.
Use the approved intended contract to distinguish a code bug from a stale guide;
if intent is unresolved, ask for a decision rather than choosing a new product
direction. Mark historical claims with their tested identity. Do not edit the
documents during this review. Reconcile old reports instead of repeating resolved
findings or reopening settled product decisions without new evidence.

8. FINDING STANDARD AND REMEDIATION

Maintain the skill's repo profile, evidence ledger (E-...), candidates (CAND-...)
and calibrated findings (F-...). Keep its type, severity and confidence fields;
also label every candidate/finding with one evidence status:
- CONFIRMED: a reproducible observation or complete reachable source/contract
  demonstration establishes the precise claim. State which kind; a confirmed
  missing projection is not a claim that physical behavior was observed.
- LIKELY: a concrete reachable mechanism has strong evidence, but an important
  runtime/input assumption or outcome has not been observed. Name that assumption.
- HYPOTHESIS: insufficient evidence to promote the suspected issue. Specify the
  exact live/platform observation that would confirm or reject it. If a portable
  probe can settle it here, run that first instead of handing off speculation.

Evidence status is separate from severity, confidence and type (confirmed defect,
inferred risk, subjective maintainability concern, insufficient data). A measured
maintenance burden can be established without calling it a runtime bug. Avoid
numeric repo grades, finding quotas and inflated release/security severity.

Every promoted finding needs: ID, title, type/status/severity/confidence, class and
journey IDs, current file:line/symbol references, violated contract, realistic
trigger/preconditions, execution path/root cause, consequence/blast radius,
reproduction or decisive evidence IDs, controls/counterpoints, why existing tests
miss it, correction direction, and exact remaining acceptance if any. Separate
new findings from resolved history, known deferred work and decision items.

After calibration, use repo-production-remediation-plan for retained findings.
For planning, "accepted" means retained by this review's evidence adjudication;
it does NOT mean I have approved implementation. Do not insert another approval
pause between the report and the requested draft plan. Park disputed/HYPOTHESIS
items and unresolved product decisions; LIKELY findings must expose their evidence
gate before a dependent behavior change can be considered ready.

Group packages by a coherent implementation seam. Each needs finding IDs, goal,
scope/non-goals, files/owners, expected behavior, approach, dependencies, risks,
rollback/data/security notes, current meaningful tests, portable versus Windows
acceptance, and any decision prerequisite. Do not prescribe a fixed model roster,
unrelated cleanup, or a new test framework. Sequence real dependencies/resources;
portable packages need not wait for unrelated Windows observations. Assign no
implementation work and write no patches.

9. DELIVERABLES, WINDOWS HANDOFF, AND STOP

Write these new files in REVIEW_DIR:

REPORT.md: use the repo-production-review report structure, augmented with the
history-derived class ledger and sibling-search coverage, journey/action/input
coverage, doc/code claim matrix, evidence/command ledger, calibrated findings,
rejected/downgraded candidates, no-finding dimension notes and explicit exclusions.
Include "Needs my decision" and "Needs physical/live observation" sections.
Do not present source-traced journeys as interactively executed journeys.

REMEDIATION.md: the planning-only package sequence from the remediation skill,
linked to final finding IDs, evidence gates and decisions. Separate packages
ready for approval from those needing more evidence or product choice.

WINDOWS_HANDOFF.md: a self-contained, copy-ready prompt for a separately invoked
Windows review. Include exact general-review folder, source/fingerprint, historical
evidence identities, relevant findings/classes/journeys, reviewed Windows surfaces,
unresolved questions, prioritized observations and prerequisites. Carry forward
portable conclusions and inspect Windows-specific gaps; do not instruct a repeat
of the entire general review or implement proposed fixes.

For every physical/live observation give an ID, linked finding/journey, exact
candidate/runtime prerequisites, synthetic or authorized-data setup, action/event
sequence, expected discriminating outcomes, neutral facts to record, cleanup,
and how each outcome changes classification. Cover native CTests; actual EOF and
continuation; buffering versus pause; replacement/seek/stop/dispose; tracks;
SDR/HDR/hardware decode/audio/subtitles; composition/fullscreen/monitor/DPI/input;
Windows filesystem/secure-storage; pinned-engine/runtime/package provenance;
clean-system launch and loader requirements; and unresolved real Plex shapes or
latency when needed. Tailor to current findings and contracts, not a rote campaign.
Headless harness evidence remains separate from visible/audible physical evidence.

The Windows handoff must preserve approved product decisions and current reference
security, use exact repo commands, and record Pass/Fail/Blocked/not run honestly.
Have the human supply physical observations one bounded step at a time. No
automatic implementation, display/timezone/driver changes, real-account mutation,
publication, or weakening of security. Missing physical resources are a precise
remaining acceptance item, not a reason to withhold the general report.

Check the artifacts for consistent IDs, source identities, links, commands,
classification and package dependencies. Verify the final diff contains only
authorized new artifacts; report pre-existing changes separately. Return links
to all three files, the highest-impact retained findings, decision requests and
Windows/live gaps. State that the GENERAL REVIEW is complete to its recorded
coverage and that Windows execution remains separate. Then STOP. Wait for my
package approval before implementation and a separate invocation before Windows
execution. Do not start either as an automatic follow-up.
```

## Prompt 2 — Later, separate Windows review

Run this only in a separately started Windows session after Prompt 1 has produced
its handoff. The generated `WINDOWS_HANDOFF.md` will contain the specific candidate
and observation packet. This starter intentionally requires no machine-specific
paths or credentials in this saved document.

```text
Perform the separate WINDOWS REVIEW for Lineup Desktop. Do not implement fixes.
Docker is excluded. This invocation authorizes review, safe verification/build
outputs, isolated synthetic probes and planning artifacts; it does not approve
remediation packages, deployment, publication or real-account/system changes.

Read this checkout's AGENTS.md, CLAUDE.md, .agents/project.md, then locate the
completed general review's REPORT.md, REMEDIATION.md and WINDOWS_HANDOFF.md under
docs/reviews/comprehensive-review-*/. Use the review I identify, or a unique handoff
whose target matches this checkout. If the intended handoff/target is ambiguous,
ask me to select it; do not silently take the newest dated folder or another
historical Windows campaign. Treat that folder as REVIEW_DIR.

Apply repo-production-review, the relevant installed specialist rubrics,
review-code, verify-code and repo-review-evidence-calibration. Use
repo-production-remediation-plan for the final Windows remediation artifact.
Carry forward general findings as attributed evidence; concentrate on its Windows
handoff, platform-specific execution and uncovered native/build/package paths.
Perform a wide Windows-surface scan and deep inspection of high-risk owners even
where the general review found no material defect. Do not rerun unrelated portable
checks just to repeat the general review.

Resolve the actual checkout/full SHA/dirty state and compare relevant source,
tests, dependencies, engine patch, metadata and runtime inputs with the handoff.
If they changed, identify affected conclusions and revalidate them; do not label
old evidence as a new candidate result. Preserve existing work and prior reports.
Do not change branches or force a clean tree. Build/package acceptance needs a
clean exact candidate under the repository's existing policy; use an available
clean candidate checkout, or record that prerequisite. Do not hide/stash/commit
review artifacts or relax dirty-tree checks to manufacture package eligibility.

Keep product source, permanent tests, configs, dependencies, goldens, engine
patches and security controls unchanged. New probe source/fixtures/sanitized logs
belong only under a unique gitignored build/review-probes/<run>-windows/ path;
verify git check-ignore before writing. Document normal tool-owned temporary,
cache/build/package outputs before execution and preserve prior artifacts.
Use synthetic fixtures and dedicated authorized media/accounts. Keep private
paths/titles, credentials, URLs/headers and raw diagnostics out of reports.

Read docs/DEVELOPMENT.md, docs/windows-native-validation.md,
docs/windows-runtime.md, tool/windows/build-metadata.psd1, the actual launch/build/
package scripts and the handoff's relevant decision/acceptance records. Discover
the pinned SDK, prepared libmpv and patched-engine paths on this host; do not use
an arbitrary PATH Flutter or substitute runtimes. Record Windows version, actual
OS timezone, tool/runtime identities, GPU/driver, displays/scaling/HDR state,
input devices, build identity and eventual package hashes without private data.
Do not change the OS timezone merely to make tests pass; Windows TZ alone is
insufficient. If prerequisites are missing, continue available inspection and
record exactly which execution remains blocked.

Select documented commands appropriate to the remaining claims. With their
prerequisites satisfied, the repository's existing commands include:
  flutter test <relevant-test-paths>
  pwsh -File ./tool/windows/verify-release-policy.ps1
  flutter build windows
  cmake --build .\build\windows\x64 --config Release --target track_list_encoder_test
  ctest --test-dir .\build\windows\x64 -C Release -R '^track_list_encoder$' --output-on-failure --timeout 30
  cmake --build .\build\windows\x64 --config Release --target authenticated_reference_test
  ctest --test-dir .\build\windows\x64 -C Release -R '^authenticated_reference$' --repeat until-fail:3 --verbose --timeout 180
  pwsh -File .\tool\windows\run.ps1
  pwsh -File .\tool\windows\run.ps1 -MediaPath <authorized-local-sample>
  pwsh -File .\tool\windows\build-release.ps1 -EngineSource <verified-engine-source>
  pwsh -File .\tool\windows\package.ps1 -Destination <unique-build/package-destination>
Resolve placeholders from this host and the documented prerequisites; do not run
the list blindly. Coordinate compiler/build/engine resources serially. Neither
native CTest is currently in the default build or CI. The authenticated-reference
harness uses production native loading with synthetic HTTPS and null outputs;
positive controls require progress AND absence of later rejection. Keep production
reference protections intact; do not perform an unhardened before/after mutation
during this review. Stock-engine compilation is not a runnable player; headless
harness success is not physical GPU, Plex, composition or package acceptance.

Execute the handoff's prioritized observations, supplemented by concrete newly
identified Windows risks. Cover the applicable Windows GPU/runtime/media, display,
native lifetime/threading, input/accessibility, filesystem/credential-store and
package contracts. Distinguish runtime media facts from observed display output.
Do not expect planned HDR matching or transcoding to work unless this target now
implements them under approved contracts. Mark scenarios requiring absent features
or hardware accurately instead of simulating acceptance.

For physical/live work, give me one bounded setup/action at a time and wait for my
observation. Record Pass, Fail or Blocked/not run with exact identity and neutral
facts. Never invent visible frames, audio, HDR display state, focus, remote-key,
network or shutdown outcomes. Handle input through the actual application where
that is the claim. Controlled cache starvation, interrupted loads, credential
containment and malformed network fixtures must remain isolated; explain needed
real-account or system changes and obtain appropriate authorization first.
Loader-absent tests belong only in an authorized disposable Windows environment;
do not remove driver/runtime components from the user's normal machine.

Maintain W-E-... evidence and W-F-... new finding IDs, and reference inherited
general F-... IDs without renumbering them. Apply CONFIRMED/LIKELY/HYPOTHESIS
separately from type, severity and confidence. A hypothesis needs the exact
remaining observation that would settle it. Calibrate against real reachability,
existing guards/tests, known limitations, approved decisions and counterexamples.
Use primary, version-appropriate external sources for platform/API claims.
Report exact commands/input identities, results/skips, runtime observations,
unexecuted scenarios and evidence limitations. Do not call missing evidence itself
a demonstrated runtime defect or general-review completion a release approval.

Write new REVIEW_DIR/windows/REPORT.md and REVIEW_DIR/windows/REMEDIATION.md,
preserving the general artifacts. If that subdirectory already holds another run,
use a unique Windows run subdirectory and name it. The Windows report must include
the source/runtime/package identity, native/source coverage, each requested
observation and outcome, new findings, explicit confirmed/rejected/downgraded/
still-open dispositions for inherited findings, and "Needs my decision" and
"Needs physical/live observation" lists for whatever remains.

Use repo-production-remediation-plan to propose coherent Windows packages for
calibrated retained findings, referencing any existing general package instead of
duplicating it. Include evidence gates, dependencies, decisions, risks, rollback
and exact physical/package acceptance. Accepted for planning does not mean
approved for implementation. Park hypotheses and unresolved decisions.

Verify artifacts and authorized file changes. Return links to the Windows report
and plan, summarize their effect on general findings, and identify remaining
acceptance or decisions. Then STOP. No fixes, permanent tests, patches, commits,
publication or implementation dispatch until I approve specific packages.
```
