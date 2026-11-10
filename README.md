# RefereeWatch

An Apple Watch app for football referees, with an iPhone companion.

The watch runs the match on its own: the match clock, stoppages, added time, haptic alerts with backup notifications, and logging of goals, cards and substitutions. Each match is saved to Apple Health as a Soccer workout. The iPhone app sets up matches, keeps the history, edits events and exports a PDF match report. The two sync both ways over WatchConnectivity.

## Requirements

- Xcode 27.2 or later, with the iOS 27 and watchOS 27 SDKs
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) when you change `project.yml`
- An Apple Watch on watchOS 27 and an iPhone on iOS 27 to run on device

## Layout

| Path | What it is |
|---|---|
| `Packages/RefereeKit` | All match logic: clock, stoppages, added time, alert plan, events, score, sync merge, storage, presets, penalties, report. Platform independent and unit tested. |
| `Watch/` | The watchOS app: screens, alerts, workout session, permissions, Action button intents, connectivity. |
| `iOS/` | The iPhone app: setup, history, report, event editor, PDF export, connectivity. |
| `iOSTests/` | iPhone app tests. |
| `project.yml` | XcodeGen spec. `RefereeWatch.xcodeproj` is generated from it and committed. |
| `docs/plans/` | Implementation plans. |

## Build and test

```bash
cd Packages/RefereeKit && swift test
```

```bash
xcodegen generate && scripts/build.sh
```

```bash
xcodebuild -project RefereeWatch.xcodeproj -scheme RefereeWatch -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.2' CODE_SIGNING_ALLOWED=NO test
```

`scripts/build.sh` builds both apps for the simulators with warnings treated as errors and prints only diagnostics.

## Running on your devices

1. Open `RefereeWatch.xcodeproj`.
2. In Signing & Capabilities, choose your team for the `RefereeWatch` and `RefereeWatchWatch` targets. Change the bundle identifiers if `com.refereewatch.app` is taken.
3. Run the `RefereeWatch` scheme on your iPhone. The watch app installs with it.
4. On the watch, open the Permissions screen before the first match and allow Health, Location and Notifications.
5. On an Apple Watch Ultra, set the Action button to RefereeWatch in Settings. A press opens the app, and later presses during a match start and stop stoppages.
