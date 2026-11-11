---
title: Windows
description: Install Lineup on Windows.
---
# Windows

Install Lineup from a portable ZIP on Windows.
{ .lead }

## Install

1. Download the ZIP from [GitHub Releases](https://github.com/TJZine/LineupDesktop/releases).
2. To verify it, run `Get-FileHash -Algorithm SHA256 .\FILE.zip` in PowerShell and compare the result with the attached `.sha256` file and release notes.
3. In File Explorer, choose **Extract All** and extract to a folder your user account can write to.
4. Read `SYSTEM-REQUIREMENTS.txt` and `BUILD-PROVENANCE.json` in the package.
5. Run `lineup_desktop.exe` as a standard user. Keep the adjacent DLLs and the `data` folder with it. Use a current GPU driver or Vulkan Runtime that provides `vulkan-1.dll`.

!!! warning
    The Windows package is unsigned. If Windows shows “Windows protected your PC,” choose **More info** and then **Run anyway** only for a ZIP from the official release page. [Smart App Control](https://learn.microsoft.com/en-us/windows/apps/develop/smart-app-control/overview) has no per-app exception. With Smart App Control on, this unsigned build cannot run. Leave it on.

??? note "For testers"
    Get the complete private ZIP and its SHA-256 hash directly from the maintainer. Compare the archive with that hash and read the package's `BUILD-INFO.txt` before running it.

## Update or uninstall

Extract an update to a new folder. Check that it works before deleting the old application folder.

To uninstall, sign out before deleting the application folder. See [Privacy and stored data](../reference/privacy.md#update-or-remove-lineup) for what stays on the PC.
