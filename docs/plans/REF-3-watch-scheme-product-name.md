# REF-3 implementation plan

Status: v1, 2026-11-13
Brief: REF-3 brief v1 (approved)

## Change

1. `project.yml`: remove `PRODUCT_NAME: RefereeWatch Watch` from the RefereeWatchWatch target, so the product name is the target name and the built app is `RefereeWatchWatch.app`.
2. Regenerate `RefereeWatch.xcodeproj`. The file reference, the Embed Watch Content phase and the RefereeWatchWatch scheme already name `RefereeWatchWatch.app`, and the target's build settings then agree with them.
3. Nothing else refers to the old name: no Swift code uses the module name `RefereeWatch_Watch`. `Watch/Info.plist` keeps `CFBundleDisplayName` RefereeWatch, so the watch shows the same name. `CFBundleName` follows `$(PRODUCT_NAME)` and becomes RefereeWatchWatch.
4. `README.md`: add how to install on an Apple Watch with a personal team. That covers registering the watch through Xcode, running the RefereeWatchWatch scheme with the watch as destination, the 7 day limit, and the `devicectl` command as a fallback.

## Gates

- `swift test` in `Packages/RefereeKit`.
- `scripts/build.sh` for both apps with warnings as errors, then a check that the watch build produced `RefereeWatchWatch.app` with display name RefereeWatch.
- A generic watchOS device build of the watch scheme without signing, to check the scheme resolves the watch app for a device destination.
- iPhone app tests on an iOS 27.2 simulator.
- CI on the pull request.
- Running on the approver's watch is the acceptance step.
