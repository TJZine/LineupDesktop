#Requires -Version 7.4

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$scripts = @(
  'tool/flutter_engine/apply.ps1',
  'tool/windows/build-inputs.ps1',
  'tool/windows/build-release.ps1',
  'tool/windows/package.ps1',
  'tool/windows/prepare-mpv.ps1',
  'tool/windows/verify-release-policy.ps1'
)
foreach ($relative in $scripts) {
  $tokens = $null
  $errors = $null
  [Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $repository $relative),
    [ref] $tokens,
    [ref] $errors
  ) | Out-Null
  if ($errors.Count) {
    throw "$relative has PowerShell parse errors: $($errors.Message -join '; ')"
  }
}

. (Join-Path $repository 'tool/windows/build-inputs.ps1')

$buildReleasePath = Join-Path $repository 'tool/windows/build-release.ps1'
$buildReleaseSource = Get-Content -Raw -LiteralPath $buildReleasePath

$pubspecTestDirectory = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
try {
  New-Item -ItemType Directory -Path $pubspecTestDirectory -ErrorAction Stop | Out-Null

  function Assert-PubspecVersionRejected {
    param(
      [Parameter(Mandatory)] [string] $Path,
      [Parameter(Mandatory)] [string] $Description
    )

    $rejected = $false
    try {
      Get-PubspecVersion -Path $Path | Out-Null
    } catch {
      $rejected = $true
    }
    if (-not $rejected) {
      throw "Pubspec version case was accepted unexpectedly: $Description."
    }
  }

  $validPath = Join-Path $pubspecTestDirectory 'valid.yaml'
  @(
    'name: lineup-desktop'
    'version: 1.2.3+45'
  ) | Set-Content -LiteralPath $validPath -Encoding utf8
  $valid = Get-PubspecVersion -Path $validPath
  if ($valid.Name -ne '1.2.3' -or $valid.Build -ne '45') {
    throw 'Get-PubspecVersion returned the wrong name or build for a valid version.'
  }

  $missingBuildPath = Join-Path $pubspecTestDirectory 'missing-build.yaml'
  'version: 1.2.3' | Set-Content -LiteralPath $missingBuildPath -Encoding utf8
  Assert-PubspecVersionRejected $missingBuildPath 'missing numeric build'

  $nonnumericBuildPath = Join-Path $pubspecTestDirectory 'nonnumeric-build.yaml'
  'version: 1.2.3+beta' |
    Set-Content -LiteralPath $nonnumericBuildPath -Encoding utf8
  Assert-PubspecVersionRejected $nonnumericBuildPath 'nonnumeric build'

  $duplicateVersionPath = Join-Path $pubspecTestDirectory 'duplicate-version.yaml'
  @(
    'version: 1.2.3+45'
    'version: 1.2.4+46'
  ) | Set-Content -LiteralPath $duplicateVersionPath -Encoding utf8
  Assert-PubspecVersionRejected $duplicateVersionPath 'duplicate top-level version entries'
} finally {
  if (Test-Path -LiteralPath $pubspecTestDirectory -PathType Container) {
    Remove-Item -LiteralPath $pubspecTestDirectory -Recurse -Force -ErrorAction Stop
  }
}

if ($buildReleaseSource -notmatch
  '(?m)^\$sourceCommit\s*=\s*Get-GitValue\s+\$repository\s+@\(''rev-parse'',\s*''--verify'',\s*''HEAD''\)') {
  throw 'build-release.ps1 must use the exact verified source commit for build provenance.'
}
if ($buildReleaseSource -notmatch
  '(?m)^\$pubspecVersion\s*=\s*Get-PubspecVersion\s+-Path\s+\(Join-Path\s+\$repository\s+''pubspec\.yaml''\)') {
  throw 'build-release.ps1 must derive diagnostics from the repository pubspec.yaml.'
}
if ($buildReleaseSource -notmatch
  '(?m)^\$lineupVersion\s*=\s*\$pubspecVersion\.Name\s*$') {
  throw 'build-release.ps1 must derive LINEUP_VERSION from the parsed pubspec version name.'
}
if ($buildReleaseSource -notmatch
  '(?m)^\$lineupBuild\s*=\s*"\$\(\$pubspecVersion\.Build\)@\$sourceCommit"\s*$') {
  throw 'build-release.ps1 must derive LINEUP_BUILD from the numeric pubspec build and source commit.'
}
if ($buildReleaseSource -notmatch
  '(?m)^\s*"--dart-define=LINEUP_VERSION=\$lineupVersion"\s*$' -or
  $buildReleaseSource -notmatch
  '(?m)^\s*"--dart-define=LINEUP_BUILD=\$lineupBuild"\s*$') {
  throw 'build-release.ps1 must pass both derived diagnostics defines to the build.'
}
if ($buildReleaseSource -notmatch
  '(?ms)&\s*\$flutter\s+build\s+windows\s+@flutterBuildArguments') {
  throw 'build-release.ps1 must pass the verified Dart defines to the canonical Flutter build.'
}

$metadataPath = Join-Path $repository 'tool/windows/build-metadata.psd1'
$metadata = Import-PowerShellDataFile -LiteralPath $metadataPath
$requiredMetadata = @(
  'FlutterFrameworkRevision',
  'FlutterEngineRevision',
  'FlutterManagerPath',
  'FlutterManagerBlob',
  'FlutterPatchedManagerSha256',
  'FlutterStandardGclientBlob',
  'FlutterEnginePatchPath',
  'FlutterEnginePatchSha256',
  'DepotToolsRevision',
  'MpvVersion',
  'FfmpegVersion',
  'LibplaceboVersion'
)
foreach ($name in $requiredMetadata) {
  if (-not $metadata[$name] -or [string]::IsNullOrWhiteSpace($metadata[$name].ToString())) {
    throw "build-metadata.psd1 is missing $name."
  }
}
foreach ($name in @(
    'FlutterFrameworkRevision',
    'FlutterEngineRevision',
    'FlutterManagerBlob',
    'FlutterStandardGclientBlob',
    'DepotToolsRevision'
  )) {
  if ($metadata[$name] -notmatch '^[A-Fa-f0-9]{40}$') {
    throw "build-metadata.psd1 has an invalid Git identity for $name."
  }
}
foreach ($name in @('FlutterPatchedManagerSha256', 'FlutterEnginePatchSha256')) {
  if ($metadata[$name] -notmatch '^[A-Fa-f0-9]{64}$') {
    throw "build-metadata.psd1 has an invalid SHA-256 for $name."
  }
}

$patchPath = $metadata.FlutterEnginePatchPath
if ($patchPath -notmatch '^[A-Za-z0-9._/-]+$' -or
  [IO.Path]::IsPathRooted($patchPath) -or
  ($patchPath -split '/') -contains '..') {
  throw 'FlutterEnginePatchPath must be a safe repository-relative path.'
}
$patch = Join-Path $repository $patchPath
if (-not (Test-Path -LiteralPath $patch -PathType Leaf) -or
  (Get-FileHash -Algorithm SHA256 -LiteralPath $patch).Hash.ToUpperInvariant() -ne
  $metadata.FlutterEnginePatchSha256) {
  throw 'Flutter engine patch does not match the pinned SHA-256.'
}

foreach ($relative in @(
    'LICENSE',
    'docs/windows-runtime.md',
    'tool/flutter_engine/NOTICE',
    'pubspec.lock',
    'pubspec.yaml'
  )) {
  if (-not (Test-Path -LiteralPath (Join-Path $repository $relative) -PathType Leaf)) {
    throw "Required package policy input is missing: $relative"
  }
}

$licenseHashes = @{
  'FFmpeg-COPYING.GPLv3' = '8CEB4B9EE5ADEDDE47B31E975C1D90C73AD27B6B165A1DCD80C7C545EB65B903'
  'FFmpeg-COPYING.LGPLv3' = 'DA7EABB7BAFDF7D3AE5E9F223AA5BDC1EECE45AC569DC21B3B037520B4464768'
  'libplacebo-LICENSE' = 'B3AA400ACA6D2BA1F0BD03BD98D03D1FE7489A3BBB26969D72016360AF8A5C9D'
  'mpv-LICENSE.LGPL' = '72B672113D642CBB8EF5DCC76938DB801983C56E50B1400AB930F1A64D6DC8D9'
}
foreach ($entry in $licenseHashes.GetEnumerator()) {
  $license = Join-Path $repository "third_party/libmpv/licenses/$($entry.Key)"
  if (-not (Test-Path -LiteralPath $license -PathType Leaf) -or
    (Get-FileHash -Algorithm SHA256 -LiteralPath $license).Hash.ToUpperInvariant() -ne
    $entry.Value) {
    throw "Pinned runtime license does not match $($entry.Key)."
  }
}
Write-Host 'Windows release policy inputs are internally consistent.'
