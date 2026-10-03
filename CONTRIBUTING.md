# Contributing to Lineup Desktop

Lineup Desktop is a pre-release Flutter-native desktop application with a narrow
Windows C++/libmpv boundary. Contributions should improve the current
architecture rather than preserve the historical Electron implementation.

Resolve the target and base from the current task, issue, or pull request
metadata. Do not infer the active development target from an old branch name.
If those sources leave a consequential base choice unresolved, clarify it
before creating or retargeting a branch or pull request.

## Before contributing

Start with [AGENTS.md](AGENTS.md), then read the relevant workflow and ownership
sections it names. Use the [documentation index](docs/README.md) when the right
authority is unclear. Read Windows acceptance and runtime provenance sections
when the task involves native behavior, packaging, or support claims; broaden
reading when an invariant remains unclear.

The preserved Electron implementation is on `electron-ui`; use the immutable
`bfaee636748f2a0d442f3690b7ba5262d32ff17c` baseline when provenance matters.
The `initial-build` branch is a later historical Flutter-replatform milestone.
Neither is a compatibility target; inspect the source that matches the evidence
being investigated.

## Architecture constraints

[Architecture](docs/architecture.md#accepted-ownership) owns the current
responsibility boundaries; the [project profile](.agents/project.md) maps
source entry points and task-specific contracts. Flutter/Dart owns application
and interaction policy. Native code owns libmpv and Windows platform mechanisms.
Preserve the relevant behavior, security, lifetime, and data obligations when
replacing an implementation. Historical structure is not a reason to retain
duplicate policy or a displaced compatibility path.

## Development setup

Use the exact Flutter revision and task-specific prerequisites documented in
[Development](docs/DEVELOPMENT.md). Do not silently substitute a newer SDK,
engine, patch, or media runtime when validating repository behavior.

Commands and evidence boundaries live in
[Development's verification map](docs/DEVELOPMENT.md#verification-by-task).

## Change design and review

Use the current [agent entry](AGENTS.md) and shared skills for agent-assisted
work. Investigate the actual owner and affected contracts before changing a
design. The project profile identifies relevant product/UI approvals and
native obligations; those are distinct from historical agent dispatch rules.

Independent tasks may run concurrently with explicit write ownership and stable
verification inputs. Keep one Git/integration owner. Review depth follows the
changed risk, not a required number of agents or repeated passes. The shared
`review-code` process adjudicates findings, including bot findings, against
the actual source and evidence.

## Tests and validation

Use [the project verification profile](.agents/project.md#verification-selection)
and [Development's command map](docs/DEVELOPMENT.md#verification-by-task).
The shared `verify-code` skill owns general evidence selection. Preserve each
relevant obligation without requiring duplicate tests or automatic new tests
for every changed file. Documentation-only changes need structural and claim
checks, not product test reruns.

Record what was actually checked, the source/build identity, and material
limits. Missing physical Windows evidence limits the particular native or
support claim; it does not block unrelated portable work. Compilation alone
does not establish native presentation, HDR, hardware decode, physical input,
or package runtime behavior. Evidence reuse follows the project profile;
an old observation is never relabeled as a newly executed candidate run.

## Security and private data

Never commit or post:

- Plex tokens or authorization headers;
- token-bearing media or artwork URLs;
- credential-store output;
- private media metadata not required for a minimal reproduction;
- personal filesystem paths; or
- unredacted diagnostics, crash dumps, screenshots, or recordings.

Report vulnerabilities through [SECURITY.md](SECURITY.md), not a public issue.

## Documentation changes

Documentation is part of the product. A documentation change should:

- name its audience and status;
- distinguish implemented, deterministically tested, platform validated, and
  supported behavior;
- link to the authoritative version or provenance owner instead of duplicating
  volatile pins;
- include failure and recovery behavior;
- keep navigation links current; and
- use synthetic or deliberately redacted examples and screenshots.

When behavior changes, update the smallest authoritative document in the same
pull request. Do not rewrite historical audit sections to imply evidence they
did not observe.

## Commits and pull requests

Use coherent conventional commits such as:

```text
feat(guide): add ...
fix(player): prevent ...
docs: clarify ...
test(channels): cover ...
ci: gate ...
```

A pull request should explain:

- the user or maintainer problem;
- the ownership and architecture decision;
- what changed and what was intentionally not changed;
- validation actually performed;
- platform evidence still missing;
- security, accessibility, performance, and packaging effects when relevant;
  and
- rollback or recovery considerations for consequential changes.

Keep the diff focused. Do not merge a native-media change solely because CI
compiled it. Apply the shared review policy and the project's native/security
risks. Read-only review may run within the authorized workflow; merge,
publication, and other consequential external actions retain their actual
authorization requirements.

## Reporting issues

Use the repository issue templates and include the operating system, exact
commit or package build information, reproduction steps, expected and actual
behavior, and only redacted diagnostics. User-facing troubleshooting is in the
[User Guide](docs/user-guide.md).
