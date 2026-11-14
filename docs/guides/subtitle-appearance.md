---
title: Subtitle appearance
description: Adjust how subtitles look in Lineup.
---
# Subtitle appearance

Open **Settings** → **Subtitles** to change how subtitles look across Lineup.
{ .lead }

## Preview and saving

The preview shows sample text at its actual playback size, independent of the app's text size. It stays visible while the controls scroll. On a narrow screen or with larger app text, the crop shrinks to make room for the focused control. The sample text keeps its size.

Changes appear in the preview while they save. A save failure restores the previous value and shows feedback beneath its control.

??? note "Details"
    If the complete focused control and save feedback still cannot fit after the preview disappears, the Subtitles heading and help text scroll with the controls. The main Settings header and category rail stay fixed. Later queued choices stay in order. A control stays focused and available during its own save.

## Style and layout

Choose a **Style** preset: **Standard**, **Drop shadow**, **Classic box**, **High contrast**, or **Light**. **Custom** means your current style differs from the presets. Presets preserve **Size**, **Position**, **Font**, **Bold**, and both subtitle toggles.

- Adjust **Size** from 50% to 300%, choose a **Position**, and set the text **Color**, **Opacity**, **Font**, and **Bold**. All seven fonts come with Lineup.
- In the edges group, choose a **Style** and a **Color**. Edge color is available when the style is above **None**.
- The background paints behind each line. The window paints one box behind the caption. Each **Color** control becomes available when its **Opacity** is above **Off**.

**Reset to standard** restores all Lineup subtitle preferences and keeps your choice for **Use device subtitle settings**.

## Device and track behavior

On Android, **Use device subtitle settings** uses the caption style and size from Android for all subtitle formats, even if Android's captions switch is off. **Position** and **Bold** stay in Lineup. The Lineup look, font, and size controls are disabled while device style is on. Other platforms use Lineup's settings.

**Apply my style to styled subtitles** uses your style for ASS/SSA dialogue and drops signs and author positioning. Leave it off to preserve authored styling.

| Track kind | Windows and macOS | Android TV, Fire OS, phone and tablet |
| --- | --- | --- |
| Plain text (SRT, WebVTT, mov_text, CEA-608/708) | All appearance settings. WebVTT cue positions are unavailable. | All appearance settings. WebVTT and CEA-608 positions map to top, middle, or bottom. |
| ASS/SSA | Size, or all appearance settings with **Apply my style to styled subtitles** on. | Size, or all appearance settings with **Apply my style to styled subtitles** on. |
| Image subtitles (PGS, VobSub, DVB) | Size and position. Large subtitles can extend beyond the picture. | Size and position. Subtitles stay inside the picture. |

See [Known limitations](../reference/limitations.md) for paused seeking with ASS/SSA on Android.

??? note "Details"
    Until an Android caption style is available, the preview uses your saved Lineup style. If an update fails, it keeps the latest valid device style.

## TV remote

From the category rail, press Right to enter the controls. Up and Down move between enabled controls. Left returns to **Subtitles**. Select opens the menu at the current value or at **Standard** when the style is **Custom**. Select applies the choice. Back closes the menu and leaves the preview unchanged.
