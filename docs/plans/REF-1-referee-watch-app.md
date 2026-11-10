# REF-1 implementation plan

Status: v1, 2026-11-10
Brief: REF-1 brief v4 (approved)

## Environment facts that shape the plan

- Xcode 27.2 with the iOS 27.2 and watchOS 27.2 SDKs, Swift 6.4, xcodegen installed.
- Only a watchOS 11.2 simulator runtime is installed. A watchOS 27 app can be built for the simulator but not run in one on this machine. iOS 27.2 simulators are available.
- The repo is empty apart from a README. There is no CI and no deploy, so shipping means merging the PR.
- No signing team is configured. Builds use `CODE_SIGNING_ALLOWED=NO` for the simulator. Running on the approver's own devices needs their team set in Xcode.

Because of this, all logic that the brief's Done when items depend on lives in a platform independent Swift package that is tested with `swift test` on macOS. The app targets stay thin. They wire Apple frameworks to that package and are build checked for both simulators with warnings treated as errors.

## Layout

```
RefereeWatch/
  project.yml                      xcodegen spec, generates RefereeWatch.xcodeproj
  RefereeWatch.xcodeproj           generated and committed so the approver can open it directly
  Packages/RefereeKit/             Swift package, platforms iOS 27, watchOS 27, macOS 27
    Sources/RefereeKit/
      Clock/                       MonotonicTime, MatchClock, Period, StoppageLedger, AddedTime
      Alerts/                      AlertPlan (what fires when)
      Events/                      MatchEvent, EventLog, Score, MatchMinute
      Match/                       MatchConfig, Match, MatchPreset, Team, PenaltyShootout
      Sync/                        Versioned, SyncMerge, SyncPayload
      Persistence/                 MatchStore (atomic JSON files)
      Report/                      MatchReport (text model used by the PDF)
    Tests/RefereeKitTests/
  iOS/                             iPhone app target
  Watch/                           watchOS app target (single target watch app, embedded in the iOS app)
  Shared/                          Info.plist fragments, privacy strings, entitlements
  docs/plans/                      this plan
```

## Domain design (RefereeKit)

### Time

- `MonotonicTime` reads `clock_gettime_nsec_np(CLOCK_MONOTONIC)`, which on Darwin keeps counting while the device sleeps and ignores system time changes. It also reads the boot session id (`sysctl kern.bootsessionuuid`). A `TimeSource` protocol wraps it so tests inject a fake clock.
- Each recorded instant is an `Anchor { monotonicNanos, bootSessionID, wall: Date }`.
- Elapsed time between two anchors uses the monotonic values when both share a boot session. Across a reboot it falls back to the wall clock difference. That fallback is Known edge case 2 in the brief.
- Nothing counts timer ticks. The UI redraws from `TimelineView` and every value is recomputed from anchors.

### Periods and the match clock

- `Period` is an enum: `firstHalf`, `halfTime`, `secondHalf`, `extraTimeBreak`, `extraTimeFirst`, `extraTimeHalfTime`, `extraTimeSecond`, `penalties`, `finished`. The Phase 3 periods exist from the start so extra time is configuration and UI, not a redesign.
- `MatchClock` is a value type state machine. Every transition is an explicit call with an anchor: `kickOff`, `endPeriod`, `startNextPeriod`, `startStoppage`, `endStoppage`. A period never ends on its own (brief scope 5).
- Each playing period has a `startOffset` (0 for the first half, half length for the second half, and so on), so the second half resumes at 45:00.
- `elapsed(now)` is the period's start offset plus monotonic time since the period's start anchor. The clock keeps running during a stoppage (scope 4).
- `display(now)` gives either `mm:ss` or the overrun form `45+2` once the period's normal end has passed.

### Stoppages and added time

- `StoppageLedger` holds closed and open stoppage intervals per period, as anchor pairs.
- `stoppedBeforeNormalEnd` and `stoppedDuringAddedTime` split each interval at the normal end. An interval that spans the boundary is split.
- `AddedTime` per period holds `suggestedMinutes = ceil(stoppedBeforeNormalEnd / 60)` (0 stays 0, exactly 120 seconds is 2), an optional `refereeMinutes` set by the crown before normal end, and `announcedMinutes`, fixed at the normal end to `refereeMinutes ?? suggestedMinutes`.
- After the announcement, `increase(by:)` is allowed and decrease is refused (scope 8).
- The deadline for the end of added time is `normalEnd + announcedMinutes * 60 + stoppedDuringAddedTime + an open stoppage's running time`. Every stoppage start or end recomputes it.
- The suggestion is visible from the first warning offset (5 minutes before normal end by default), per scope 8.

### Alerts

- `AlertPlan.alerts(for: clock, config:, now:)` returns the upcoming alerts for the current period as `(kind, dueElapsed)`: each warning offset before normal end, the normal end, and the end of added time when it is known.
- The watch layer turns each one into a monotonic deadline. A pure function does this, so the timing is unit tested.
- Alerts that are already past are not returned. Each alert has a stable id (`matchID-period-kind`), so rescheduling replaces it rather than duplicating it.

### Events and score

- `MatchEvent { id: UUID, kind: goal | yellow | red | substitution | penaltyKick(scored), team: home | away, shirtNumber: Int?, playerOff: Int?, playerOn: Int?, period, minute: MatchMinute, version: Version }`.
- `MatchMinute` is base plus optional added: minute = floor(elapsed / 60) + 1 inside normal time, and `normalEndMinute + floor(overrun / 60) + 1` after it. For example, 61 seconds into first half added time is 45+2.
- `Version { modifiedAt: Date, deviceID: String, deleted: Bool }`. A deletion is a version with `deleted = true`, which is the tombstone.
- `Score` is always computed from live (not deleted) goal events. It is never stored.
- `EventLog` supports append, undo last (writes a tombstone for the most recent live event created on this device), and edit (new version).

### Sync merge

- `SyncMerge.resolve(a, b)` for two versions of one event or of match metadata, in this order:
  1. The later `modifiedAt` wins.
  2. On equal times, `deleted = true` wins.
  3. Then the greater `deviceID` by plain string comparison wins.
  4. Identical versions are equal.
- `merge(local: Match, remote: Match) -> Match` applies `resolve` per event id and to match metadata. It is commutative, associative and idempotent. Tests check these properties over generated inputs, including equal timestamps and edit against tombstone.
- Tombstones are kept forever. Matches are small, so this costs nothing.

### Persistence

- `MatchStore` keeps one JSON file per match in the app's Application Support folder. It writes atomically (`Data.write(options: .atomic)`) after every change: transitions, stoppages, events and added time.
- On launch the watch loads any match that is not finished and restores the clock from its anchors (scope 13 and Done when 1).

### Report

- `MatchReport` builds the ordered lines (score, events by minute, workout summary). The iPhone renders it to PDF, and the text is unit tested.

## Watch app

- **WorkoutManager:** `HKWorkoutSession` (`.soccer`, `.outdoor`) with `HKLiveWorkoutBuilder` and `HKWorkoutRouteBuilder` fed by `CLLocationManager`. It starts at kick off and ends at the final whistle. It saves the workout (with a route only when location is authorized) and reports distance and average heart rate into the match.
  - If the session fails to start or ends early, a published `sessionHealthy = false` shows the "screen may sleep" banner (scope 15).
- **Permissions:** separate requests for HealthKit (share workout, read heart rate and distance), location (when in use) and notifications.
  - The pre-match screen shows the status of each permission. It shows a warning when notification authorization is denied, or when alert style or sound and haptics are disabled (read via `UNNotificationSettings`).
  - The clock and event logging never depend on any permission (scope 14).
- **AlertService:** for each planned alert it runs a `Task` sleeping until the monotonic deadline, using `ContinuousClock` with zero tolerance. It plays `WKInterfaceDevice.current().play(.notification)` (end of normal time and end of added time repeat three times, a touch shorter for warnings).
  - Each alert is also scheduled as a `UNTimeIntervalNotificationTrigger` with the stable id, and the backup is removed when the in-app alert fires.
  - All of this is rescheduled on every stoppage change, added time change, transition and app relaunch.
- **Screens**, all SwiftUI with large targets:
  - Pre-match setup: shows the iPhone setup if one was received, otherwise lets the referee pick a preset and start.
  - Main clock: period, big clock, stoppage toggle, score and a banner with the added time suggestion.
  - Event logging: Goal, Yellow, Red and Sub buttons. Team is the second tap, and Save is the third with the number optional, so it takes 3 actions without a number.
  - Event list with undo last and edit.
  - Period transition confirmations with a hold-to-confirm to avoid accidental taps.
  - Half time timer.
- **Digital Crown:**
  - On the clock screen a deliberate rotation past a threshold toggles a stoppage, with a haptic click.
  - While the added time suggestion is visible, the crown adjusts the minutes instead.
  - After the announcement it can only increase.
- **Action button (Apple Watch Ultra):** the app provides a `StartWorkoutIntent` so the button can launch it. During a session, presses are delivered to the app's workout intent handler and mapped to toggle stoppage.
  - The exact API surface for in-session presses is checked against the watchOS 27.2 SDK headers during implementation. If it differs, the approach is documented in the PR and in the report.
- **Connectivity:** see Sync below.

## iPhone app

- **Match setup form:** team names and colours, half length, half time length, warning offsets, extra time on or off with its lengths, penalties on or off, competition and kick off time. Presets come from Phase 3. The setup is sent to the watch.
- **Match history list and match report view.** PDF export uses `ImageRenderer` into a PDF context, shared with `ShareLink`.
- **Event editor:** add a missing shirt number, change team or kind, delete.

## Sync

- Both apps use `WCSession`.
- Setup goes from iPhone to watch with `updateApplicationContext`, so only the latest setup is kept, and also with `transferUserInfo` for queued delivery.
- Match data goes both ways as a full `SyncPayload` (the match with all event versions) using `transferUserInfo`, which queues and retries across disconnects.
  - The receiver merges with `SyncMerge.merge` and persists the result.
  - It sends the merged result back only when the merge changed something the sender did not have, which stops ping-pong.
- A payload is a few KB per match, well under WatchConnectivity limits.

## Build and quality gates

- `swift test` in `Packages/RefereeKit`: all domain tests.
- `xcodebuild build` of the iOS scheme for `generic/platform=iOS Simulator`, and of the watch scheme for `generic/platform=watchOS Simulator`, both with `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` and `GCC_TREAT_WARNINGS_AS_ERRORS=YES`.
- A small iOS unit test target runs on an iOS 27.2 simulator for the PDF report rendering.
- Unit tests cover the clock, period transitions, stoppage splitting, added time (suggestion, referee override, announce, increase only, extension), the alert plan, event minutes, undo and edit, score, sync merge including ties and edit against tombstone, persistence round trip and clock restore after relaunch (Done when 11).

## Steps

Steps 2 and 3 run in parallel after step 1. Steps 4, 5 and 6 run in parallel after steps 2 and 3. Step 7 runs last.

1. **Scaffold:** `project.yml`, package manifest, empty targets, privacy strings, entitlements (HealthKit, background workout processing), `.gitignore`, a README with build steps. It must build clean before anything else starts.
2. **Clock domain:** MonotonicTime, MatchClock, Period, StoppageLedger, AddedTime, AlertPlan, MatchMinute, with tests.
3. **Event and sync domain:** MatchEvent, Version, EventLog, Score, SyncMerge, SyncPayload, Match, MatchConfig, MatchPreset, PenaltyShootout, MatchStore, MatchReport, with tests.
4. **Watch app:** services (workout, permissions, alerts, store wiring, connectivity, Action button) and screens.
5. **iPhone app:** setup, presets, history, report, PDF, editor, connectivity.
6. **Phase 3 UI:** extra time and penalty screens on the watch, and penalty logging. The domain from steps 2 and 3 already covers them.
7. **Integration:** regenerate the project, run every gate, fix warnings, update the README.

## What can only be verified on real hardware

These Done when items need the approver's devices and are in the acceptance checklist, not in automated tests:
- 1: 90 minutes with the screen mostly off, and the system time changed.
- 2: live alerts within one second.
- 3: backup notifications while suspended.
- 5: the Action button.
- 9: the workout in Apple Health.
- 10: the battery.

Their logic is unit tested where it is pure: deadlines, rescheduling and clock recovery.

## Risks specific to the plan

- In-session Action button routing may need a different intent type than assumed. Step 4 checks the SDK first.
- Without a watchOS 27 simulator runtime, watch UI is only build checked here. Installing the runtime is a download that needs the approver's permission. It is not required for this plan.
