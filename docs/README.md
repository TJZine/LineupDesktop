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
| Channel Studio implementation or investigation | [Channel Studio Specification](channel-studio-spec.md) | [Architecture](architecture.md) and current source/tests; the [completed plan](channel-studio-implementation-plan.md) only for historical evidence |
| Windows media, runner, or packaging work | [Development verification map](DEVELOPMENT.md#verification-by-task) | [Architecture](architecture.md#windows-presentation-and-ownership), [Windows Runtime Provenance](windows-runtime.md), and relevant [physical acceptance](windows-native-validation.md) scenarios |
| Planned audio passthrough work | [Audio Passthrough Specification](audio-passthrough-spec.md) | [Windows Native Acceptance](windows-native-validation.md), [Architecture](architecture.md), and the current source |
| Planned automatic fullscreen HDR work | [Fullscreen HDR Presentation Specification](fullscreen-hdr-spec.md) | [Windows Native Acceptance](windows-native-validation.md), [Architecture](architecture.md), and the current source |
| Deferred Guide freshness / collection investigation | [Guide Freshness and Collection Revalidation Investigation](guide-freshness-collection-investigation.md) | [Architecture](architecture.md), the current source, and its cited upstream evidence |
| Guide/PiP implementation or investigation | [Guide PiP Specification](guide-pip-composition-spec.md) | [Architecture](architecture.md) and the current source |
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

- [Desktop UI Design Specification](desktop-ui-design-spec.md) records the
  current refinement campaign's locked decisions and remaining design work.
  The full package is not yet locked or authorized for implementation.
- [Desktop UI Implementation Plan](desktop-ui-implementation-plan.md) is the
  associated planning scaffold and future worker/reviewer handoff contract.

- [Product Parity](product-parity.md) is the authoritative current
  bidirectional product-parity, UX/UI, evidence-gap, and release-readiness
  audit. Use it for current classifications and backlog priority.
- [Portable UI Parity](ui-parity.md) is a detailed historical evidence record
  for the portable UI campaigns. Its classifications belong to the named
  campaign sections and must not be generalized into Windows support claims.
- [Guide PiP Specification](guide-pip-composition-spec.md) records the
  implemented responsive composition, ownership boundaries, and physical
  Windows proof still required for Guide/PiP behavior.
- [Channel Studio Specification](channel-studio-spec.md) records the locked
  product direction, ownership semantics, authoring UX, Air Check contract,
  implementation boundaries, acceptance criteria, and deterministic evidence
  for the implemented Desktop-specific channel workspace.
- [Channel Studio Implementation Plan](channel-studio-implementation-plan.md)
  is a historical record of the completed implementation campaign. Its agent
  assignments, review gates, and handoffs applied to that campaign only; use
  the current specification and source for new work.
- [Windows Runtime Provenance](windows-runtime.md) records exact native runtime
  sources, hashes, licenses, package policy, and unresolved redistribution
  gates.
- [Audio Passthrough Specification](audio-passthrough-spec.md) records the
  deferred default-off Settings feature, native ownership boundary, discovery
  gate, implementation checklist, and physical Windows evidence required before
  compressed bitstream output can be claimed.
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
