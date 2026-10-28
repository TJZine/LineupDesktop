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
if (-not $IsWindows -and $env:OS -ne 'Windows_NT') {
  throw 'run.ps1 must be run on Windows.'
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

Invoke-LineupLaunch -Launch $launchInput
