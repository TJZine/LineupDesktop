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
    '--local-engine=lineup_ax_debug_x64'
    '--local-engine-host=lineup_ax_debug_x64'
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

function Get-LineupPackageInput {
  [CmdletBinding()]
  param(
    [string] $BuildDirectory = 'build/windows/x64/runner/Release',
    [string] $Destination
  )

  $repository = Get-LineupRepository
  $version = Get-PubspecVersion -Path (Join-Path $repository 'pubspec.yaml')
  if (-not $Destination) {
    $Destination = "build/package/LineupDesktop-$($version.Name)-$($version.Build)-windows-x64"
  }
  $destinationPath = [IO.Path]::GetFullPath((Join-Path $repository $Destination))
  $packageRoot = [IO.Path]::GetFullPath((Join-Path $repository 'build/package'))
  if (-not $destinationPath.StartsWith($packageRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Package destination must be below $packageRoot."
  }
  [pscustomobject]@{
    Version = "$($version.Name)+$($version.Build)"
    BuildDirectory = [IO.Path]::GetFullPath((Join-Path $repository $BuildDirectory))
    Destination = $destinationPath
  }
}

function Get-VerifiedWindowsEngine {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string] $Root,
    [Parameter(Mandatory)] [ValidateSet('debug', 'release')] [string] $Mode
  )
  $name = "lineup_ax_${Mode}_x64"
  $nativePreference = $PSNativeCommandUseErrorActionPreference
  $PSNativeCommandUseErrorActionPreference = $false
  try {
    $output = @(& python (Join-Path (Get-LineupRepository) 'tool/flutter_engine/desktop_accessibility.py') `
      verify --flutter-root $Root --platform windows --architecture x64 --mode $Mode --output-name $name)
    $status = $LASTEXITCODE
  } finally {
    $PSNativeCommandUseErrorActionPreference = $nativePreference
  }
  if ($status) { throw "Combined Windows engine verification failed. Exit code $status. Build a fresh candidate." }
  try { $selected = ($output -join "`n") | ConvertFrom-Json -ErrorAction Stop } catch {
    throw 'Combined Windows engine verifier returned invalid JSON.'
  }
  $expectedBinary = [IO.Path]::GetFullPath((Join-Path $Root "engine/src/out/$name/flutter_windows.dll"))
  if ($selected.kind -cne 'verified-local-desktop-accessibility' -or
    $selected.platform -cne 'windows' -or $selected.architecture -cne 'x64' -or
    $selected.mode -cne $Mode -or $selected.outputName -cne $name -or
    $selected.binary -isnot [string] -or
    [IO.Path]::GetFullPath($selected.binary) -ne $expectedBinary -or
    [IO.Path]::GetFullPath($selected.flutterRoot) -ne [IO.Path]::GetFullPath($Root) -or
    [IO.Path]::GetFullPath($selected.engineSource) -ne [IO.Path]::GetFullPath((Join-Path $Root 'engine/src')) -or
    $selected.binarySha256 -cnotmatch '^[a-f0-9]{64}$' -or
    $selected.provenanceSha256 -cnotmatch '^[a-f0-9]{64}$' -or -not $selected.recipe) {
    throw 'Combined Windows engine verifier returned the wrong output or identity.'
  }
  $selected
}

function Get-WindowsEngineReceipt {
  param([Parameter(Mandatory)] [psobject] $Selected)
  # Export only portable identities, never local checkout/toolchain paths.
  [ordered]@{
    recipe = $Selected.recipe
    outputName = $Selected.outputName
    mode = $Selected.mode
    architecture = $Selected.architecture
    provenanceSha256 = $Selected.provenanceSha256
    binarySha256 = $Selected.binarySha256
  }
}

function Assert-WindowsEngineReceipt {
  param([Parameter(Mandatory)] [psobject] $Receipt)
  $repository = Get-LineupRepository
  $metadata = Import-PowerShellDataFile -LiteralPath (Join-Path $repository 'tool/windows/build-metadata.psd1')
  $manifest = Get-Content -Raw -LiteralPath (Join-Path $repository 'tool/flutter_engine/desktop-accessibility.json') | ConvertFrom-Json
  if ($Receipt.outputName -cne 'lineup_ax_release_x64' -or $Receipt.mode -cne 'release' -or
    $Receipt.architecture -cne 'x64' -or $Receipt.provenanceSha256 -cnotmatch '^[a-f0-9]{64}$' -or
    $Receipt.binarySha256 -cnotmatch '^[a-f0-9]{64}$' -or
    $Receipt.recipe.frameworkRevision -cne $metadata.FlutterFrameworkRevision -or
    $Receipt.recipe.engineVersion -cne $metadata.FlutterEngineRevision) { throw 'Invalid combined engine receipt identity.' }
  foreach ($name in @('tool/flutter_version.json', 'tool/windows/build-metadata.psd1')) {
    if ($Receipt.recipe.pinSha256.$name -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $repository $name)).Hash) {
      throw 'Combined engine receipt pin mismatch.'
    }
  }
  if ($Receipt.recipe.manifestSha256 -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $repository 'tool/flutter_engine/desktop-accessibility.json')).Hash) {
    throw 'Combined engine receipt manifest mismatch.'
  }
  $expected = @($metadata.FlutterEnginePatchPath, 'tool/flutter_engine/0002-desktop-accessibility.patch')
  if (@($Receipt.recipe.patches).Count -ne $expected.Count) { throw 'Combined engine receipt requires both ordered patches.' }
  for ($index = 0; $index -lt $expected.Count; $index++) {
    $patch = $Receipt.recipe.patches[$index]
    if ($patch.path -cne $expected[$index] -or
      $patch.sha256 -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $repository $expected[$index])).Hash) {
      throw 'Combined engine receipt patch order/hash mismatch.'
    }
  }
  if ($manifest.patches[0].path -cne $expected[1] -or
    $manifest.patches[0].sha256 -ne $Receipt.recipe.patches[1].sha256) { throw 'Combined engine manifest authority mismatch.' }
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
      '--local-engine=lineup_ax_release_x64'
      '--local-engine-host=lineup_ax_release_x64'
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
    EngineOutput = Join-Path -Path $engine -ChildPath 'out/lineup_ax_debug_x64'
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

function Invoke-LineupLaunch {
  [CmdletBinding()]
  param([Parameter(Mandatory)] [psobject] $Launch)

  $previousMpv = Get-Item -LiteralPath 'Env:LINEUP_MPV_ROOT' -ErrorAction SilentlyContinue
  $hadMpv = $null -ne $previousMpv
  $previousMpvValue = if ($hadMpv) { $previousMpv.Value } else { $null }
  $locationPushed = $false
  $flutterExitCode = 0
  try {
    Push-Location -LiteralPath $Launch.Repository
    $locationPushed = $true
    $env:LINEUP_MPV_ROOT = $Launch.MpvRoot

    Get-VerifiedWindowsEngine -Root $Launch.FlutterRoot -Mode debug | Out-Null
    $cache = Join-Path -Path $Launch.FlutterRoot -ChildPath 'bin/cache/artifacts/engine/windows-x64'
    if (-not (Test-Path -LiteralPath $cache -PathType Container)) {
      Write-Host 'Pinned Flutter Windows artifacts are not cached; preparing them with the pinned flutter.bat.'
      Invoke-NativeChecked -FilePath $Launch.Flutter -Arguments @('precache', '--windows') `
        -FailureMessage 'Pinned Flutter SDK cache preparation failed.'
    }

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
