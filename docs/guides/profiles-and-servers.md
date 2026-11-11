---
title: Profiles and servers
description: Choose your Plex Home profile and server.
---
# Profiles and servers

Choose who is watching and where Lineup gets your Plex libraries.
{ .lead }

## Plex Home profiles

After you link Plex, Lineup shows the picker if Plex returns more than one profile. Choose the person watching. Lineup uses a single profile automatically. If Plex returns no profiles, you go straight to choosing a server.

A protected profile opens a four-digit PIN keypad. You can also use the number row or numeric keypad. Lineup shows a lock for a protected profile. **Admin** and **Restricted** appear when Plex identifies those roles. **Current** marks the selected profile when you reopen the picker, regardless of which card has focus.

Your profile has its own sign-in, selected server, saved lineup, and related settings. Switching profiles keeps that setup separate. In **Settings** → **Account**, choose **Switch profile** or turn on **Show profile picker on startup** to ask who is watching when Plex returns multiple profiles.

## Plex Media Server

Choose an **Owned server** or a **Shared server**. Lineup tries usable direct connections before relays. **Current** marks the connected server and **Previously used** marks a saved choice. **Limited** means the connection uses a relay.

If you see **No servers found**, confirm the server is online and reachable, then choose **Refresh servers**. Choose **Switch profile** if you expect to find the server under a different profile, or choose another server when one is available. In **Settings** → **Account**, choose **Switch server** to reopen the server list.

??? note "Details"
    Only the selected server shows its measured route and latency. **Very slow** means 500 ms or more. Lower measured latencies show their route and value.

## Sign out

Choose **Sign out of Plex** in **Settings** → **Account**, or **Sign out** from the server picker or an empty library setup. Confirm to stop playback and return to Plex linking. See [Privacy and stored data](../reference/privacy.md#update-or-remove-lineup) for what stays on the device.
