# REF-5 implementation plan

Status: v1, 2026-11-13
Brief: REF-5 brief v1 (approved)

## Vector source

No SVG renderer is installed on the build machine (no rsvg-convert, ImageMagick, Inkscape or cairosvg), and installing one would be a download. The icon is therefore drawn by a Swift script that uses Core Graphics paths, which ships with Xcode:

- `Design/AppIcon/render_icon.swift` holds the whole drawing as vector paths and parameters (colours, sizes, extrusion depth). Changing the look means editing this file.
- `swift Design/AppIcon/render_icon.swift` writes the 1024 by 1024 PNG into both asset catalogs and writes `Design/AppIcon/preview.png`.

## Drawing

- Background: grass green, with a soft vertical gradient and faint mowing stripes.
- Whistle: a classic referee whistle with a round chamber, a mouthpiece flush with the top of the chamber, the sound slot on top and a lanyard ring.
- Three quarter view: the side outline is extruded towards the back and up to the right, so the top surface and the side of the chamber show. The sides are shaded from dark at the back to light at the front, and the front face gets a metallic gradient, a highlight and a thin darker edge so it stays readable when small.
- A soft shadow under the whistle separates it from the green.
- Everything stays inside a circle of radius 0.8 of the half width around the centre, so the round watch mask and the rounded iPhone mask never cut it.
- The PNG is written without an alpha channel.

## Preview sheet

`Design/AppIcon/preview.png` shows the icon in the iPhone rounded mask and the watch circle mask at large, medium and small sizes, down to 29 points for iPhone Settings and 40 points for the watch grid, at 2x. It goes to the ticket as an attachment before the pull request.

## Project

- `iOS/Assets.xcassets/AppIcon.appiconset` and `Watch/Assets.xcassets/AppIcon.appiconset`, each a single size 1024 icon for its platform.
- `project.yml`: `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` on both app targets, then `xcodegen generate`.
- README: a short "App icon" section.

## Gates

- `swift test` in `Packages/RefereeKit`, `scripts/build.sh`, and the iPhone app tests, as AGENTS.md requires.
- A check that both built apps contain a compiled icon and that the PNG is 1024 by 1024 with no alpha.
- CI on the pull request.
