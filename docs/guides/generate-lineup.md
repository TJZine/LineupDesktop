---
title: Generate a lineup
description: Build suggested channels from your Plex libraries.
---
# Generate a lineup

Let Lineup suggest channels from your Plex libraries, then review what it will change.
{ .lead }

## Choose libraries

Open **Channels** → **Generate lineup**, or continue from first-run setup. On **Choose libraries**, select the libraries to scan. The scan shows page and item counts, and reports ready, empty, unsupported, cancelled, or failed libraries. You can cancel a scan, retry failed libraries, or continue with the libraries that are ready.

If there are no usable movie or show libraries, choose **Switch server** or [sign out](profiles-and-servers.md#sign-out).

??? note "Details"
    Continuing saves the selected ready libraries. Cancelled or failed scans preserve the previous selection. Successful libraries remain available when you retry failures with the same profile and server.

    Collection discovery supports up to 100,000 records per collection listing and 100,000 member occurrences per library scan. Each listing or member stream stops at 1,000 pages. Repeated members and reads used to recover recreated collections count toward the member limit. If you hit the limit, reduce the collection inventory in Plex before rescanning. Retrying the same inventory reaches the same limit.

    Saved channels remain in place. An incomplete scan cannot establish that a saved collection source disappeared. If a saved lineup needs those collections, Lineup cannot restore or save that library selection until discovery succeeds. For temporary failures, use **Retry**.

## Configure

On **Configure**, choose playlists, collections, recently added content, genres, studios, actors, decades, or directors. Pick sources from individual libraries or group libraries. Choose a [playback order](schedules.md#playback-order), minimum programs per channel, and a limit for generated channels.

??? note "Details"
    Lineup takes one eligible original from each enabled source in order, then repeats the order and skips exhausted sources. Extra versions start off and come after originals when enabled. Review distinguishes exclusions caused by your configured limit from those caused by running out of channel numbers.

## Review and apply

In **Review**, look through the full proposed lineup and its current and final counts. Search by number or name, or filter for unchanged, updated, added, and removed entries. Custom channels stay unchanged in all three modes.

| Mode | What it does |
| --- | --- |
| **Update and add** | Updates matching generated channels in place and adds new channels. |
| **Replace generated channels** | Replaces generated programming and keeps your custom channels. |
| **Add as new channels** | Appends the proposed channels as new channels. |

Confirm removals and apply the changes explicitly. In replace mode, the confirmation stays visible while you inspect the roster.

On TV, Right from a channel row or disclosure heading jumps to the enabled primary action, or to **Back to configure** when the primary action is disabled. The hint reads **Press right on any channel to jump here**. Up returns to the remembered row. Moving between these areas leaves your search and confirmation in place and does not apply changes.

After an unchanged plan or a successful save, **View lineup** opens the lineup on desktop. On TV, **Open guide** goes to the Guide. After a successful save, **Add a custom channel** opens Channel Studio.

??? note "Details"
    **Update and add** preserves the matching channel's number, visible name, schedule starting point, and shuffle choices while updating its programming.

    If your lineup changes during review, review it again and apply it explicitly. A failed save preserves the prior lineup and review choices. If there are no changes, you can view the lineup without saving.
