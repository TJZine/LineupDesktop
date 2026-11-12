---
title: Windows
description: Install Lineup on Windows.
---
# Windows

Install Lineup from a portable ZIP on Windows.
{ .lead }

## Install

1. Download `LineupDesktop-<version>-windows-x64.zip` and its `.sha256` file from [GitHub Releases](https://github.com/TJZine/LineupDesktop/releases). If no Lineup ZIP is listed there, there is no public Windows build yet.
2. To verify it, run `Get-FileHash -Algorithm SHA256 .\LineupDesktop-<version>-windows-x64.zip` in PowerShell and compare the result with the `.sha256` file.
3. In File Explorer, choose **Extract All** and extract to a folder your user account can write to.
4. Read `SYSTEM-REQUIREMENTS.txt` in the package.
5. Run `lineup_desktop.exe` as a standard user. Keep the adjacent DLLs and the `data` folder with it. Use a current GPU driver or Vulkan Runtime that provides `vulkan-1.dll`.

!!! warning
    The Windows package is unsigned. If Windows shows “Windows protected your PC,” choose **More info** and then **Run anyway**, but only for a ZIP from the official release page. If [Smart App Control](https://learn.microsoft.com/en-us/windows/apps/develop/smart-app-control/overview) is on, Windows blocks this unsigned build and offers no exception for it. Don't turn Smart App Control off to run Lineup.

??? note "For testers"
    Get the complete private ZIP and its SHA-256 hash directly from the maintainer. Compare the archive with that hash and read the package's `BUILD-INFO.txt` and `BUILD-PROVENANCE.json` before running it.

## Update or uninstall

Extract an update to a new folder. Check that it works before deleting the old application folder.

To uninstall, sign out before deleting the application folder. See [Privacy and stored data](../reference/privacy.md#update-or-remove-lineup) for what stays on the PC.
