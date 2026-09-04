#Requires -Version 7.4

function Get-BuildInputs {
  param(
    [Parameter(Mandatory)] [string] $Root,
    [scriptblock] $FailureReporter = {
      param([Parameter(Mandatory)] [string] $Message)
      throw $Message
    }
  )

  $required = @(
    'lineup_desktop.exe',
    'flutter_windows.dll',
    'flutter_secure_storage_windows_plugin.dll',
    'libmpv-2.dll'
  )
  $paths = [System.Collections.Generic.List[string]]::new()
  foreach ($relative in $required) {
    $path = Join-Path $Root $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
      & $FailureReporter "Release build is missing $relative."
      throw 'The build-input failure reporter returned unexpectedly.'
    }
    $paths.Add($relative)
  }

  $data = Join-Path $Root 'data'
  if (-not (Test-Path -LiteralPath $data -PathType Container)) {
    & $FailureReporter 'Release build is missing the data directory.'
    throw 'The build-input failure reporter returned unexpectedly.'
  }
  foreach ($file in Get-ChildItem -LiteralPath $data -Recurse -File) {
    $paths.Add($file.FullName.Substring($Root.Length + 1).Replace('\', '/'))
  }

  $nativeAssets = Join-Path $Root 'native_assets.json'
  if (Test-Path -LiteralPath $nativeAssets -PathType Leaf) {
    $paths.Add('native_assets.json')
  }
  @($paths | Sort-Object -Unique)
}
