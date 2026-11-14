# Verification notes

## Version 2.2.0: overtime and session reviews

All 40 tests pass (24 core tests and 16 application integration tests). The new flow is covered by deadline/no-auto-break checks, actual overtime duration, exactly-once completion, long-break cadence, midnight attribution, sleep/relaunch recovery, schema 2 migration with an immutable backup, review drafts and edits across restart, Calendar synchronization using the actual end time, movable-window stability, menu actions, and Chinese review composition during break timer updates.

A fresh Release build and ad-hoc signature checks pass. Data schema 3 protects the new review fields from older app versions. Ratings and reflection text are not sent to Calendar. The interface remains in Simplified Chinese.

Live interface verification used a separate application identity and synthetic local data with Calendar disabled. A one-minute focus automatically opened the overtime window, which remained movable while its counter advanced. Clicking Start Break recorded a single 2-minute-18-second session, including 1 minute 18 seconds of overtime, and started a full five-minute break at the click time. Selecting a rating, entering a Chinese reflection, and saving persisted the review and closed the popup without interrupting the break.

An installed-version upgrade was also verified: existing goals, sessions, settings, and drafts remained semantically identical after schema migration, and the preserved pre-upgrade JSON matched its original bytes. Personal data and backups are excluded from source and application release archives.


## Version and scope

Version 2.1.1 changes the application name to Daylight. The interface, menus, messages, date formatting, and input behavior remain in Simplified Chinese. The bundle identifier, data location, and data schema remain unchanged.

Version 2.1.1 passed all 35 automated tests, a fresh release build, and ad-hoc signature verification on Apple Silicon. Source comparison confirmed that application strings changed only for the product name and version; a live launch showed the Daylight name with Chinese controls and existing records. The project declares macOS 14 as its minimum and uses a Swift 6 toolchain in Swift 5 language mode. Intel Macs and all supported macOS versions have not been tested on hardware.

## Automated coverage

| Area | Coverage |
| --- | --- |
| Dates and goals | Month, week, and year boundaries; goal scopes; completion state; exports |
| Persistence | Save, backup, corrupt-data protection, writer locking, version 1.x migration, and restore |
| Pomodoros | Estimates, completed/interrupted sessions, short/long breaks, midnight boundaries, sleep/relaunch recovery, and duplicate transitions |
| Tasks and drafts | Rename/delete history retention and drafts across date changes and relaunch |
| Chinese input | Native marked text, autosave and timer refresh, date changes, undo and redo |
| Calendar | Mocked success, denied access, retry, deduplication, and persisted pending state |
| Monthly harvest | Local completion-month boundaries, exclusion of interruptions, grouping above 240 sessions, pause when hidden, and Reduce Motion |

Run all tests:

```sh
swift test --disable-sandbox
```

AppKit and SpriteKit tests require access to macOS graphics services. Restricted environments without a desktop graphics session may not support them. For core logic only:

```sh
swift test --disable-sandbox --filter DaylightCoreTests
```

## Interface checks and limitations

- Isolated demo data was used to check goals, strikethrough completion, reflections, Pomodoro settings, history, and clothesline checkboxes.
- A separate preview app with 17 synthetic sessions was used to check falling, collisions, stacking, click-to-bounce, settling, and reopening the harvest.
- Menu action paths have integration tests. The monochrome tomato icon was checked through offscreen rendering; live screenshots of every system menu bar appearance were not collected.
- Chinese composition was verified through the NSTextInputClient protocol, not every third-party input method.
- Calendar tests use a mock service. No test events were written to a real calendar, and every calendar account type has not been tested end to end.
- Developer ID signing, notarization, App Store distribution, and private iCloud app-data synchronization have not been verified.

The public source includes generic demo wording. Runtime logs, generated apps, and demo records are excluded from the repository.

## Public release packaging

The public 2.1.1 application is stripped of debug and local symbols before ad-hoc signing. Its bundle was scanned for developer home-directory paths and private records, and the packaged archive is verified after extraction. No app logic or data schema changes are introduced by this packaging step.
