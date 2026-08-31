#Requires -Version 7.4

[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string] $EngineSource
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$metadata = Import-PowerShellDataFile -LiteralPath (Join-Path $repository 'tool/windows/build-metadata.psd1')
. (Join-Path $PSScriptRoot 'build-inputs.ps1')
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

function Get-NormalizedTextSha256 {
  param([Parameter(Mandatory)] [string] $Path)

  $text = [IO.File]::ReadAllText($Path).Replace("`r`n", "`n").Replace("`r", "`n")
  $bytes = [Text.UTF8Encoding]::new($false).GetBytes($text)
  [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
}

function Assert-PinnedFlutterCheckout {
  param([Parameter(Mandatory)] [string] $Root)

  $PSNativeCommandUseErrorActionPreference = $false
  if ((Get-GitValue $Root @('rev-parse', '--verify', 'HEAD')) -ne
    $metadata.FlutterFrameworkRevision) {
    throw 'Flutter checkout does not match the pinned framework revision.'
  }
  if ((Get-Content -Raw -LiteralPath (Join-Path $Root 'bin/internal/engine.version')).Trim() -ne
    $metadata.FlutterEngineRevision) {
    throw 'Flutter checkout does not pin the required engine revision.'
  }

  $trackedChanges = @(& git -C $Root status --porcelain --untracked-files=no)
  if ($LASTEXITCODE) { throw 'Could not inspect the Flutter checkout state.' }
  $changedPaths = @($trackedChanges | ForEach-Object {
      if ($_.Length -lt 4) { throw "Unexpected git status entry: $_" }
      $_.Substring(3).Trim('"').Replace('\', '/')
    } | Sort-Object -Unique)
  if ($changedPaths.Count -ne 1 -or $changedPaths[0] -ne $metadata.FlutterManagerPath) {
    throw 'Flutter checkout must contain only the repository-owned engine patch.'
  }
  $managerPath = Join-Path $Root $metadata.FlutterManagerPath
  if ((Get-NormalizedTextSha256 $managerPath) -ne
    $metadata.FlutterPatchedManagerSha256) {
    throw 'Patched Flutter manager source does not match the pinned result.'
  }
  & git -C $Root apply --reverse --check $patchPath
  if ($LASTEXITCODE) { throw 'The exact repository-owned Flutter engine patch is not applied.' }
}

if (Test-SourceDirty $repository) {
  throw 'Refusing to create release provenance from a dirty Lineup source tree.'
}
$sourceCommit = Get-GitValue $repository @('rev-parse', '--verify', 'HEAD')

$EngineSource = (Resolve-Path -LiteralPath $EngineSource).Path
$flutterRoot = Split-Path -Parent (Split-Path -Parent $EngineSource)
if (-not (Test-Path -LiteralPath (Join-Path $flutterRoot 'bin/flutter.bat') -PathType Leaf)) {
  throw 'EngineSource must be the engine/src directory below the pinned Flutter checkout.'
}
Assert-PinnedFlutterCheckout $flutterRoot
$flutter = Join-Path $flutterRoot 'bin/flutter.bat'
Set-Location $flutterRoot
& {
  $PSNativeCommandUseErrorActionPreference = $false
  & $flutter precache --windows
  if ($LASTEXITCODE) { throw 'Pinned Flutter SDK cache preparation failed.' }
}
Assert-PinnedFlutterCheckout $flutterRoot

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
Assert-PinnedFlutterCheckout $flutterRoot
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
& {
  $PSNativeCommandUseErrorActionPreference = $false
  & $flutter build windows `
    --local-engine=host_release `
    --local-engine-host=host_release `
    --local-engine-src-path=$EngineSource
  if ($LASTEXITCODE) { throw 'Flutter Windows release build failed.' }
}

if ((Test-SourceDirty $repository) -or
  (Get-GitValue $repository @('rev-parse', '--verify', 'HEAD')) -ne $sourceCommit) {
  throw 'Lineup source changed during the release build.'
}
Assert-PinnedFlutterCheckout $flutterRoot

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
