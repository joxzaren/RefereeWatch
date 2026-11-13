# REF-4 implementation plan

Status: v1, 2026-11-13
Brief: REF-4 brief v2 (approved)

## Change

1. `AGENTS.md` at the repo root, with two sections:
   - Release notes: the Confluence "Release notes" page in the RefereeWat space as the main destination, and `CHANGELOG.md` as a further destination. It says how a CHANGELOG entry looks, how it reaches main through a `changelog/<ticket>` pull request merged once CI passes, and how it is read back. It also gives the retry rule from brief scope item 3.
   - Build and test: the rules from brief scope item 4.
2. `CHANGELOG.md` with a title and a line saying newest entries come first. No entries.

## Gates

- No code changes, so the local gates are a markdown check of the two files.
- CI on the pull request runs the package tests and both app builds as usual.
- Done when item 3 is checked by the REF-1 accept that follows.
