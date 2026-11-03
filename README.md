<img src="Support/icon.png" alt="darkfield" width="128" height="128">

# darkfield

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-555)
![Swift](https://img.shields.io/badge/swift-6-F05138?logo=swift&logoColor=white)
[![License](https://img.shields.io/github/license/lockyc/darkfield)](LICENSE)

Present only the windows you choose. darkfield puts the windows you pick onto a clean 16:9
canvas over your current desktop wallpaper. You share that canvas in Zoom, Meet or Teams, or
show it full-screen on a projector. Notifications, desktop icons and every other window stay
off it. An audience pointer shows where you're pointing, without a hotkey.

## Status

**In development, not yet released.** The first release covers:

- window picking with ⌘F1
- the live-wallpaper canvas
- fill and mirror layouts
- the meeting and projector outputs
- the audience pointer

Later work is in [docs/FOLLOWUPS.md](docs/FOLLOWUPS.md).

## Build

Needs macOS 14+, Xcode's Swift 6 toolchain and [`just`](https://github.com/casey/just).

```bash
just test     # unit tests
just gate     # build + tests
just run      # build build/darkfield.app and launch it
```
