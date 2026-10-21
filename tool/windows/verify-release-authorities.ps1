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

    # Validate the portable receipt against the real canonical inputs without an
    # engine checkout. Full schema/artifact packaging controls run on Windows CI.
    $repository = Get-LineupRepository
    $metadata = Import-PowerShellDataFile -LiteralPath (Join-Path $repository 'tool/windows/build-metadata.psd1')
    $pins = [ordered]@{}
    foreach ($name in @('tool/flutter_version.json', 'tool/windows/build-metadata.psd1')) {
      $pins[$name] = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $repository $name)).Hash.ToLowerInvariant()
    }
    $patches = @($metadata.FlutterEnginePatchPath, 'tool/flutter_engine/0002-desktop-accessibility.patch') | ForEach-Object {
      @{ path = $_; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $repository $_)).Hash.ToLowerInvariant() }
    }
    $validReceipt = @{
      outputName = 'lineup_ax_release_x64'; mode = 'release'; architecture = 'x64'
      provenanceSha256 = 'a' * 64; binarySha256 = 'b' * 64
      recipe = @{
        frameworkRevision = $metadata.FlutterFrameworkRevision; engineVersion = $metadata.FlutterEngineRevision
        pinSha256 = $pins; patches = @($patches)
        manifestSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $repository 'tool/flutter_engine/desktop-accessibility.json')).Hash.ToLowerInvariant()
      }
    } | ConvertTo-Json -Depth 10
    Assert-WindowsEngineReceipt ($validReceipt | ConvertFrom-Json)
    foreach ($probe in @('order', 'missing', 'manifest', 'provenance', 'binary', 'mode', 'pin')) {
      $receipt = $validReceipt | ConvertFrom-Json
      switch ($probe) {
        'order' { $receipt.recipe.patches = @($receipt.recipe.patches[1], $receipt.recipe.patches[0]) }
        'missing' { $receipt.recipe.patches = @($receipt.recipe.patches[0]) }
        'manifest' { $receipt.recipe.manifestSha256 = '0' * 64 }
        'provenance' { $receipt.provenanceSha256 = 'invalid' }
        'binary' { $receipt.binarySha256 = 'invalid' }
        'mode' { $receipt.mode = 'debug' }
        'pin' { $receipt.recipe.pinSha256.'tool/flutter_version.json' = '0' * 64 }
      }
      $expectedError = switch ($probe) {
        'order' { 'patch order/hash mismatch' }
        'missing' { 'both ordered patches' }
        'manifest' { 'manifest mismatch' }
        'pin' { 'pin mismatch' }
        default { 'receipt identity' }
      }
      Assert-AuthorityRejected { Assert-WindowsEngineReceipt $receipt } $expectedError
      Assert-WindowsEngineReceipt ($validReceipt | ConvertFrom-Json)
    }

    # Execute the real adapter against a controlled process boundary. Python
    # temporary-Git fixtures own exact combined source policy; this tests checked
    # invocation/JSON/output rejection without duplicating that policy in PS.
    $flutter = Join-Path $directory 'flutter'
    $expectedBinary = Join-Path $flutter 'engine/src/out/lineup_ax_debug_x64/flutter_windows.dll'
    New-Item -ItemType Directory -Path (Split-Path -Parent $expectedBinary) -Force | Out-Null
    $env:LINEUP_ADAPTER_ROOT = $flutter
    $env:LINEUP_ADAPTER_BINARY = $expectedBinary
    $env:LINEUP_ADAPTER_SCENARIO = 'valid'
    function python {
      if ($args[1] -cne 'verify' -or ($args -join '|') -notlike '*--platform|windows|--architecture|x64|--mode|debug|--output-name|lineup_ax_debug_x64') {
        throw 'Adapter changed its fixed invocation.'
      }
      $global:LASTEXITCODE = if ($env:LINEUP_ADAPTER_SCENARIO -eq 'failure') { 23 } else { 0 }
      if ($env:LINEUP_ADAPTER_SCENARIO -eq 'malformed') { return 'not JSON' }
      $name = if ($env:LINEUP_ADAPTER_SCENARIO -eq 'wrong-output') { 'host_debug' } else { 'lineup_ax_debug_x64' }
      @{
        kind = 'verified-local-desktop-accessibility'; platform = 'windows'; architecture = 'x64'; mode = 'debug'
        outputName = $name; flutterRoot = $env:LINEUP_ADAPTER_ROOT
        engineSource = Join-Path $env:LINEUP_ADAPTER_ROOT 'engine/src'
        binary = $env:LINEUP_ADAPTER_BINARY; binarySha256 = 'a' * 64; provenanceSha256 = 'b' * 64
        recipe = @{ fixture = $true }
      } | ConvertTo-Json -Depth 10 -Compress
    }
    $location = (Get-Location).Path
    $preference = $PSNativeCommandUseErrorActionPreference
    Get-VerifiedWindowsEngine -Root $flutter -Mode debug | Out-Null
    foreach ($scenario in @(@{ Name = 'failure'; Error = 'Exit code 23' },
        @{ Name = 'malformed'; Error = 'invalid JSON' }, @{ Name = 'wrong-output'; Error = 'wrong output' })) {
      $env:LINEUP_ADAPTER_SCENARIO = $scenario.Name
      Assert-AuthorityRejected { Get-VerifiedWindowsEngine -Root $flutter -Mode debug } $scenario.Error
      if ((Get-Location).Path -ne $location -or $preference -ne $PSNativeCommandUseErrorActionPreference) {
        throw 'Adapter changed caller location or native error preference.'
      }
      $env:LINEUP_ADAPTER_SCENARIO = 'valid'
      Get-VerifiedWindowsEngine -Root $flutter -Mode debug | Out-Null
    }
    # A failed verifier must prevent even Flutter cache preparation.
    $launch = Get-LineupLaunchInput -EngineSource (Join-Path $flutter 'engine/src') -MpvRoot $directory -BoundParameters @{}
    function Invoke-NativeChecked { throw 'Flutter reached after failed verifier.' }
    foreach ($scenario in @(@{ Name = 'failure'; Error = 'Exit code 23' },
        @{ Name = 'malformed'; Error = 'invalid JSON' }, @{ Name = 'wrong-output'; Error = 'wrong output' })) {
      $env:LINEUP_ADAPTER_SCENARIO = $scenario.Name
      Assert-AuthorityRejected { Invoke-LineupLaunch -Launch $launch } $scenario.Error
      if ((Get-Location).Path -ne $location) { throw 'Failed verification lost launch cleanup.' }
    }
    Remove-Item Function:python
    Remove-Item Env:LINEUP_ADAPTER_ROOT, Env:LINEUP_ADAPTER_BINARY, Env:LINEUP_ADAPTER_SCENARIO
    Write-Host 'Package identity/path and checked combined-engine adapter controls passed.'
  } finally {
    . $owner
    if (Test-Path -LiteralPath $directory) { Remove-Item -LiteralPath $directory -Recurse -Force }
  }
}
