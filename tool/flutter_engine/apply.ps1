[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string] $FlutterRoot
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$metadataPath = Join-Path $repositoryRoot 'tool/windows/build-metadata.psd1'
$metadata = Import-PowerShellDataFile -LiteralPath $metadataPath
$frameworkRevision = $metadata.FlutterFrameworkRevision
$engineRevision = $metadata.FlutterEngineRevision
$managerPath = $metadata.FlutterManagerPath
$managerBlob = $metadata.FlutterManagerBlob
$FlutterRoot = (Resolve-Path -LiteralPath $FlutterRoot).Path
$patch = Join-Path $repositoryRoot $metadata.FlutterEnginePatchPath

if ((git -C $FlutterRoot rev-parse HEAD).Trim() -ne $frameworkRevision) {
  throw "FlutterRoot must be framework revision $frameworkRevision."
}
if ((Get-Content -Raw (Join-Path $FlutterRoot 'bin/internal/engine.version')).Trim() -ne $engineRevision) {
  throw "FlutterRoot must pin engine revision $engineRevision."
}
if ((git -C $FlutterRoot rev-parse "HEAD:$managerPath").Trim() -ne $managerBlob) {
  throw 'FlutterRoot does not contain the exact pinned Windows EGL manager source.'
}

# The patch has normal source context; this rejects a source tree it does not target.
& git -C $FlutterRoot apply --check $patch
if ($LASTEXITCODE) { throw 'Flutter engine patch does not apply to this checkout.' }
& git -C $FlutterRoot apply $patch
if ($LASTEXITCODE) { throw 'Flutter engine patch could not be applied.' }
