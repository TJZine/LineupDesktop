---
name: dart-flutter-quality
description: Use when implementing or refactoring LineupDesktop Dart/Flutter behavior involving feature ownership, typed boundaries, asynchronous state, persistence, diagnostics, or resource lifetimes. Native-only C++ work uses the repository's native contracts.
---

# Dart and Flutter Quality

Keep the change in the owner of its policy, state, and lifetime. Apply the
[architecture practice](../../../docs/DEVELOPMENT.md#architecture-practice)
to the affected design; this skill does not initiate a repository-wide cleanup.

## Ownership and types

- Keep product policy in Dart and interaction, focus, semantics, and overlays in
  Flutter. Use `NativePlayer` for native media/platform operations; do not expose
  mpv handles or platform-channel payloads to views. Resolve an uncertain seam
  from [accepted ownership](../../../docs/architecture.md#accepted-ownership).
- Reuse the shared channel resolver and scheduler for Studio, Guide, and Player.
  Similar-looking view code need not share an abstraction, but the same scheduling
  rule must not acquire a second implementation.
- Translate untrusted Plex, persisted JSON, and method-channel values into typed
  models at their existing boundary. Do not use `dynamic`, unchecked casts, `!`,
  or mutable property bags to hide an unresolved state. Use focused outcome types
  only when callers actually need to distinguish outcomes.
- Prefer constructor-supplied collaborators or function callbacks at real seams.
  Avoid an abstract class for a single callback or static-only utility classes;
  see [Effective Dart design](https://dart.dev/effective-dart/design) for disputed
  API choices. Preserve a substitute's failure and lifecycle contract as well as
  its successful return values.

## Async state and resources

- Reuse each owner's currentness authority. The application operation epoch and
  committed content generation have different meanings; do not replace both with
  widget `mounted` checks. Guard late success, failure, and cleanup that could
  overwrite newer state. Abort obsolete IO where the transport supports it.
- For mutations, preserve the controller transaction queue, the store's file-write
  queue, and the separate credential queue. They protect different races. For
  schema changes, exercise previously valid saved data before calling a stricter
  decoder safe. Read the affected
  [async/persistence contract](../../../docs/architecture.md#changing-asynchronous-and-persisted-state).
- Give timers, subscriptions, pending futures, isolates, and native sessions an
  explicit cleanup owner. A displayed playback error does not discharge native
  cleanup. When changing the adapter, preserve separate lifecycle, load, and stop
  identities and readiness/idle acknowledgments; consult
  [native lifetime](../../../docs/architecture.md#windows-presentation-and-ownership).
- Keep secrets out of ordinary UI state and diagnostics. Producers emit fixed
  safe messages and normalized facts; the logger does not sanitize arbitrary
  exception text. Preserve authenticated HTTPS and redirect restrictions at the
  relevant transport boundary.
- For expensive catalog/Guide work, measure the affected path and reuse existing
  schedule-worker and bounded-cache owners. Do not add a second scheduler, generic
  job framework, or cache without a demonstrated bottleneck and invalidation rule.

For UI changes, use the relevant approved decisions in
[the interface system](../../../.interface-design/system.md), including protected
Player layouts. Select proof from
[verification by task](../../../docs/DEVELOPMENT.md#verification-by-task);
portable contract results do not establish native Windows behavior.
