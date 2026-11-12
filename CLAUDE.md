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
- `Sources/Darkfield/` is the AppKit executable: capture, canvas layers, outputs and the panel,
  plus Darkfield Camera's capture, processing and relay (`Camera*.swift`).
- `Sources/DarkfieldCameraExtension/` is the CoreMediaIO camera system extension. It shares only
  `DarkfieldCore` (`CameraIDs`, `IdleFrame`) with the app.
- `Tests/DarkfieldCoreTests/` holds the XCTest suite, run with `swift test`.
- `Support/Info.plist` is the bundle template; `just bundle` stamps `VERSION` into it.
- `Support/icon.svg` is the icon master; `just icons` renders `AppIcon.icns` and `icon.png`
  from it. The menu-bar mark, `StatusItem.menuBarImage`, is drawn in code to match it, so change
  both together.

## Invariants

- The canvas never shows anything the presenter didn't pick. Capture is one
  `SCContentFilter(desktopIndependentWindow:)` per shared window, with `showsCursor = false`.
  Never capture by display or by app.
- The canvas never carries branding: no watermark, no app name. The one overlay is
  `PickingOverlay`, on the share window only while a window picker is open; it is removed on
  `pickerDidClose`, which a client posts when its capture request completes, before any frame is
  sent.
- Core geometry is in CG global coordinates (top-left origin, y down). AppKit points are
  converted at the edge.
- Darkfield Camera's extension never opens a camera. darkfield captures and processes; the
  extension relays darkfield's latest frame, or black once it is stale (`IdleFrame`).
- The physical camera runs only while `CameraDemand` wants it: an app streaming from Darkfield
  Camera, or Preview on with the panel open. It is the first connected camera in
  `CameraSettings.preferred`; with none of those connected the frame is dark, never a camera the
  presenter didn't choose.
- The only global hotkeys are the ones in `Settings`. The window toggle defaults to ⇧⌘1,
  Screegle's, and fit-unscaled to ⇧⌘2. Every other hotkey ships unassigned.
- Fit-unscaled (`WindowFitter`) is the one thing darkfield does to another app's window, and
  the one use of the Accessibility grant.

## Capture

- **Wallpaper.** The canvas background comes from streaming the system wallpaper window: the
  `SCWindow` owned by `com.apple.WindowManager`, titled `Wallpaper`, that is `isOnScreen` and
  whose frame is the target display's. While a window is shared this tracks rotating, dynamic
  and folder-shuffled wallpapers live. With nothing shared, darkfield captures nothing at all
  (`Wallpaper.update`'s `live`). Don't use `NSWorkspace.desktopImageURL(for:)`: for a folder rotation it
  returns the folder, not the image on screen. Each display also has an off-screen `Wallpaper`
  window, and capturing that fails with `-3811`. Enumerating these windows needs
  `excludingDesktopWindows: false`.
- **Windows on another Space** (for example a full-screen Chrome presentation) still deliver
  frames through an `SCStream`. A one-off `SCScreenshotManager` capture of the same window
  fails with `-3811`, so all capture goes through streams.

## Build, test, verify, branches

- `just test`, `just gate`; `just run` builds and launches `build/darkfield.app`.
- Verify UI changes in the running app with `winshot`. Screen Recording permission must be
  granted to the built bundle. The panel is a transient popover that `winshot` doesn't list and
  that closes on focus loss (turning Preview off), so a camera check needs the presenter's own
  screenshot; the camera's on/off decisions are logged under subsystem `com.lockyc.darkfield`.
- `just bundle` embeds the camera extension only when a Developer ID identity and the app's
  Developer ID provisioning profile (`~/.config/darkfield/darkfield.provisionprofile`) are
  present: `com.apple.developer.system-extension.install` can't be signed without it. The
  extension needs no profile (sandbox plus a team-prefixed app group). The app is signed with
  `Support/Darkfield.entitlements` (camera only) or, with the extension,
  `Support/Darkfield-Extension.entitlements`. A system extension activates only from
  `/Applications` and only notarized, which is why `just install` notarizes (run `apple-notary`
  first).
- **Minting the profile needs no portal clicks:** Xcode's stored account does it. Make a throwaway
  XcodeGen project with an app `com.lockyc.darkfield` (entitlements:
  `Darkfield-Extension.entitlements` minus the two identifier keys) embedding a system-extension
  target, `xcodebuild archive … CODE_SIGNING_ALLOWED=NO`, ad-hoc sign the archived extension then
  app with their entitlements, then `xcodebuild -exportArchive -allowProvisioningUpdates` with
  `method developer-id`, `signingStyle automatic`. The export's `embedded.provisionprofile` is
  the profile. A plain archive fails: development signing needs a registered device and the team
  has none.
- Branches: `main` + `dev`. Work lands on `dev`. A release fast-forwards `main` from `dev`
  (`git merge --ff-only dev`). Docs-only changes may land on `main` and are forward-merged into
  `dev` immediately.
- Version: the root `VERSION` file is the only source. A release is `lockstep.sh release darkfield`
  (fleet repo `docs/RELEASING.md`). It tags `v<VERSION>` and publishes a GitHub release with
  notes, `darkfield.zip` and the Sparkle `appcast.xml` that `SUFeedURL` reads. The Sparkle key is
  `~/.sparkle/darkfield-ed25519.key`, vaulted as `darkfield — Sparkle signing key`. Its public
  half is `SUPublicEDKey`. The release interface: `just gate`, `VERSION`, `just bundle` (signs
  with `APPLE_SIGNING_IDENTITY`, else the keychain's Developer ID, else ad-hoc), `info_plist`, `just sparkle-bin`.
