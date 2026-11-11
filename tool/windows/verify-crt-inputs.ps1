#Requires -Version 7.4

function Assert-WindowsCrtInputs {
  . (Join-Path $PSScriptRoot 'crt-inputs.ps1')
  function Assert-CrtRejected {
    param([scriptblock] $Action, [string] $Reason)
    try { & $Action | Out-Null } catch {
      if ($_.Exception.Message -notlike "*$Reason*") { throw }
      return
    }
    throw "CRT fixture did not reject: $Reason"
  }
  # Certificate is a controlled fixture, not cryptographic verification evidence.
  function Signature([string] $Status = 'Valid', [string] $Publisher = 'Microsoft Corporation') {
    $certificate = [pscustomobject]@{ Publisher = $Publisher }
    $certificate | Add-Member ScriptMethod GetNameInfo { param($Type, $Issuer) $this.Publisher }
    [pscustomobject]@{ Status = $Status; SignerCertificate = $certificate }
  }
  $directoryVersion = '14.44.35112'
  $toolset = [version] '14.44.35207'
  $runtime = [version] '14.44.35211.0'
  foreach ($status in @('NotSigned', 'HashMismatch', 'NotTrusted', 'UnknownError')) {
    Assert-CrtRejected { Assert-LineupCrtIdentity (Signature $status) $runtime $toolset $directoryVersion } 'valid Microsoft'
  }
  Assert-CrtRejected { Assert-LineupCrtIdentity (Signature 'Valid' 'Other Publisher') $runtime $toolset $directoryVersion } 'valid Microsoft'
  $unsigned = [pscustomobject]@{ Status = 'Valid'; SignerCertificate = $null }
  Assert-CrtRejected { Assert-LineupCrtIdentity $unsigned $runtime $toolset $directoryVersion } 'valid Microsoft'
  Assert-CrtRejected { Assert-LineupCrtIdentity (Signature) ([version] '14.38.33135') $toolset $directoryVersion } 'unsupported or older'
  $oldRuntime = [version] '14.44.35200.0'
  Assert-CrtRejected {
    Assert-LineupCrtIdentity (Signature) $oldRuntime $toolset $directoryVersion
  } "directory version: '$directoryVersion', toolset version: $toolset, file version: $oldRuntime"
  Assert-CrtRejected { Assert-LineupCrtIdentity (Signature) $runtime ([version] '14.50.1') $directoryVersion } 'unsupported or older'

  $image = [byte[]]::new(128)
  $image[0] = 0x4d; $image[1] = 0x5a; $image[0x3c] = 64
  $image[64] = 0x50; $image[65] = 0x45
  $image[68] = 0x64; $image[69] = 0x86
  Assert-LineupCrtImage $image
  $image[68] = 0x4c; $image[69] = 0x01
  Assert-CrtRejected { Assert-LineupCrtImage $image } 'AMD64 PE'
  $image[0x3c] = 127
  Assert-CrtRejected { Assert-LineupCrtImage $image } 'AMD64 PE'
  Assert-CrtRejected { Assert-LineupCrtImage ([byte[]]::new(4)) } 'AMD64 PE'

  $root = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
  try {
    $vs = Join-Path $root 'VS'
    $cmake = Join-Path $root 'build'
    $compiler = Join-Path $cmake 'CMakeFiles/3.29.0/CMakeCXXCompiler.cmake'
    $default = Join-Path $vs 'VC/Auxiliary/Build/Microsoft.VCRedistVersion.default.txt'
    New-Item -ItemType Directory -Path (Split-Path $compiler), (Split-Path $default) -Force | Out-Null
    $vsPath = $vs.Replace('\', '/')
    "set(CMAKE_CXX_COMPILER `"$vsPath/VC/Tools/MSVC/14.44.35207/bin/Hostx64/x64/cl.exe`")" |
      Set-Content -LiteralPath $compiler
    $directoryVersion | Set-Content -LiteralPath $default
    $selection = Get-LineupCrtSelection $cmake
    if ($selection.Version -cne $directoryVersion -or $selection.Toolset -ne $toolset -or
      $selection.Directory -cne (Join-Path $vs "VC/Redist/MSVC/$directoryVersion/x64/Microsoft.VC143.CRT")) {
      throw 'CRT selection did not use the actual compiler installation.'
    }
    Assert-LineupCrtIdentity (Signature) $runtime $selection.Toolset $selection.Version
    foreach ($version in @('14.38.33135', '14.50.1', '../other', 'not-a-version')) {
      $version | Set-Content -LiteralPath $default
      Assert-CrtRejected { Get-LineupCrtSelection $cmake } `
        "directory version: '$version', toolset version: $toolset, file version: not inspected"
    }
    'set(CMAKE_CXX_COMPILER "untrusted/cl.exe")' | Set-Content -LiteralPath $compiler
    Assert-CrtRejected { Get-LineupCrtSelection $cmake } 'supported MSVC'
  } finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
  }
  Write-Host 'Windows CRT selection and signature-policy fixtures passed (no Windows trust validation).'
}
