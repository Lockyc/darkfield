<img src="Support/icon.png" alt="darkfield" width="128" height="128">

# darkfield

[![Release](https://img.shields.io/github/v/release/lockyc/darkfield?sort=semver&label=release)](https://github.com/lockyc/darkfield/releases/latest)
![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-555)
![Swift](https://img.shields.io/badge/swift-6-F05138?logo=swift&logoColor=white)
[![License](https://img.shields.io/github/license/lockyc/darkfield)](LICENSE)

Present only the windows you choose. darkfield puts the windows you pick onto a clean 16:9
canvas over your desktop wallpaper. You share that canvas in Zoom, Meet or Teams, or show it
full-screen on a projector. Notifications, desktop icons and every other window stay off it, and
an audience pointer shows where you're pointing.

![darkfield's preview: one shared app window centred on the 16:9 canvas over a mountain wallpaper, nothing else on screen](docs/screenshots/canvas.png)

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/lockyc/darkfield/main/install.sh | bash
```

Needs macOS 14 or later. The installer downloads the latest release, checks that it is signed and
notarized, installs `/Applications/darkfield.app` and launches it. darkfield then updates itself:
it checks daily, and **Check for Updates…** in its panel checks now.

## First run

Allow darkfield in System Settings → Privacy & Security → Screen Recording; until you do, its
panel says so and has a button that opens the setting. darkfield lives in the menu bar, with no
Dock icon. Opening it again from Spotlight or Finder brings back the preview.

## Features

- **Share a window** by pressing **⇧⌘1** over it, or with **Add Window…** in the panel; press
  ⇧⌘1 again to stop. A shared window keeps an amber ring around it while it's shared.
- **Shared windows stack** on the canvas, each scaled to fill it, in the same order as on your
  screen: the shared window you bring to the front is the one the audience sees.
- **In a call**, share the **▶ Darkfield** window from Zoom, Meet or Teams. It sits off screen at
  the canvas's full 1920×1080. You watch a small preview that floats above your windows on every
  Space and never appears in a share; its close button hides it, and sharing a window or
  **Show Preview Window** brings it back. A picker that selects a window by clicking it (Meet in
  [cooee](https://github.com/lockyc/cooee)) has ▶ Darkfield shown centred on your main display
  while it is open; another app can do the same by posting the distributed notifications
  `com.lockyc.darkfield.pickerWillOpen` and `com.lockyc.darkfield.pickerDidClose`.
- **On a projector**, set your displays to extended (not mirrored), then choose **Present to →
  Projector** in the panel. The canvas fills the projector, and your mouse stays on your own
  screen.
- **The audience pointer** is your cursor on the canvas, with an amber halo behind it so viewers
  find it. The halo fades after 10 seconds of stillness; shake the mouse to enlarge it, and clicks
  ripple. Turn it off in the panel, or give it a shortcut in Settings.
- **The panel** (the menu-bar icon) holds the live preview, the shared windows (✕ removes one),
  **Present to**, the margin and the pointer toggle.
- **Settings** — the share and pointer shortcuts, the halo's fade time, and the wallpaper behind
  the canvas: the primary display's, another display's, or an image you choose.

## Status

In use, `0.x`. Planned next: recording, a virtual camera and cropping. The full list:
[docs/FOLLOWUPS.md](docs/FOLLOWUPS.md).

## Development

Needs Xcode's Swift 6 toolchain and [`just`](https://github.com/casey/just).

```bash
git clone https://github.com/lockyc/darkfield && cd darkfield
just test       # unit tests
just gate       # installer lint, build, tests
just install    # build, install to /Applications and launch
```

Architecture, conventions and the release process: [CLAUDE.md](CLAUDE.md).

## License

MIT — see [LICENSE](LICENSE).
