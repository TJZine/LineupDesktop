[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string] $FlutterRoot
)

$ErrorActionPreference = 'Stop'
$frameworkRevision = '4cf24164269a5ebf0c16a028a00727d0e77bbb05'
$engineRevision = '5f77625673248ee5846fbcaf5d3e1a3878386fd7'
$managerBlob = '64fb765bf546190fa610a9bdff007fc881c3cc7e'
$FlutterRoot = (Resolve-Path -LiteralPath $FlutterRoot).Path
$patch = Join-Path $PSScriptRoot '0001-windows-direct-composition.patch'

if ((git -C $FlutterRoot rev-parse HEAD).Trim() -ne $frameworkRevision) {
  throw "FlutterRoot must be framework revision $frameworkRevision."
}
if ((Get-Content -Raw (Join-Path $FlutterRoot 'bin/internal/engine.version')).Trim() -ne $engineRevision) {
  throw "FlutterRoot must pin engine revision $engineRevision."
}
$managerPath = 'engine/src/flutter/shell/platform/windows/egl/manager.cc'
if ((git -C $FlutterRoot rev-parse "HEAD:$managerPath").Trim() -ne $managerBlob) {
  throw 'FlutterRoot does not contain the exact pinned Windows EGL manager source.'
}

# The patch has normal source context; this rejects a source tree it does not target.
& git -C $FlutterRoot apply --check $patch
if ($LASTEXITCODE) { throw 'Flutter engine patch does not apply to this checkout.' }
& git -C $FlutterRoot apply $patch
if ($LASTEXITCODE) { throw 'Flutter engine patch could not be applied.' }
