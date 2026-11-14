# Daylight

**English** | [简体中文](README.zh-CN.md)

**Keep your goals in sight. Turn focused time into a harvest.**

Daylight is a native macOS menu bar app for long-term goals, monthly and weekly plans, daily checklists, and task-based Pomodoro timers. Open the clothesline panel to see your week at a glance, then watch completed sessions collect as smiling tomatoes at the bottom.

**Version 2.2.0** · SwiftUI / AppKit / SpriteKit · No third-party package dependencies

> The app is named Daylight, and this README is available in English and Simplified Chinese. The application interface remains in Simplified Chinese, including menus, settings, messages, and reflection prompts. You can write your own tasks in any language.

## Features

| Feature | What it does |
| --- | --- |
| Four levels of goals | Keep shared long-term goals, separate monthly and weekly goals, and daily tasks |
| Checklists | Check off tasks without removing them; paste multiple lines or `- [ ]` / `- [x]` lists |
| Daily reflection | Plan your day and keep a separate evening reflection |
| Task-based Pomodoros | Start a named timer directly from a daily task; track estimated and completed sessions |
| Overtime and reflection | A movable completion window keeps counting until you start a break; rate the session and write a reflection |
| Flexible breaks | Configure focus duration, short breaks, long-break frequency, and long-break duration |
| Menu bar controls | Show today's completed count when idle, or the current activity and remaining time |
| Monthly harvest | Watch tomatoes fall, collide, and stack; click one to make it bounce |
| Apple Calendar | Optionally record completed or interrupted focus sessions in a selected calendar |
| Local storage | Autosave, full JSON backup and restore, and daily or weekly Markdown export |
| Chinese input support | Preserve input-method composition during autosave and timer updates |

## Install a release

Download [Daylight v2.2.0 for macOS (Apple Silicon)](https://github.com/liyizhen127/Daylight/releases/download/v2.2.0/Daylight-v2.2.0-macOS-arm64.zip), for **Apple Silicon Macs running macOS 14 or later**. Unzip it, drag `Daylight.app` into Applications, and open it. Intel Macs are not supported by this binary.

The app, source archive, and checksums are available on the [v2.2.0 release page](https://github.com/liyizhen127/Daylight/releases/tag/v2.2.0). This build uses ad-hoc signing and is **not notarized by Apple**, so macOS may block first launch pending user approval. See the [release notes](docs/releases/v2.2.0.md) for package contents and checksum verification.

## Build

Requires macOS 14 or later and an Xcode or Command Line Tools installation providing the Swift 6 toolchain. The app has been built and checked on Apple Silicon. Intel Macs and every supported macOS version have not been tested on hardware.

From the repository root:

```sh
bash scripts/build-app.sh
open "build/Daylight.app"
```

The script builds the release executable, generates the icon, assembles the app bundle, and applies a local ad-hoc signature. You can then move `build/Daylight.app` into Applications. Developer ID signing, notarization, and App Store distribution are not configured.

To use a different build directory:

```sh
DAYLIGHT_BUILD_ROOT="$PWD/build-release" bash scripts/build-app.sh
```

## Use

1. Launch Daylight. Left-click its menu bar tomato to open or close the clothesline; right-click to select a task or control a timer.
2. Click a goal card or its pencil button to edit it. Completed items remain visible with a strikethrough.
3. Set an estimated Pomodoro count beside a daily task and start a focus session.
4. Press `⌘,` to adjust Pomodoro settings or opt into Calendar sync.
5. Write a daily reflection in the evening. Open the full planner for date navigation, weekly reviews, exports, and backups.

Keyboard shortcuts while the app is active:

| Shortcut | Action |
| --- | --- |
| `⌘L` | Toggle the clothesline |
| `⌘T` | Go to today |
| `⌘1` / `⌘2` | Daily plan / weekly review |
| `⌘[` / `⌘]` | Previous / next week |
| `⌘,` | Pomodoro and Calendar settings |
| `⌘S` / `⌘E` | Save / export the current day as Markdown |

See the [usage guide](docs/USAGE.md) for timer behavior, migration, and backup details.

## How the harvest is counted

- At the focus deadline, a movable window shows live overtime. Clicking Start Break finalizes exactly one completed Pomodoro, including the overtime. Early interruptions keep the elapsed interval but do not count as completed Pomodoros.
- Breaks start only when you click Start Break. Rate the finished session (great, okay, or poor) and optionally write a reflection while the break runs. Drafts autosave and can be reopened from recent focus history.
- Daily and monthly totals use the local completion date. A session still belongs to the task and task date selected when it started.
- Usually, one displayed tomato represents one completed session. Above 240 sessions, tomatoes are grouped and labeled; the total remains exact.
- Hiding the panel pauses animation immediately. Each animation runs for approximately 13 seconds; Reduce Motion uses a static arrangement.

## Data and privacy

No account is required. Goals, reflections, timer history, and settings are stored locally:

```text
~/Library/Application Support/DaylightGoals/
```

Calendar sync is off by default. After you enable it and grant access, EventKit writes focus intervals to the selected calendar. Events in an iCloud or shared calendar follow that calendar service's sync settings.

There is no built-in analytics or telemetry upload. This repository contains source, generic examples, tests, and documentation, without personal records, calendar accounts, backups, or real-use screenshots. Local JSON files are **not encrypted by the app**. See [privacy details](docs/PRIVACY.md).

The English app name does not change the bundle identifier or storage directory, so existing records remain available when upgrading.

Version 2.2 upgrades data to schema 3 and preserves the original file as `planner.before-v3.json`. Versions 2.1 and earlier cannot read the upgraded data; retain this backup if you need to roll back. Session ratings and reflections stay local and are not added to Calendar events.

## Development

```sh
swift test --disable-sandbox
```

The 40-test suite includes AppKit input-method and SpriteKit scene tests. Full tests require a macOS desktop environment with access to system graphics services. See [verification notes](docs/VERIFICATION.md) for coverage and limitations.

```text
.
├── Package.swift             # Swift Package entry point
├── Sources/
│   ├── DaylightCore/          # Dates, tasks, persistence, timers, and statistics
│   └── DaylightGoals/         # Native UI, menu bar, Calendar, and physics scene
├── Tests/                    # Core and application integration tests
├── Resources/Info.plist       # Bundle metadata and permission descriptions
├── scripts/                  # App build and icon generation
├── docs/                     # Usage, privacy, and verification
└── THIRD-PARTY-NOTICES.txt    # Reference project attribution
```

## Acknowledgments and license

Inspired by [AetherNote](https://github.com/bcblr1993/AetherNote), particularly its weekly notes and local persistence approach. Daylight's goal checklists, Pomodoro features, and interface are independently implemented. The reference project's MIT license and attribution are retained in [THIRD-PARTY-NOTICES.txt](THIRD-PARTY-NOTICES.txt).

A license for this project has not yet been selected. No project-wide `LICENSE` is included; the reference project's MIT license does not automatically license this entire project. The project owner should select the intended terms before an open-source release.
