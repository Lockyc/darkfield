---
type: roadmap
links:
  - rel: see-also
    to: CLAUDE.md
    note: architecture and invariants these items touch
---

# darkfield — follow-ups

Planned work beyond the first release. Remove an item when it lands.

- **Recording.** Record the canvas to a video file. It reuses the canvas, so it adds to the app
  without changing it. Next: an `AVAssetWriter` sink fed from the same frames as the outputs.
- **Virtual camera.** One CoreMediaIO camera system extension hosts every Darkfield camera
  device, so each new device adds no second extension or approval. First device: the presenter
  from any physical camera, with background blur and Center-Stage-style framing, for video apps
  that do neither. Later devices: the canvas as a webcam, and the canvas with the presenter
  inset. darkfield captures and processes; the extension only relays frames. Next: the
  presenter device.
- **Virtual monitor.** Make the canvas a display, so meeting pickers list it under Screens.
  Relies on the unsupported `CGVirtualDisplay` API, which a macOS update can break. Next: revisit
  if the "▶ Darkfield" window is still hard to find in pickers.
- **Cropping.** Share only a region of a window.
- **Child windows.** Show a shared window's menus, popovers and sheets on the canvas, for live
  demos. Needs owner, z-order and attachment tracking.
- **Google Slides polish.** Trim the browser's black letterbox bars around a presented slide.
