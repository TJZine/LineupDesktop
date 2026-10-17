#Requires -Version 7.4

[CmdletBinding()]
param(
  [string] $EngineSource = $env:LINEUP_ENGINE_SOURCE,
  [string] $MpvRoot = $env:LINEUP_MPV_ROOT,
  [string] $MediaPath
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
. (Join-Path $PSScriptRoot 'build-inputs.ps1')
$repository = Get-LineupRepository
$metadataPath = Join-Path $repository 'tool/windows/build-metadata.psd1'

if (-not $IsWindows -and $env:OS -ne 'Windows_NT') {
  throw 'run.ps1 must be run on Windows.'
}

function Get-GitValue {
  param(
    [Parameter(Mandatory)] [string] $Root,
    [Parameter(Mandatory)] [string[]] $Arguments
  )

  $nativePreference = $PSNativeCommandUseErrorActionPreference
  $PSNativeCommandUseErrorActionPreference = $false
  try {
    $output = @(& git -C $Root @Arguments)
    $exitCode = $LASTEXITCODE
  } finally {
    $PSNativeCommandUseErrorActionPreference = $nativePreference
  }
  if ($exitCode -or $output.Count -ne 1 -or
    [string]::IsNullOrWhiteSpace($output[0])) {
    throw "git $($Arguments -join ' ') failed in $Root."
  }
  $output[0].Trim()
}

function Assert-CommittedInput {
  param([Parameter(Mandatory)] [string] $RelativePath)

  $committed = Get-GitValue $repository @('rev-parse', "HEAD:$RelativePath")
  $working = Get-GitValue $repository @('hash-object', '--', $RelativePath)
  if ($working -ne $committed) {
    throw "Build input must match its committed revision: $RelativePath"
  }
}

Assert-CommittedInput 'tool/windows/build-metadata.psd1'
$metadata = Import-PowerShellDataFile -LiteralPath $metadataPath
$patchRelativePath = $metadata.FlutterEnginePatchPath
if ($patchRelativePath -notmatch '^[A-Za-z0-9._/-]+$' -or
  [IO.Path]::IsPathRooted($patchRelativePath) -or
  ($patchRelativePath -split '/') -contains '..') {
  throw 'FlutterEnginePatchPath must be a safe repository-relative path.'
}
Assert-CommittedInput $patchRelativePath
$patchPath = [IO.Path]::GetFullPath((Join-Path $repository $patchRelativePath))
if (-not (Test-Path -LiteralPath $patchPath -PathType Leaf) -or
  (Get-FileHash -Algorithm SHA256 -LiteralPath $patchPath).Hash.ToUpperInvariant() -ne
  $metadata.FlutterEnginePatchSha256) {
  throw 'Flutter engine patch does not match the pinned SHA-256.'
}

$launchInput = Get-LineupLaunchInput -EngineSource $EngineSource -MpvRoot $MpvRoot `
  -BoundParameters $PSBoundParameters -MediaPath $MediaPath
$engineSource = $launchInput.EngineSource
$mpvRoot = $launchInput.MpvRoot
$flutterRoot = $launchInput.FlutterRoot
$flutter = $launchInput.Flutter
if (-not (Test-Path -LiteralPath $flutter -PathType Leaf)) {
  throw 'EngineSource must be the engine/src directory below the pinned Flutter checkout.'
}
$engineVersion = Join-Path $flutterRoot 'bin/internal/engine.version'
if (-not (Test-Path -LiteralPath $engineVersion -PathType Leaf)) {
  throw 'Pinned Flutter checkout is missing bin/internal/engine.version.'
}
Assert-PinnedFlutterCheckout -Root $flutterRoot -Metadata $metadata -PatchPath $patchPath

foreach ($relative in @(
    'include/mpv/client.h',
    'libmpv.lib',
    'libmpv-2.dll',
    'lineup-mpv-provenance.cmake'
  )) {
  if (-not (Test-Path -LiteralPath (Join-Path $mpvRoot $relative) -PathType Leaf)) {
    throw "MpvRoot is missing $relative. Prepare the pinned runtime with tool/windows/prepare-mpv.ps1."
  }
}

$engineOutput = $launchInput.EngineOutput
$buildNinja = Join-Path $engineOutput 'build.ninja'
if (-not (Test-Path -LiteralPath $buildNinja -PathType Leaf)) {
  throw 'Configure the pinned host_debug engine first; see docs/DEVELOPMENT.md#patched-engine-provisioning. The launcher does not run GN or provision engine sources.'
}
$ninjaCommand = Get-Command 'ninja.exe' -CommandType Application -ErrorAction SilentlyContinue
if (-not $ninjaCommand) {
  $ninjaCommand = Get-Command 'ninja' -CommandType Application -ErrorAction SilentlyContinue
}
if (-not $ninjaCommand) {
  throw 'ninja is required on PATH to refresh the configured host_debug engine.'
}
$ninja = $ninjaCommand.Source

Invoke-LineupLaunch -Launch $launchInput -Ninja $ninja
