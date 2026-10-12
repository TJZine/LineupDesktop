#Requires -Version 7.4

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

function Get-FlutterArguments {
  param(
    [Parameter(Mandatory)] [string] $EngineSource,
    [Parameter(Mandatory)] [System.Collections.IDictionary] $BoundParameters,
    [AllowEmptyString()] [string] $MediaPath
  )

  if ([string]::IsNullOrWhiteSpace($EngineSource)) {
    throw 'EngineSource must be a nonblank path.'
  }
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

function Get-PubspecVersion {
  param([Parameter(Mandatory)] [string] $Path)

  $versionLines = @(
    Get-Content -LiteralPath $Path | Where-Object { $_ -match '^version\s*:' }
  )
  if ($versionLines.Count -ne 1) {
    throw 'pubspec.yaml must contain exactly one top-level version entry.'
  }
  if ($versionLines[0] -notmatch
    '^version\s*:\s*(?<name>[^+\s]+)\+(?<build>[0-9]+)\s*(?:#.*)?$') {
    throw 'pubspec.yaml version must have a name and numeric build number (name+build).'
  }

  [pscustomobject]@{
    Name = $Matches.name
    Build = $Matches.build
  }
}

function Assert-NoTrackedSymlinks {
  param(
    [Parameter(Mandatory)] [string] $Repository,
    [scriptblock] $FailureReporter = {
      param([Parameter(Mandatory)] [string] $Message)
      throw $Message
    }
  )

  $nativeErrorPreference = $PSNativeCommandUseErrorActionPreference
  $PSNativeCommandUseErrorActionPreference = $false
  try {
    $entries = @(& git -C $Repository ls-files --stage)
    if ($LASTEXITCODE) { throw 'git ls-files failed while checking tracked symlinks.' }
  } finally {
    $PSNativeCommandUseErrorActionPreference = $nativeErrorPreference
  }
  $symlinks = @($entries | Where-Object { $_ -match "^120000\s+\S+\s+[0-3]`t" })
  if ($symlinks.Count) {
    & $FailureReporter "Release source tree contains $($symlinks.Count) tracked symbolic link(s)."
    throw 'The tracked-symlink failure reporter returned unexpectedly.'
  }
}

function Assert-NoReparsePoints {
  param(
    [Parameter(Mandatory)] [string] $Root,
    [scriptblock] $FailureReporter = {
      param([Parameter(Mandatory)] [string] $Message)
      throw $Message
    }
  )

  $rootPath = [IO.Path]::GetFullPath($Root)
  $items = @(
    Get-Item -LiteralPath $rootPath -Force -ErrorAction Stop
    Get-ChildItem -LiteralPath $rootPath -Recurse -Force -ErrorAction Stop
  )
  foreach ($item in $items) {
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) { continue }
    $relative = [IO.Path]::GetRelativePath($rootPath, $item.FullName).Replace('\', '/')
    & $FailureReporter "Release build contains an unsupported reparse point: $relative."
    throw 'The reparse-point failure reporter returned unexpectedly.'
  }
}

function Get-ReparsePointPathWithin {
  param(
    [Parameter(Mandatory)] [string] $Path,
    [Parameter(Mandatory)] [string] $Boundary
  )

  $current = [IO.Path]::GetFullPath($Path)
  $boundaryPath = [IO.Path]::GetFullPath($Boundary)
  while ($true) {
    $item = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
    if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
      return $current
    }
    if ($current.Equals($boundaryPath, [StringComparison]::OrdinalIgnoreCase)) {
      return $null
    }
    $parent = [IO.Path]::GetDirectoryName($current)
    if ([string]::IsNullOrEmpty($parent) -or
      -not $current.StartsWith($boundaryPath + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
      throw 'Path is not below the required containment boundary.'
    }
    $current = $parent
  }
}

function Get-BuildInputs {
  param(
    [Parameter(Mandatory)] [string] $Root,
    [scriptblock] $FailureReporter = {
      param([Parameter(Mandatory)] [string] $Message)
      throw $Message
    }
  )

  Assert-NoReparsePoints -Root $Root -FailureReporter $FailureReporter

  $required = @(
    'lineup_desktop.exe',
    'flutter_windows.dll',
    'flutter_secure_storage_windows_plugin.dll',
    'libmpv-2.dll'
  )
  $paths = [System.Collections.Generic.List[string]]::new()
  foreach ($relative in $required) {
    $path = Join-Path $Root $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
      & $FailureReporter "Release build is missing $relative."
      throw 'The build-input failure reporter returned unexpectedly.'
    }
    $paths.Add($relative)
  }

  $data = Join-Path $Root 'data'
  if (-not (Test-Path -LiteralPath $data -PathType Container)) {
    & $FailureReporter 'Release build is missing the data directory.'
    throw 'The build-input failure reporter returned unexpectedly.'
  }
  foreach ($file in Get-ChildItem -LiteralPath $data -Recurse -File) {
    $paths.Add($file.FullName.Substring($Root.Length + 1).Replace('\', '/'))
  }

  $nativeAssets = Join-Path $Root 'native_assets.json'
  if (Test-Path -LiteralPath $nativeAssets -PathType Leaf) {
    $paths.Add('native_assets.json')
  }
  @($paths | Sort-Object -Unique)
}

# The script location is the source authority. Callers cannot supply an unrelated
# pubspec/commit pair or silently use a parent repository's HEAD.
function Get-LineupRepository {
  [IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath '../..'))
}

function Get-LineupReleaseInput {
  [CmdletBinding()]
  param([Parameter(Mandatory)] [string] $EngineSource)

  $repository = Get-LineupRepository
  $nativePreference = $PSNativeCommandUseErrorActionPreference
  $PSNativeCommandUseErrorActionPreference = $false
  try {
    # An empty prefix proves this directory is the Git root without comparing
    # physical/logical spellings of the system's temporary-directory symlinks.
    $prefix = @(& git -C $repository rev-parse --show-prefix)
    if ($LASTEXITCODE -or $prefix.Count -gt 1 -or ($prefix -join '') -ne '') {
      throw 'Release inputs must belong to the canonical Lineup repository.'
    }
    $commit = @(& git -C $repository rev-parse --verify HEAD)
    if ($LASTEXITCODE -or $commit.Count -ne 1 -or
      $commit[0] -cnotmatch '^[a-fA-F0-9]{40}$') {
      throw 'Release build identity must contain an exact Git commit.'
    }
  } finally {
    $PSNativeCommandUseErrorActionPreference = $nativePreference
  }
  $version = Get-PubspecVersion -Path (Join-Path -Path $repository -ChildPath 'pubspec.yaml')
  $engine = Resolve-RequiredPath -Path $EngineSource -Name EngineSource -PathType Container
  $flutterRoot = Split-Path -Parent (Split-Path -Parent $engine)
  [pscustomobject]@{
    Repository = $repository
    SourceCommit = $commit[0]
    EngineSource = $engine
    FlutterRoot = $flutterRoot
    Flutter = Join-Path -Path $flutterRoot -ChildPath 'bin/flutter.bat'
    Arguments = @(
      'build'
      'windows'
      '--local-engine=host_release'
      '--local-engine-host=host_release'
      "--local-engine-src-path=$engine"
      "--dart-define=LINEUP_VERSION=$($version.Name)"
      "--dart-define=LINEUP_BUILD=$($version.Build)@$($commit[0])"
    )
  }
}

function Get-LineupLaunchInput {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string] $EngineSource,
    [Parameter(Mandatory)] [string] $MpvRoot,
    [Parameter(Mandatory)] [System.Collections.IDictionary] $BoundParameters,
    [AllowEmptyString()] [string] $MediaPath
  )

  $engine = Resolve-RequiredPath -Path $EngineSource -Name EngineSource -PathType Container
  $mpv = Resolve-RequiredPath -Path $MpvRoot -Name MpvRoot -PathType Container
  if ($BoundParameters.ContainsKey('MediaPath')) {
    $MediaPath = Resolve-RequiredPath -Path $MediaPath -Name MediaPath -PathType Leaf
  }
  $flutterRoot = Split-Path -Parent (Split-Path -Parent $engine)
  [pscustomobject]@{
    Repository = Get-LineupRepository
    EngineSource = $engine
    MpvRoot = $mpv
    FlutterRoot = $flutterRoot
    Flutter = Join-Path -Path $flutterRoot -ChildPath 'bin/flutter.bat'
    EngineOutput = Join-Path -Path $engine -ChildPath 'out/host_debug'
    Arguments = @(Get-FlutterArguments -EngineSource $engine `
      -BoundParameters $BoundParameters -MediaPath $MediaPath)
  }
}

function Invoke-LineupReleaseBuild {
  [CmdletBinding()]
  param([Parameter(Mandatory)] [psobject] $Release)

  Invoke-NativeChecked -FilePath $Release.Flutter -Arguments $Release.Arguments `
    -FailureMessage 'Flutter Windows release build failed.'
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

# The canonical launcher calls this complete operation. Exit belongs here so a
# wrapper cannot forget to forward Flutter's status after restoring cwd/env.
function Invoke-LineupLaunch {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [psobject] $Launch,
    [Parameter(Mandatory)] [string] $Ninja
  )

  $previousMpv = Get-Item -LiteralPath 'Env:LINEUP_MPV_ROOT' -ErrorAction SilentlyContinue
  $hadMpv = $null -ne $previousMpv
  $previousMpvValue = if ($hadMpv) { $previousMpv.Value } else { $null }
  $locationPushed = $false
  $flutterExitCode = 0
  try {
    Push-Location -LiteralPath $Launch.Repository
    $locationPushed = $true
    $env:LINEUP_MPV_ROOT = $Launch.MpvRoot

    $cache = Join-Path -Path $Launch.FlutterRoot -ChildPath 'bin/cache/artifacts/engine/windows-x64'
    if (-not (Test-Path -LiteralPath $cache -PathType Container)) {
      Write-Host 'Pinned Flutter Windows artifacts are not cached; preparing them with the pinned flutter.bat.'
      Invoke-NativeChecked -FilePath $Launch.Flutter -Arguments @('precache', '--windows') `
        -FailureMessage 'Pinned Flutter SDK cache preparation failed.'
    }

    Write-Host "Refreshing pinned host_debug engine output with $Ninja."
    Invoke-NativeChecked -FilePath $Ninja -Arguments @('-C', $Launch.EngineOutput) `
      -FailureMessage 'Pinned host_debug engine build failed.'

    $nativePreference = $PSNativeCommandUseErrorActionPreference
    $PSNativeCommandUseErrorActionPreference = $false
    try {
      $arguments = $Launch.Arguments
      & $Launch.Flutter @arguments
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
  exit $flutterExitCode
}
