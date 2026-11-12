---
title: How schedules work
description: Learn how Lineup keeps each channel on its schedule.
---
# How schedules work

Each channel keeps its own schedule, so tuning in joins the program already on.
{ .lead }

## Playback order

**Playback order** determines the sequence of programs. Choose **Shuffle**, **In order**, or **Mini-marathons**. Mini-marathons play blocks of two to five episodes from one show and require episodes that Lineup can group by show. They can include specials when enabled, including in additional versions.

??? note "Details"
    A new custom channel saves the schedule starting point and shuffle choices shown in the schedule preview. Updating a matching generated channel keeps its schedule starting point and shuffle choices.

    Shuffle accounts for each occurrence and its duration before shuffling. A Plex server response that only reorders the same programs won't reshuffle the schedule. A saved shuffle can transition once when the scheduling rules change, while preserving the cycle before the transition. **In order** and **Mini-marathons** keep their ordering rules.

## Program endings

If a Plex item has several sequential parts, Lineup plays them back to back as one program. With DVR controls on, the Player can show total progress and seek across parts when it knows all the durations it needs. Otherwise it shows the current part's timing.

At the natural end of a channel's last media part, Lineup starts the next scheduled program from the beginning, even if the previous file ends before its slot ends. It allows small loading delays to preserve the next program's opening. After a longer delay, Lineup rejoins the live schedule. Manually tuning or choosing **Retry** also joins live.

If the next program fails to start, Lineup waits for you to choose **Retry**.

The Player title, progress, and **Up next** follow the loaded program. The full Guide and Mini Guide stay on the clock schedule. Changing channel, stopping, a sleep timer ending, signing out, or changing the lineup cancels a next program that hasn't started yet.

??? note "Details"
    If the next program's scheduled start was more than 30 seconds ago, such as after a pause, Lineup joins the program airing now at its live position. If a stream ends more than 30 seconds before its known duration, Lineup shows a playback error with **Retry** instead of advancing.
