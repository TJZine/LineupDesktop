# Lineup Desktop

Read `docs/README.md`, `docs/DEVELOPMENT.md`, and `docs/architecture.md` before
substantial work. Use `docs/user-guide.md` for current user-facing behavior and
`docs/windows-native-validation.md` for physical Windows evidence.

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
- Observe risk-matched verification. Hardware, HDR, DirectComposition, native
  video layering, fullscreen, focus/input, and packaging claims require
  physical Windows evidence at the exact tested commit.
- Keep documentation claims calibrated: distinguish implemented,
  deterministically tested, platform validated, and supported behavior.
  Historical audit sections retain their original evidence boundaries.
- Never include Plex credentials, token-bearing URLs, private media metadata,
  personal paths, or unredacted logs/screenshots in documentation or evidence.
- Independent review is user-controlled, never automatic. At closeout, state
  whether independent review is specifically recommended.
