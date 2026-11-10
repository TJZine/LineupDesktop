# Signing and verifying a release

Android and Windows release independently. Production signing and publication
each require maintainer authorization. [Repository security](repository-security.md)
owns GitHub protection activation. The existing [Android runtime](android-runtime.md),
[Windows runtime](windows-runtime.md) and [Windows acceptance](windows-native-validation.md)
instructions retain their platform/build obligations.

## Contexts and prerequisites

Build accounts, dependencies and candidate code must have no access to production
keys, passwords, provider tokens or usable backups. Gate 2 must establish that
isolation, safe recovery material and the Windows signed/explicitly unsigned choice.
Signing later on an account already used for builds does not meet this condition.
Do not rotate the retained Android update key or delete the only recovery copy.

Android candidate signing uses a fresh standard GitHub-hosted Ubuntu runner with
maintained Android SDK build-tools 36.0.0 and Java. Windows signing, when applicable,
uses Windows SDK SignTool, PowerShell 7.4+ and the chosen standard certificate or
provider. Publication uses GitHub CLI with `gh release verify` and `verify-asset`
support.
Python 3.11+ runs the optional [verification helper](../tool/release/verify.py).
Supply absolute paths to independently installed SDK/tools. Check their versions
and official distribution origins during provisioning, separately from candidates.

Install only independently reviewed copies of this helper/runbook in a protected
location, outside candidate directories and Python import/search paths controlled
by candidates. Record the reviewed helper hashes in the operator's ordinary notes.
The integration owner must arrange that independent review before installation.
Invoke the helper using `python3 -I /trusted/release/verify.py ...`; do not run the
copy shipped with an artifact. Never run candidate Gradle, Flutter, scripts,
executables, package verifiers or tests in signing **or publishing** contexts.
Do not use candidate directories as the working directory or put them on `PATH`.
Acceptance happens on separate disposable/assigned hosts without those credentials.

These commands are templates: replace uppercase identities with the selected
values, use new private scratch directories and stop on any failure. Shell examples
use Bash with `set -euo pipefail`; PowerShell examples require
`$ErrorActionPreference = 'Stop'` and explicit checks of native exit codes.
No production commands below are part of the local rehearsal.

## Select the source and CI artifact independently

Record the repository, full reviewed commit, source review, applicable successful
CI run ID, **attempt**, workflow path and numeric artifact ID from GitHub. Inspect
the applicable job results and build logs, including conditional Windows jobs;
overall success alone does not prove that a platform build ran. Select the
artifact by its API identity, not just a familiar artifact name.

```sh
gh run view RUN_ID -R TJZine/LineupDesktop --attempt ATTEMPT --log
gh api repos/TJZine/LineupDesktop/actions/runs/RUN_ID
gh api repos/TJZine/LineupDesktop/actions/runs/RUN_ID/artifacts
gh api repos/TJZine/LineupDesktop/actions/artifacts/ARTIFACT_ID/zip > ci-artifact.zip
python3 -I /trusted/release/verify.py ci ci-artifact.zip \
  --repo TJZine/LineupDesktop --commit FULL_REVIEWED_COMMIT \
  --run RUN_ID --attempt ATTEMPT --workflow .github/workflows/ci.yml \
  --artifact ARTIFACT_ID --extract new-ci-input
```

The helper independently fetches run/artifact metadata from GitHub, requires a
successful current attempt at that commit/workflow and rejects artifacts older
than that attempt. It compares the original downloaded artifact ZIP with GitHub's
API `digest`. `gh run download` extracts that ZIP and is unsuitable for comparing
the API ZIP digest. Missing/expired digests or unavailable GitHub API access are
failures, not permission to trust an internal checksum instead. Preserve the API
responses/run links in ordinary evidence; credentials and token URLs stay private.

The API digest binds the downloaded container. Recompute the inner unsigned APK
or Windows ZIP hash separately. Check build logs for the clean full source commit,
toolchain checker success and pinned tool identities. For Android, inspect P2's
ordinary `build-evidence.txt`, resolved dependency output and `SHA256SUMS`; compare
their assertions with the selected GitHub logs and independently obtained source.
For Windows, retain `BUILD-INFO.txt`, `BUILD-PROVENANCE.json`, engine receipt,
`PACKAGE-MANIFEST.sha256`, CRT evidence and licenses. Check them against the
reviewed [build metadata](../tool/windows/build-metadata.psd1) and build logs.
Internal metadata/checksums alone do not establish source or origin; do not run
the candidate's verification scripts. No new provenance document/schema is needed.

The helper checks every ZIP member's CRC, caps total expanded bytes at 2 GiB and
entries at 20,000, rejects traversal, symlinks, special/encrypted members, duplicate
case-insensitive paths and unsafe Windows names, including reserved devices and
COM/LPT superscript-digit aliases. Extraction is optional and only
into a new directory. A failed extraction may leave partial files: discard the
whole scratch directory. Run archive parsing without credentials where feasible;
never execute its contents. If a legitimate package exceeds a bound, review and
adjust the installed helper before use rather than bypassing inspection.

## Android signing setup and custody

The maintainer selected [Sign Android candidate](../.github/workflows/sign-android.yml)
for Android. It runs on manual dispatch from protected `main` in this repository.
Its unprivileged job prepares the input manifest. The signing job waits for the
`android-production-signing` environment approval and starts on a fresh runner.
Both jobs load only the two reviewed release helpers from the workflow revision.
They read the selected commit's `pubspec.yaml` as data and use the fixed update
application ID `com.tjzine.lineup`. Review workflow, helper and action-pin changes
as signing-authority changes under the protected source process.

Before adding any production credentials, obtain authorization for these settings
and custody actions. Read the applied settings back before trusting the gate.

1. Activate and test the `main` protections in [Repository security](repository-security.md).
   Keep the repository public and use the standard `ubuntu-24.04` runner for both
   signing jobs. Read the account's Actions and Packages usage and billing budget,
   including the stop-usage behavior. Keep paid runner use disabled and maintain
   the zero-spend limit. Download approved output promptly. The signing artifact
   expires after three days. Avoid repeated dispatches and account for the existing
   CI artifact retention in storage usage. [GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions)
2. In **Settings → Environments**, create `android-production-signing` explicitly.
   Under deployment branches and tags, select **Selected branches and tags** and
   allow only the branch `main`. Require the maintainer as reviewer, leave
   **Prevent self-review** off for the sole maintainer, and disable administrator
   bypass. Read back the branch rule and approval settings in that environment.
   GitHub can create an unconfigured environment when a workflow first references
   it. Verify the configured rules before placing secrets there.
   [GitHub environment controls](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments)
3. Establish an independent, access-restricted backup of the retained update key
   and a way to recover its credentials outside GitHub and build accounts. Confirm
   recovery before restricting historical copies. Obtain the certificate SHA-256
   independently from trusted installed or previously published APKs or verified
   custody records. Set the public pin as the **repository** Actions variable
   `ANDROID_SIGNING_CERT_SHA256`, using 64 lowercase hexadecimal characters with
   no separators. Use the repository variable for both jobs and keep its expected
   value in the release review. Avoid an environment variable with the same name.
4. After custody authorization, enter the signing secrets privately under
   **Settings → Environments → android-production-signing → Environment secrets**.
   The names are `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`,
   `ANDROID_KEY_ALIAS` and `ANDROID_KEY_PASSWORD`. Encode the keystore as one
   Base64 line. If creating a temporary encoded file on a trusted custody host,
   use `umask 077` and `openssl base64 -A -in /protected/retained-update-key.jks
   -out /private/scratch/key.b64` as one command. Remove the encoded copy after
   entry. Treat Base64 as key material and keep it and passwords out of terminals,
   logs, chat, repository files and ordinary build accounts. Enter the key and
   store password separately, even if they are the same for the retained store.
   The encoded value must fit GitHub's 48 KB secret limit. Read back secret names
   and scope, without attempting to read their values. Reserve these names for
   the signing environment, with no repository or organization fallback secrets.
   [GitHub secrets and Base64](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets)

Before using production credentials, separately authorize a hosted rehearsal with
only a disposable key and its matching public pin. Read back protection, verify
that an off-main dispatch cannot reach signing, and observe a valid main dispatch
wait after preflight. Reject one approval and confirm there is no signed artifact.
Approve a separate reviewed disposable dispatch, then verify the exact downloaded
candidate and checksum independently. Actions artifacts in the public repository
can be accessed by signed-in readers. Include the disposable candidate's upload
in rehearsal authorization. Clear disposable credentials and confirm the production
pin and environment scope again before authorizing production signing.

## Android candidate generation and approval

1. Choose the reviewed full commit and a successful CI run from a push to this
   repository's `main` branch. CI retries of that push can qualify. This trigger
   identifies the branch even if the repository also has a tag named `main`.
   Inspect the Android job and logs, including the clean-source check, pinned
   toolchain, resolved dependencies and packaged manifest inspection. Record the
   successful attempt and numeric ID of `android-unsigned-<source_sha>` from the
   API as described above. Dispatch **Sign Android candidate** on `main` with the
   full source SHA, CI run ID, attempt and artifact ID.
2. Open the signing run summary before approving the environment job. Compare its
   input manifest with the source review, CI evidence and trusted certificate pin.
   It shows the signing workflow revision and attempt, source SHA, CI run and
   attempt, artifact ID, API ZIP SHA-256, unsigned APK SHA-256, application, version
   and expected certificate. Approve only this run and record the manifest SHA-256
   with the decision. Solo approval is a deliberate release action. The signing
   job re-fetches the same API data and archive and recomputes the manifest hash.
   A changed manifest, selected CI attempt, or signing attempt requires a fresh
   dispatch and review. Use fresh dispatches for retries.
3. The signing step alone receives the environment secrets. It writes a private
   temporary keystore and passes password environment references to `apksigner`.
   The helper removes the temporary store on exit and the hosted runner is
   discarded at job end. Separate verification checks the exact signed APK's
   application/version, alignment, signature validity and expected certificate
   before upload. The artifact contains `lineup-final.apk`, its `.sha256`, the
   approved input manifest and non-sensitive signing evidence. Do not mutate the
   signed APK after verification.
4. Download the artifact into a clean acceptance context and compare its manifest
   and final APK hash with the approved manifest and signing job evidence. Repeat
   APK verification with independently trusted SDK tooling and the retained public
   certificate fingerprint before testing the exact APK on assigned Android TV
   and Fire TV devices. Production upgrade and data preservation belong to Gate 3.
   Publication remains the separate manual operation below.

```sh
python3 -I /trusted/release/verify.py apk lineup-final.apk \
  --sha256 FINAL_APK_SHA256 --build-tools /trusted/android/build-tools/36.0.0 \
  --package com.tjzine.lineup --version-code VERSION_CODE --version-name VERSION_NAME \
  --certificate AUTHORIZED_CERTIFICATE_SHA256
```

## Windows: choose the recorded Gate 2 route

Inspect the original ZIP before extraction, using its independently established
hash. Retain a pristine copy of unsigned inputs and existing build metadata.

```powershell
python -I C:\Trusted\release\verify.py archive .\lineup-unsigned.zip `
  --sha256 UNSIGNED_ZIP_SHA256 --extract C:\Scratch\new-package
if ($LASTEXITCODE) { throw 'Package inspection failed.' }
```

For the **signed route**, inventory **all** shipped `.exe`/`.dll` and any other PE
images by file content with maintained Windows SDK tools (for example
`dumpbin /headers FILE`). Reconcile that inventory with the entire archive listing;
do not classify solely by extensions. Classify each PE in ordinary release notes:

- First-party/build-produced: `lineup_desktop.exe`, the patched
  `flutter_windows.dll`, `flutter_secure_storage_windows_plugin.dll`, and any
  additional built native plugins/helpers found in the selected package.
- Verified vendor binaries: the pinned `libmpv-2.dll` and Microsoft CRT inputs.
  Preserve existing valid vendor signatures; verify publisher/chain and pinned
  hashes/version evidence. A vendor binary without an Authenticode signature must
  be recorded explicitly as vendor-unsigned with its existing pinned hash/origin;
  never describe it as publisher-verified or silently re-sign it as first-party.

Stop for an unclassified/unexpected PE or an invalid vendor signature. Compare
actual input hashes with the existing provenance/manifest before signing. Sign
every first-party-built PE using the selected provider, SHA-256 and an approved
RFC 3161 timestamp service. An example for an authorized Windows certificate store:

Use the installed SDK's `dumpbin /headers` over the entire extracted file list,
recording the file-to-output association; classify the PE images reported there.
Non-PE files naturally produce a non-PE diagnostic. A file expected to be a PE
that fails inspection is a failure, not an excuse to drop it from the inventory.
This invokes only installed inspection tools, never a candidate executable.

```powershell
$signTool = 'C:\Trusted\WindowsSDK\signtool.exe'
$firstParty = @('C:\Scratch\new-package\PACKAGE_ROOT\lineup_desktop.exe',
                'C:\Scratch\new-package\PACKAGE_ROOT\flutter_windows.dll',
                'C:\Scratch\new-package\PACKAGE_ROOT\flutter_secure_storage_windows_plugin.dll')
# Complete/reconcile this list with the inspected candidate before proceeding.
foreach ($file in $firstParty) {
  & $signTool sign /sha1 AUTHORIZED_STORE_CERT_THUMBPRINT /fd SHA256 `
    /tr APPROVED_HTTPS_TIMESTAMP_URL /td SHA256 $file
  if ($LASTEXITCODE) { throw 'Signing failed.' }
  & $signTool verify /pa /all /v /tw $file
  if ($LASTEXITCODE) { throw 'Signature verification failed.' }
  $signature = Get-AuthenticodeSignature -LiteralPath $file
  if ($signature.Status -ne 'Valid' -or
      $signature.SignerCertificate.Thumbprint -ne 'AUTHORIZED_STORE_CERT_THUMBPRINT') {
    throw 'Unexpected first-party publisher/certificate.'
  }
}
```

Independently repeat signature/publisher/timestamp checks on the final extracted
ZIP on a verification host using its installed SDK tools. Confirm vendor identities
against the approved provider records, not just a string containing "Microsoft".
Use a valid timestamp and chain accepted on supported clean hosts. Certificate
renewal/provider-specific commands are Gate 2 operational choices.

Signing changes PE bytes: retain the original build provenance as **pre-signing**
evidence rather than rewriting it to pretend those bytes came from compilation.
Regenerate the existing `PACKAGE-MANIFEST.sha256` after signing (exclude the
manifest itself), retain licenses/CRT evidence, then create the final ZIP using
maintained `Compress-Archive`. Hash the entire final ZIP after all mutations.
Record before/after PE hashes and the signing certificate/timestamp in ordinary
release notes. Do not rerun the candidate's packaging script in this context.

```powershell
$package = (Get-Item -LiteralPath C:\Scratch\new-package\PACKAGE_ROOT).FullName
$manifest = Join-Path $package 'PACKAGE-MANIFEST.sha256'
$lines = Get-ChildItem -LiteralPath $package -Recurse -File |
  Where-Object { $_.FullName -ne $manifest } | Sort-Object FullName | ForEach-Object {
    $relative = $_.FullName.Substring($package.Length + 1).Replace('\', '/')
    "$((Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash)  $relative"
  }
[IO.File]::WriteAllLines($manifest, [string[]]$lines, [Text.Encoding]::ASCII)
if (Test-Path -LiteralPath C:\Final\lineup-final.zip) { throw 'Final output already exists.' }
Compress-Archive -LiteralPath $package -DestinationPath C:\Final\lineup-final.zip
```

For the **explicitly unsigned route**, omit first-party Authenticode signing and
record the maintainer's acceptance of weaker Windows publisher assurance in Gate 2
and release notes. Keep vendor signature/input checks. The complete ZIP, immutable
distribution, whole-asset digest and exact-candidate clean-host acceptance
requirements are identical for both routes; an unsigned binary is not authenticated
by its filename or an internal manifest.

For either route, use this ordinary checksum format for the final archive:

```powershell
$asset = Get-Item -LiteralPath C:\Final\lineup-final.zip
$digest = (Get-FileHash -Algorithm SHA256 -LiteralPath $asset.FullName).Hash.ToLowerInvariant()
[IO.File]::WriteAllText("$($asset.FullName).sha256", "$digest  $($asset.Name)`n", [Text.Encoding]::ASCII)
```

The whole-ZIP hash protects non-PE assets too. Updating either PE or data bytes,
archive corruption or a different download must invalidate the accepted digest.

## Draft, physical acceptance and immutable publication

Proceed only after applicable P1/P2/P3 checks and included hardening pass, with
explicit dispositions for deferred optional findings. Gate 3 assigns exact Android
TV, Fire TV and supported clean Windows targets and identifies the existing
production Android installation for upgrade testing. Do not uninstall it or rotate
its key to make a rehearsal pass.

After separate publication authorization, a maintainer uses a protected tag that
already resolves to the full reviewed commit. Read back the remote tag, peeling an
annotated tag if needed, and stop on mismatch. Release notes include source/run/
attempt links, platform identities, toolchain evidence, signing route/certificate,
unsigned/final hashes, acceptance scenarios/hosts/results and any residual risk
acceptance. Do not include secrets or private media identities.

```sh
gh release create RELEASE_TAG -R TJZine/LineupDesktop --verify-tag --draft \
  --title RELEASE_TITLE --notes-file /trusted/approved-release-notes.txt \
  /final/lineup-final.apk /final/lineup-final.apk.sha256 \
  /final/lineup-final.zip /final/lineup-final.zip.sha256
gh release view RELEASE_TAG -R TJZine/LineupDesktop
gh release download RELEASE_TAG -R TJZine/LineupDesktop --dir new-draft-download
```

Include only platforms cleared for this release. Recompute downloaded digests and
compare with the approved local final hashes, not solely downloaded checksum files.
Independently repeat APK/certificate/version or ZIP/platform checks. On separate
acceptance hosts, test this exact downloaded APK's install/upgrade/data preservation
and playback on assigned Android TV/Fire TV, and this exact ZIP on assigned clean
Windows/media/input targets. Record exact hashes. Drafts remain mutable: any change
requires re-verification and affected acceptance. No candidate is run in a context
holding signing or publication credentials.

Only after acceptance and explicit publication authorization:

```sh
gh release view RELEASE_TAG -R TJZine/LineupDesktop
gh release edit RELEASE_TAG -R TJZine/LineupDesktop --draft=false
gh release verify RELEASE_TAG -R TJZine/LineupDesktop
gh release download RELEASE_TAG -R TJZine/LineupDesktop --dir new-public-download
gh release verify-asset RELEASE_TAG new-public-download/lineup-final.apk -R TJZine/LineupDesktop
gh release verify-asset RELEASE_TAG new-public-download/lineup-final.zip -R TJZine/LineupDesktop
```

Verify the checksum assets with `verify-asset` too. Compare every public asset with
the accepted local digest and recheck the attested tag/commit against the selected
full source commit. GitHub's [standard verification procedure](https://docs.github.com/en/code-security/how-tos/secure-your-supply-chain/secure-your-dependencies/verify-release-integrity)
uses the release attestation for immutable publication. `gh release verify` must
succeed; a draft cannot establish final immutable-release acceptance. A mismatch
stops promotion and is reported. After an ambiguous upload/publish response, read
GitHub state before retrying; do not overwrite/retarget/delete a published release.
Corrections use a new version/tag. Physical results can be reused only for the
exact same public hashes.

## Local disposable rehearsal and remaining acceptance

```sh
JAVA_HOME=/opt/homebrew/opt/openjdk@17 \
LINEUP_RELEASE_TEST_SDK="$HOME/Library/Android/sdk" \
python3 -m unittest discover -s tool/release -p '*_test.py' -v
```

Override `LINEUP_RELEASE_TEST_BUILD_TOOLS`/`LINEUP_RELEASE_TEST_PLATFORM` for another
independently installed SDK. The suite makes a minimal synthetic APK with `aapt`,
aligns it, creates a one-day disposable key, signs and verifies it, and rejects
wrong digest/certificate/application/version, signed-as-unsigned and post-signing
mutation. It also checks wrong CI source/run/attempt/workflow, unsafe/corrupt
archives and PE/non-PE digest substitution. All APK/key files use auto-removed OS
temporary directories; no Gradle/Flutter, production store or device is used.
The hosted-workflow helper rehearsal exercises `prepare`, `sign` and `finalize`
with fixture GitHub API responses and the real Android SDK. It checks that a fresh
work directory reproduces the approved manifest and rejects wrong CI selection,
changed input bytes, mismatched approval and a wrong signing certificate.
Without the SDK variable the Android rehearsal is explicitly skipped, not passed.

The macOS rehearsal proves tool behavior on synthetic bytes. It does not prove
an integrated release candidate, production custody, Windows signing/timestamping,
GitHub protection/immutable publication or physical upgrade/media acceptance.
Those remain the exact separate production/external steps above. Use maintained
[Android signing documentation](https://developer.android.com/tools/apksigner)
for provider options, never a candidate-supplied procedure.

The preparation also exercised the helper against GitHub run `42431596198`,
attempt `1`, full baseline commit `2a23bbc0b75658301062c17ec71b3bebdc06bf19`,
artifact `13601346363` (`windows-engine-tests-debug`), original archive SHA-256
`681fa78d40c499c6f9391d18869c8c80def4b3d57ea5db8a81ab70a5b2e8452f`.
The independently fetched API digest matched; all 11 entries passed bounded CRC
inspection. Wrong source/run/attempt and a changed download were rejected.
This historical test-report archive is a transport verification fixture, **not**
an application release candidate or P4/physical Windows acceptance.

Windows path restrictions follow the [Microsoft naming reference](https://learn.microsoft.com/en-us/windows/win32/fileio/naming-a-file) and [DOS device-name reference](https://learn.microsoft.com/en-us/windows/win32/devnotes/rtlisdosdevicename_u).
