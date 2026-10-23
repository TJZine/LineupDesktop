# Lineup Desktop Documentation

Start with the current owner for the question. The October 20 reconciliation in
[Open obligations](open-obligations.md) is the single unfinished-work register;
the [Opus 5.5 handoff](handoffs/opus-5-5-core-readiness-handoff.md) supplies current
core/macOS context and TV feasibility boundaries. Dated audits and archived
campaign results retain their original source, build and platform limits.

## Choose a starting point

| Audience or task | Start here | Continue with |
| --- | --- | --- |
| User or private tester | [User Guide](user-guide.md) | [Windows Native Acceptance](windows-native-validation.md) for hardware testing |
| Contributor | [Contributing](../CONTRIBUTING.md) | [Development](DEVELOPMENT.md), [Architecture](architecture.md) |
| Agent-assisted work | [Agent entry](../AGENTS.md) | [Project profile](../.agents/project.md), then affected authorities |
| Pending work or release planning | [Open obligations](open-obligations.md) | Current plans below; [August 23, 2026 product-parity audit](product-parity.md) for dated context |
| Application, async, persistence or credential work | [Architecture](architecture.md) | Current source and linked owner tests |
| UI, Guide, PiP or Studio | [Desktop UI specification](desktop-ui-design-spec.md) | [Interface system](../.interface-design/system.md), retained decision records, current source |
| Native media protocol or macOS port planning | [Native-player protocol](native-player-protocol.md) | [Platform ownership](architecture.md#platform-neutral-native-player-protocol), [macOS backlog](open-obligations.md#macos-media-backlog), [macOS port plan](macos-port-plan.md) |
| Android TV / Fire TV host and sideloading | [Android runtime](android-runtime.md) | [Development](DEVELOPMENT.md#android-tv-development) |
| Windows media, runner or packaging | [Development verification map](DEVELOPMENT.md#verification-by-task) | [Windows presentation](architecture.md#windows-presentation-and-ownership), [runtime provenance](windows-runtime.md), [physical acceptance](windows-native-validation.md) |
| Security report | [Security Policy](../SECURITY.md) | Private reporting route; never include secrets in a public issue |

## Current operational authorities

- [User Guide](user-guide.md): setup, navigation, controls, settings, recovery,
  privacy and limitations.
- [Development](DEVELOPMENT.md): canonical toolchain configuration, commands,
  prerequisites, test tiers, native builds and package evidence boundaries.
- [Architecture](architecture.md): current ownership, platform-neutral seam,
  Windows mechanisms, data, source/schedule, async and privacy contracts.
- [Native-player protocol](native-player-protocol.md): methods, events,
  correlation, lifetime, bounds, token safety and presentation obligations.
  Windows and macOS playback backends are implemented; neither implementation
  alone establishes final platform/package acceptance. Other backends are absent.
- [Windows Native Acceptance](windows-native-validation.md): exact-candidate
  physical-machine scenarios and safety requirements; a procedure, not proof.
- [Windows Runtime Provenance](windows-runtime.md): pinned libmpv/FFmpeg sources,
  hashes, licenses, package policy and redistribution obligations.
- [Open obligations](open-obligations.md): unfinished acceptance and product work,
  deduplicated remaining platform gates, macOS/TV status and full-commit recovery.
- [Agent entry](../AGENTS.md) and [project profile](../.agents/project.md): shared
  workflow routing and repository-specific constraints. `CLAUDE.md` imports the
  same entry; historical dispatch prompts are not current workflow policy.

## Product and design decisions

These records retain approval authority; later explicit supersessions govern
older requirements. Design agreement, implementation, deterministic verification
and physical acceptance are different states.

- [Desktop UI specification](desktop-ui-design-spec.md), [surface approvals](desktop-ui-surface-approvals.md)
  and [second-pass decisions](desktop-ui-second-pass.md) retain the approved
  compositions, including protected Player/OSD/Now Playing layouts.
- [Startup and setup reentry](setup-reentry-startup-plan.md) and
  [Player/Guide polish](player-guide-polish-plan.md) retain October 7 decisions
  and render refinements. Their portable implementation landed; physical
  acceptance remains open. They are retained because they uniquely record live
  approvals and supersessions.
- [Desktop visual evidence](design/desktop-ui/README.md) and the
  [portable 1080p packet](design/desktop-ui/review-packets/README.md) identify
  synthetic evidence for the recorded states, not current Windows acceptance.
- [Fullscreen HDR specification](fullscreen-hdr-spec.md) and
  [implementation plan](fullscreen-hdr-implementation-plan.md) own the enabled
  matching/session/hold/restoration contract. Hardware and package acceptance
  remain pending; the October 9 discovery is archived feasibility evidence.
- [OSD and collection plan](osd-autohide-and-collection-membership-plan.md) and
  [scheduled continuation plan](schedule-continuation-plan.md) retain implemented
  product contracts and outstanding live/physical acceptance.
- [Track-label plan](audio-subtitle-track-label-implementation-plan.md) retains
  accepted P0–P3 evidence, later Player/Guide supersessions and pending P4
  visual, label-to-output and Narrator acceptance.

## Active plans and investigations

- [Direct Play stabilization status](open-obligations.md): current macOS private-beta
  scope, data-format protection, Windows engine integration and remaining acceptance
  gates. Implementation plans are local working documents, not shipped references.
- [Approved Licenses design](handoffs/licenses-design-2026-10-21.md): in-app notices
  presentation, implemented reader/source tooling and remaining candidate delivery gates.
- [Code-quality implementation plan](code-quality-implementation-plan.md):
  portable packages and documentation consolidation (G) integrated and reviewed;
  native restoration work (F) merged for Windows testing, with validation still
  pending. The full plan is not complete. Its native contract and review
  conditions remain live. The closure table records actual integration SHAs.
- [Plex transcoding plan](plex-transcoding-implementation-plan.md): production
  packages, P0b evidence and Settings/product gates remain pending. Headless
  feasibility does not establish integrated playback.
- [Guide freshness/collection investigation](guide-freshness-collection-investigation.md):
  source-order shuffle resolved deterministically; live-session refresh and
  actual membership-change policy remain deferred.
- [Authenticated-reference investigation](libmpv-authenticated-reference-investigation.md):
  pinned native containment and per-load HLS feasibility evidence, with explicit
  production restrictions and physical limits.
- [UX/functionality audit](ux-functionality-audit.md): original observations plus
  dated dispositions, implementations and remaining walkthrough/live acceptance.
- [Feature opportunity report](feature-opportunity-report.md), [Opus research
  request](opus-feature-research-request.md) and [validation findings](feature-validation-findings.md):
  retained feature-track inputs, evidence and maintainer questions; no
  implementation approval.
- [Product Parity — August 23, 2026](product-parity.md): historical audit with
  explicitly dated later updates, not an authoritative current classification.

## Review records with unfinished obligations

- [October 7 review](reviews/comprehensive-review-2026-10-07/REPORT.md) and
  [remediation](reviews/comprehensive-review-2026-10-07/REMEDIATION.md): buffering
  hypothesis and physical acceptance context.
- [October 10 review](reviews/comprehensive-review-2026-10-10/REPORT.md),
  [implementation](reviews/comprehensive-review-2026-10-10/IMPLEMENTATION.md) and
  [Windows handoff](reviews/comprehensive-review-2026-10-10/WINDOWS_HANDOFF.md):
  ancestor-junction policy, native gates and targeted physical observations.
- [Workflow remediation](reviews/workflow-remediation-2026-10-04/REPORT.md),
  [maintainability execution](reviews/maintainability-remediation-2026-10-12/EXECUTION.md)
  and [audit follow-up](reviews/audit-followup-2026-10-12/IMPLEMENTATION.md):
  scoped evidence and unperformed platform checks.
- [Code-quality execution](reviews/code-quality-2026-10-15/EXECUTION.md),
  [combined review](reviews/code-quality-2026-10-15/IMPLEMENTATION_COMBINED_REVIEW.md)
  and [final review](reviews/code-quality-2026-10-15/IMPLEMENTATION_FINAL_REVIEW.md):
  attributed package histories and clear portable code-review closure. Later F
  integration and partial native CI supersede the old unmerged/unexecuted labels;
  the current register retains outstanding lifecycle/physical/package gates.

## Historical material in Git

[The archive recovery and preservation map](open-obligations.md#archive-recovery-and-preservation-map)
provides verified full-commit `git show` commands for the completed desktop UI
implementation/execution/readiness/scaling, portable parity, HDR discovery,
Windows collaborative prompt and code-quality assessment documents. Their live
contracts, open obligations and useful rationale remain in named current owners
or the recoverable snapshots. Links within `docs/reviews/` are historical and
exempt from live dangling-link checks; those records are not rewritten.

Earlier completed prompts, superseded design discussions and the redundant 1080p
packet ZIP also remain in Git. The extracted packet was checked byte for byte
before that earlier cleanup. For example:

```sh
git show 13d711e02b7fa5d4bb3687e138429baa0a768c97:docs/desktop-ui-design-history.md
```

Historical workspace inventories and hash manifests describe their recorded
checkout, not current dependencies. Old execution procedures do not select
models, prescribe review panels, or override current repository instructions.

## Documentation authority and standards

Current source and observed evidence outrank old prompts and screenshots.
Preserve approved product/design contracts, including the [protected Player
baseline](../.interface-design/system.md#player-protected-baseline).

- **Implemented:** behavior exists in current source.
- **Deterministically tested:** an automated check exercised the named contract.
- **Platform validated:** observed on the recorded OS, hardware and commit.
- **Supported:** a user-facing commitment with documented prerequisites/recovery.

Compilation, fake-boundary tests and synthetic images do not establish native
media, HDR, hardware decode, composition, physical input/AT or package execution.
Use the [evidence reuse rules](../.agents/project.md#native-evidence-and-reuse);
never relabel an old run as a newly tested candidate.

Name the audience/status, link current owners for volatile commands and pins,
describe failure/recovery, preserve exact evidence limits, redact private data,
and update navigation when archiving. Prefer the existing authoritative owner
unless new material has a distinct audience or lifecycle.
