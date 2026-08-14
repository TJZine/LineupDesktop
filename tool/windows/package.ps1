[CmdletBinding()]
param(
  [string] $BuildDirectory = 'build/windows/x64/runner/Release',
  [string] $Destination
)

$ErrorActionPreference = 'Stop'
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
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

$runtime = Join-Path $BuildDirectory 'libmpv-2.dll'
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $runtime).Hash -ne
  '353D527E569F69D822A9D679B28D2E975C6B22A82AB9924D533110E1C21C8508') {
  throw 'Release build does not contain the pinned LGPL libmpv runtime.'
}
if (-not $env:LINEUP_MPV_ROOT -or
  -not (Test-Path -LiteralPath (Join-Path $env:LINEUP_MPV_ROOT 'licenses'))) {
  throw 'LINEUP_MPV_ROOT must point to the prepared production runtime.'
}

New-Item -ItemType Directory -Path $Destination | Out-Null
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
$vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
$redistVersion = Get-ChildItem -Directory (Join-Path $vs 'VC/Redist/MSVC') |
  Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'x64/Microsoft.VC143.CRT') } |
  Sort-Object { [version]$_.Name } -Descending |
  Select-Object -First 1
if (-not $redistVersion) { throw 'The retail x64 VC143 runtime is not installed.' }
$redist = Join-Path $redistVersion.FullName 'x64/Microsoft.VC143.CRT'
foreach ($file in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
  Copy-Item -LiteralPath (Join-Path $redist $file) -Destination $Destination
}

$licenses = Join-Path $Destination 'licenses'
New-Item -ItemType Directory -Path $licenses | Out-Null
Copy-Item -LiteralPath (Join-Path $repository 'LICENSE') -Destination (Join-Path $licenses 'Lineup-Desktop-Apache-2.0.txt')
Copy-Item -LiteralPath (Join-Path $repository 'tool/flutter_engine/NOTICE') -Destination (Join-Path $licenses 'Flutter-engine-patch-NOTICE.txt')
Copy-Item -LiteralPath (Join-Path $repository 'docs/windows-runtime.md') -Destination (Join-Path $licenses 'Windows-runtime-provenance.md')
foreach ($file in @('mpv-LICENSE.LGPL', 'FFmpeg-COPYING.LGPLv3', 'libplacebo-LICENSE')) {
  Copy-Item -LiteralPath (Join-Path $env:LINEUP_MPV_ROOT "licenses/$file") -Destination $licenses
}

$vcVersions = @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') | ForEach-Object {
  $file = Get-Item -LiteralPath (Join-Path $Destination $_)
  "$($file.Name)=$($file.VersionInfo.FileVersion)"
}
$sourceCommit = (git -C $repository rev-parse HEAD).Trim()
git -C $repository diff --quiet
$sourceDirty = $LASTEXITCODE -ne 0
git -C $repository diff --cached --quiet
$sourceDirty = $sourceDirty -or $LASTEXITCODE -ne 0
$sourceDirty = $sourceDirty -or @(
  git -C $repository ls-files --others --exclude-standard
).Count -ne 0
@(
  "Lineup Desktop $pubspecVersion Windows x64",
  "source-commit=$sourceCommit",
  "source-dirty=$($sourceDirty.ToString().ToLowerInvariant())",
  'flutter-framework=4cf24164269a5ebf0c16a028a00727d0e77bbb05',
  'flutter-engine=5f77625673248ee5846fbcaf5d3e1a3878386fd7',
  'flutter-engine-patch=tool/flutter_engine/0001-windows-direct-composition.patch',
  'mpv=mpv-v0.41.0-923-g7b8915bc1',
  'ffmpeg=N-126123-g8b4fad11a',
  'libplacebo=v7.371.0-111-g22ee762',
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
