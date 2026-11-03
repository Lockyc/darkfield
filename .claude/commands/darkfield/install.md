You are installing or updating **darkfield**, a macOS menu-bar app that shows only the windows you
choose, on a clean canvas, to a video call or a projector.

## 1. Check the Mac

```bash
sw_vers -productVersion
```

darkfield needs macOS 14 or later. On an older Mac, say so and stop.

## 2. Install

From a darkfield checkout (`[ -f install.sh ] && [ -f Package.swift ]`), ask with AskUserQuestion:
- **Latest release** (recommended): `bash install.sh`
- **This checkout's code**: `just install`

Outside a checkout, run `curl -fsSL https://raw.githubusercontent.com/lockyc/darkfield/main/install.sh | bash`.

If the installer needs `sudo`, the user types their password in this session: suggest `! <the command>`.

## 3. Check it is running

```bash
pgrep -x Darkfield && /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' /Applications/darkfield.app/Contents/Info.plist
```

Expect a process id and the installed version. If Screegle is running, it also holds ⌘F1: say so,
and say that darkfield's shortcut can be changed in its Settings (menu-bar icon → Settings…).

## 4. Screen Recording permission

On first launch macOS asks for Screen Recording permission. The user turns on **darkfield** in System
Settings → Privacy & Security → Screen Recording, then quits and reopens darkfield from its panel.

## 5. Done

Report the installed version. Tell the user three things:
- **⌘F1** shares or unshares the front window.
- To share in a call, they pick the **▶ Darkfield** window in Zoom, Meet or Teams.
- darkfield updates itself. The panel's **Check for Updates…** checks now.
