#Requires -Version 7.4

function Assert-NoTrackedSymlinks {
  param(
    [Parameter(Mandatory)] [string] $Repository,
    [scriptblock] $FailureReporter = {
      param([Parameter(Mandatory)] [string] $Message)
      throw $Message
    }
  )

  $nativeErrorPreference = $PSNativeCommandUseErrorActionPreference
  $PSNativeCommandUseErrorActionPreference = $false
  try {
    $entries = @(& git -C $Repository ls-files --stage)
    if ($LASTEXITCODE) { throw 'git ls-files failed while checking tracked symlinks.' }
  } finally {
    $PSNativeCommandUseErrorActionPreference = $nativeErrorPreference
  }
  $symlinks = @($entries | Where-Object { $_ -match "^120000\s+\S+\s+[0-3]`t" })
  if ($symlinks.Count) {
    & $FailureReporter "Release source tree contains $($symlinks.Count) tracked symbolic link(s)."
    throw 'The tracked-symlink failure reporter returned unexpectedly.'
  }
}

function Assert-NoReparsePoints {
  param(
    [Parameter(Mandatory)] [string] $Root,
    [scriptblock] $FailureReporter = {
      param([Parameter(Mandatory)] [string] $Message)
      throw $Message
    }
  )

  $rootPath = [IO.Path]::GetFullPath($Root)
  $items = @(
    Get-Item -LiteralPath $rootPath -Force -ErrorAction Stop
    Get-ChildItem -LiteralPath $rootPath -Recurse -Force -ErrorAction Stop
  )
  foreach ($item in $items) {
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) { continue }
    $relative = [IO.Path]::GetRelativePath($rootPath, $item.FullName).Replace('\', '/')
    & $FailureReporter "Release build contains an unsupported reparse point: $relative."
    throw 'The reparse-point failure reporter returned unexpectedly.'
  }
}

function Get-ReparsePointPathWithin {
  param(
    [Parameter(Mandatory)] [string] $Path,
    [Parameter(Mandatory)] [string] $Boundary
  )

  $current = [IO.Path]::GetFullPath($Path)
  $boundaryPath = [IO.Path]::GetFullPath($Boundary)
  while ($true) {
    $item = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
    if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
      return $current
    }
    if ($current.Equals($boundaryPath, [StringComparison]::OrdinalIgnoreCase)) {
      return $null
    }
    $parent = [IO.Path]::GetDirectoryName($current)
    if ([string]::IsNullOrEmpty($parent) -or
      -not $current.StartsWith($boundaryPath + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
      throw 'Path is not below the required containment boundary.'
    }
    $current = $parent
  }
}

function Get-BuildInputs {
  param(
    [Parameter(Mandatory)] [string] $Root,
    [scriptblock] $FailureReporter = {
      param([Parameter(Mandatory)] [string] $Message)
      throw $Message
    }
  )

  Assert-NoReparsePoints -Root $Root -FailureReporter $FailureReporter

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
