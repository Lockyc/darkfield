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
- **More camera devices.** The canvas as a webcam, and the canvas with the presenter inset. Each
  is another device in the existing camera extension, so no second approval. The canvas is
  composited from layers, not pixel buffers, so it needs rendering to frames first. Next: render
  the canvas into `CVPixelBuffer`s (the same frames recording would use).
- **Lens correction for framing.** A tight crop away from the centre of a wide-angle webcam
  makes vertical lines lean. Unlock: noticing the lean on calls.
- **Virtual monitor.** Make the canvas a display, so meeting pickers list it under Screens.
  Relies on the unsupported `CGVirtualDisplay` API, which a macOS update can break. Next: revisit
  if the "▶ Darkfield" window is still hard to find in pickers.
- **Cropping.** Share only a region of a window.
- **Child windows.** Show a shared window's menus, popovers and sheets on the canvas, for live
  demos. Needs owner, z-order and attachment tracking.
- **Google Slides polish.** Trim the browser's black letterbox bars around a presented slide.
