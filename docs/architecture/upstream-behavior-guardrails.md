# Upstream Behavior Guardrails

Original Lineup behavior is reference evidence for Desktop planning, not
Desktop architecture truth. Desktop truth lives in this repository's
architecture docs, roadmap, contracts, reviewed plans, tests, fixtures, and
recorded divergence rationale.

Future product-slice plans must consult this guardrail before copying,
adapting, or intentionally diverging from original Lineup behavior. Source
audits are temporary proof only until a Desktop owner exists. When practical,
future plans should convert source audits into Desktop tests or fixtures at the
same time the owner is implemented.

## Guardrail Matrix

| Slice | Preserved Behavior Evidence | Required Desktop Proof Surface | Intentional Divergence Policy | Forbidden Shortcuts |
| --- | --- | --- | --- | --- |
| RD-07/RD-08 player and stream behavior | Original player command, state, event, stale-load, descriptor, URL/header split, track selection, subtitle fallback, stream decision, recoverable/error taxonomy, diagnostic redaction, teardown, and cleanup behavior. | Contract tests, stream-policy fixtures, player adapter tests, source audit only before a runtime owner exists, or explicit divergence rationale. | Divergence must name the Desktop capability profile, security boundary, user-visible behavior change, and replacement proof. | Do not expose raw media URLs, headers, native handles, engine ids, libmpv objects, or webOS constants through renderer-facing state. Do not preserve upstream browser playback assumptions as Desktop capability truth. |
| RD-10 Plex auth/discovery/library | Original PIN and Plex Home auth flows, selected-server and discovery persistence, retry/backoff policy, parser validation, pagination and cancellation, auth/authorization/network error taxonomy, stream metadata, URL/header handling, subtitle delivery, and redacted logging. | Auth/discovery/library tests, parser fixtures, redaction tests, source audit only before an owner exists, or explicit divergence rationale. | Divergence must explain credential custody, persistence ownership, API error mapping, diagnostics, and user recovery behavior. | Do not place Plex tokens, tokenized URLs, auth headers, selected-server secrets, or raw API responses in renderer ownership. Do not mirror localStorage or upstream path mechanics. |
| RD-11 scheduler/channel/content | Original deterministic anchor-time scheduling, loop wrapping, current/next/previous lookup, schedule windows, shuffle seed behavior, block playback validation, channel authoring validation, content resolution, stale fallback, import normalization, transactional updates, cache cloning, persistence queues, and malformed storage recovery. | Scheduler and channel tests, content fixtures, persistence fixtures, source audit only before an owner exists, or explicit divergence rationale. | Divergence must state how deterministic playback, channel persistence, malformed-data recovery, and user-visible schedule continuity are preserved or replaced. | Do not import storage queues, cache shapes, or channel schemas without Desktop ownership. Do not rely on ambient browser storage, mutable shared fixtures, or nondeterministic wall-clock behavior. |
| RD-13 UI/navigation/settings | Original focus registration cleanup, directional repeat, channel-number buffering, modal focus restoration, auth stale async cancellation, EPG virtualization and refresh windows, overlay auto-hide and throttling, settings validation, and persisted preference normalization. | Renderer tests, interaction fixtures, accessibility/focus audits, source audit only before an owner exists, or explicit divergence rationale. | Divergence must identify the Desktop focus model, navigation input model, settings owner, persisted preference migration policy, and user-visible behavior change. | Do not copy TV UI wholesale into privileged renderer paths. Do not couple navigation to upstream DOM globals, stale async ownership, browser storage, or hidden settings side effects. |
| RD-20 reference compatibility | Original Lineup behavior that future Desktop releases still use as compatibility evidence across Plex, scheduler, player, stream, navigation, settings, and diagnostics. | Compatibility review notes, targeted regression tests, fixture refreshes, source audit only where no owner exists, or explicit divergence rationale. | Divergence must be reviewed as a product compatibility decision and must update the relevant architecture, roadmap, contract, or plan owner. | Do not treat upstream source as a live dependency, compatibility shim, package mirror, root barrel, or automatic authority over Desktop architecture. |

## Slice Plan Obligations

Every future product-slice plan that uses original Lineup behavior must name:

- the upstream behavior evidence being preserved
- the Desktop proof surface that will protect it
- any intentional divergence and why Desktop owns that choice
- shortcuts that are explicitly forbidden for that slice

If a source audit is used because the Desktop owner does not exist yet, the plan
must say when that audit should become a test or fixture, or why automated proof
is not practical for that behavior.
