# REF-2 implementation plan

Status: v1, 2026-11-11
Brief: REF-2 brief v1 (approved)

## Change

1. `project.yml`: set `options.deploymentTarget` to iOS "26.0" and watchOS "26.0".
2. `Packages/RefereeKit/Package.swift`: set platforms to `.iOS("26.0")`, `.watchOS("26.0")` and `.macOS("26.0")`.
3. Regenerate `RefereeWatch.xcodeproj` with `xcodegen generate`.
4. `README.md`: requirements say devices on iOS 26 and watchOS 26 or later. Building still needs Xcode 27.2, whose SDKs build for the lower targets.

A trial build on 2026-11-11 with these targets had no availability errors or warnings, so no code changes are expected. If the gates show any, wrap the call in `if #available` with behaviour that keeps the brief's guarantees, and list it in the report.

## Gates

- `swift test` in `Packages/RefereeKit`.
- `scripts/build.sh` for both apps with warnings as errors.
- iPhone app tests on an iOS 27.2 simulator. No iOS 26 or watchOS 26 runtime is installed, so running on version 26 is left to the approver's devices.
- CI on the pull request.
