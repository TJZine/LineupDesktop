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
  # Certificates are controlled fixtures, not cryptographic verification
  # evidence: Status is scripted, while subject and issuer are real DER-encoded
  # X500DistinguishedName values so the identity rule parses actual name
  # structure. Name takes attribute/value pairs; values may contain any text.
  function Name {
    param([Parameter(ValueFromRemainingArguments)] [string[]] $Pairs)
    $builder = [Security.Cryptography.X509Certificates.X500DistinguishedNameBuilder]::new()
    for ($index = 0; $index -lt $Pairs.Count; $index += 2) {
      $value = $Pairs[$index + 1]
      switch -CaseSensitive ($Pairs[$index]) {
        'CN' { $builder.AddCommonName($value) }
        'OU' { $builder.AddOrganizationalUnitName($value) }
        'O' { $builder.AddOrganizationName($value) }
        'L' { $builder.AddLocalityName($value) }
        'S' { $builder.AddStateOrProvinceName($value) }
        'C' { $builder.AddCountryOrRegion($value) }
        default { throw "Unknown CRT fixture name attribute: $_" }
      }
    }
    $builder.Build()
  }
  # One RDN holding both OU and O, which the builder cannot express.
  function MultiValuedName([string] $Organization) {
    Add-Type -AssemblyName System.Formats.Asn1
    $writer = [Formats.Asn1.AsnWriter]::new([Formats.Asn1.AsnEncodingRules]::DER)
    # Push* returns a disposable scope in .NET 7+; discard it and pop explicitly.
    $null = $writer.PushSequence()
    $null = $writer.PushSetOf()
    foreach ($attribute in @(@('2.5.4.11', 'Contoso Signing'), @('2.5.4.10', $Organization))) {
      $null = $writer.PushSequence()
      $writer.WriteObjectIdentifier($attribute[0])
      $writer.WriteCharacterString([Formats.Asn1.UniversalTagNumber]::UTF8String, $attribute[1])
      $writer.PopSequence()
    }
    $writer.PopSetOf()
    $writer.PopSequence()
    [Security.Cryptography.X509Certificates.X500DistinguishedName]::new($writer.Encode())
  }
  $microsoftLocation = @('L', 'Redmond', 'S', 'Washington', 'C', 'US')
  $microsoftIssuer = Name 'CN' 'Microsoft Code Signing PCA 2011' 'O' 'Microsoft Corporation' @microsoftLocation
  function Signature {
    param(
      [string] $Status = 'Valid',
      [Security.Cryptography.X509Certificates.X500DistinguishedName] $Subject =
        (Name 'CN' 'Microsoft Corporation' 'O' 'Microsoft Corporation' @microsoftLocation),
      [Security.Cryptography.X509Certificates.X500DistinguishedName] $Issuer = $microsoftIssuer
    )
    $certificate = [pscustomobject]@{
      SubjectName = $Subject
      IssuerName = $Issuer
      Subject = $Subject.Name
      Issuer = $Issuer.Name
    }
    # Mirrors X509Certificate2.GetNameInfo(SimpleName): the name's CN.
    $certificate | Add-Member ScriptMethod GetNameInfo {
      param($Type, $ForIssuer)
      $name = if ($ForIssuer) { $this.IssuerName } else { $this.SubjectName }
      foreach ($rdn in $name.EnumerateRelativeDistinguishedNames($true)) {
        if (-not $rdn.HasMultipleElements -and $rdn.GetSingleElementType().Value -ceq '2.5.4.3') {
          return $rdn.GetSingleElementValue()
        }
      }
      ''
    }
    [pscustomobject]@{ Status = $Status; SignerCertificate = $certificate }
  }
  $directoryVersion = '14.44.35112'
  $toolset = [version] '14.44.35207'
  $runtime = [version] '14.44.35211.0'

  # Accepted: the hosted VS 2022 14.44 msvcp140.dll signer, and the
  # "Microsoft Corporation" signer used by the other VC143 CRT DLLs.
  $compatibilitySubject = Name 'CN' 'Microsoft Windows Software Compatibility Publisher' 'O' 'Microsoft Corporation' @microsoftLocation
  $compatibilityIssuer = Name 'CN' 'Microsoft Windows Third Party Component CA 2013' 'O' 'Microsoft Corporation' @microsoftLocation
  Assert-LineupCrtIdentity (Signature -Subject $compatibilitySubject -Issuer $compatibilityIssuer) $runtime $toolset $directoryVersion
  Assert-LineupCrtIdentity (Signature) $runtime $toolset $directoryVersion

  foreach ($status in @('NotSigned', 'HashMismatch', 'NotTrusted', 'UnknownError')) {
    Assert-CrtRejected { Assert-LineupCrtIdentity (Signature $status) $runtime $toolset $directoryVersion } 'valid Microsoft'
  }
  $otherPublisher = Name 'CN' 'Other Publisher' 'O' 'Other Publisher' @microsoftLocation
  # Identity is the X.500 organisation attribute, never text inside CN or OU.
  $rejectedNames = @(
    @{ Subject = $otherPublisher },
    @{ Issuer = (Name 'CN' 'Microsoft Code Signing PCA 2011' 'O' 'Contoso' @microsoftLocation) },
    @{ Issuer = (Name 'CN' 'Microsoft Code Signing PCA 2011') },
    @{ Subject = (Name 'CN' 'Microsoft Corporation') },
    @{ Subject = (Name 'CN' 'Contoso, O=Microsoft Corporation' 'O' 'Contoso') },
    @{ Subject = (Name 'CN' 'Contoso' 'OU' 'O=Microsoft Corporation' 'O' 'Contoso') },
    @{ Subject = (Name 'CN' 'Contoso' 'OU' '"Microsoft Corporation"' 'O' '"Microsoft Corporation"') },
    @{ Subject = (Name 'CN' 'Contoso' 'O' 'microsoft corporation') },
    @{ Subject = (Name 'CN' 'Microsoft Corporation' 'O' 'Microsoft Corporation ') },
    @{ Subject = (Name 'CN' 'Contoso' 'O' 'Microsoft Corporation' 'O' 'Contoso') },
    @{ Subject = (Name 'CN' 'Contoso' 'O' 'Microsoft Corporation' 'O' 'Microsoft Corporation') },
    @{ Subject = (MultiValuedName 'Microsoft Corporation') }
  )
  foreach ($names in $rejectedNames) {
    Assert-CrtRejected { Assert-LineupCrtIdentity (Signature @names) $runtime $toolset $directoryVersion } 'valid Microsoft'
  }
  # Rejections name the failed condition so hosted trust failures are diagnosable.
  Assert-CrtRejected { Assert-LineupCrtIdentity (Signature 'NotTrusted') $runtime $toolset $directoryVersion 'fixture.dll' } 'file: fixture.dll; status: NotTrusted'
  Assert-CrtRejected { Assert-LineupCrtIdentity (Signature -Subject $otherPublisher) $runtime $toolset $directoryVersion } 'signer: Other Publisher; issuer: Microsoft Code Signing PCA 2011'
  Assert-CrtRejected { Assert-LineupCrtIdentity (Signature -Subject $otherPublisher) $runtime $toolset $directoryVersion } "subject: $($otherPublisher.Name); issuer name: $($microsoftIssuer.Name)"
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
