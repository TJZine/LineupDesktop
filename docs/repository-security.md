# Repository security and activation

Gate 1 covers activating and testing repository protections. Obtain maintainer
authorization after the proposed checks pass on the reviewed commit. This
document describes repository settings and source checks.

## Required source checks

The stable `Required CI checks` job in `.github/workflows/ci.yml` requires these
unconditional jobs to succeed:

- `verify`
- `android`
- `build-macos`
- `macos-player-core`
- `windows-release-policy`
- `build-windows`
- `release-inputs`

It also evaluates `windows-engine-tests` and `build-windows-engine` according to
the explicit `engine-required` and `package-required` outputs from
`release-inputs`. The aggregate runs with `if: always()`, so missing decisions,
cancellation, unexpected skips, and failure fail the aggregate. Advisory
state changes over time, so review it separately from the required
checks. Windows engine tests may skip only when `engine-required` is
explicitly `false`. The patched-engine/package build may skip only when both
release-input outputs are explicitly `false`.

Run the source-level aggregation fixtures from the repository root:

```sh
python3 -m unittest discover -s tool/ci -p '*_test.py'
```

These fixtures establish decision logic and workflow wiring. They do not
establish GitHub enforcement.

## Gate 1 activation and observed enforcement

1. Review the full source commit. Observe a successful `Required CI checks` run
   for that commit and a completed Security workflow with the actual CodeQL
   check names. Resolve configuration failures before requiring checks. Do not
   require Security workflow checks or code-scanning merge protection until
   those checks have run green and their names are stable.

2. In GitHub repository settings, create an active branch ruleset for the
   default branch. Require pull requests, zero approvals while solo-maintained,
   resolved review conversations, up-to-date branches, and the observed
   `Required CI checks` source. Bind required checks to GitHub Actions where the
   ruleset supports the expected integration. Restrict deletion and force
   pushes, apply the rules to administrators, and keep the routine bypass list
   empty.

   Do **not** enable **Require review from Code Owners** or **Require approval
   of the most recent reviewable push** while `CODEOWNERS` contains `* @TJZine`:
   either setting blocks a sole maintainer from merging.

3. Create an active tag ruleset for both `v*` and `runtime-*`. Restrict tag
   updates and deletions, retain the ability to create a new reviewed release
   tag, and enable immutable releases before any public release. A published
   immutable tag stays fixed. Corrections use a new version.

4. Enable private vulnerability reporting for the form linked from [SECURITY.md](../SECURITY.md).
   Enable the dependency graph, Dependabot alerts and security updates, secret
   scanning and push protection, and code scanning using the committed advanced
   workflow. The Dependabot policy disables version-update PRs for Pub and Gradle
   with `open-pull-requests-limit: 0` and retains security updates. GitHub
   Actions updates run monthly in one group.

5. Keep no payment method on the account and confirm the usage-blocking budget
   posture before enabling hosted work. Set repository artifact retention to
   allow the workflow limits of 30 days for the Windows ZIP, 14 days for the
   unsigned Android artifact, and 1 day for the signed Android artifact.
   Mark the `runtime-mpv-…` release as **not Latest** so the runtime download
   stays separate from the latest application release. See [GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions).

6. Read back branch and tag rules, required-check sources, Dependabot settings,
   security settings, artifact retention, and immutable-release state through
   GitHub UI or REST. Record repository, full source SHA, rule IDs, observed
   settings, and date in ordinary release evidence. A prepared file is
   insufficient.

7. With separately authorized disposable refs or pull requests, demonstrate
   failed-check merge rejection, direct protected update/force-push/deletion
   rejection, and release tag retarget/deletion rejection. Review each canary's
   scope before mutation and clean up only allowed disposable refs.

If emergency administration is necessary, record why and exactly which rule was
temporarily changed. Restore it and read back the original rule. Do not leave a
standing routine bypass. Preserve unrelated ownership rules. The current
`CODEOWNERS` owner is `@TJZine`.

### Ruleset cautions

- Renaming the `Required CI checks` job requires updating the ruleset in the
  same change window.
- A skipped job can count as success for a dependency, but a workflow that does
  not run at all leaves a required check pending.
- Do not require a Security workflow job or code-scanning result before its
  hosted name and successful behavior are established.
- Keep release tag patterns `v*` and `runtime-*` protected.

## Advisory coverage and gaps

`tool/security/osv-scan.sh` downloads pinned OSV-Scanner 2.7.1 release bytes,
checks the committed upstream digest, runs live affected/fixed Pub controls, and
scans explicit committed inputs. The scheduled Security workflow scans only the
current `pubspec.lock`. Scanner failures and vulnerabilities fail visibly.
Network or API errors cannot satisfy the affected/fixed controls.

Run the Pub scan locally from the repository root:

```sh
tool/security/osv-scan.sh --lockfile=pubspec.lock
```

Gradle verification metadata is a conservative release-time inventory because
it includes historical and build-tool coordinates. It is no longer a scheduled
required job and does not prove runtime resolution. During release review, run:

```sh
tool/security/osv-scan.sh --lockfile=android/gradle/verification-metadata.xml
```

Review the result against the resolved Android graph and
`runtime-dependencies.txt` from the CI artifact. Record unavailable package
ecosystems or tool errors as gaps, with equivalent manual advisory review when
needed. Never label a failed or unavailable scan clean.

## Code-scanning coverage and caveats

CodeQL covers:

- GitHub Actions workflows with `build-mode: none`
- Python release helpers with `build-mode: none`
- C/C++ with `build-mode: none`
- Java/Kotlin through the Android build and JVM tests

The Kotlin job uses KGP 2.4.21 for the CVE fix. The hosted CodeQL Kotlin
extractor's current documented support ends at 2.4.20. If hosted extraction
warns or fails on 2.4.21, do not downgrade KGP. Keep that job outside required
merge checks and record the exact hosted gap and source SHA. For Dart, Pub
advisories, tests, and the analyzer cover distinct obligations.
No macOS physical release gate is added by scanning or existing macOS CI.

No scanner or CodeQL result substitutes for the physical Windows and Android
acceptance rows in [release acceptance](release-acceptance.md), or for the
artifact and publication checks in [release security](release-security.md).

## Pinned inputs and advisory sources

The native dependency inventory already exists in [Windows runtime notices](windows-runtime.md)
and [Android runtime notices](android-runtime.md). Keep those inventories and
existing build metadata current instead of adding a second machine-readable
ledger.

| Pinned input | Authoritative identity | Primary advisory review |
| --- | --- | --- |
| Flutter/Dart and patched Windows engine | `tool/flutter_version.json`, `tool/windows/build-metadata.psd1`, committed engine patches and verified SDK action | [Flutter security advisories](https://github.com/flutter/flutter/security/advisories) and [Dart advisories](https://github.com/dart-lang/sdk/security/advisories) |
| libmpv and statically linked media dependencies | `tool/windows/build-metadata.psd1`, `third_party/libmpv/`, Windows runtime inventory with documented closure limits | [mpv security policy](https://github.com/mpv-player/mpv/security), [FFmpeg security](https://ffmpeg.org/security.html), and each inventoried upstream's advisories |
| Android Media3, OkHttp, Kotlin/Gradle and transitives | Committed Gradle inputs, verification metadata and resolved graphs | [Android security bulletins](https://source.android.com/docs/security/bulletin), [Media3 releases](https://developer.android.com/jetpack/androidx/releases/media3), [OkHttp advisories](https://github.com/square/okhttp/security/advisories), and [GitHub Advisory Database](https://github.com/advisories) |
| Microsoft runtime and SDK/toolchain | Selected toolchain CRT with signature/version/hash evidence | [Microsoft Security Update Guide](https://msrc.microsoft.com/update-guide) |

Before release, review alerts, workflow failures, the actual runtime graph, and
the native inventory advisory sources. Record source/version/date, relevant
findings, mitigation or explicit maintainer disposition, and remaining gaps
with the release checks. Do not create general exceptions to make a failing
scan appear successful.

## Sources and related procedures

The [Dependabot ecosystem reference](https://docs.github.com/en/code-security/reference/supply-chain-security/supported-ecosystems-and-repositories),
[CodeQL build options](https://docs.github.com/en/code-security/reference/code-scanning/codeql/build-options-for-compiled-languages),
and [OSV supported artifacts](https://google.github.io/osv-scanner/supported-languages-and-lockfiles/)
describe coverage limits. The Pub control uses
[GHSA-9v85-q87q-g4vg](https://github.com/advisories/GHSA-9v85-q87q-g4vg), fixed in
archive 3.3.8. Use [release security](release-security.md) for exact artifact
handoff and [release acceptance](release-acceptance.md) for the final platform
pass.
