# RefereeWatch

An Apple Watch app for football referees, with an iPhone companion.

The watch runs the match on its own: the match clock, stoppages, added time, haptic alerts with backup notifications, and logging of goals, cards and substitutions. Each match is saved to Apple Health as a Soccer workout. The iPhone app sets up matches, keeps the history, edits events and exports a PDF match report. The two sync both ways over WatchConnectivity.

## Requirements

- Xcode 27.2 or later to build. Its iOS 27 and watchOS 27 SDKs build for the iOS 26 and watchOS 26 minimums
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) when you change `project.yml`
- An Apple Watch on watchOS 26 or later and an iPhone on iOS 26 or later to run on device

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

1. Turn on Developer Mode on the iPhone and on the watch (Settings, Privacy & Security, Developer Mode). The watch only shows the option after Xcode has seen it, so connect the iPhone and open Window, Devices and Simulators first.
2. Open `RefereeWatch.xcodeproj`.
3. In Signing & Capabilities, choose your team for the `RefereeWatch` and `RefereeWatchWatch` targets. Change the bundle identifiers if `com.refereewatch.app` is taken.
4. Run the `RefereeWatch` scheme on your iPhone.
5. Select the `RefereeWatchWatch` scheme, choose your Apple Watch as the destination and press Run. The first time, Signing & Capabilities may ask you to register the watch. This puts the watch in the provisioning profile; without it the watch refuses the app because "its integrity could not be verified". The first install over Wi-Fi can take a few minutes.
6. On the watch, open the Permissions screen before the first match and allow Health, Location and Notifications.
7. On an Apple Watch Ultra, set the Action button to RefereeWatch in Settings. A press opens the app, and later presses during a match start and stop stoppages.

### Personal (free) teams

- Apps signed with a personal team stop launching after 7 days. Run both schemes from Xcode again to renew them.
- Backup alerts arrive at normal priority, because personal teams cannot use the time-sensitive notifications entitlement. A Focus mode can hold them back.

### Installing the watch app without Xcode's Run

If running the watch scheme fails, build `RefereeWatchWatch` for "Any watchOS Device" and install the result with `devicectl`. Find the watch's identifier with `xcrun devicectl list devices`:

```bash
xcrun devicectl device install app --device <watch identifier> ~/Library/Developer/Xcode/DerivedData/RefereeWatch-*/Build/Products/Debug-watchos/RefereeWatchWatch.app
```
