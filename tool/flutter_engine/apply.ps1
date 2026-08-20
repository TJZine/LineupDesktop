[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string] $FlutterRoot
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$metadataRelativePath = 'tool/windows/build-metadata.psd1'
$metadataPath = Join-Path $repositoryRoot $metadataRelativePath

function Assert-CommittedInput {
  param([Parameter(Mandatory)] [string] $RelativePath)

  $committed = & git -C $repositoryRoot rev-parse "HEAD:$RelativePath"
  if ($LASTEXITCODE) { throw "Required committed input is missing: $RelativePath" }
  $committed = $committed.Trim()
  $working = & git -C $repositoryRoot hash-object -- $RelativePath
  if ($LASTEXITCODE) {
    throw "Build input must match its committed revision: $RelativePath"
  }
  $working = $working.Trim()
  if ($working -ne $committed) {
    throw "Build input must match its committed revision: $RelativePath"
  }
}

Assert-CommittedInput $metadataRelativePath
$metadata = Import-PowerShellDataFile -LiteralPath $metadataPath
$frameworkRevision = $metadata.FlutterFrameworkRevision
$engineRevision = $metadata.FlutterEngineRevision
$managerPath = $metadata.FlutterManagerPath
$managerBlob = $metadata.FlutterManagerBlob
$FlutterRoot = (Resolve-Path -LiteralPath $FlutterRoot).Path
$patchRelativePath = $metadata.FlutterEnginePatchPath
$patch = [IO.Path]::GetFullPath((Join-Path $repositoryRoot $patchRelativePath))
if (-not $patch.StartsWith(
    $repositoryRoot + [IO.Path]::DirectorySeparatorChar,
    [StringComparison]::OrdinalIgnoreCase)) {
  throw 'Flutter engine patch path escapes the Lineup repository.'
}
Assert-CommittedInput $patchRelativePath
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $patch).Hash -ne
  $metadata.FlutterEnginePatchSha256) {
  throw 'Flutter engine patch does not match its pinned SHA-256.'
}

$trackedChanges = @(& git -C $FlutterRoot status --porcelain --untracked-files=no)
if ($LASTEXITCODE) { throw 'Could not inspect FlutterRoot working-tree state.' }
if ($trackedChanges) {
  throw 'FlutterRoot must have no staged or unstaged tracked changes.'
}

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
