[CmdletBinding()]
param(
  [string] $BuildDirectory = 'build/windows/x64/runner/Release',
  [string] $Destination
)

$ErrorActionPreference = 'Stop'
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$metadata = Import-PowerShellDataFile -LiteralPath (Join-Path $repository 'tool/windows/build-metadata.psd1')
$versionMatch = Select-String -LiteralPath (Join-Path $repository 'pubspec.yaml') -Pattern '^version:\s*(\S+)\s*$'
if (-not $versionMatch) { throw 'pubspec.yaml does not contain a version.' }
$pubspecVersion = $versionMatch.Matches[0].Groups[1].Value
$packageVersion = $pubspecVersion.Replace('+', '-')
if (-not $Destination) {
  $Destination = "build/package/LineupDesktop-$packageVersion-windows-x64"
}
$BuildDirectory = [IO.Path]::GetFullPath((Join-Path $repository $BuildDirectory))
$Destination = [IO.Path]::GetFullPath((Join-Path $repository $Destination))
$packageRoot = [IO.Path]::GetFullPath((Join-Path $repository 'build/package'))
if (-not $Destination.StartsWith($packageRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
  throw "Package destination must be below $packageRoot."
}
if (-not (Test-Path -LiteralPath $BuildDirectory)) { throw 'Release build directory does not exist.' }
if (Test-Path -LiteralPath $Destination) { throw "Package destination already exists: $Destination" }

$sourceCommit = & {
  $PSNativeCommandUseErrorActionPreference = $false
  $output = @(git -C $repository rev-parse --verify HEAD)
  if ($LASTEXITCODE -or $output.Count -ne 1 -or [string]::IsNullOrWhiteSpace($output[0])) {
    throw 'git rev-parse failed while computing source provenance.'
  }
  $output[0].Trim()
}
$sourceDirty = & {
  $PSNativeCommandUseErrorActionPreference = $false

  git -C $repository diff --quiet
  $worktreeExit = $LASTEXITCODE
  if ($worktreeExit -gt 1) { throw "git diff failed with exit code $worktreeExit." }

  git -C $repository diff --cached --quiet
  $indexExit = $LASTEXITCODE
  if ($indexExit -gt 1) { throw "git diff --cached failed with exit code $indexExit." }

  $untracked = @(git -C $repository ls-files --others --exclude-standard)
  if ($LASTEXITCODE) { throw 'git ls-files failed while computing source provenance.' }

  $worktreeExit -eq 1 -or $indexExit -eq 1 -or $untracked.Count -ne 0
}
if ($sourceDirty) {
  throw 'Refusing to create a release package from a dirty source tree. Commit or stash all tracked and untracked changes first.'
}

$runtime = Join-Path $BuildDirectory 'libmpv-2.dll'
$pinnedMpvDllHash = '353D527E569F69D822A9D679B28D2E975C6B22A82AB9924D533110E1C21C8508'
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $runtime).Hash.ToUpperInvariant() -ne $pinnedMpvDllHash) {
  throw 'Release build does not contain the pinned LGPL libmpv runtime.'
}
if (-not $env:LINEUP_MPV_ROOT -or
  -not (Test-Path -LiteralPath (Join-Path $env:LINEUP_MPV_ROOT 'licenses'))) {
  throw 'LINEUP_MPV_ROOT must point to the prepared production runtime.'
}
$provenancePath = Join-Path $env:LINEUP_MPV_ROOT 'lineup-mpv-provenance.cmake'
if (-not (Test-Path -LiteralPath $provenancePath)) {
  throw 'Prepared production runtime provenance is missing.'
}
$provenance = Get-Content -LiteralPath $provenancePath
function Get-ProvenanceValue {
  param([Parameter(Mandatory)] [string] $Name)
  foreach ($line in $provenance) {
    if ($line -match ('^set\(' + [regex]::Escape($Name) + ' "([^"]+)"\)$')) {
      return $Matches[1]
    }
  }
  throw "Prepared production runtime provenance is missing $Name."
}
$provenanceDllHash = (Get-ProvenanceValue 'LINEUP_MPV_DLL_SHA256').ToUpperInvariant()
if ($provenanceDllHash -ne $pinnedMpvDllHash) {
  throw 'Prepared production runtime provenance does not match the pinned libmpv runtime.'
}
$expectedProvenance = @{
  LINEUP_MPV_DISTRIBUTION = 'production'
  LINEUP_MPV_LICENSE = 'LGPL-2.1-or-later'
  LINEUP_MPV_ASSET_SHA256 = '13723530C3A719577A27EA19E0127175CE6A047071F8D988ADC1B0DD400B3D18'
}
foreach ($entry in $expectedProvenance.GetEnumerator()) {
  if ((Get-ProvenanceValue $entry.Key) -ne $entry.Value) {
    throw "Prepared production runtime provenance does not match $($entry.Key)."
  }
}
$descriptiveRevisions = @{
  LINEUP_MPV_VERSION = $metadata.MpvVersion
  LINEUP_MPV_FFMPEG_VERSION = $metadata.FfmpegVersion
  LINEUP_MPV_LIBPLACEBO_VERSION = $metadata.LibplaceboVersion
}
foreach ($entry in $descriptiveRevisions.GetEnumerator()) {
  if ((Get-ProvenanceValue $entry.Key) -ne $entry.Value) {
    throw "Prepared production runtime provenance does not match $($entry.Key)."
  }
}
$licenseMetadata = @{
  'mpv-LICENSE.LGPL' = @{
    Provenance = 'LINEUP_MPV_MPV_LICENSE_SHA256'
    Sha256 = '72B672113D642CBB8EF5DCC76938DB801983C56E50B1400AB930F1A64D6DC8D9'
  }
  'FFmpeg-COPYING.LGPLv3' = @{
    Provenance = 'LINEUP_MPV_FFMPEG_LICENSE_SHA256'
    Sha256 = 'DA7EABB7BAFDF7D3AE5E9F223AA5BDC1EECE45AC569DC21B3B037520B4464768'
  }
  'libplacebo-LICENSE' = @{
    Provenance = 'LINEUP_MPV_LIBPLACEBO_LICENSE_SHA256'
    Sha256 = 'B3AA400ACA6D2BA1F0BD03BD98D03D1FE7489A3BBB26969D72016360AF8A5C9D'
  }
}
foreach ($entry in $licenseMetadata.GetEnumerator()) {
  $license = Join-Path $env:LINEUP_MPV_ROOT "licenses/$($entry.Key)"
  if ((Get-ProvenanceValue $entry.Value.Provenance) -ne $entry.Value.Sha256 -or
    -not (Test-Path -LiteralPath $license) -or
    (Get-FileHash -Algorithm SHA256 -LiteralPath $license).Hash -ne $entry.Value.Sha256) {
    throw "Prepared production runtime license does not match $($entry.Key)."
  }
}

[IO.Directory]::CreateDirectory($Destination) | Out-Null
foreach ($file in @(
    'lineup_desktop.exe',
    'flutter_windows.dll',
    'flutter_secure_storage_windows_plugin.dll',
    'libmpv-2.dll',
    'native_assets.json'
  )) {
  Copy-Item -LiteralPath (Join-Path $BuildDirectory $file) -Destination $Destination
}
Copy-Item -LiteralPath (Join-Path $BuildDirectory 'data') -Destination $Destination -Recurse

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
$redistRoot = Join-Path $vs.Trim() 'VC/Redist/MSVC'
if (-not (Test-Path -LiteralPath $redistRoot)) {
  throw "MSVC redistributable directory was not found: $redistRoot"
}
$redistVersion = Get-ChildItem -LiteralPath $redistRoot -Directory |
  Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'x64/Microsoft.VC143.CRT') } |
  Sort-Object { [version]$_.Name } -Descending |
  Select-Object -First 1
if (-not $redistVersion) { throw 'The retail x64 VC143 runtime is not installed.' }
$redist = Join-Path $redistVersion.FullName 'x64/Microsoft.VC143.CRT'
foreach ($file in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
  Copy-Item -LiteralPath (Join-Path $redist $file) -Destination $Destination
}

$licenses = Join-Path $Destination 'licenses'
[IO.Directory]::CreateDirectory($licenses) | Out-Null
Copy-Item -LiteralPath (Join-Path $repository 'LICENSE') -Destination (Join-Path $licenses 'Lineup-Desktop-Apache-2.0.txt')
Copy-Item -LiteralPath (Join-Path $repository 'tool/flutter_engine/NOTICE') -Destination (Join-Path $licenses 'Flutter-engine-patch-NOTICE.txt')
Copy-Item -LiteralPath (Join-Path $repository 'docs/windows-runtime.md') -Destination (Join-Path $licenses 'Windows-runtime-provenance.md')
foreach ($file in $licenseMetadata.Keys) {
  Copy-Item -LiteralPath (Join-Path $env:LINEUP_MPV_ROOT "licenses/$file") -Destination $licenses
}

$vcVersions = @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') | ForEach-Object {
  $file = Get-Item -LiteralPath (Join-Path $Destination $_)
  "$($file.Name)=$($file.VersionInfo.FileVersion)"
}
@(
  "Lineup Desktop $pubspecVersion Windows x64",
  "source-commit=$sourceCommit",
  "source-dirty=$($sourceDirty.ToString().ToLowerInvariant())",
  "flutter-framework=$($metadata.FlutterFrameworkRevision)",
  "flutter-engine=$($metadata.FlutterEngineRevision)",
  "flutter-engine-patch=$($metadata.FlutterEnginePatchPath)",
  "mpv=$($metadata.MpvVersion)",
  "ffmpeg=$($metadata.FfmpegVersion)",
  "libplacebo=$($metadata.LibplaceboVersion)",
  'system-requirement=vulkan-1.dll supplied by a current GPU driver or Vulkan Runtime',
  $vcVersions
) | Set-Content -LiteralPath (Join-Path $Destination 'BUILD-INFO.txt') -Encoding ascii
@(
  'Lineup Desktop requires Windows 10 or 11 x64.',
  'Install a current GPU driver that supplies the Khronos Vulkan loader (vulkan-1.dll).',
  'The pinned libmpv build imports that loader even though Lineup selects D3D11 output.',
  'A reachable Plex Media Server and a Plex account are required for library playback.'
) | Set-Content -LiteralPath (Join-Path $Destination 'SYSTEM-REQUIREMENTS.txt') -Encoding ascii

$forbidden = Get-ChildItem -LiteralPath $Destination -Recurse -File | Where-Object {
  $_.Name -eq 'dartjni.dll' -or
  $_.Extension -in '.pdb', '.lib', '.exp', '.def' -or
  $_.Name -match '(?i)credential|token|private.*media'
}
if ($forbidden) { throw "Package contains forbidden files: $($forbidden.FullName -join ', ')" }

$manifest = Get-ChildItem -LiteralPath $Destination -Recurse -File |
  Sort-Object FullName |
  ForEach-Object {
    $relative = $_.FullName.Substring($Destination.Length + 1).Replace('\', '/')
    "$((Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash)  $relative"
  }
$manifest | Set-Content -LiteralPath (Join-Path $Destination 'PACKAGE-MANIFEST.sha256') -Encoding ascii

$archive = "$Destination.zip"
if (Test-Path -LiteralPath $archive) { throw "Package archive already exists: $archive" }
Compress-Archive -LiteralPath $Destination -DestinationPath $archive -CompressionLevel Optimal
Write-Host "Created $archive"
