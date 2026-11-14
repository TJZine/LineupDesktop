# Signing and verifying a release

Android and Windows release independently. Production signing and publication
each require maintainer authorization. [Repository security](repository-security.md)
owns GitHub protection activation. The existing [Android runtime](android-runtime.md),
[Windows runtime](windows-runtime.md), and [Windows acceptance](windows-native-validation.md)
documents retain their platform and build obligations. The final platform pass
is [Release acceptance](release-acceptance.md).

## One-page release checklist

Use a fresh scratch directory and stop on any failed command. Replace uppercase
placeholders with the selected values. Use bare 64-character hexadecimal
digests for `*_SHA256` placeholders, without a `sha256:` prefix. Keep
credentials, token-bearing URLs, private media details, and unredacted
diagnostics out of release evidence.

### Android APK

1. Select the full reviewed commit and a successful **CI push to `main`**. The
   generic verifier accepts `push` or `workflow_dispatch` on `main`, but the
   Android signing helper intentionally accepts only a `push` run on `main`.
   Record the run ID, attempt, and numeric `android-unsigned-SOURCE_SHA` artifact
   ID.

2. Download the original API artifact ZIP and verify its GitHub identity and
   digest with the independently reviewed helper:

   ```sh
   gh run view CI_RUN_ID -R TJZine/LineupDesktop --attempt CI_ATTEMPT --log
   gh api repos/TJZine/LineupDesktop/actions/runs/CI_RUN_ID
   gh api repos/TJZine/LineupDesktop/actions/runs/CI_RUN_ID/artifacts
   gh api repos/TJZine/LineupDesktop/actions/artifacts/CI_ARTIFACT_ID/zip > ci-artifact.zip
   python3 -I /trusted/release/verify.py ci ci-artifact.zip \
     --repo TJZine/LineupDesktop --commit SOURCE_SHA \
     --run CI_RUN_ID --attempt CI_ATTEMPT --workflow .github/workflows/ci.yml \
     --artifact CI_ARTIFACT_ID --extract ci-input
   ```

3. Run the Gradle inventory advisory scan and review `runtime-dependencies.txt`
   from the verified CI artifact. Record dispositions for the resolved
   dependencies as described in [Manual advisory review](#manual-advisory-review).

   ```sh
   tool/security/osv-scan.sh --lockfile=android/gradle/verification-metadata.xml
   ```

4. Dispatch **Sign Android candidate** on protected `main`, using the selected
   source, CI run, attempt, and artifact. Do not use a signing-workflow rerun:

   ```sh
   gh workflow run sign-android.yml -R TJZine/LineupDesktop --ref main \
     -f source_sha=SOURCE_SHA -f ci_run=CI_RUN_ID \
     -f ci_attempt=CI_ATTEMPT -f artifact_id=CI_ARTIFACT_ID
   ```

   Review the prepare manifest and certificate pin before approving the
   `android-production-signing` environment. The signed artifact is retained
   for **1 day**.

5. Select the signed artifact by numeric ID from the approved signing run.
   Obtain its API SHA-256 digest, compare the extracted manifest with the
   approved manifest, and verify the APK against the independently recorded
   final hash and certificate. Delete the public handoff artifact immediately
   after verifying the download:

   ```sh
   gh api repos/TJZine/LineupDesktop/actions/runs/SIGNING_RUN_ID/artifacts
   gh api repos/TJZine/LineupDesktop/actions/artifacts/SIGNED_ARTIFACT_ID
   gh api repos/TJZine/LineupDesktop/actions/artifacts/SIGNED_ARTIFACT_ID/zip > signed-artifact.zip
   python3 -I /trusted/release/verify.py archive signed-artifact.zip \
     --sha256 SIGNED_ARTIFACT_ZIP_SHA256 --extract signed-candidate
   shasum -a 256 signed-candidate/input-manifest.txt
   python3 -I /trusted/release/verify.py apk signed-candidate/lineup-final.apk \
     --sha256 FINAL_APK_SHA256 --build-tools /trusted/android/build-tools/36.0.0 \
     --package com.tjzine.lineup --version-code VERSION_CODE --version-name VERSION_NAME \
     --certificate AUTHORIZED_CERTIFICATE_SHA256
   gh api -X DELETE repos/TJZine/LineupDesktop/actions/artifacts/SIGNED_ARTIFACT_ID
   ```

6. Run [Release acceptance](release-acceptance.md) against this exact signed
   APK. Record the asset SHA-256, signer, versionCode, devices, results, and
   any blocker or limitation before drafting a release.

### Windows portable ZIP

1. Dispatch only while `SOURCE_SHA` is the tip of `main`. The only release input is the
   `LineupDesktop-windows-x64` artifact from a manually dispatched CI run at
   that commit. Ordinary pushes skip the package job unless package inputs
   changed. If a later merge cancels the release commit's push run, use
   **Re-run all jobs** on that push run or release the later commit.

2. Start the package run and inspect the actual run and artifact IDs:

   ```sh
   gh workflow run ci.yml -R TJZine/LineupDesktop --ref main
   gh run list -w ci.yml -R TJZine/LineupDesktop -b main -e workflow_dispatch -c SOURCE_SHA -L 10
   gh run view WINDOWS_CI_RUN_ID -R TJZine/LineupDesktop --attempt WINDOWS_CI_ATTEMPT --log
   gh api repos/TJZine/LineupDesktop/actions/runs/WINDOWS_CI_RUN_ID
   gh api repos/TJZine/LineupDesktop/actions/runs/WINDOWS_CI_RUN_ID/artifacts
   gh api repos/TJZine/LineupDesktop/actions/artifacts/WINDOWS_ARTIFACT_ID/zip > windows-ci-artifact.zip
   ```

3. Confirm the run's `event` is `workflow_dispatch` and its `head_sha` is
   the reviewed commit. Verify the API artifact digest before extracting it.
   Replace `WINDOWS_ZIP` with the actual
   `LineupDesktop-*-windows-x64.zip` filename from that artifact:

   ```sh
   python3 -I /trusted/release/verify.py ci windows-ci-artifact.zip \
     --repo TJZine/LineupDesktop --commit SOURCE_SHA --run WINDOWS_CI_RUN_ID \
     --attempt WINDOWS_CI_ATTEMPT --workflow .github/workflows/ci.yml \
     --artifact WINDOWS_ARTIFACT_ID --extract windows-ci-artifact
   (cd windows-ci-artifact && shasum -a 256 WINDOWS_ZIP > WINDOWS_ZIP.sha256)
   python3 -I /trusted/release/verify.py archive windows-ci-artifact/WINDOWS_ZIP \
     --sha256 WINDOWS_ZIP_SHA256 --extract windows-package
   ```

   Compare `BUILD-INFO.txt`, `BUILD-PROVENANCE.json`, licenses, and the package
   manifest with the selected source and build evidence. The local packaging
   recipe in [Windows acceptance, section 8](windows-native-validation.md#8-portable-package-acceptance)
   is for development and acceptance preparation, not a public-release input.

4. Windows is unsigned for the MVP. Follow the
   [draft and publication procedure](#draft-physical-acceptance-and-immutable-publication)
   to upload the exact ZIP and checksum for acceptance. On the assigned clean
   host, download the ZIP from the draft and run [Release acceptance](release-acceptance.md)
   before publication. If Windows fails acceptance, remove its ZIP and checksum
   from the draft. Retire the version only if no platform ships.

## Rules that apply to both platforms

### Source, workflow and retry rules

The helper checks a full 40-character source SHA, workflow path, run ID,
attempt, artifact ID, repository, successful conclusion, and GitHub artifact
digest. A re-run keeps the run ID but changes the attempt, so an artifact from a
previous attempt must not pass. **Re-run failed jobs** fails closed for signing
because the approval manifest binds the signing attempt. It also leaves CI
artifacts from earlier attempts ineligible for the new attempt. Use a fresh
signing dispatch. For Windows CI, use a fresh dispatch on `main` or
**Re-run all jobs** on the selected dispatch. For Android CI, use
**Re-run all jobs** on the selected `main` push to rebuild its artifact.

The generic `verify.py ci` command permits a successful `push` or
`workflow_dispatch` run on `main`. Android signing remains main-push-only
because `sign_android.py prepare` also requires `event == push`. Windows
release packaging requires the manual CI dispatch on `main` described above.

### Immutable versions and releases

Use one shared `vX.Y.Z` tag line. A release includes only the platforms
cleared for that version. A platform that ships later uses the next version.
Draft releases remain mutable. A published release permanently consumes its tag
name, even if the release is later deleted. If a tag is created for draft
acceptance, retire that version only if no platform ships. Follow GitHub's
[immutable release guidance](https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases).

Require GitHub CLI 2.81.0 or newer for the verification commands introduced in
the [v2.81.0 release](https://github.com/cli/cli/releases/tag/v2.81.0):

```sh
gh --version
gh release verify RELEASE_TAG -R TJZine/LineupDesktop
gh release verify-asset RELEASE_TAG ASSET_PATH -R TJZine/LineupDesktop
```

After publication, verify every public asset, including checksum assets, and
compare the attested tag and asset digests with the accepted evidence. A draft
cannot establish final immutable-release acceptance. An ambiguous upload or
publication response requires reading GitHub state before any retry. Keep
published tags fixed.

### Artifact handoff and verification

Build accounts, candidates, dependencies, and acceptance hosts must not have
access to production keys, passwords, provider tokens, or usable backups.
Download artifacts into a clean acceptance context and use an independently
reviewed copy of `tool/release/verify.py`, invoked with `python3 -I`. Verify the
original API artifact ZIP before trusting its contents, then verify the inner
APK or Windows ZIP separately.
Checksums and attestations identify bytes and provenance. Software safety
requires separate evidence.

## Select the source and CI artifact independently

Record the repository, full reviewed commit, source review, applicable successful
CI run ID, **attempt**, workflow path, and numeric artifact ID from GitHub. Inspect
the applicable job results and build logs, including conditional Windows jobs;
overall success alone does not prove that a platform build ran. Select the
artifact by its API identity, not just a familiar artifact name.

The helper independently fetches run and artifact metadata, requires a successful
current attempt at that commit and workflow, rejects artifacts older than that
attempt, and compares the original API ZIP with GitHub's `digest`. `gh run
download` extracts files and is unsuitable for comparing the API ZIP digest.
Missing or expired digests and unavailable API access are failures, not permission
to trust an internal checksum instead.

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

The API digest binds the downloaded container. Recompute the inner unsigned APK
or Windows ZIP hash separately. Check build logs for the clean full source
commit, toolchain checker, and pinned tool identities. Internal metadata and
checksums alone do not establish source or origin. Review Android's
`build-evidence.txt`, `runtime-dependencies.txt`, and `SHA256SUMS` against the
selected run and reviewed source. Review the Windows `BUILD-INFO.txt`,
`BUILD-PROVENANCE.json`, engine receipt, `PACKAGE-MANIFEST.sha256`, CRT
evidence, and licenses against the logs and
[build metadata](../tool/windows/build-metadata.psd1).

The helper checks ZIP member CRCs and bounds expansion to 2 GiB and 20,000
entries. It rejects traversal, symlinks, special or encrypted members, case
collisions, and unsafe Windows names. Use a new extraction directory and
discard it after failed extraction. Parse archives without production
credentials where feasible. See the [Windows naming reference](https://learn.microsoft.com/en-us/windows/win32/fileio/naming-a-file)
and [DOS device names](https://learn.microsoft.com/en-us/windows/win32/devnotes/rtlisdosdevicename_u).

## Android signing setup and custody

The maintainer-selected [Sign Android candidate workflow](../.github/workflows/sign-android.yml)
runs only by manual dispatch on protected `main`. Its unprivileged job prepares
the input manifest. The signing job waits for the `android-production-signing`
environment approval, starts on a fresh `ubuntu-24.04` runner, and uploads the
signed candidate with `retention-days: 1`. Both jobs load only the reviewed
helpers from the workflow revision. They read the selected commit's
`pubspec.yaml` as data and use the fixed update application ID
`com.tjzine.lineup`. Review workflow, helper, and action-pin changes as
signing-authority changes.

Before adding production credentials, obtain authorization for these settings
and read them back:

1. Activate and test [repository security](repository-security.md). Keep paid
   runner use disabled and maintain the zero-spend limit. Download approved
   output promptly and delete the signed artifact after handoff.
2. Create `android-production-signing` explicitly. Under deployment branches
   and tags, choose **Selected branches and tags** and allow only the branch
   `main`. Require the maintainer as reviewer, leave
   **Prevent self-review** off for the sole maintainer, and disable administrator
   bypass. Verify the configured rules before placing secrets there.
3. Back up the retained update key to two independent encrypted copies. Test
   recovery in a separate macOS user without development tools. Compare the
   recovered certificate SHA-256 with the trusted value and sign a throwaway
   APK before removing the retained key from the build account. Set the
   repository Actions variable `ANDROID_SIGNING_CERT_SHA256` to 64 lowercase
   hexadecimal characters. Use the same repository pin for both jobs.
4. After custody authorization, enter `ANDROID_KEYSTORE_BASE64`,
   `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, and
   `ANDROID_KEY_PASSWORD` only as environment secrets. Reserve the names for
   that environment and keep repository or organization fallbacks unset.
   Encode the keystore as one Base64 line within GitHub's 48 KB secret limit.
   Treat the encoded value as key material and remove any temporary copy after
   entry. Keep it and passwords out of terminals, logs, chat, repository files,
   and ordinary build accounts. Read back names and scope without reading values.

Rehearse the protected workflow with a disposable key and matching certificate
pin before production credentials are added. Verify that off-main dispatches
cannot reach signing, that a rejected approval produces no signed artifact, and
that a separately approved disposable dispatch can be independently verified.
Signed-in GitHub readers can download artifacts from the public repository.
Include the disposable candidate's upload in the rehearsal authorization.
Clear disposable credentials and read back the production pin and environment
scope before production authorization. See [GitHub environment controls](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments)
and [GitHub secrets](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets)
for the provider controls.

## Android candidate generation and approval

1. Choose the reviewed full commit and a successful CI run from a push to this
   repository's `main` branch. CI retries of that push can qualify when the
   selected attempt and artifact are recorded. Inspect the Android job, clean
   source check, pinned toolchain, resolved dependencies, and packaged manifest.
   Dispatch **Sign Android candidate** on `main` with the full source SHA, CI run
   ID, attempt, and artifact ID.
2. Open the signing run summary before approving the environment job. Compare
   its input manifest with the source review, CI evidence, and trusted
   certificate pin. A changed manifest, selected CI attempt, or signing attempt
   requires a fresh dispatch and review.
3. Only the signing step receives environment secrets. It writes a private
   temporary keystore and passes password environment references to `apksigner`.
   The helper removes the temporary store on exit. It verifies the exact signed
   APK's application/version, alignment, signature, and certificate before
   upload. Do not mutate the signed APK after verification.
4. Download the artifact into a clean acceptance context, compare its manifest
   and APK hash with the signing evidence, and repeat verification with
   independently trusted SDK tooling before [Release acceptance](release-acceptance.md).

```sh
python3 -I /trusted/release/verify.py apk lineup-final.apk \
  --sha256 FINAL_APK_SHA256 --build-tools /trusted/android/build-tools/36.0.0 \
  --package com.tjzine.lineup --version-code VERSION_CODE --version-name VERSION_NAME \
  --certificate AUTHORIZED_CERTIFICATE_SHA256
```

## Contexts and prerequisites

Keep build, acceptance, signing, and publication contexts separate. Keep
production credentials away from candidate code, dependencies, and execution.
Preserve the retained Android update key and its recovery copies.

Install the independently reviewed [verification helper](../tool/release/verify.py)
with Python 3.11 or newer outside candidate-controlled directories and import
paths. Record the reviewed helper hash. Run it with `python3 -I` and absolute
paths to trusted SDK tools. Use Bash with `set -euo pipefail`. In PowerShell,
set `$ErrorActionPreference = 'Stop'` and check native exit codes explicitly.
Run candidate binaries only in the separate acceptance context.

## Manual advisory review

The Security workflow (pushes to `main`, pull requests, its weekly schedule and
manual dispatch) scans `pubspec.lock`. Gradle verification
metadata is a conservative inventory, not proof of runtime resolution. At
release time, run the documented inventory scan and review the resolved
`runtime-dependencies.txt` from the CI artifact:

```sh
tool/security/osv-scan.sh --lockfile=pubspec.lock
tool/security/osv-scan.sh --lockfile=android/gradle/verification-metadata.xml
```

Record source/version/date, findings, mitigation or maintainer disposition, and
remaining gaps. Do not make a failing or unavailable scan appear clean.

## Code-scanning caveat

See [repository security](repository-security.md#code-scanning-coverage-and-caveats)
for CodeQL coverage and the Kotlin extraction caveat.

## Windows release route

Windows is unsigned for the MVP. Preserve the CI-produced ZIP byte for byte,
including the vendor signature and input checks in the package build. Record
the unsigned status, provenance, licenses, whole-asset digest, and clean-host
acceptance. For future signing, evaluate the $0
[SignPath Foundation](https://signpath.org/terms.html) route. It requires
CI-built artifacts and MFA, and the certificate names SignPath Foundation as
publisher.

## Local disposable rehearsal and remaining acceptance

Run the helper tests with an independently installed Android SDK. The SDK
rehearsal must be required, not silently skipped:

```sh
JAVA_HOME=/opt/homebrew/opt/openjdk@17 \
LINEUP_RELEASE_TEST_SDK="$HOME/Library/Android/sdk" \
LINEUP_RELEASE_TEST_REQUIRE_SDK=1 \
python3 -m unittest discover -s tool/release -p '*_test.py' -v
```

The suite uses temporary synthetic APKs and disposable keys. It checks helper
behavior, archive bounds, APK identity/alignment/signature, wrong source/run/
attempt/workflow selection, changed bytes, and certificate mismatches. This
does not establish a production signing run, GitHub enforcement, device
behavior, Windows runtime behavior, or publication.

Override `LINEUP_RELEASE_TEST_BUILD_TOOLS` or `LINEUP_RELEASE_TEST_PLATFORM`
only for another independently installed SDK. See [Android signing tools](https://developer.android.com/tools/apksigner).
The transport rehearsal before the main-branch provenance restriction verified
run `42431596198` attempt `1` and artifact `13601346363`
(`windows-engine-tests-debug`). Its API ZIP digest
matched, and all 11 entries passed bounded CRC inspection. That historical
fixture did not exercise public-release selection or clean-host acceptance.

## Draft, physical acceptance and immutable publication

Prepare release notes with the source SHA, run and attempt links, platform and
toolchain identities, signer or unsigned status, and exact asset digests.
After the artifact checks, the maintainer can reserve a version and create a
draft for exact-download acceptance. This procedure creates the protected tag
before the draft. Include only the intended platforms' asset and checksum pairs.
If a platform fails acceptance, remove only its assets from the draft. Retire
the version if no platform ships.

```sh
git tag RELEASE_TAG SOURCE_SHA
git push origin refs/tags/RELEASE_TAG
test "$(gh api repos/TJZine/LineupDesktop/git/ref/tags/RELEASE_TAG --jq '.object.sha')" = SOURCE_SHA
gh release create RELEASE_TAG -R TJZine/LineupDesktop --verify-tag --draft \
  --title "RELEASE_TITLE" --notes-file /trusted/approved-release-notes.txt \
  /final/lineup-final.apk /final/lineup-final.apk.sha256 \
  /final/WINDOWS_ZIP /final/WINDOWS_ZIP.sha256
gh release view RELEASE_TAG -R TJZine/LineupDesktop
gh release download RELEASE_TAG -R TJZine/LineupDesktop --dir new-draft-download
```

Verify draft download hashes and run [Release acceptance](release-acceptance.md)
on the exact files. For Windows, download the draft ZIP in Edge on the clean
host. For Android, acceptance can use the signed handoff APK when the draft
download has the exact accepted SHA-256. Record redacted host and device results.
If a draft asset changes, verify it and repeat the affected acceptance rows.
Publish only after the checks pass and publication is separately authorized:

```sh
gh release edit RELEASE_TAG -R TJZine/LineupDesktop --draft=false
gh release verify RELEASE_TAG -R TJZine/LineupDesktop
gh release download RELEASE_TAG -R TJZine/LineupDesktop --dir new-public-download
gh release verify-asset RELEASE_TAG new-public-download/ASSET_FILE -R TJZine/LineupDesktop
```

Repeat `verify-asset` for each asset and checksum. Compare their digests and
the attested commit with the accepted evidence. Corrections use a new version.
