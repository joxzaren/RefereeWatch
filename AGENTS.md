# AGENTS.md

Standing rules for anyone, person or agent, who changes or accepts work in this repository. Tickets live in the Jira project REF.

## Release notes

Each accepted ticket gets one release note in each of these destinations.

1. **Main destination:** the "Release notes" page in the RefereeWat Confluence space. Add a new section at the top, headed `## <ticket key> · <ticket title>`, with the line `Accepted <YYYY-MM-DD>.` followed by the builds the ticket deployed (this repo has no deploy, so the merge commit), and then the note text from the ticket's "Release note" comment.
2. **Further destination:** `CHANGELOG.md` on `main`. Add a new section at the top, below the file's title and intro line, in the same shape: the heading `## <ticket key> · <ticket title>`, the line `Accepted <YYYY-MM-DD>.`, and the note text.
   - Make the change on a branch named `changelog/<ticket key>`, for example `changelog/REF-1`, cut from the latest `main`.
   - Open a pull request into `main`, wait for the `package-tests` and `app-builds` checks to pass, then merge it.
   - Read `CHANGELOG.md` back from `origin/main` and check the section is there exactly once.

### Retry rule

An accept may stop partway and be run again. Every accept therefore starts by checking each destination for a section headed with the ticket key.

- A section already on the Confluence page, or already in `CHANGELOG.md` on `main`, is confirmed, never added again.
- An open pull request from `changelog/<ticket key>` is reused: finish it by waiting for its checks and merging it.
- A `changelog/<ticket key>` branch that has no pull request gets one, after checking it holds only the entry for that ticket.
- Only when none of these exist is a new section or branch created.

A retry after any partial failure ends with exactly one release note per ticket in each destination.

## Build and test

- Build with Xcode 27.2 or later. The minimums are iOS 26 and watchOS 26.
- `project.yml` is the source of the Xcode project. After any change to it, run `xcodegen generate` and commit the regenerated `RefereeWatch.xcodeproj` with it. Never edit the project in Xcode and commit that instead.
- Warnings are errors in every target.
- Before opening a pull request, these pass locally:
  - `swift test` in `Packages/RefereeKit`
  - `scripts/build.sh`, which builds both apps for the simulators
  - the iPhone app tests: `xcodebuild -project RefereeWatch.xcodeproj -scheme RefereeWatch -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.2' CODE_SIGNING_ALLOWED=NO test`
- A pull request is merged only when the `package-tests` and `app-builds` CI checks pass.
