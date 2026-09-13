# Post-refresh maintenance

User authorization: improve Windows launch/package usability, repair the current
non-golden CI failure, reduce goldens to a small useful set, and update dependencies
as far as current compatibility evidence supports. Use sequential fresh Luna/xhigh
implementation tasks in the existing checkout; Astra supplies the decisions,
reviews results, verifies and commits. No worktrees or automatic reviewers.

## Work sequence

1. Small Windows development launcher and clear portable-package instructions.
   Reuse the provisioned patched engine and existing release/package scripts.
   Environment defaults may remember local paths; no new configuration framework.
2. Repair the Settings overflow at800x600/text200 reported by CI, preserving the
   locked1080 appearance. Reduce mandatory goldens to representative Guide,
   Player and Settings coverage, preserving meaningful behavior assertions and
   capture tooling. Astra selects exact retained cases before dispatch.
3. Dependency upgrades after Astra's current upstream/version/compatibility
   assessment. Include Dart dependencies/transitives, Flutter/Dart, CI actions and
   native/toolchain pins in the inventory. Prefer latest stable compatible
   versions; don't bypass SDK constraints or integrity/native-engine contracts.
   Explain any retained pin rather than silently omitting it.

## Starting evidence

Base137b0778c774aea162a206d2dfbd4b41ac3bf923. GitHub PR41 latest run34734716604:
Verify Dart803passed/1failed; theme_shell_test accessible theme check reports an
8.7px horizontal overflow at800x600/text200, reproduced locally at8.8px.
Windows application build/tests and release-policy checks passed. Golden failures
are known; the running patched-engine job is outside this CI-failure diagnosis.

The dependency inventory currently reports secure-storage11.0.0 ->11.1.1 plus
three compatible platform updates. Other reported newer transitives are blocked
by existing package/SDK constraints and require explicit assessment.

## Status

Planning and source inspection complete for the Windows launcher unit; remaining
units await sequential implementation and assessment. No physical Windows build
or launch validation is implied by portable checks.
