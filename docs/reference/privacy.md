---
title: Privacy and stored data
description: Learn what Lineup stores and how diagnostics protect private data.
---
# Privacy and stored data

Lineup keeps your Plex sign-in in your system's secure credential storage and saves your lineup on your device.
{ .lead }

## Plex sign-in and servers

Your Plex account and profile credentials stay out of ordinary app data. Each discovered Plex Media Server has a separate credential. Lineup uses it only to contact that server during the current session and keeps it out of saved app data and the interface.

Cancelling Plex sign-in clears the pending credentials before returning you to the welcome screen. If Lineup cannot confirm secure cancellation, follow the [sign-in recovery steps](../guides/troubleshooting.md#plex-linking-and-servers).

## Update or remove Lineup

Signing out stops playback and removes Plex sign-in credentials. Your lineup and media metadata remain in local app data. Removing that data through the operating system permanently deletes your saved setup, settings, and lineups.

On Windows, replacing or deleting the portable application folder leaves local app data in place. Sign out before removing the app folder if you want to remove your sign-in.

On Android TV and Fire TV, install an update over the Lineup app you already have. Uninstalling first removes your saved lineups and sign-in credentials.

## Diagnostics

Lineup records only a small, fixed set of facts. It redacts known credentials, authorization headers, URLs that contain a Plex token, and private paths. It omits arbitrary exception text and arbitrary messages from the playback engine. [Review a support report](../guides/support-reports.md) before sharing it because it can still describe private activity.
