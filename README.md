<img src="Support/icon.png" alt="darkfield" width="128" height="128">

# darkfield

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-555)
![Swift](https://img.shields.io/badge/swift-6-F05138?logo=swift&logoColor=white)
[![License](https://img.shields.io/github/license/lockyc/darkfield)](LICENSE)

Present only the windows you choose. darkfield puts the windows you pick onto a clean 16:9
canvas over your current desktop wallpaper. You share that canvas in Zoom, Meet or Teams, or
show it full-screen on a projector. Notifications, desktop icons and every other window stay
off it, and an audience pointer shows where you're pointing.

## Install

**Guided (Claude Code):** from a clone of this repo, run `/darkfield:install`. It installs the
latest release and walks through the Screen Recording permission.

**Manual:**

```bash
curl -fsSL https://raw.githubusercontent.com/lockyc/darkfield/main/install.sh | bash
```

The installer downloads the latest release and checks that it is signed and notarized. It then
installs `/Applications/darkfield.app` and launches it. Needs macOS 14 or later. On first launch,
allow darkfield in System Settings → Privacy & Security → Screen Recording.

darkfield lives in the menu bar and has no Dock icon. Opening it again from Spotlight or Finder
brings back the ▶ Darkfield window and Settings, which has **Quit darkfield**. It updates itself: it checks daily, and
**Check for Updates…** in its panel checks now.

## Use

- **⇧⌘1** shares the front window, and pressing it again stops sharing it. You can change the
  shortcut in Settings.
- **In a call**, share the **▶ Darkfield** window from Zoom, Meet or Teams. It keeps working
  behind other windows. It floats above your other windows on every Space.
- **On a projector**, set your displays to extended (not mirrored). Then choose **Present to →
  Projector** in the panel. The canvas fills the projector, and your mouse stays on your own
  screen.
- **The panel** (click the menu-bar icon) holds:
  - a live preview
  - the shared windows (drag to reorder, ✕ to remove)
  - the layout: **Fill** arranges windows for the audience, **Mirror** keeps your on-screen
    arrangement
  - the margin
  - the audience pointer toggle
- **The audience pointer** shows over shared windows and fades after 10 seconds of stillness.
  Shake the mouse to make it a spotlight, and clicks ripple. The fade time is in Settings.

## Status

**In use, `0.x`.** Planned next: recording, a virtual camera, and cropping. The full list is
[docs/FOLLOWUPS.md](docs/FOLLOWUPS.md).

## Build

Needs Xcode's Swift 6 toolchain and [`just`](https://github.com/casey/just).

```bash
just test       # unit tests
just gate       # installer lint, build, tests
just install    # build, install to /Applications and launch
```
