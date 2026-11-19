# Developing MacSweat

MacSweat is a native Swift menu bar app (AppKit and SwiftUI) built with plain `swiftc`. There is no Xcode project and no dependencies.

It's Mac only. It relies on macOS frameworks and system calls, so it doesn't run or build on Windows or Linux.

## Build

```sh
./build.sh            # universal build -> build/MacSweat.app
./build.sh --install  # also copies it to /Applications and opens it
```

You need a Mac with the Xcode command-line tools. The build targets macOS 13 and produces one app for Apple silicon and Intel.

## Layout

| Path | What's in it |
|---|---|
| `Sources/Monitor.swift` | Reads CPU, memory and the process list, and groups processes into apps, tasks and services |
| `Sources/Knowledge.swift` | Plain-English names for macOS services and developer tools |
| `Sources/Model.swift` | Sampling schedule, the one-line verdict, and the `Brand` constants |
| `Sources/PanelView.swift` | The panel, its rows, and the Quit, Stop and update actions |
| `Sources/MacSweat.swift` | Menu bar item, popover, and the command-line flags |
| `Sources/Demo.swift` | Sample data for `--demo` |
| `Tools/make-icon.swift` | Draws the app icon; `build.sh` turns it into `Resources/AppIcon.icns` |
| `Tools/og-card.html` | The 1200×630 link-preview card, built from the icon and the dark screenshot. Its header comment has the command that renders it to `site/assets/og.png` |
| `site/` | The landing page and the install and uninstall scripts. Vercel publishes this folder |
| `scripts/release.sh` | Packages and publishes a release |

## Flags

Run these on the built binary, `MacSweat.app/Contents/MacOS/MacSweat`.

| Flag | What it does |
|---|---|
| `--check` | Prints a text reading to compare against `top` or Activity Monitor |
| `--login-item on\|off\|status` | Same as **Open at Login** in the ⋯ menu. Run it from the copy in `/Applications` |
| `--demo` | Shows sample data in place of live readings; Quit and Stop do nothing |
| `--snapshot DIR` | Renders the panel and the menu bar item to PNGs in `DIR`, then quits |
| `--light`, `--dark` | Forces an appearance, for snapshots |

The website screenshots come from `--demo --snapshot DIR` with `--light` and `--dark`.

## Releasing

1. Bump `VERSION`.
2. Run `scripts/release.sh`. It builds, zips to `dist/`, stamps `site/install` with the version and the zip's SHA-256, and updates the version link beside the install command on `site/index.html`.
3. Commit the stamped `site/install` and `site/index.html`.
4. Run `scripts/release.sh --publish` from `main`. It uploads that exact zip as a GitHub release, then pushes `main`, which publishes the site.

Things that have gone wrong before:

- **Don't rebuild between steps 2 and 4.** Every build produces a slightly different zip, so the checksum in `site/install` would no longer match. `--publish` checks this and stops.
- **Keep `site/install` and `site/uninstall` plain ASCII.** Under a UTF-8 locale, macOS's `sh` (bash 3.2) reads the first byte of a non-ASCII character as part of a variable name when it follows one directly. `$VERSION` followed by an ellipsis broke the installer in every normal Terminal.
- **Test the installer the way a Terminal runs it:** `cat site/install | env LC_ALL=en_US.UTF-8 sh`, with the output uncut.
- **Every push to `main` publishes the site.** The Vercel project is connected to this repository with its Root Directory set to `site`. If that setting is ever lost, Vercel publishes the whole repository and the homepage returns 404 while the page sits at `/site/`. After any push to `main`, check the live site and not only GitHub.
- **Never push a new installer checksum to `main` before its release exists.** The site would go live pointing at a zip that isn't there. `--publish` handles the order: tag, release, then `main`.
- **Bump the images' version tags.** The page loads `assets/screenshot-dark.png?v=2`, and link previews use `assets/og.png?v=2`. Raise the number when an image changes, or browsers and link previews keep showing the old one. When the dark screenshot changes, render `Tools/og-card.html` again too.

## How the readings are made

- **CPU per row** is CPU time used since the last scan, where 100% is one core. `proc_pid_rusage` reports that time in Mach ticks, which are not nanoseconds on Apple silicon, so it is converted with `mach_timebase_info`.
- **System processes** belong to other users, so MacSweat can't query them directly. It reads them through `ps`, which can. Their memory is resident size, an estimate.
- **Helpers** are attributed to their app with the same responsibility lookup Activity Monitor uses, so WebKit processes count under Safari.
- **Background tasks** are developer runtimes working in a project folder, grouped by that folder's Git root.
- **Stop** signals only processes whose start time still matches the scan, so a reused process ID is never signalled.
