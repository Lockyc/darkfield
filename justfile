# `default` pipes `just --list` through a small stock-perl filter that clips long recipe
# docs to your terminal width (…) instead of wrapping. Self-contained — no external files;
# falls back to plain `just --list` where perl is absent. Edit the recipes below, not this.
# List available recipes
default:
    @if command -v perl >/dev/null 2>&1; then just --color always --list | perl -CS -Mutf8 -lpe 'BEGIN{($w)=`stty size 2>/dev/null </dev/tty`=~/ (\d+)/; $w||=100; $col=(-t STDOUT && !exists $ENV{NO_COLOR})} s/\e\[[0-9;]*m//g unless $col; (my $v=$_)=~s/\e\[[0-9;]*m//g; if(length($v)>$w){my($o,$n)=("",0); while(length && $n<$w-1){ if($col && s/^(\e\[[0-9;]*m)//){$o.=$1}else{s/^(.)//;$o.=$1;$n++} } $_=$o."…".($col?"\e[0m":"")}'; else just --list; fi

# Run the unit tests
test:
    swift test

# Pre-merge gate: lint the installer, build everything, run the tests
gate:
    shellcheck install.sh
    swift build
    swift test

app := "build/darkfield.app"
info_plist := "Support/Info.plist"
# Where darkfield.provisionprofile lives: the app's Developer ID profile, which lets it install Darkfield Camera
profiles := env_var("HOME") / ".config/darkfield"

# Render Support/AppIcon.icns and the README's icon.png from the Support/icon.svg master
icons:
    plate icon --icns Support/AppIcon.icns --png 256:Support/icon.png Support/icon.svg

# Build build/darkfield.app (version from VERSION, Sparkle embedded; signed with APPLE_SIGNING_IDENTITY, else the keychain's Developer ID, else ad-hoc)
bundle:
    #!/usr/bin/env bash
    set -euo pipefail
    swift build -c release --product Darkfield
    bin=$(swift build -c release --show-bin-path)
    rm -rf {{app}}
    mkdir -p {{app}}/Contents/MacOS {{app}}/Contents/Resources {{app}}/Contents/Frameworks
    cp "$bin/Darkfield" {{app}}/Contents/MacOS/Darkfield
    cp Support/AppIcon.icns {{app}}/Contents/Resources/AppIcon.icns
    install_name_tool -add_rpath @executable_path/../Frameworks {{app}}/Contents/MacOS/Darkfield
    ditto "$bin/Sparkle.framework" {{app}}/Contents/Frameworks/Sparkle.framework
    cp {{info_plist}} {{app}}/Contents/Info.plist
    plutil -replace CFBundleShortVersionString -string "$(cat VERSION)" {{app}}/Contents/Info.plist
    plutil -replace CFBundleVersion -string "$(cat VERSION)" {{app}}/Contents/Info.plist
    # Inside-out: each nested Sparkle helper before the framework, the framework before the app.
    # Unset APPLE_SIGNING_IDENTITY → this Mac's Developer ID when the keychain has one: its designated
    # requirement is bundle id + team, stable across builds, so privacy grants (folder access) survive
    # a rebuild. An ad-hoc signature's is the cdhash — every rebuild is a new app to TCC.
    identity=${APPLE_SIGNING_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk '/"Developer ID Application: /{print $2; exit}')}
    ts=--timestamp; [ -n "${APPLE_SIGNING_IDENTITY:-}" ] || ts=--timestamp=none
    if [ -n "$identity" ]; then
        sign=(codesign --force --options runtime "$ts" --sign "$identity")
    else
        sign=(codesign --force --sign -)
    fi
    sparkle={{app}}/Contents/Frameworks/Sparkle.framework
    "${sign[@]}" "$sparkle/Versions/B/XPCServices/Installer.xpc"
    "${sign[@]}" --preserve-metadata=entitlements "$sparkle/Versions/B/XPCServices/Downloader.xpc"
    "${sign[@]}" "$sparkle/Versions/B/Autoupdate" "$sparkle/Versions/B/Updater.app" "$sparkle"
    # Installing Darkfield Camera's extension takes a restricted entitlement, which a Developer ID
    # app may carry only with a provisioning profile; signing it without one stops the app
    # launching. The extension itself needs no profile. The profile stays on this machine (the
    # repo is public). Without it the app ships without the extension and its panel says so.
    app_profile={{profiles}}/darkfield.provisionprofile
    entitlements=Support/Darkfield.entitlements
    if [ -n "$identity" ] && [ -f "$app_profile" ]; then
        swift build -c release --product DarkfieldCameraExtension
        ext={{app}}/Contents/Library/SystemExtensions/com.lockyc.darkfield.camera.systemextension
        mkdir -p "$ext/Contents/MacOS"
        cp "$bin/DarkfieldCameraExtension" "$ext/Contents/MacOS/DarkfieldCameraExtension"
        cp Support/CameraExtension-Info.plist "$ext/Contents/Info.plist"
        plutil -replace CFBundleShortVersionString -string "$(cat VERSION)" "$ext/Contents/Info.plist"
        plutil -replace CFBundleVersion -string "$(cat VERSION)" "$ext/Contents/Info.plist"
        "${sign[@]}" --entitlements Support/CameraExtension.entitlements "$ext"
        cp "$app_profile" {{app}}/Contents/embedded.provisionprofile
        entitlements=Support/Darkfield-Extension.entitlements
    else
        echo "bundle: Darkfield Camera's extension left out (needs a Developer ID identity and {{profiles}}/darkfield.provisionprofile)"
    fi
    # The hardened runtime refuses the camera, with no prompt, to an app without the camera entitlement.
    "${sign[@]}" --entitlements "$entitlements" {{app}}

# Print the directory holding Sparkle's sign_update and generate_keys (resolving packages first)
sparkle-bin:
    @swift package resolve >/dev/null
    @echo "{{justfile_directory()}}/.build/artifacts/sparkle/Sparkle/bin"

# Build and launch the local bundle
run: quit bundle
    @just launch {{app}}

# Build, notarize and install to /Applications, then launch (~2 min; needs the Apple signing and notary env)
install: notary-env bundle
    #!/usr/bin/env bash
    set -euo pipefail
    # macOS activates Darkfield Camera's system extension only from a notarized app.
    zip=build/darkfield-notarize.zip
    rm -f "$zip"
    ditto -c -k --keepParent {{app}} "$zip"
    xcrun notarytool submit "$zip" --apple-id "$APPLE_ID" --password "$APPLE_PASSWORD" --team-id "$APPLE_TEAM_ID" --wait
    rm -f "$zip"
    xcrun stapler staple {{app}}
    # The running copy keeps working through the build and notarization; it quits only now.
    just quit
    rm -rf /Applications/darkfield.app
    cp -R {{app}} /Applications/darkfield.app
    # the commit this build came from: lets a later release (lockstep.sh) tell whether it is newer before replacing it
    xattr -w com.lockyc.build-commit "$(git rev-parse HEAD)$(git status --porcelain | grep -q . && echo -dirty)" /Applications/darkfield.app
    just launch /Applications/darkfield.app

# Fails before building unless the Developer ID identity and notary credentials are exported.
# `bundle` timestamps its signatures, which notarization requires, only with APPLE_SIGNING_IDENTITY set.
[private]
notary-env:
    @: "${APPLE_SIGNING_IDENTITY:?not set}" "${APPLE_ID:?not set}" "${APPLE_PASSWORD:?not set}" "${APPLE_TEAM_ID:?not set}"

# Quits any running Darkfield, force-killing one still alive after 3s. `run` quits before `bundle`:
# a Darkfield whose bundle is rewritten under it fails its screen-recording check and prompts.
[private]
quit:
    #!/usr/bin/env bash
    killall Darkfield 2>/dev/null || exit 0
    for _ in {1..30}; do pgrep -x Darkfield >/dev/null || exit 0; sleep 0.1; done
    killall -9 Darkfield 2>/dev/null
    while pgrep -x Darkfield >/dev/null; do sleep 0.1; done

# Opens the app at `path`, retrying for up to 5s: LaunchServices keeps a quit app on its
# books briefly after the process is gone, and `open` fails with error -600 until it lets go.
[private]
launch path:
    #!/usr/bin/env bash
    for _ in {1..20}; do open "{{path}}" 2>/dev/null && exit 0; sleep 0.25; done
    open "{{path}}"
