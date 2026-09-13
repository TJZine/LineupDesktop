#Requires -Version 7.4

[CmdletBinding()]
param(
  [string] $EngineSource = $env:LINEUP_ENGINE_SOURCE,
  [string] $MpvRoot = $env:LINEUP_MPV_ROOT,
  [string] $MediaPath
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$metadataPath = Join-Path $repository 'tool/windows/build-metadata.psd1'

if (-not $IsWindows -and $env:OS -ne 'Windows_NT') {
  throw 'run.ps1 must be run on Windows.'
}

function Resolve-RequiredPath {
  param(
    [Parameter(Mandatory)] [AllowEmptyString()] [string] $Path,
    [Parameter(Mandatory)] [string] $Name,
    [Parameter(Mandatory)] [ValidateSet('Container', 'Leaf')] [string] $PathType
  )

  if ([string]::IsNullOrWhiteSpace($Path)) {
    throw "$Name must be a nonblank path."
  }
  try {
    $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
  } catch {
    throw "$Name does not exist: $Path"
  }
  if (-not (Test-Path -LiteralPath $resolved -PathType $PathType)) {
    throw "$Name must be a $($PathType.ToLowerInvariant()): $resolved"
  }
  [IO.Path]::GetFullPath($resolved)
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

function Get-GitLines {
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
  if ($exitCode) { throw "git $($Arguments -join ' ') failed in $Root." }
  $output
}

function Assert-CommittedInput {
  param([Parameter(Mandatory)] [string] $RelativePath)

  $committed = Get-GitValue $repository @('rev-parse', "HEAD:$RelativePath")
  $working = Get-GitValue $repository @('hash-object', '--', $RelativePath)
  if ($working -ne $committed) {
    throw "Build input must match its committed revision: $RelativePath"
  }
}

function Get-NormalizedTextSha256 {
  param([Parameter(Mandatory)] [string] $Path)

  $text = [IO.File]::ReadAllText($Path).Replace("`r`n", "`n").Replace("`r", "`n")
  $bytes = [Text.UTF8Encoding]::new($false).GetBytes($text)
  [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
}

function Assert-PinnedFlutterCheckout {
  param([Parameter(Mandatory)] [string] $Root)

  $metadataFlutter = $metadata.FlutterFrameworkRevision
  if ((Get-GitValue $Root @('rev-parse', '--verify', 'HEAD')) -ne $metadataFlutter) {
    throw 'Flutter checkout does not match the pinned framework revision.'
  }
  $engineVersion = Join-Path $Root 'bin/internal/engine.version'
  if ((Get-Content -Raw -LiteralPath $engineVersion).Trim() -ne
    $metadata.FlutterEngineRevision) {
    throw 'Flutter checkout does not pin the required engine revision.'
  }

  $trackedChanges = @(Get-GitLines $Root @('status', '--porcelain', '--untracked-files=no'))
  $changedPaths = @($trackedChanges | ForEach-Object {
      if ($_.Length -lt 4) { throw "Unexpected git status entry: $_" }
      $_.Substring(3).Trim('"').Replace('\', '/')
    } | Sort-Object -Unique)
  if ($changedPaths.Count -ne 1 -or
    $changedPaths[0] -ne $metadata.FlutterManagerPath) {
    throw 'Flutter checkout must contain only the repository-owned engine patch.'
  }

  $managerPath = Join-Path $Root $metadata.FlutterManagerPath
  if (-not (Test-Path -LiteralPath $managerPath -PathType Leaf) -or
    (Get-NormalizedTextSha256 $managerPath) -ne
    $metadata.FlutterPatchedManagerSha256) {
    throw 'Patched Flutter manager source does not match the pinned result.'
  }

  $nativePreference = $PSNativeCommandUseErrorActionPreference
  $PSNativeCommandUseErrorActionPreference = $false
  try {
    & git -C $Root apply --reverse --check $patchPath
    $patchExitCode = $LASTEXITCODE
  } finally {
    $PSNativeCommandUseErrorActionPreference = $nativePreference
  }
  if ($patchExitCode) {
    throw 'The exact repository-owned Flutter engine patch is not applied.'
  }
}

function Invoke-NativeChecked {
  param(
    [Parameter(Mandatory)] [string] $FilePath,
    [Parameter(Mandatory)] [string[]] $Arguments,
    [Parameter(Mandatory)] [string] $FailureMessage
  )

  $nativePreference = $PSNativeCommandUseErrorActionPreference
  $PSNativeCommandUseErrorActionPreference = $false
  try {
    & $FilePath @Arguments
    $exitCode = $LASTEXITCODE
  } finally {
    $PSNativeCommandUseErrorActionPreference = $nativePreference
  }
  if ($exitCode) { throw "$FailureMessage Exit code $exitCode." }
}

function Get-FlutterArguments {
  param(
    [Parameter(Mandatory)] [string] $EngineSource,
    [Parameter(Mandatory)] [System.Collections.IDictionary] $BoundParameters,
    [AllowEmptyString()] [string] $MediaPath
  )

  $arguments = @(
    'run'
    '-d'
    'windows'
    '--local-engine=host_debug'
    '--local-engine-host=host_debug'
    "--local-engine-src-path=$EngineSource"
  )
  if ($BoundParameters.ContainsKey('MediaPath')) {
    if ([string]::IsNullOrWhiteSpace($MediaPath)) {
      throw 'MediaPath must be a nonblank path when supplied.'
    }
    $arguments += "--dart-entrypoint-args=--media=$MediaPath"
  }
  $arguments
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

$engineSource = Resolve-RequiredPath $EngineSource 'EngineSource' 'Container'
$mpvRoot = Resolve-RequiredPath $MpvRoot 'MpvRoot' 'Container'
if ($PSBoundParameters.ContainsKey('MediaPath')) {
  if ([string]::IsNullOrWhiteSpace($MediaPath)) {
    throw 'MediaPath must be a nonblank path when supplied.'
  }
  $MediaPath = Resolve-RequiredPath $MediaPath 'MediaPath' 'Leaf'
}

$flutterRoot = Split-Path -Parent (Split-Path -Parent $engineSource)
$flutter = Join-Path $flutterRoot 'bin/flutter.bat'
if (-not (Test-Path -LiteralPath $flutter -PathType Leaf)) {
  throw 'EngineSource must be the engine/src directory below the pinned Flutter checkout.'
}
$engineVersion = Join-Path $flutterRoot 'bin/internal/engine.version'
if (-not (Test-Path -LiteralPath $engineVersion -PathType Leaf)) {
  throw 'Pinned Flutter checkout is missing bin/internal/engine.version.'
}
Assert-PinnedFlutterCheckout $flutterRoot

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

$engineOutput = Join-Path $engineSource 'out/host_debug'
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

$flutterArguments = Get-FlutterArguments -EngineSource $engineSource `
  -BoundParameters $PSBoundParameters -MediaPath $MediaPath

$previousMpv = Get-Item -LiteralPath 'Env:LINEUP_MPV_ROOT' -ErrorAction SilentlyContinue
$hadMpv = $null -ne $previousMpv
$previousMpvValue = if ($hadMpv) { $previousMpv.Value } else { $null }
$locationPushed = $false
$flutterExitCode = 0
try {
  Push-Location -LiteralPath $repository
  $locationPushed = $true
  $env:LINEUP_MPV_ROOT = $mpvRoot

  $flutterWindowsCache = Join-Path $flutterRoot 'bin/cache/artifacts/engine/windows-x64'
  if (-not (Test-Path -LiteralPath $flutterWindowsCache -PathType Container)) {
    Write-Host 'Pinned Flutter Windows artifacts are not cached; preparing them with the pinned flutter.bat.'
    Invoke-NativeChecked -FilePath $flutter -Arguments @('precache', '--windows') `
      -FailureMessage 'Pinned Flutter SDK cache preparation failed.'
  }

  Write-Host "Refreshing pinned host_debug engine output with $ninja."
  Invoke-NativeChecked -FilePath $ninja -Arguments @('-C', $engineOutput) `
    -FailureMessage 'Pinned host_debug engine build failed.'

  $nativePreference = $PSNativeCommandUseErrorActionPreference
  $PSNativeCommandUseErrorActionPreference = $false
  try {
    & $flutter @flutterArguments
    $flutterExitCode = $LASTEXITCODE
  } finally {
    $PSNativeCommandUseErrorActionPreference = $nativePreference
  }
  if ($flutterExitCode) {
    [Console]::Error.WriteLine("flutter run failed with exit code $flutterExitCode.")
  }
} finally {
  if ($locationPushed) { Pop-Location }
  if ($hadMpv) {
    $env:LINEUP_MPV_ROOT = $previousMpvValue
  } else {
    Remove-Item -LiteralPath 'Env:LINEUP_MPV_ROOT' -ErrorAction SilentlyContinue
  }
}

if ($flutterExitCode) { exit $flutterExitCode }
