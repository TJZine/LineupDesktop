[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string] $Destination
)

$ErrorActionPreference = 'Stop'

function Invoke-DownloadWithRetry {
  param([string] $Uri, [string] $OutFile)

  for ($attempt = 1; $attempt -le 3; $attempt++) {
    try {
      Invoke-WebRequest -Uri $Uri -OutFile $OutFile -ErrorAction Stop
      return
    } catch {
      if ($attempt -eq 3) { throw }
      Start-Sleep -Seconds (1 -shl ($attempt - 1))
    }
  }
}

$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$metadata = Import-PowerShellDataFile -LiteralPath (Join-Path $repository 'tool/windows/build-metadata.psd1')
$asset = 'mpv-dev-lgpl-x86_64-20260813-git-7b8915bc1d.7z'
$sha256 = '13723530C3A719577A27EA19E0127175CE6A047071F8D988ADC1B0DD400B3D18'
$url = "https://github.com/zhongfly/mpv-winbuild/releases/download/2026-08-13-7b8915bc1d/$asset"
$Destination = [IO.Path]::GetFullPath($Destination)
if (Test-Path -LiteralPath $Destination) {
  if (Get-ChildItem -LiteralPath $Destination -Force | Select-Object -First 1) {
    throw "Preparation destination must be new or empty: $Destination"
  }
} else {
  [IO.Directory]::CreateDirectory($Destination) | Out-Null
}
$temporaryDirectory = if ($env:RUNNER_TEMP) {
  $env:RUNNER_TEMP
} else {
  [IO.Path]::GetTempPath()
}
$archive = Join-Path $temporaryDirectory $asset

Invoke-DownloadWithRetry -Uri $url -OutFile $archive
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash -ne $sha256) {
  throw "SHA-256 mismatch for $asset."
}

$sevenZip = (Get-Command 7z.exe -ErrorAction SilentlyContinue).Source
if (-not $sevenZip) {
  $installedSevenZip = Join-Path $env:ProgramFiles '7-Zip\7z.exe'
  if (Test-Path -LiteralPath $installedSevenZip) { $sevenZip = $installedSevenZip }
}
if (-not $sevenZip) { throw '7z.exe is required to extract the pinned mpv asset.' }
& $sevenZip x -y "-o$Destination" $archive | Out-Null
if ($LASTEXITCODE) { throw 'Could not extract the pinned mpv asset.' }

$root = $Destination
$header = Join-Path $root 'include/mpv/client.h'
$dll = Join-Path $root 'libmpv-2.dll'
if (-not (Test-Path -LiteralPath $header) -or -not (Test-Path -LiteralPath $dll)) {
  throw 'The verified archive did not contain the expected libmpv header and DLL.'
}
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $header).Hash -ne
  '1ACF99EE77C8C2A6F1D1993BD81BBC8A91D27FB5924E80171670E6139A4BD353' -or
  (Get-FileHash -Algorithm SHA256 -LiteralPath $dll).Hash -ne
  '353D527E569F69D822A9D679B28D2E975C6B22A82AB9924D533110E1C21C8508') {
  throw 'The verified archive contents do not match the pinned Lineup runtime.'
}

$licenseDirectory = Join-Path $root 'licenses'
[IO.Directory]::CreateDirectory($licenseDirectory) | Out-Null
$licenseSourceDirectory = Join-Path $repository 'third_party/libmpv/licenses'
$licenses = @(
  @{
    Name = 'mpv-LICENSE.LGPL'
    Sha256 = '72B672113D642CBB8EF5DCC76938DB801983C56E50B1400AB930F1A64D6DC8D9'
  },
  @{
    Name = 'FFmpeg-COPYING.LGPLv3'
    Sha256 = 'DA7EABB7BAFDF7D3AE5E9F223AA5BDC1EECE45AC569DC21B3B037520B4464768'
  },
  @{
    Name = 'FFmpeg-COPYING.GPLv3'
    Sha256 = '8CEB4B9EE5ADEDDE47B31E975C1D90C73AD27B6B165A1DCD80C7C545EB65B903'
  },
  @{
    Name = 'libplacebo-LICENSE'
    Sha256 = 'B3AA400ACA6D2BA1F0BD03BD98D03D1FE7489A3BBB26969D72016360AF8A5C9D'
  }
)
$licenseHashes = @{}
foreach ($license in $licenses) {
  $source = Join-Path $licenseSourceDirectory $license.Name
  $path = Join-Path $licenseDirectory $license.Name
  if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
    throw "Pinned license source is missing: $($license.Name)."
  }
  if ((Get-FileHash -Algorithm SHA256 -LiteralPath $source).Hash -ne $license.Sha256) {
    throw "SHA-256 mismatch for pinned license source: $($license.Name)."
  }
  Copy-Item -LiteralPath $source -Destination $path
  if ((Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne $license.Sha256) {
    throw "SHA-256 mismatch for $($license.Name)."
  }
  $licenseHashes[$license.Name] = $license.Sha256
}

$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path -LiteralPath $vswhere)) {
  throw 'Visual Studio Installer vswhere.exe was not found.'
}
$vsOutput = @(& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath)
$vsExit = $LASTEXITCODE
$vs = $vsOutput | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1
if ($vsExit -or -not $vs) {
  throw 'Visual Studio with the MSVC x64 tools component was not found.'
}
$toolsRoot = Join-Path $vs.Trim() 'VC/Tools/MSVC'
if (-not (Test-Path -LiteralPath $toolsRoot)) {
  throw "MSVC tools directory was not found: $toolsRoot"
}
$tools = Get-ChildItem -LiteralPath $toolsRoot -Directory |
  Sort-Object { [version]$_.Name } -Descending |
  Select-Object -First 1
if (-not $tools) { throw 'No installed MSVC toolset was found.' }
$lib = Join-Path $tools.FullName 'bin/Hostx64/x64/lib.exe'
$dumpbin = Join-Path $tools.FullName 'bin/Hostx64/x64/dumpbin.exe'
if (-not (Test-Path -LiteralPath $lib) -or -not (Test-Path -LiteralPath $dumpbin)) {
  throw 'MSVC x64 lib.exe and dumpbin.exe are required.'
}

$exports = & $dumpbin /exports $dll | ForEach-Object {
  if ($_ -match '^\s*\d+\s+[0-9A-F]+\s+[0-9A-F]+\s+(.+)$') { $Matches[1].Trim() }
} | Where-Object { $_ -and $_ -notmatch '^\[' }
if (-not $exports) { throw 'Could not read libmpv DLL exports.' }
$def = Join-Path $root 'libmpv-2.def'
@('LIBRARY libmpv-2.dll', 'EXPORTS') + $exports | Set-Content -LiteralPath $def -NoNewline:$false -Encoding ascii
& $lib "/def:$def" /machine:x64 "/out:$root/libmpv.lib" | Out-Null
if ($LASTEXITCODE) { throw 'Could not create the MSVC libmpv import library.' }

$provenance = Join-Path $root 'lineup-mpv-provenance.cmake'
@(
  'set(LINEUP_MPV_DISTRIBUTION "production")',
  'set(LINEUP_MPV_LICENSE "LGPL-2.1-or-later")',
  "set(LINEUP_MPV_VERSION `"$($metadata.MpvVersion)`")",
  "set(LINEUP_MPV_FFMPEG_VERSION `"$($metadata.FfmpegVersion)`")",
  "set(LINEUP_MPV_LIBPLACEBO_VERSION `"$($metadata.LibplaceboVersion)`")",
  "set(LINEUP_MPV_ASSET_SHA256 `"$sha256`")",
  "set(LINEUP_MPV_DLL_SHA256 `"$((Get-FileHash -Algorithm SHA256 -LiteralPath $dll).Hash)`")",
  "set(LINEUP_MPV_IMPORT_LIBRARY_SHA256 `"$((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $root 'libmpv.lib')).Hash)`")",
  "set(LINEUP_MPV_MPV_LICENSE_SHA256 `"$($licenseHashes['mpv-LICENSE.LGPL'])`")",
  "set(LINEUP_MPV_FFMPEG_LICENSE_SHA256 `"$($licenseHashes['FFmpeg-COPYING.LGPLv3'])`")",
  "set(LINEUP_MPV_FFMPEG_GPL_LICENSE_SHA256 `"$($licenseHashes['FFmpeg-COPYING.GPLv3'])`")",
  "set(LINEUP_MPV_LIBPLACEBO_LICENSE_SHA256 `"$($licenseHashes['libplacebo-LICENSE'])`")"
) | Set-Content -LiteralPath $provenance -Encoding ascii
Write-Host "Prepared verified LGPL libmpv production files at $root"
