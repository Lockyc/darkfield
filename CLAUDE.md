---
type: architecture
links:
  - rel: covers
    to: Sources
  - rel: see-also
    to: README.md
    note: human-facing counterpart — what darkfield is and how to build it
  - rel: see-also
    to: docs/FOLLOWUPS.md
    note: deferred work — what is next
---

# darkfield — agent notes

A macOS menu-bar app for presenting. The presenter picks windows, and darkfield composites only
those windows onto a 1920×1080 canvas over the live desktop wallpaper, with its own audience
pointer. The canvas goes to a shareable Meeting window or full-screen on a projector. It is a
Swift package using AppKit and ScreenCaptureKit, for macOS 14+. What's next:
[docs/FOLLOWUPS.md](docs/FOLLOWUPS.md).

## Layout

- `Sources/DarkfieldCore/` uses Foundation/CoreGraphics only. It holds layout, pointer
  mapping and timing, the shared-window set and settings. **Every unit test lives here**; keep
  AppKit out of it.
- `Sources/Darkfield/` is the AppKit executable: capture, canvas layers, outputs and the panel.
- `Tests/DarkfieldCoreTests/` holds the XCTest suite, run with `swift test`.
- `Support/Info.plist` is the bundle template; `just bundle` stamps `VERSION` into it.
- `Support/icon.svg` is the icon master; `just icons` renders `AppIcon.icns` and `icon.png`
  from it.

## Invariants

- The canvas never shows anything the presenter didn't pick. Capture is one
  `SCContentFilter(desktopIndependentWindow:)` per shared window, with `showsCursor = false`.
  Never capture by display or by app.
- The canvas never carries branding: no watermark, no app name.
- Core geometry is in CG global coordinates (top-left origin, y down). AppKit points are
  converted at the edge.
- The only global hotkeys are the ones in `Settings`. The window toggle defaults to ⌘F1,
  registered on the F1 keycode. Every other hotkey ships unassigned.

## Build, test, verify, branches

- `just test`, `just gate`; `just run` builds and launches `build/darkfield.app`.
- Verify UI changes in the running app with `winshot`. Screen Recording permission must be
  granted to the built bundle.
- Branches: `main` + `dev`. Work lands on `dev`. A release fast-forwards `main` from `dev`
  (`git merge --ff-only dev`). Docs-only changes may land on `main` and are forward-merged into
  `dev` immediately.
- Version: the root `VERSION` file is the only source.
