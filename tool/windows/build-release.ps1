#Requires -Version 7.4

[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string] $EngineSource
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
. (Join-Path $PSScriptRoot 'build-inputs.ps1')
$repository = Get-LineupRepository
$metadata = Import-PowerShellDataFile -LiteralPath (Join-Path $repository 'tool/windows/build-metadata.psd1')
$patchRelativePath = $metadata.FlutterEnginePatchPath
if ($patchRelativePath -notmatch '^[A-Za-z0-9._/-]+$' -or
  [IO.Path]::IsPathRooted($patchRelativePath) -or
  ($patchRelativePath -split '/') -contains '..') {
  throw 'FlutterEnginePatchPath must be a safe repository-relative path.'
}
$patchPath = [IO.Path]::GetFullPath((Join-Path $repository $metadata.FlutterEnginePatchPath))
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $patchPath).Hash.ToUpperInvariant() -ne
  $metadata.FlutterEnginePatchSha256) {
  throw 'Flutter engine patch does not match the pinned SHA-256.'
}

function Get-GitValue {
  param(
    [Parameter(Mandatory)] [string] $Repository,
    [Parameter(Mandatory)] [string[]] $Arguments
  )

  $PSNativeCommandUseErrorActionPreference = $false
  $output = @(& git -C $Repository @Arguments)
  if ($LASTEXITCODE -or $output.Count -ne 1 -or
    [string]::IsNullOrWhiteSpace($output[0])) {
    throw "git $($Arguments -join ' ') failed in $Repository."
  }
  $output[0].Trim()
}

function Test-SourceDirty {
  param([Parameter(Mandatory)] [string] $Repository)

  $nativeErrorPreference = $PSNativeCommandUseErrorActionPreference
  $PSNativeCommandUseErrorActionPreference = $false
  try {
    git -C $Repository diff --quiet
    $worktreeExit = $LASTEXITCODE
    if ($worktreeExit -gt 1) { throw "git diff failed with exit code $worktreeExit." }

    git -C $Repository diff --cached --quiet
    $indexExit = $LASTEXITCODE
    if ($indexExit -gt 1) { throw "git diff --cached failed with exit code $indexExit." }

    $untracked = @(git -C $Repository ls-files --others --exclude-standard)
    if ($LASTEXITCODE) { throw 'git ls-files failed while checking source state.' }
    $dirty = $worktreeExit -eq 1 -or $indexExit -eq 1 -or $untracked.Count -ne 0
  } finally {
    $PSNativeCommandUseErrorActionPreference = $nativeErrorPreference
  }
  $dirty
}

if (Test-SourceDirty $repository) {
  throw 'Refusing to create release provenance from a dirty Lineup source tree.'
}
Assert-NoTrackedSymlinks -Repository $repository
$releaseInput = Get-LineupReleaseInput -EngineSource $EngineSource
$sourceCommit = $releaseInput.SourceCommit
$EngineSource = $releaseInput.EngineSource
$flutterRoot = $releaseInput.FlutterRoot
if (-not (Test-Path -LiteralPath (Join-Path $flutterRoot 'bin/flutter.bat') -PathType Leaf)) {
  throw 'EngineSource must be the engine/src directory below the pinned Flutter checkout.'
}
Assert-PinnedFlutterCheckout -Root $flutterRoot -Metadata $metadata -PatchPath $patchPath
$flutter = $releaseInput.Flutter
Set-Location $flutterRoot
Invoke-NativeChecked -FilePath $flutter -Arguments @('precache', '--windows') `
  -FailureMessage 'Pinned Flutter SDK cache preparation failed.'
Assert-PinnedFlutterCheckout -Root $flutterRoot -Metadata $metadata -PatchPath $patchPath

$engineOutput = Join-Path $EngineSource 'out/host_release'
if (-not (Test-Path -LiteralPath (Join-Path $engineOutput 'build.ninja') -PathType Leaf)) {
  throw 'Configure the pinned host_release engine before the application release build.'
}
Set-Location $EngineSource
& {
  $PSNativeCommandUseErrorActionPreference = $false
  & ninja -C $engineOutput
  if ($LASTEXITCODE) { throw 'Pinned host_release engine build failed.' }
}
Assert-PinnedFlutterCheckout -Root $flutterRoot -Metadata $metadata -PatchPath $patchPath
$engineLibrary = Join-Path $engineOutput 'flutter_windows.dll'
if (-not (Test-Path -LiteralPath $engineLibrary -PathType Leaf)) {
  throw 'Pinned host_release engine did not produce flutter_windows.dll.'
}

$BuildDirectory = [IO.Path]::GetFullPath(
  (Join-Path $repository 'build/windows/x64/runner/Release')
)
$buildMarkerPath = Join-Path $BuildDirectory 'LINEUP-BUILD-PROVENANCE.json'
if (Test-Path -LiteralPath $buildMarkerPath -PathType Leaf) {
  Remove-Item -LiteralPath $buildMarkerPath
}
Set-Location $repository
Invoke-LineupReleaseBuild -Release $releaseInput

if ((Test-SourceDirty $repository) -or
  (Get-GitValue $repository @('rev-parse', '--verify', 'HEAD')) -ne $sourceCommit) {
  throw 'Lineup source changed during the release build.'
}
Assert-PinnedFlutterCheckout -Root $flutterRoot -Metadata $metadata -PatchPath $patchPath

if (-not (Test-Path -LiteralPath $BuildDirectory -PathType Container)) {
  throw 'Release build directory does not exist after the build.'
}
$builtEngine = Join-Path $BuildDirectory 'flutter_windows.dll'
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $builtEngine).Hash -ne
  (Get-FileHash -Algorithm SHA256 -LiteralPath $engineLibrary).Hash) {
  throw 'Release build does not contain the selected host_release Flutter engine.'
}

$artifacts = @(Get-BuildInputs $BuildDirectory | ForEach-Object {
    [ordered]@{
      path = $_
      sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $BuildDirectory $_)).Hash.ToUpperInvariant()
    }
  })
$marker = [ordered]@{
  schemaVersion = 1
  sourceCommit = $sourceCommit
  flutterFramework = $metadata.FlutterFrameworkRevision
  flutterEngine = $metadata.FlutterEngineRevision
  flutterEnginePatch = $metadata.FlutterEnginePatchPath
  flutterEnginePatchSha256 = $metadata.FlutterEnginePatchSha256
  flutterPatchedManagerSha256 = $metadata.FlutterPatchedManagerSha256
  artifacts = $artifacts
}
$marker | ConvertTo-Json -Depth 4 |
  Set-Content -LiteralPath $buildMarkerPath -Encoding ascii
Write-Host "Created an artifact-bound release marker for $sourceCommit."
