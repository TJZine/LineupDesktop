#Requires -Version 7.4

[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string] $Executable
)

$ErrorActionPreference = 'Stop'
if (-not $IsWindows -or
    [Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture -ne [Runtime.InteropServices.Architecture]::X64) {
  throw 'Native startup diagnostics require x64 PowerShell on Windows.'
}
$Executable = [IO.Path]::GetFullPath($Executable)
$directory = Split-Path -Parent $Executable
$roots = @($Executable, (Join-Path $directory 'libmpv-2.dll'), (Join-Path $directory 'flutter_windows.dll'))

$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if ($LASTEXITCODE -or -not $vs) { throw 'Could not locate MSVC for dependency diagnostics.' }
$tools = Get-ChildItem -LiteralPath (Join-Path $vs.Trim() 'VC/Tools/MSVC') -Directory |
  Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
if (-not $tools) { throw 'No MSVC toolset was found for dependency diagnostics.' }
$dumpbin = Join-Path $tools.FullName 'bin/Hostx64/x64/dumpbin.exe'

# Inspect the actual built files rather than assuming which runtime is absent.
$dependencies = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($file in $roots) {
  if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
    Write-Host "MISSING FILE: $file"
    continue
  }
  Write-Host "Dependency root: $file SHA256=$((Get-FileHash -Algorithm SHA256 -LiteralPath $file).Hash)"
  $imports = & $dumpbin /dependents $file
  if ($LASTEXITCODE) { throw "dumpbin failed for $file." }
  $imports | ForEach-Object { Write-Host $_ }
  foreach ($line in $imports) {
    if ($line -match '^\s+([A-Za-z0-9_.-]+\.dll)\s*$') {
      $null = $dependencies.Add($Matches[1])
    }
  }
}
if (-not $dependencies.Count) { throw 'No DLL imports were found in the built test or its runtimes.' }

Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class LineupNativeStartupDiagnostic {
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
  public static extern IntPtr LoadLibraryExW(string name, IntPtr reserved, uint flags);
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
  public static extern uint GetModuleFileNameW(IntPtr module, StringBuilder path, int size);
  [DllImport("kernel32.dll", SetLastError = true)]
  [return: MarshalAs(UnmanagedType.Bool)]
  public static extern bool FreeLibrary(IntPtr module);
}
'@

foreach ($name in ($dependencies | Sort-Object)) {
  $local = Join-Path $directory $name
  # Full-path loads use LOAD_WITH_ALTERED_SEARCH_PATH: dependencies start in
  # the test's directory. System/API-set imports use normal Windows lookup.
  $path = if (Test-Path -LiteralPath $local -PathType Leaf) { $local } else { $name }
  $flags = if ([IO.Path]::IsPathRooted($path)) { 8 } else { 0 }
  $module = [LineupNativeStartupDiagnostic]::LoadLibraryExW($path, [IntPtr]::Zero, $flags)
  $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
  if ($module -eq [IntPtr]::Zero) {
    $message = [ComponentModel.Win32Exception]::new($errorCode).Message
    Write-Host "LOAD FAILED: $name Win32=$errorCode ($message)"
    continue
  }
  try {
    $resolved = [Text.StringBuilder]::new(32768)
    $length = [LineupNativeStartupDiagnostic]::GetModuleFileNameW($module, $resolved, $resolved.Capacity)
    if (-not $length) { throw "Could not identify the loaded path for $name." }
    Write-Host "LOAD OK: $name -> $resolved"
  } finally {
    if (-not [LineupNativeStartupDiagnostic]::FreeLibrary($module)) {
      Write-Warning "FreeLibrary failed for $name."
    }
  }
}
