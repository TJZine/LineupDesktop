#Requires -Version 7.4

# Use the Visual Studio instance/toolset that CMake actually compiled with.
# Do not select an unrelated newest installation or arbitrary redist directory.
function Get-LineupCrtSelection {
  param([Parameter(Mandatory)] [string] $CmakeDirectory)

  $compilerFiles = @(Get-ChildItem -Path (Join-Path $CmakeDirectory 'CMakeFiles/*/CMakeCXXCompiler.cmake') -File)
  if ($compilerFiles.Count -ne 1) { throw 'Expected one CMake C++ compiler identity; rebuild in a fresh directory.' }
  $compiler = Get-Content -Raw -LiteralPath $compilerFiles[0].FullName
  if ($compiler -notmatch 'set\(CMAKE_CXX_COMPILER "([^"\r\n]+/VC/Tools/MSVC/(14\.[0-9]+\.[0-9]+)/bin/Hostx64/x64/cl\.exe)"\)') {
    throw 'Release compiler must be the supported MSVC v14 x64 toolchain.'
  }
  $compilerPath = $Matches[1]
  $toolset = [version] $Matches[2]
  $vs = $compilerPath.Substring(0, $compilerPath.IndexOf('/VC/Tools/MSVC/'))
  $default = Join-Path $vs 'VC/Auxiliary/Build/Microsoft.VCRedistVersion.default.txt'
  $redistVersion = (Get-Content -Raw -LiteralPath $default).Trim()
  # VS2022 17.14 (14.44) is the supported VC143 servicing baseline.
  # The directory identifies the servicing generation. The DLL versions
  # determine whether the redistributable is current enough for the toolset.
  if ($redistVersion -notmatch '^14\.44\.[0-9]+$') {
    throw "The selected VC143 redistributable directory version is unsupported (directory version: '$redistVersion', toolset version: $toolset, file version: not inspected)."
  }
  [pscustomobject]@{
    Directory = Join-Path $vs "VC/Redist/MSVC/$redistVersion/x64/Microsoft.VC143.CRT"
    Version = $redistVersion
    Toolset = $toolset
  }
}

# Describe a rejected signature without trusting it, so hosted failures show
# which trust or identity condition failed. Public certificate fields only.
function Get-LineupCrtSignatureDetail {
  param($Signature, [string] $Path)
  function Read-Field($Object, [string] $Name) {
    if ($null -ne $Object -and $Object.PSObject.Properties[$Name] -and $null -ne $Object.$Name) {
      return "$($Object.$Name)"
    }
    '<none>'
  }
  $certificate = if ($null -ne $Signature) { $Signature.SignerCertificate } else { $null }
  $signer = '<none>'
  $issuer = '<none>'
  if ($null -ne $certificate) {
    $nameType = [Security.Cryptography.X509Certificates.X509NameType]::SimpleName
    $signer = "$($certificate.GetNameInfo($nameType, $false))"
    $issuer = "$($certificate.GetNameInfo($nameType, $true))"
  }
  @(
    "file: $Path",
    "status: $(Read-Field $Signature 'Status')",
    "status message: $(Read-Field $Signature 'StatusMessage')",
    "signer: $signer",
    "issuer: $issuer",
    "subject: $(Read-Field $certificate 'Subject')",
    "thumbprint: $(Read-Field $certificate 'Thumbprint')",
    "not after: $(Read-Field $certificate 'NotAfter')"
  ) -join '; '
}

function Assert-LineupCrtIdentity {
  param(
    [Parameter(Mandatory)] $Signature,
    [Parameter(Mandatory)] [version] $Version,
    [Parameter(Mandatory)] [version] $Toolset,
    [Parameter(Mandatory)] [string] $DirectoryVersion,
    [string] $Path = '<unspecified>'
  )
  # Windows trust validation must succeed, including digest/chain validation.
  # A Microsoft-looking filename or version resource is not signature proof.
  if ($Signature.Status.ToString() -cne 'Valid' -or -not $Signature.SignerCertificate -or
    $Signature.SignerCertificate.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false) -cne 'Microsoft Corporation') {
    throw "CRT requires a valid Microsoft Corporation Authenticode signature ($(Get-LineupCrtSignatureDetail -Signature $Signature -Path $Path))."
  }
  if ($Version.Major -ne 14 -or $Version.Minor -ne 44 -or
    $Version -lt $Toolset) {
    throw "CRT file version is unsupported or older than the build toolset (directory version: '$DirectoryVersion', toolset version: $Toolset, file version: $Version)."
  }
}

function Assert-LineupCrtImage {
  param([Parameter(Mandatory)] [byte[]] $Bytes)
  if ($Bytes.Length -lt 64 -or [BitConverter]::ToUInt16($Bytes, 0) -ne 0x5a4d) {
    throw 'CRT must be an AMD64 PE image.'
  }
  $offset = [BitConverter]::ToInt32($Bytes, 0x3c)
  if ($offset -lt 64 -or $offset -gt $Bytes.Length - 6 -or
    [BitConverter]::ToUInt32($Bytes, $offset) -ne 0x4550 -or
    [BitConverter]::ToUInt16($Bytes, $offset + 4) -ne 0x8664) {
    throw 'CRT must be an AMD64 PE image.'
  }
}

function Copy-LineupVerifiedCrt {
  param(
    [Parameter(Mandatory)] $Selection,
    [Parameter(Mandatory)] [string] $Destination
  )
  if (-not $IsWindows) { throw 'CRT Authenticode verification requires Windows.' }
  foreach ($name in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
    $source = Join-Path $Selection.Directory $name
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $source).Hash
    Assert-LineupCrtImage -Bytes ([IO.File]::ReadAllBytes($source))
    $file = Get-Item -LiteralPath $source
    $version = [version]::new($file.VersionInfo.FileMajorPart, $file.VersionInfo.FileMinorPart,
      $file.VersionInfo.FileBuildPart, $file.VersionInfo.FilePrivatePart)
    $signature = Microsoft.PowerShell.Security\Get-AuthenticodeSignature -LiteralPath $source -ErrorAction Stop
    Assert-LineupCrtIdentity -Signature $signature -Version $version `
      -Toolset $Selection.Toolset -DirectoryVersion $Selection.Version -Path $source
    $target = Join-Path $Destination $name
    Copy-Item -LiteralPath $source -Destination $target
    # Bind the checked input to the actual copied bytes, failing on substitution.
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $target).Hash -cne $hash) {
      throw 'CRT changed while copying into the package.'
    }
    $copiedSignature = Microsoft.PowerShell.Security\Get-AuthenticodeSignature -LiteralPath $target -ErrorAction Stop
    Assert-LineupCrtIdentity -Signature $copiedSignature -Version $version `
      -Toolset $Selection.Toolset -DirectoryVersion $Selection.Version -Path $target
    "$name=$version sha256=$hash signer=Microsoft Corporation"
  }
}
