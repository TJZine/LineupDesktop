---
title: Support reports
description: Review and share a redacted report when you need help.
---
# Support reports

Record a problem, then review a redacted support report before sharing it.
{ .lead }

## Record and copy

Diagnostics is off by default. Open **Settings** → **Support** and turn on **Record redacted diagnostics** before reproducing a problem. Choose **Open Diagnostics** to review recent events from this session, then select **Copy redacted report**. Turning recording off clears the recorded events.

See [Privacy and stored data](../reference/privacy.md#diagnostics) for what the report redacts.

??? note "Details"
    Technical details and reports show separate **Windows display**, **HDR matching**, and **Renderer output** facts with normalized values. The Windows display state comes from Windows and cannot confirm the TV's picture. Source HDR, renderer output, and Windows display state are separate observations. Decoded dimensions and hardware-decoder facts can also appear in Diagnostics.

    A completed or failed library scan can log **Library scan budget usage** with `bytes`, `entries`, `requests`, and `elapsedMs`. These fields measure scan work Lineup admitted.

## Share safely

1. Review every line and screenshot.
2. Remove private media titles and account details the report doesn't need.
3. Keep your Plex token, authorization header, URLs with credentials, and credential-store content private.

Use the [bug-report template](https://github.com/TJZine/LineupDesktop/blob/main/.github/ISSUE_TEMPLATE/bug_report.md) for ordinary issues. Report vulnerabilities privately through the [security policy](https://github.com/TJZine/LineupDesktop/blob/main/SECURITY.md).

??? note "For testers"
    Include the source commit or package `BUILD-INFO.txt`, Windows version, GPU and driver, display resolution and scaling, connection type, and exact reproduction steps.

    For black or hidden video, record the window size, scaling, fullscreen state, Guide layout, whether audio continues, and whether the problem follows a resize, minimize, or restore. Report it as a native composition problem with the current commit.

    If a replacement channel leaves stale audio or video, stop that scenario, record both channel transitions and timestamps, and report it as a native playback-lifetime problem.
