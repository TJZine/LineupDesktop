#Requires -Version 7.4

# Inspect only the public owner/entry-point relationship. Input derivation,
# invocation, cleanup and exit behavior are exercised below in real processes.
function Assert-BuildInputWiring {
  param([string] $Path, [string[]] $Contracts)

  $tokens = $null
  $errors = $null
  $ast = [Management.Automation.Language.Parser]::ParseFile($Path, [ref] $tokens, [ref] $errors)
  if ($errors.Count) { throw "Build entry point has parse errors: $Path" }
  $commands = @($ast.FindAll({ param($node)
      $node -is [Management.Automation.Language.CommandAst]
    }, $true))
  $names = @($commands | ForEach-Object { $_.GetCommandName() })
  foreach ($contract in $Contracts) {
    if ($names -notcontains $contract -or @($ast.FindAll({ param($node)
          $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $contract
        }, $true)).Count) {
      throw "Build entry point must use the shared public contract: $contract"
    }
  }
  foreach ($command in $commands) {
    if ($command.GetCommandName() -eq 'Invoke-Expression') { throw 'Build entry points must not use shell interpolation.' }
    if ($command.GetCommandName() -eq 'Get-Command' -and @($command.FindAll({ param($node)
          $node -is [Management.Automation.Language.StringConstantExpressionAst] -and $node.Value -match '^flutter(?:\.bat)?$'
        }, $true)).Count) { throw 'Build entry points must not select Flutter from PATH.' }
    if ($command.InvocationOperator -ne [Management.Automation.Language.TokenKind]::Ampersand -or
      $command.CommandElements[0] -isnot [Management.Automation.Language.VariableExpressionAst]) { continue }
    $inFunction = $false
    for ($parent = $command.Parent; $parent; $parent = $parent.Parent) {
      if ($parent -is [Management.Automation.Language.FunctionDefinitionAst]) { $inFunction = $true; break }
    }
    if (-not $inFunction) { throw 'Flutter invocation and exit must remain in the shared operation.' }
  }
}

function Assert-WindowsBuildInputContracts {
  param([string] $LauncherPath, [string] $ReleasePath)

  Assert-BuildInputWiring $LauncherPath @('Get-LineupRepository', 'Get-LineupLaunchInput', 'Invoke-LineupLaunch')
  Assert-BuildInputWiring $ReleasePath @('Get-LineupRepository', 'Get-LineupReleaseInput', 'Invoke-LineupReleaseBuild')
  $owner = Join-Path $PSScriptRoot 'build-inputs.ps1'
  $directory = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
  function Assert-Arguments {
    param([string[]] $Actual, [string[]] $Expected)
    if ($Actual.Count -ne $Expected.Count) { throw 'Flutter argument count changed.' }
    for ($index = 0; $index -lt $Expected.Count; $index++) {
      if ($Actual[$index] -cne $Expected[$index]) { throw "Flutter argument $index changed." }
    }
  }
  function Assert-Rejected {
    param([scriptblock] $Action, [string] $Description)
    $rejected = $false
    try { & $Action | Out-Null } catch { $rejected = $true }
    if (-not $rejected) { throw "Unsafe input was accepted: $Description" }
  }
  function Invoke-FixtureGit {
    param([string] $Root, [string[]] $Arguments)
    $output = @(& git -C $Root @Arguments)
    if ($LASTEXITCODE) { throw 'Fixture Git command failed.' }
    $output
  }
  try {
    New-Item -ItemType Directory -Path $directory | Out-Null
    $wiringFixture = Join-Path $directory 'equivalent entry point.ps1'
    @'
. (Join-Path -ChildPath 'build-inputs.ps1' -Path ($PSScriptRoot))
$renamedRepository = (Get-LineupRepository)
$renamedLaunch = (Get-LineupLaunchInput -MpvRoot ($MpvRoot) -EngineSource ($EngineSource) -BoundParameters $PSBoundParameters -MediaPath $MediaPath)
(Invoke-LineupLaunch -Ninja ($ninja) -Launch $renamedLaunch)
'@ | Set-Content -LiteralPath $wiringFixture
    $launchContracts = @('Get-LineupRepository', 'Get-LineupLaunchInput', 'Invoke-LineupLaunch')
    Assert-BuildInputWiring $wiringFixture $launchContracts
    $wiringSource = Get-Content -Raw -LiteralPath $wiringFixture
    $wiringSource.Replace('Invoke-LineupLaunch', 'Invoke-UnrelatedOperation') | Set-Content -LiteralPath $wiringFixture
    Assert-Rejected { Assert-BuildInputWiring $wiringFixture $launchContracts } 'removed canonical launch operation'
    $media = Join-Path $directory 'media [1] with spaces; $literal.mp4'
    [IO.File]::WriteAllText($media, '')
    $resolved = Resolve-RequiredPath $media MediaPath Leaf
    if ($resolved -cne [IO.Path]::GetFullPath($media)) { throw 'Literal media path changed.' }
    $engine = Join-Path $directory 'engine root; $literal/engine/src'
    $mpv = Join-Path $directory 'mpv root'
    New-Item -ItemType Directory -Path $engine, $mpv -Force | Out-Null
    $engine = Resolve-RequiredPath $engine EngineSource Container
    $expectedLaunch = @('run', '-d', 'windows', '--local-engine=host_debug',
      '--local-engine-host=host_debug', "--local-engine-src-path=$engine")
    $launch = Get-LineupLaunchInput -EngineSource $engine -MpvRoot $mpv -BoundParameters @{}
    Assert-Arguments $launch.Arguments $expectedLaunch
    $withMedia = Get-LineupLaunchInput -EngineSource $engine -MpvRoot $mpv -BoundParameters @{ MediaPath = $media } -MediaPath $media
    Assert-Arguments $withMedia.Arguments ($expectedLaunch + "--dart-entrypoint-args=--media=$resolved")
    foreach ($blank in @('', ' ', "`t")) {
      Assert-Rejected { Get-LineupLaunchInput -EngineSource $engine -MpvRoot $mpv -BoundParameters @{ MediaPath = $blank } -MediaPath $blank } 'blank supplied media'
      Assert-Rejected { Resolve-RequiredPath $blank EngineSource Container } 'blank required path'
      Assert-Rejected { Get-LineupLaunchInput -EngineSource $blank -MpvRoot $mpv -BoundParameters @{} } 'blank launch engine'
    }
    Assert-Rejected { Resolve-RequiredPath (Join-Path $directory 'missing') MediaPath Leaf } 'missing media'
    Assert-Rejected { Resolve-RequiredPath $directory MediaPath Leaf } 'directory as media'
    Assert-Rejected { Resolve-RequiredPath $media EngineSource Container } 'file as engine'

    # Two real repositories make cross-repository HEAD/pubspec substitutions
    # observable. The owner is copied to its actual repository-relative location.
    foreach ($scenario in @(@{ Name = 'first'; Version = '1.2.3+45'; Build = '45'; Label = '1.2.3' },
        @{ Name = 'second'; Version = '9.8.7+65'; Build = '65'; Label = '9.8.7' })) {
      $root = Join-Path $directory $scenario.Name
      $tools = Join-Path $root 'tool/windows'
      New-Item -ItemType Directory -Path $tools -Force | Out-Null
      $fixtureOwner = Join-Path $tools 'build-inputs.ps1'
      Copy-Item -LiteralPath $owner -Destination $fixtureOwner
      $pubspec = Join-Path $root 'pubspec.yaml'
      "version: $($scenario.Version) # release" | Set-Content -LiteralPath $pubspec
      Invoke-FixtureGit $root @('init', '--quiet')
      Invoke-FixtureGit $root @('add', '.')
      Invoke-FixtureGit $root @('-c', 'user.name=Lineup fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '--quiet', '-m', $scenario.Name)
      $commit = Invoke-FixtureGit $root @('rev-parse', '--verify', 'HEAD')
      . $fixtureOwner
      $release = Get-LineupReleaseInput -EngineSource $engine
      if ($release.Repository -ne $root -or $release.SourceCommit -cne $commit) { throw 'Release identity escaped its canonical repository.' }
      Assert-Arguments $release.Arguments @('build', 'windows', '--local-engine=host_release',
        '--local-engine-host=host_release', "--local-engine-src-path=$engine",
        "--dart-define=LINEUP_VERSION=$($scenario.Label)", "--dart-define=LINEUP_BUILD=$($scenario.Build)@$commit")
      Assert-Rejected { Get-LineupReleaseInput -EngineSource $engine -PubspecPath $media } 'independently supplied pubspec'
      Assert-Rejected { Get-LineupReleaseInput -EngineSource $engine -SourceCommit ('0' * 40) } 'independently supplied commit'
      Assert-Rejected { Get-LineupReleaseInput -EngineSource ' ' } 'blank release engine'
      foreach ($badVersion in @('name: missing-version', 'version: 1.2.3', 'version: 1.2.3+beta', "version: 1.2.3+45`nversion: 2.0.0+46")) {
        $badVersion | Set-Content -LiteralPath $pubspec
        Assert-Rejected { Get-LineupReleaseInput -EngineSource $engine } 'invalid release pubspec'
      }
      $nested = Join-Path $root 'nested/tool/windows'
      New-Item -ItemType Directory -Path $nested -Force | Out-Null
      Copy-Item -LiteralPath $owner -Destination (Join-Path $nested 'build-inputs.ps1')
      . (Join-Path $nested 'build-inputs.ps1')
      Assert-Rejected { Get-LineupReleaseInput -EngineSource $engine } 'unrelated parent Git root'
    }
    $unborn = Join-Path $directory 'unborn/tool/windows'
    New-Item -ItemType Directory -Path $unborn -Force | Out-Null
    Copy-Item -LiteralPath $owner -Destination (Join-Path $unborn 'build-inputs.ps1')
    $unbornRoot = Join-Path $directory 'unborn'
    'version: 1.2.3+45' | Set-Content -LiteralPath (Join-Path $unbornRoot 'pubspec.yaml')
    Invoke-FixtureGit $unbornRoot @('init', '--quiet')
    . (Join-Path $unborn 'build-inputs.ps1')
    Assert-Rejected { Get-LineupReleaseInput -EngineSource $engine } 'no actual HEAD'
    . $owner

    # Release invocation consumes the same complete operation input that owns
    # version/commit association; capture real delivery and its failure result.
    $releaseFixture = Join-Path $directory 'release fixture.ps1'
    @'
$args | ConvertTo-Json -Compress | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'release arguments.json')
exit 0
'@ | Set-Content -LiteralPath $releaseFixture
    $release.Flutter = $releaseFixture
    Invoke-LineupReleaseBuild -Release $release
    $delivered = Get-Content -Raw -LiteralPath (Join-Path $directory 'release arguments.json') | ConvertFrom-Json
    Assert-Arguments $delivered $release.Arguments
    'exit 23' | Set-Content -LiteralPath $releaseFixture
    $failed = $false
    try { Invoke-LineupReleaseBuild -Release $release } catch {
      if ($_.Exception.Message -notmatch 'Flutter Windows release build failed\. Exit code 23\.') { throw }
      $failed = $true
    }
    if (-not $failed) { throw 'Canonical release invocation lost its failure status.' }

    # Real child processes exercise the production operation's exit and cleanup.
    # Windows platform executables alone are replaced; orchestration stays real.
    $runtime = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $flutterFixture = Join-Path $directory 'flutter fixture.ps1'
    @'
if ((Get-Location).Path -ne $env:LINEUP_EXPECTED_CWD -or $env:LINEUP_MPV_ROOT -ne $env:LINEUP_EXPECTED_MPV) { exit 90 }
Add-Content -LiteralPath $env:LINEUP_TEST_LOG -Value ($args | ConvertTo-Json -Compress)
if ($args[0] -eq 'precache') { exit 0 }
exit ([int] $env:LINEUP_TEST_EXIT)
'@ | Set-Content -LiteralPath $flutterFixture
    $ninjaFixture = Join-Path $directory 'ninja fixture.ps1'
    @'
if ($args.Count -ne 2 -or $args[0] -ne '-C' -or $args[1] -ne $env:LINEUP_EXPECTED_OUTPUT) { exit 91 }
Add-Content -LiteralPath $env:LINEUP_TEST_LOG -Value 'ninja'
exit ([int] $env:LINEUP_NINJA_EXIT)
'@ | Set-Content -LiteralPath $ninjaFixture
    $child = Join-Path $directory 'launch child.ps1'
    @'
param($Owner, $Engine, $Mpv, $Flutter, $Ninja, $Log, [int] $Code, [int] $NinjaCode, $ExistingMpv)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
. $Owner
$launch = Get-LineupLaunchInput -EngineSource $Engine -MpvRoot $Mpv -BoundParameters @{}
$launch.Repository = Split-Path -Parent $Log
$launch.Flutter = $Flutter
$env:LINEUP_EXPECTED_CWD = $launch.Repository
$env:LINEUP_EXPECTED_MPV = $launch.MpvRoot
$env:LINEUP_EXPECTED_OUTPUT = $launch.EngineOutput
$env:LINEUP_TEST_LOG = $Log
$env:LINEUP_TEST_EXIT = "$Code"
$env:LINEUP_NINJA_EXIT = "$NinjaCode"
if ($ExistingMpv -eq 'true') { $env:LINEUP_MPV_ROOT = 'original value' } else { Remove-Item Env:LINEUP_MPV_ROOT -ErrorAction SilentlyContinue }
$originalLocation = (Get-Location).Path
try { Invoke-LineupLaunch -Launch $launch -Ninja $Ninja } finally {
  $restored = if ($ExistingMpv -eq 'true') { $env:LINEUP_MPV_ROOT -eq 'original value' } else { -not (Test-Path Env:LINEUP_MPV_ROOT) }
  if (-not $restored -or (Get-Location).Path -ne $originalLocation -or -not $PSNativeCommandUseErrorActionPreference) { exit 92 }
  Add-Content -LiteralPath $Log -Value 'cleanup'
}
'@ | Set-Content -LiteralPath $child
    foreach ($scenario in @(@{ Exit = 0; Ninja = 0; Existing = 'true' },
        @{ Exit = 23; Ninja = 0; Existing = 'false' }, @{ Exit = 0; Ninja = 24; Existing = 'true' })) {
      $log = Join-Path $directory ([Guid]::NewGuid().ToString() + '.log')
      $nativePreference = $PSNativeCommandUseErrorActionPreference
      $PSNativeCommandUseErrorActionPreference = $false
      try {
        & $runtime -NoProfile -File $child $owner $engine $mpv $flutterFixture $ninjaFixture $log $scenario.Exit $scenario.Ninja $scenario.Existing
        $status = $LASTEXITCODE
      } finally { $PSNativeCommandUseErrorActionPreference = $nativePreference }
      $lines = @(Get-Content -LiteralPath $log)
      if ($lines[-1] -ne 'cleanup' -or ($scenario.Ninja -eq 0 -and $status -ne $scenario.Exit) -or
        ($scenario.Ninja -ne 0 -and ($status -eq 0 -or $lines.Count -ne 3))) { throw 'Canonical launch exit, ordering or cleanup failed.' }
      if ($scenario.Ninja -eq 0) {
        if ($lines.Count -ne 4 -or $lines[1] -ne 'ninja') { throw 'Launch operation order changed.' }
        Assert-Arguments @($lines[0] | ConvertFrom-Json) @('precache', '--windows')
        Assert-Arguments @($lines[2] | ConvertFrom-Json) $expectedLaunch
      }
    }
    $literalChild = Join-Path $directory 'literal child.ps1'
    @'
param([string] $Value)
if ($Value -cne 'spaces; $literal [1]') { exit 91 }
exit 0
'@ | Set-Content -LiteralPath $literalChild
    Invoke-NativeChecked -FilePath $runtime -Arguments @('-NoProfile', '-File', $literalChild, 'spaces; $literal [1]') -FailureMessage 'Native argument fidelity failed.'
    $nativePreference = $PSNativeCommandUseErrorActionPreference
    $rejected = $false
    try { Invoke-NativeChecked -FilePath $runtime -Arguments @('-NoProfile', '-Command', 'exit 23') -FailureMessage 'Deliberate failure.' } catch {
      if ($_.Exception.Message -notmatch 'Exit code 23\.') { throw }
      $rejected = $true
    }
    if (-not $rejected -or $nativePreference -ne $PSNativeCommandUseErrorActionPreference) { throw 'Checked invocation lost native status or preference.' }
    Write-Host 'Repository-derived release inputs and production launch/exit contracts passed (Windows mechanisms replaced by fixtures).'
  } finally {
    . $owner
    if (Test-Path -LiteralPath $directory) { Remove-Item -LiteralPath $directory -Recurse -Force }
  }
}
