# Unlocked Time

A native macOS menu bar app that tracks how long your Mac is unlocked and reports daily and
weekly totals against limits you set.

## What it shows

- Today's total against the daily maximum.
- This week's total against the weekly maximum.
- Remaining time, or a red over-limit amount.
- The moment the weekly limit was reached, once it is passed.
- A trend chart of the last 7 days or 8 weeks, with the limit marked.
- A matching list of those days or weeks.
- Which days or weeks are marked as PTO.
- Manual pause and resume.

## History

The list starts on the last 7 days or the last 8 weeks. Clicking a week opens that week's days,
and clicking a day opens the individual sessions worked that day, with start and end times. The
chevron by the title steps back up, and closing the panel returns it to the top level.

## PTO

Right-click a day or week in the history list to mark it as PTO, or to clear the mark. Marking a
week marks all seven of its days, and a week shows as PTO only when every day is marked.

PTO is a label by default. It does not change any total, and time tracked on a PTO day is still
counted.

With **PTO reduces weekly maximum** on, each PTO weekday lowers that week's maximum by the
configured **PTO day value**, so a week with a day off is judged against a smaller ceiling
instead of looking artificially under. Weekend days never reduce it, and the result never drops
below zero.

## Tracking

A session runs while the app is open and the screen is unlocked. It stops when the screen locks,
the display sleeps, or the user session becomes inactive, and resumes on unlock or wake.

With **Pause when idle** on, a session also stops after the configured number of minutes without
keyboard or mouse input. The stop is backdated to the last input, so the idle stretch is never
counted, and tracking resumes as soon as you use the Mac again. Idle is measured from input
alone, so watching a video counts as idle.

The app only observes these events while it is running. It cannot reconstruct activity from
periods when it was closed. After an unexpected exit, an open session is closed at its last
one-minute heartbeat.

## Settings

Set the daily and weekly maximum with separate hour and minute adjusters, in 5-minute steps.

**PTO reduces weekly maximum** lowers a week's ceiling for each PTO weekday, by the **PTO day
value**. Off by default.

**Pause when idle** turns idle detection on or off, and **Idle after** sets the threshold in
minutes. Idle pausing defaults to on with a 10-minute threshold.

**Start at login** registers the app as a login item, so tracking resumes after a restart
without opening it manually.

**Import work log** reads completed intervals from a plain text file:

```text
2026-08-17 08:20-14:30+16:00-23:30
2026-08-19 PTO
2026-08-20 PTO 09:00-11:00
```

One date per line, with intervals joined by `+` and an optional leading `PTO` marker. Blank
lines and lines starting with `#` are ignored, and open intervals are rejected. A session
running to midnight ends at `24:00`. Exact duplicates are skipped, so importing the same file
twice is safe.

**Export** in the History window writes this same format, so exports can be re-imported. Times
are written to the minute, and a session in progress is written up to the current time.

History and settings are stored locally:

```text
~/Library/Application Support/UnlockedTime/history.json
```

## Build

Requires macOS 14 or newer and Xcode Command Line Tools.

```sh
./build-app.sh
open "dist/Unlocked Time.app"
```

Import a work log at launch:

```sh
open -n "dist/Unlocked Time.app" --args --import ~/time_worked.txt
```

The app has no Dock icon. Keep it running for tracking to continue.

The app icon is generated rather than stored as an opaque asset. To change it, edit
`Tools/make-icon.swift`, then:

```sh
swift Tools/make-icon.swift
iconutil -c icns App/AppIcon.iconset -o App/AppIcon.icns
```

## Tests

```sh
swift test
```
