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
