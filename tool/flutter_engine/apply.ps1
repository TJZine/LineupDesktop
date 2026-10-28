#Requires -Version 7.4
[CmdletBinding()]
param([Parameter(Mandatory)] [string] $FlutterRoot)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../windows/build-inputs.ps1')
Invoke-NativeChecked -FilePath 'python' -Arguments @(
  (Join-Path $PSScriptRoot 'desktop_accessibility.py'), 'apply',
  '--flutter-root', $FlutterRoot, '--platform', 'windows'
) -FailureMessage 'Combined Windows engine patch application failed.'
