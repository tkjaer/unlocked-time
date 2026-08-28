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
- Manual pause and resume.

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

Set the daily and weekly maximum in 15-minute steps.

**Pause when idle** turns idle detection on or off, and **Idle after** sets the threshold in
minutes. Idle pausing defaults to on with a 10-minute threshold.

**Start at login** registers the app as a login item, so tracking resumes after a restart
without opening it manually.

**Import work log** reads completed intervals from a plain text file:

```text
2026-08-17 08:20-14:30+16:00-23:30
2026-08-18 07:45-16:15
```

One date per line, with intervals joined by `+`. Blank lines and lines starting with `#` are
ignored, and open intervals are rejected. Exact duplicates are skipped, so importing the same
file twice is safe.

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

## Tests

```sh
swift test
```
