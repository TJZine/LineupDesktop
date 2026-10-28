#Requires -Version 7.4

[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string] $Destination
)

$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_OS -ne 'Windows' -or -not $env:RUNNER_TEMP) {
  throw 'This prerequisite is only for an ephemeral Windows GitHub Actions job.'
}
$temporaryRoot = [IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd([IO.Path]::DirectorySeparatorChar)
$Destination = [IO.Path]::GetFullPath($Destination)
if (-not $Destination.StartsWith("$temporaryRoot$([IO.Path]::DirectorySeparatorChar)", [StringComparison]::OrdinalIgnoreCase)) {
  throw 'The CI Vulkan destination must be inside RUNNER_TEMP.'
}
if ([IO.Directory]::Exists($Destination) -or [IO.File]::Exists($Destination)) {
  throw 'The CI Vulkan destination must be new.'
}

# Official non-installer components ZIP and published checksum:
# https://vulkan.lunarg.com/sdk/files.json (Runtime zip, record 2542).
$version = '1.4.335.0'
$components = "VulkanRT-X64-$version-Components"
$archiveSha256 = '4F856DA356FFB1C16FBFC792CAE70F6E6873680E6B62BC132B9D7131CBC97FE2'
$dllSha256 = '5C42CA8EA4BC43EE17FFE8FCDAFBA36E377C2AF29722CB09F400C24D9D80FB73'
$url = "https://sdk.lunarg.com/sdk/download/$version/windows/$components.zip"
$null = [IO.Directory]::CreateDirectory($Destination)
$archive = Join-Path $Destination 'components.zip'
for ($attempt = 1; $attempt -le 3; $attempt++) {
  try {
    Invoke-WebRequest -Uri $url -OutFile $archive -ConnectionTimeoutSeconds 30 -OperationTimeoutSeconds 60
    break
  } catch {
    if ($attempt -eq 3) { throw }
    Start-Sleep -Seconds $attempt
  }
}
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash -ne $archiveSha256) {
  throw 'SHA-256 mismatch for the pinned CI Vulkan components archive.'
}

# Extract only the x64 loader and its license, never the installer or tools.
Add-Type -AssemblyName System.IO.Compression.ZipFile
$zip = [IO.Compression.ZipFile]::OpenRead($archive)
try {
  foreach ($file in @(
    @{ Entry = "$components/x64/vulkan-1.dll"; Name = 'vulkan-1.dll' },
    @{ Entry = "$components/VulkanRT-License.txt"; Name = 'VulkanRT-License.txt' }
  )) {
    $entry = $zip.GetEntry($file.Entry)
    if (-not $entry) { throw "Pinned Vulkan archive is missing $($file.Entry)." }
    [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, (Join-Path $Destination $file.Name))
  }
} finally {
  $zip.Dispose()
}
$dll = Join-Path $Destination 'vulkan-1.dll'
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $dll).Hash -ne $dllSha256) {
  throw 'SHA-256 mismatch for the pinned x64 CI Vulkan loader.'
}
$bytes = [IO.File]::ReadAllBytes($dll)
$peOffset = [BitConverter]::ToInt32($bytes, 0x3c)
if ([BitConverter]::ToUInt32($bytes, $peOffset) -ne 0x4550 -or
    [BitConverter]::ToUInt16($bytes, $peOffset + 4) -ne 0x8664) {
  throw 'The pinned CI Vulkan loader is not an AMD64 PE image.'
}
Remove-Item -LiteralPath $archive -Force
Write-Host "Prepared CI-only Vulkan loader $version (AMD64), SHA256=$dllSha256 at $Destination"
