# Lineup Desktop Documentation

This index separates user guidance, contributor instructions, architecture
records, and platform-acceptance evidence so each document has one clear
audience and purpose.

## Choose a starting point

| Audience or task | Start here | Continue with |
| --- | --- | --- |
| Private tester or future end user | [User Guide](user-guide.md) | [Windows Native Acceptance](windows-native-validation.md) when participating in hardware testing |
| New contributor | [Contributing](../CONTRIBUTING.md) | [Development](DEVELOPMENT.md) and [Architecture](architecture.md) |
| Product, parity, or release planning | [Product Parity](product-parity.md) | [Architecture](architecture.md) and [Portable UI Parity](ui-parity.md) |
| Application or UI work | [Architecture](architecture.md) | [Approved interface system](../.interface-design/system.md), [Product Parity](product-parity.md), and the affected source/tests; historical parity records only when relevant |
| Async, persistence, or credential work | [Architecture](architecture.md#changing-asynchronous-and-persisted-state) | Credential/diagnostic contracts in [Implemented now](architecture.md#implemented-now) and the linked owner tests |
| Channel Studio implementation or investigation | [Desktop UI target specification](desktop-ui-design-spec.md) | [Architecture](architecture.md), current source/tests and the design-only [delivery plan](desktop-ui-implementation-plan.md); historical Studio documents are absent from this checkout |
| Windows media, runner, or packaging work | [Development verification map](DEVELOPMENT.md#verification-by-task) | [Architecture](architecture.md#windows-presentation-and-ownership), [Windows Runtime Provenance](windows-runtime.md), and relevant [physical acceptance](windows-native-validation.md) scenarios |
| Planned audio passthrough work | [Architecture](architecture.md) and current source | [Windows Native Acceptance](windows-native-validation.md); the previously indexed passthrough specification is absent, so do not infer an approved plan from this index |
| Planned automatic fullscreen HDR work | [Fullscreen HDR Presentation Specification](fullscreen-hdr-spec.md) | [Windows Native Acceptance](windows-native-validation.md), [Architecture](architecture.md), and the current source |
| Deferred Guide freshness / collection investigation | [Guide Freshness and Collection Revalidation Investigation](guide-freshness-collection-investigation.md) | [Architecture](architecture.md), the current source, and its cited upstream evidence |
| Guide/PiP implementation or investigation | [Desktop UI target specification](desktop-ui-design-spec.md) | [Architecture](architecture.md), [interface system](../.interface-design/system.md) and current source; target design is not implemented evidence |
| Security report | [Security Policy](../SECURITY.md) | Use the private reporting route; never open a public issue containing secrets |

## Current operational documents

### User and tester documentation

- [User Guide](user-guide.md) explains installation of a private portable build,
  first-run setup, navigation, keyboard/remote controls, settings, diagnostics,
  known limitations, and safe issue reporting.
- [Windows Native Acceptance](windows-native-validation.md) defines the
  physical-machine campaign that must be executed before Windows playback,
  HDR, packaging, or release-readiness claims are promoted.

### Contributor documentation

- [Contributing](../CONTRIBUTING.md) covers branch targeting, architecture
  constraints, security expectations, validation, commits, pull requests, and
  documentation standards.
- [Development](DEVELOPMENT.md) is the toolchain and build authority, including
  the exact Flutter revision, native Windows prerequisites, pinned libmpv
  preparation, and local-engine commands.
- [Architecture](architecture.md) is the current ownership and dependency
  authority for Flutter/Dart, C++, libmpv, DirectComposition, persistence,
  diagnostics, and application state.

### Evidence and design records

- [Desktop UI Design Specification](desktop-ui-design-spec.md) contains the
  consolidated approved target. It does not authorize implementation or claim
  that the design has been implemented.
- [Desktop UI Implementation Plan](desktop-ui-implementation-plan.md) maps the
  delivery packages, owners, migration safeguards and worker/reviewer verification.
- [Desktop UI orchestration handoff](desktop-ui-orchestration-handoff.md) supplies
  worker/Luna assignment rules, grouped reviews and the new-session start prompt.
- [Desktop UI readiness review](desktop-ui-readiness-review.md) records the
  independent reviewer findings, corrections and P0-ready/P1-gated verdict.
- [Desktop UI visual evidence](design/desktop-ui/README.md) identifies approved
  synthetic compositions and later refinements; [design history](desktop-ui-design-history.md)
  preserves superseded discussion separately from active requirements.

- [Product Parity](product-parity.md) is the authoritative current
  bidirectional product-parity, UX/UI, evidence-gap, and release-readiness
  audit. Use it for current classifications and backlog priority.
- [Portable UI Parity](ui-parity.md) is a detailed historical evidence record
  for the portable UI campaigns. Its classifications belong to the named
  campaign sections and must not be generalized into Windows support claims.
- Historical `guide-pip-composition-spec.md`, `channel-studio-spec.md` and
  `channel-studio-implementation-plan.md` were previously indexed but are absent
  from this checkout. Use current source and architecture for baseline behavior,
  and the Desktop UI specification for the approved future direction. Do not
  treat missing documents as evidence of implementation or validation.
- [Windows Runtime Provenance](windows-runtime.md) records exact native runtime
  sources, hashes, licenses, package policy, and unresolved redistribution
  gates.
- Historical `audio-passthrough-spec.md` is also absent. Its former index entry
  is not an executable plan or proof of compressed-bitstream support; investigate
  current source and physical Windows evidence before any such work.
- [Fullscreen HDR Presentation Specification](fullscreen-hdr-spec.md) records
  the planned automatic HDR/SDR fullscreen contract, composition decision gate,
  ownership boundary, and required physical Windows evidence.
- [Guide Freshness and Collection Revalidation Investigation](guide-freshness-collection-investigation.md)
  records two deferred, evidence-led Guide risks: collection/source freshness
  after cold start or automation, and shuffled schedule continuity across Plex
  response reorderings. Its upstream references are investigation context, not
  a Desktop porting mandate.

## Documentation authority

Current source and freshly observed evidence outrank old prompts, screenshots,
commit descriptions, and historical audit sections.
Completed plans and issue-specific implementation restrictions do not prescribe
execution for a new task. Preserve still-approved product/design contracts,
including the [protected Player layouts](../.interface-design/system.md#player-protected-baseline).

Use these terms precisely:

- **Implemented**: the current source contains the behavior.
- **Deterministically tested**: an automated test exercised the relevant public
  contract.
- **Platform validated**: the behavior was observed on the named operating
  system, hardware, and commit.
- **Supported**: the project is prepared to make a user-facing compatibility
  commitment and has documented prerequisites and recovery guidance.

An implemented or compiling path is not automatically platform validated or
supported. Native video, HDR, hardware decode, DirectComposition, packaging,
focus, and input claims require physical Windows evidence at the exact commit
being evaluated.

## Documentation standards

Documentation changes should:

1. Name the intended audience and current status.
2. Link to the authoritative owner instead of duplicating volatile version pins
   or long setup procedures.
3. Distinguish current behavior from planned, historical, or unverified work.
4. Use exact commands only when they have an observable success condition.
5. Describe failure and recovery behavior, not only the happy path.
6. Avoid credentials, tokenized URLs, private media metadata, personal paths,
   and unredacted logs or screenshots.
7. Update navigation links when files are added, renamed, superseded, or
   archived.

Before adding a new document, prefer improving an existing authoritative
document unless the new material serves a genuinely different audience or
lifecycle.
