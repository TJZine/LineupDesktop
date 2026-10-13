#Requires -Version 7.4

function Assert-WindowsReleaseAuthorities {
  $owner = Join-Path $PSScriptRoot 'build-inputs.ps1'
  $directory = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())

  function Invoke-AuthorityFixtureGit {
    param([string] $Root, [string[]] $Arguments)
    $output = @(& git -C $Root @Arguments)
    if ($LASTEXITCODE) { throw "Fixture git failed: $($Arguments -join ' ')" }
    $output
  }
  function Assert-AuthorityRejected {
    param([scriptblock] $Action, [string] $Expected)
    try { & $Action | Out-Null } catch {
      if ($_.Exception.Message -notlike "*$Expected*") { throw }
      return
    }
    throw "Expected rejection: $Expected"
  }

  try {
    $tools = Join-Path $directory 'package/tool/windows'
    New-Item -ItemType Directory -Path $tools -Force | Out-Null
    $fixtureOwner = Join-Path $tools 'build-inputs.ps1'
    Copy-Item -LiteralPath $owner -Destination $fixtureOwner
    $packageScript = Join-Path $tools 'package.ps1'
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'package.ps1') -Destination $packageScript
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'build-metadata.psd1') -Destination $tools
    . $fixtureOwner
    $root = Get-LineupRepository
    $pubspec = Join-Path $root 'pubspec.yaml'
    foreach ($line in @('version: 1.2.3+45', 'version: 1.2.3+45 # release')) {
      $line | Set-Content -LiteralPath $pubspec
      $input = Get-LineupPackageInput
      $expected = [IO.Path]::GetFullPath((Join-Path $root 'build/package/LineupDesktop-1.2.3-45-windows-x64'))
      if ($input.Version -cne '1.2.3+45' -or $input.Destination -cne $expected -or
        $input.BuildDirectory -cne (Join-Path $root 'build/windows/x64/runner/Release')) {
        throw 'Consumed package version, build path or archive destination changed.'
      }
      # Run the actual package entry point in its copied repository. The existing
      # destination guard stops before Git/build/runtime checks or artifact writes.
      New-Item -ItemType Directory -Path $input.BuildDirectory, $expected -Force | Out-Null
      Assert-AuthorityRejected { & $packageScript } "Package destination already exists: $expected"
      $custom = Get-LineupPackageInput -BuildDirectory 'build/custom' -Destination 'build/package/custom'
      if ($custom.Destination -cne (Join-Path $root 'build/package/custom') -or
        $custom.BuildDirectory -cne (Join-Path $root 'build/custom')) {
        throw 'Explicit package paths changed.'
      }
      Assert-AuthorityRejected { Get-LineupPackageInput -Destination 'build/package/../escape' } 'Package destination must be below'
    }
    foreach ($line in @('name: missing', 'version: 1.2.3', 'version: 1.2.3+beta', "version: 1.2.3+45`nversion: 2.0.0+46")) {
      $line | Set-Content -LiteralPath $pubspec
      Assert-AuthorityRejected { Get-LineupPackageInput } 'pubspec.yaml'
      Assert-AuthorityRejected { & $packageScript } 'pubspec.yaml'
    }
    . $owner

    # Real Git checkout and patch data exercise all pinned-checkout predicates.
    $flutter = Join-Path $directory 'flutter'
    New-Item -ItemType Directory -Path (Join-Path $flutter 'bin/internal') -Force | Out-Null
    $manager = Join-Path $flutter 'manager.txt'
    $engine = Join-Path $flutter 'bin/internal/engine.version'
    [IO.File]::WriteAllText($manager, "original`n")
    [IO.File]::WriteAllText($engine, "engine-pin`n")
    [IO.File]::WriteAllText((Join-Path $flutter 'other.txt'), "unchanged`n")
    Invoke-AuthorityFixtureGit $flutter @('init', '--quiet')
    Invoke-AuthorityFixtureGit $flutter @('config', 'core.autocrlf', 'false')
    Invoke-AuthorityFixtureGit $flutter @('add', '.')
    Invoke-AuthorityFixtureGit $flutter @('-c', 'user.name=Lineup fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '--quiet', '-m', 'fixture')
    $head = Invoke-AuthorityFixtureGit $flutter @('rev-parse', '--verify', 'HEAD')
    [IO.File]::WriteAllText($manager, "patched`n")
    $patch = Join-Path $directory 'manager.patch'
    $diff = Invoke-AuthorityFixtureGit $flutter @('diff', '--', 'manager.txt')
    [IO.File]::WriteAllText($patch, ($diff -join "`n") + "`n")
    Invoke-AuthorityFixtureGit $flutter @('checkout', '--', 'manager.txt')
    Invoke-AuthorityFixtureGit $flutter @('apply', $patch)
    $metadata = @{
      FlutterFrameworkRevision = $head
      FlutterEngineRevision = 'engine-pin'
      FlutterManagerPath = 'manager.txt'
      FlutterPatchedManagerSha256 = Get-NormalizedTextSha256 $manager
    }
    $check = { Assert-PinnedFlutterCheckout -Root $flutter -Metadata $metadata -PatchPath $patch }
    & $check
    $preference = $PSNativeCommandUseErrorActionPreference
    foreach ($nativePreference in @($false, $true)) {
      $PSNativeCommandUseErrorActionPreference = $nativePreference
      & $check
      $metadata.FlutterFrameworkRevision = '0' * 40
      Assert-AuthorityRejected $check 'pinned framework revision'
      $metadata.FlutterFrameworkRevision = $head
      [IO.File]::WriteAllText($engine, "wrong-engine`n")
      Assert-AuthorityRejected $check 'required engine revision'
      Invoke-AuthorityFixtureGit $flutter @('checkout', '--', 'bin/internal/engine.version')
      [IO.File]::WriteAllText((Join-Path $flutter 'other.txt'), "changed`n")
      Assert-AuthorityRejected $check 'only the repository-owned engine patch'
      Invoke-AuthorityFixtureGit $flutter @('checkout', '--', 'other.txt')
      [IO.File]::WriteAllText($manager, "wrong bytes`n")
      Assert-AuthorityRejected $check 'pinned result'
      [IO.File]::WriteAllText($manager, "patched`n")
      $wrongPatch = Join-Path $directory 'wrong.patch'
      [IO.File]::WriteAllText($wrongPatch, [IO.File]::ReadAllText($patch).Replace('+patched', '+other'))
      Assert-AuthorityRejected { Assert-PinnedFlutterCheckout -Root $flutter -Metadata $metadata -PatchPath $wrongPatch } 'exact repository-owned Flutter engine patch'
      Assert-AuthorityRejected { Assert-PinnedFlutterCheckout -Root $directory -Metadata $metadata -PatchPath $patch } 'git rev-parse'
      if ($PSNativeCommandUseErrorActionPreference -ne $nativePreference) { throw 'Checkout verifier changed native error preference.' }
      & $check
    }
    Invoke-AuthorityFixtureGit $flutter @('checkout', '--', 'manager.txt')
    Assert-AuthorityRejected $check 'only the repository-owned engine patch'
    Invoke-AuthorityFixtureGit $flutter @('apply', $patch)
    & $check
    $PSNativeCommandUseErrorActionPreference = $preference
    # Normalized manager hashes tolerate host line endings; Git still checks patch applicability.
    [IO.File]::WriteAllText($manager, "patched`r`n")
    if ((Get-NormalizedTextSha256 $manager) -ne $metadata.FlutterPatchedManagerSha256) { throw 'Manager normalization changed.' }
    [IO.File]::WriteAllText($manager, "patched`n")
    & $check
    Write-Host 'Package identity/path and pinned patched-checkout authority controls passed (real temporary Git/patch fixtures).'
  } finally {
    . $owner
    if (Test-Path -LiteralPath $directory) { Remove-Item -LiteralPath $directory -Recurse -Force }
  }
}
