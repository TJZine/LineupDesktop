# Lineup Desktop

Read `docs/DEVELOPMENT.md` and `docs/architecture.md` before substantial work.

- Flutter/Dart owns application and product logic. Flutter owns UI, Guide,
  input, focus, overlays, and accessibility.
- C++ owns only genuinely native media and platform behavior. libmpv is the
  media engine; Windows native presentation with DirectComposition is the
  target video architecture.
- `initial-build` is historical reference, not a compatibility target. Inspect
  it with `git show origin/initial-build:<path>` when needed.
- Inspect the real flow before editing. Fix root causes, keep one authoritative
  owner per responsibility, and delete obsolete alternatives.
- Use Codanna for unknown native-code owners, callers, and impact when available;
  confirm important results in source and use `rg`/direct reads for exact queries.
  Codanna does not currently parse Dart, so never treat its native-only index as
  coverage of Flutter application logic.
- Do not add speculative abstractions, compatibility layers, or dependencies.
  Interfaces require a real platform, test, or ownership seam. Do not default
  to event buses, service locators, DI frameworks, repository layers, plugin
  architectures, or browser/WebView application UI.
- Prefer the simplest complete solution, but choose localized complexity when
  evidence shows a material correctness, reliability, quality, performance,
  security, accessibility, maintainability, debugging, integration, or total
  ownership advantage.
- Observe risk-matched verification. Hardware, HDR, and DirectComposition
  claims require Windows evidence.
- Independent review is user-controlled, never automatic. At closeout, state
  whether independent review is specifically recommended.
