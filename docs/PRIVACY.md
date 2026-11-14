# Data and privacy

## Local records

Daylight stores goals, completion state, daily reflections, task drafts, Pomodoro estimates, focus history, session ratings, session reflection drafts, and timer settings in `~/Library/Application Support/DaylightGoals/`. Calendar sync also stores the selected calendar identifier, synced event identifiers, and pending-sync state.

| File | Purpose |
| --- | --- |
| `planner.json` | Current data |
| `planner.previous.json` | Previous save |
| `planner.before-v2.json` | Original version 1.x data, if a migration occurred |
| `planner.before-v3.json` | Original data preserved before the version 2.2 upgrade |
| `before-restore-*.json` | Data preserved before a manual restore |
| `.writer.lock` | Prevents concurrent writers to the same data directory |

Records use plain JSON. The app sets user-level filesystem permissions but does not add encryption. Markdown exports and JSON backups can contain complete personal records.

Changing the application name to Daylight does not rename or rewrite the data directory, its contents, or the bundle identifier.

## Calendar access

Calendar sync is off by default. Enabling it requests full EventKit access so the app can list writable calendars, create focus events, and detect duplicates before retrying.

- A completed or interrupted focus session becomes an event with the task title and actual focus interval.
- Notes include outcome, task date, elapsed focus seconds, and record identifier. The URL field contains a unique record marker.
- Deduplication reads events in the relevant interval to inspect their markers. The app does not modify unrelated events or upload their contents to a separate server.
- Session ratings and reflections remain local and are not included in Calendar notes. Editing a review does not resync the event.
- Breaks do not create events. Disabling sync does not delete previously created events.
- Events in iCloud, shared, or other account calendars follow that service's synchronization and sharing settings.

## Network behavior

There are no account, advertising, analytics, or telemetry endpoints and no third-party network dependencies. The AetherNote help link opens in a browser only when selected. The operating system and selected calendar service handle any Calendar synchronization.

## Repository contents

This repository includes source, tests, build configuration, and documentation. Tests use temporary directories and generic fixtures. Demo tasks are generic learning, reading, and exercise examples and are generated only when both `--data-dir` and `--demo` are explicitly supplied.

Personal runtime data, real calendar identifiers, backups, screenshots, compiled applications, debug symbols, logs, signing keys, local account names, and development conversations are excluded. Build output is kept outside the source distribution to avoid publishing machine paths embedded in debug information.

The `.gitignore` covers common data, export, credential, and build paths. Review screenshots and any newly added files before publishing. Ignore rules cannot remove files already present in Git history.
