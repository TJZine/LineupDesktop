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
| Application or UI work | [Architecture](architecture.md) | [Product Parity](product-parity.md) and [Portable UI Parity](ui-parity.md) |
| Channel Studio implementation or investigation | [Channel Studio Specification](channel-studio-spec.md) | [Channel Studio Implementation Plan](channel-studio-implementation-plan.md), [Product Parity](product-parity.md), and [Architecture](architecture.md) |
| Windows media, runner, or packaging work | [Windows Native Acceptance](windows-native-validation.md) | [Development](DEVELOPMENT.md) and [Windows Runtime Provenance](windows-runtime.md) |
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
  implementation boundaries, and acceptance criteria for the planned
  Desktop-specific channel workspace.
- [Channel Studio Implementation Plan](channel-studio-implementation-plan.md)
  records the reviewed implementation slices, Ponytail constraints,
  orchestration protocol, verification gates, and handoff requirements for the
  planned work.
- [Windows Runtime Provenance](windows-runtime.md) records exact native runtime
  sources, hashes, licenses, package policy, and unresolved redistribution
  gates.

## Documentation authority

Current source and freshly observed evidence outrank old prompts, screenshots,
commit descriptions, and historical audit sections.

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
