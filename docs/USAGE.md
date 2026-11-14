# Usage guide

The app is named Daylight. The README is available in English and Simplified Chinese; this detailed guide is in English. All application controls and prompts remain in Simplified Chinese.

## Goals and checklists

Left-click the menu bar tomato to open the clothesline, or right-click it to open the task and timer menu. Click a card or pencil to edit. Clicking a checkbox completes or reopens a task; completed tasks remain visible with a strikethrough.

Long-term goals are shared across all dates. Monthly goals belong to a calendar month. Weekly goals belong to Monday through Sunday, including weeks that span two months. Daily tasks and reflections belong to individual dates. New periods start empty; navigate to another date to view or edit that period.

The task input accepts one item per line, including `- [ ]` and `- [x]` notation. Both task edits and unsubmitted drafts are autosaved. Daily tasks have an estimated Pomodoro count and an actual completed count. An estimate of zero means no estimate has been set.

Daily planning and reflection remain separate. Completing a Pomodoro does not automatically check off its task.

## Pomodoro timers

Start focus beside a daily task, or select one of today's tasks from the menu bar. Every daily task is already a named timer target; separate labels are unnecessary.

Defaults are 25 minutes of focus, a 5-minute short break, and a 15-minute long break after every 4 completed sessions. Change these in Pomodoro and Calendar settings (`⌘,`). New settings apply to the next interval without resetting the current one.

During focus, the menu bar shows the task title and remaining time; after the deadline, it shows the same task with a `+MM:SS` overtime counter. During a break, it shows the break type and remaining time. When idle, it shows a monochrome smiling tomato followed by today's completed count. Long titles are shortened; the tooltip retains the full title.

At the planned focus deadline, a floating, movable window appears automatically and displays elapsed overtime in minutes and seconds. It is non-modal: move it aside to keep working. It stays open until you click Start Break and does not move or reclaim focus every second. No break or completed-session record is generated just by reaching the deadline.

Clicking Start Break finalizes exactly one completed Pomodoro using the actual click time as its end, starts a full short or long break from that moment, and opens a review. Choose great, okay, or poor; optionally write a reflection. The break continues while you write. Review drafts autosave, including after postponing a review; unfinished reviews reappear after relaunch. Recent focus history lets you reopen or edit a review. Ratings and reflections stay local rather than being copied into Calendar.

After the break, select a task to start another focus interval. You can interrupt an unfinished focus interval or skip a break. An early interruption saves the elapsed interval but does not increment completed counts.

Renaming a task preserves its statistics. Finished sessions retain the title used at the time. Deleting a task does not delete its focus history or existing Calendar events.

Timers use wall-clock deadlines. Time continues to pass while the computer sleeps or the app is closed. On wake or relaunch, an overdue focus session resumes its overtime display until you explicitly start a break. Already-started breaks can expire while the app is away. The app does not create further focus sessions automatically. Closing an editing window does not stop a timer.

A session finalized after midnight contributes to that day's menu bar count while remaining linked to its original task date. The month of the actual finish click determines its harvest month.

## Monthly harvest

The clothesline's bottom panel shows completed sessions for the current calendar month, determined by their local end time. Interrupted sessions are excluded. Navigating to a different week does not change the current-month harvest.

Opening the clothesline makes orange smiling tomatoes fall, collide, roll, and stack. Click a tomato to bounce it. On smaller screens, the cards above can scroll while the harvest stays visible.

Hiding the panel pauses rendering immediately. An animation pauses after approximately 13 seconds. With the system's Reduce Motion setting enabled, the scene displays a static arrangement.

Up to 240 sessions, each displayed tomato represents one completed session. Above that limit, tomatoes are grouped and labeled with their counts, preserving the exact monthly total. An empty month displays a message and no artificial tomatoes.

## Apple Calendar

Turn on Calendar sync in Pomodoro and Calendar settings, grant the macOS permission request, and choose a writable calendar. Full EventKit access is used to list calendars and detect previously written records before retrying.

- Newly ended focus sessions use the task title as the event title and actual start/end times as the event interval.
- Completed and interrupted focus sessions are recorded, with their status in the notes. Interruptions shorter than a second are represented as one second. Breaks do not create events.
- If permission is denied, a calendar becomes unavailable, or saving fails, the focus record remains local with a pending status. Select a valid calendar and retry.
- Events carry a unique record URL. Before writing, the app checks that marker to avoid duplicates after a crash or retry.
- Turning sync off retains existing events. Re-enabling it retries records that already requested sync; it does not backfill history created while sync was disabled.
- Deduplication reads events in the relevant time interval to inspect their markers. It does not modify unrelated events. iCloud and shared-calendar behavior follows the selected service's own settings.

## Storage, backup, and migration

Data remains in `~/Library/Application Support/DaylightGoals/`, including after the rename to Daylight. The bundle identifier also remains unchanged.

Version 2.2 uses schema 3 for planned focus deadlines, session ratings, and reflection drafts. Loading schema 1 or 2 creates an immutable `planner.before-v3.json` backup before writing the upgrade. Existing goals, focus records, calendar settings, and running timers are preserved. Legacy sessions do not generate unwanted review prompts.

For version 1.x data, the previous migration also applies:

1. The original file is preserved as `planner.before-v2.json`; later autosaves do not overwrite this migration backup.
2. Nonempty goal lines become checklist items. Existing `- [x]` markers retain completion state.
3. The old actual-completion text moves into daily reflection without dropping historical dates.
4. Tasks, estimates, focus records, timer state, and drafts are stored together in the current schema.

`planner.json` is current data; `planner.previous.json` is the previous save. The full planner provides JSON backup, restore, and Markdown export controls. Restoring preserves the current file first and does not resume a historical running timer from the backup.

Version 2.1 and earlier cannot read schema 3. Rolling back requires restoring a compatible pre-migration backup as well as the old application.

Autosave runs approximately 0.35 seconds after input stops. The native text editor keeps Chinese input-method composition under the input method's control; confirmed text then updates the model. Switching dates or closing windows preserves visible input. Per-second timer updates do not replace marked text.

## Build and test

```sh
bash scripts/build-app.sh
swift test --disable-sandbox
```

The app is generated at `build/Daylight.app`. Set `DAYLIGHT_BUILD_ROOT` to override the output directory. The local build uses ad-hoc signing. See [verification notes](VERIFICATION.md) for test coverage and platform limits.
