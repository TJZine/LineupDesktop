[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string] $Destination
)

$ErrorActionPreference = 'Stop'
$asset = 'mpv-dev-x86_64-20260813-git-f4d13e1c2c.7z'
$sha256 = '4425B3E9768452FCBA31EE2EC61456514FAF9C5CF11D919B1A889D1C415C1A12'
$url = "https://github.com/shinchiro/mpv-winbuild-cmake/releases/download/20260813/$asset"
$Destination = [IO.Path]::GetFullPath($Destination)
$temporaryDirectory = if ($env:RUNNER_TEMP) {
  $env:RUNNER_TEMP
} else {
  [IO.Path]::GetTempPath()
}
$archive = Join-Path $temporaryDirectory $asset

New-Item -ItemType Directory -Force -Path $Destination | Out-Null
Invoke-WebRequest -Uri $url -OutFile $archive
if ((Get-FileHash -Algorithm SHA256 $archive).Hash -ne $sha256) {
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

$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
$tools = Get-ChildItem -Directory (Join-Path $vs 'VC/Tools/MSVC') | Sort-Object Name -Descending | Select-Object -First 1
$lib = Join-Path $tools.FullName 'bin/Hostx64/x64/lib.exe'
$dumpbin = Join-Path $tools.FullName 'bin/Hostx64/x64/dumpbin.exe'
if (-not (Test-Path $lib) -or -not (Test-Path $dumpbin)) { throw 'MSVC x64 lib.exe and dumpbin.exe are required.' }

$exports = & $dumpbin /exports $dll | ForEach-Object {
  if ($_ -match '^\s*\d+\s+[0-9A-F]+\s+[0-9A-F]+\s+(.+)$') { $Matches[1].Trim() }
} | Where-Object { $_ -and $_ -notmatch '^\[' }
if (-not $exports) { throw 'Could not read libmpv DLL exports.' }
$def = Join-Path $root 'libmpv-2.def'
@('LIBRARY libmpv-2.dll', 'EXPORTS') + $exports | Set-Content -NoNewline:$false -Encoding ascii $def
& $lib "/def:$def" /machine:x64 "/out:$root/libmpv.lib" | Out-Null
if ($LASTEXITCODE) { throw 'Could not create the MSVC libmpv import library.' }

$provenance = Join-Path $root 'lineup-mpv-provenance.cmake'
@(
  "set(LINEUP_MPV_ASSET_SHA256 `"$sha256`")",
  "set(LINEUP_MPV_IMPORT_LIBRARY_SHA256 `"$((Get-FileHash -Algorithm SHA256 (Join-Path $root 'libmpv.lib')).Hash)`")"
) | Set-Content -Encoding ascii $provenance
Write-Host "Prepared verified libmpv development files at $root"
