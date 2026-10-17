#Requires -Version 7.4

function Write-LineupNinjaDiagnostics {
  param(
    [Parameter(Mandatory)] [string] $BuildDirectory,
    [Parameter(Mandatory)] [string] $Stage,
    [switch] $InspectCommand
  )

  # Observation only: never replace Ninja selection, clean outputs, or hide a build failure.
  $previousExitCode = $global:LASTEXITCODE
  $PSNativeCommandUseErrorActionPreference = $false
  try {
    Write-Host "Ninja diagnostics [$Stage]"
    $output = (Resolve-Path -LiteralPath $BuildDirectory -ErrorAction Stop).Path
    Write-Host "Working directory: $((Get-Location).Path)"
    Write-Host "Build directory: $output"
    foreach ($name in @('build.ninja', '.ninja_log')) {
      $path = Join-Path $output $name
      if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Write-Host "${path}: missing"
        continue
      }
      $file = Get-Item -LiteralPath $path -Force -ErrorAction Stop
      $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path -ErrorAction Stop).Hash
      Write-Host "${path}: bytes=$($file.Length) modifiedUtc=$($file.LastWriteTimeUtc.ToString('o')) sha256=$hash"
      if ($name -eq '.ninja_log') {
        $header = Get-Content -LiteralPath $path -TotalCount 1 -ErrorAction Stop
        Write-Host "Ninja log header: $header"
      }
    }

    if (-not $InspectCommand) { return }
    $commands = @(Get-Command ninja -All -ErrorAction Stop)
    foreach ($command in $commands) {
      Write-Host "Ninja command candidate: type=$($command.CommandType) path=$($command.Source)"
    }
    $selected = $commands[0]
    if ($selected.CommandType -ne 'Application') {
      throw "Cannot inspect Ninja command type $($selected.CommandType)."
    }
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $selected.Source -ErrorAction Stop).Hash
    Write-Host "Selected Ninja command: $($selected.Source) sha256=$hash"

    $wrapper = Join-Path (Split-Path -Parent $selected.Source) 'ninja.py'
    if ($selected.Name -eq 'ninja.bat' -and (Test-Path -LiteralPath $wrapper -PathType Leaf)) {
      $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $wrapper -ErrorAction Stop).Hash
      Write-Host "Ninja Python wrapper: $wrapper sha256=$hash"
      # Run the wrapper's own selection code for --version, observing its real
      # subprocess launch instead of guessing which checkout/PATH binary it uses.
      $probe = @'
import hashlib
import os
from pathlib import Path
import runpy
import shutil
import subprocess
import sys

wrapper = Path(sys.argv[1]).resolve()
output = sys.argv[2]

class ObservedPopen(subprocess.Popen):
    def __init__(self, args, *positional, **keywords):
        executable = keywords.get("executable") or (args[0] if isinstance(args, (list, tuple)) else args)
        executable = Path(shutil.which(executable) or executable).resolve()
        if executable.name.lower() in ("ninja", "ninja.exe"):
            digest = hashlib.sha256(executable.read_bytes()).hexdigest().upper()
            print(f"Ninja wrapper child executable: {executable} sha256={digest}", flush=True)
        super().__init__(args, *positional, **keywords)

# Keep Popen a class: depot_tools also imports a subprocess2 subclass.
subprocess.Popen = ObservedPopen
# Match ninja.bat's appended depot_tools entry and Python script import path.
os.environ["PATH"] = os.environ.get("PATH", "") + os.pathsep + str(wrapper.parent)
sys.path.insert(0, str(wrapper.parent))
sys.argv = [str(wrapper), "-C", output, "--version"]
runpy.run_path(str(wrapper), run_name="__main__")
'@
      Write-Host 'Ninja version (wrapper probe):'
      # python3 can itself be a depot_tools batch file; a script file avoids
      # passing multiline Python through Windows batch argument quoting.
      $probeFile = [IO.Path]::GetTempFileName()
      try {
        [IO.File]::WriteAllText($probeFile, $probe)
        & python3 $probeFile $wrapper $output | ForEach-Object { Write-Host $_ }
        $versionExitCode = $LASTEXITCODE
      } finally {
        Remove-Item -LiteralPath $probeFile -Force -ErrorAction SilentlyContinue
      }
    } else {
      Write-Host 'Ninja version:'
      & $selected -C $output --version | ForEach-Object { Write-Host $_ }
      $versionExitCode = $LASTEXITCODE
    }
    if ($versionExitCode) { throw "Ninja version probe exited with code $versionExitCode." }
  } catch {
    Write-Warning "Ninja diagnostics [$Stage] unavailable: $($_.Exception.Message)"
  } finally {
    $global:LASTEXITCODE = $previousExitCode
  }
}
