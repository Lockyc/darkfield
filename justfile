# `default` pipes `just --list` through a small stock-perl filter that clips long recipe
# docs to your terminal width (…) instead of wrapping. Self-contained — no external files;
# falls back to plain `just --list` where perl is absent. Edit the recipes below, not this.
# List available recipes
default:
    @if command -v perl >/dev/null 2>&1; then just --color always --list | perl -CS -Mutf8 -lpe 'BEGIN{($w)=`stty size 2>/dev/null </dev/tty`=~/ (\d+)/; $w||=100; $col=(-t STDOUT && !exists $ENV{NO_COLOR})} s/\e\[[0-9;]*m//g unless $col; (my $v=$_)=~s/\e\[[0-9;]*m//g; if(length($v)>$w){my($o,$n)=("",0); while(length && $n<$w-1){ if($col && s/^(\e\[[0-9;]*m)//){$o.=$1}else{s/^(.)//;$o.=$1;$n++} } $_=$o."…".($col?"\e[0m":"")}'; else just --list; fi

# Run the unit tests
test:
    swift test

# Pre-merge gate: build everything and run the tests
gate:
    swift build
    swift test

app := "build/darkfield.app"
info_plist := "Support/Info.plist"

# Render Support/AppIcon.icns and the README's icon.png from the Support/icon.svg master
icons:
    plate icon --icns Support/AppIcon.icns --png 256:Support/icon.png Support/icon.svg

# Build build/darkfield.app (version from VERSION; signed with APPLE_SIGNING_IDENTITY, else ad-hoc)
bundle:
    #!/usr/bin/env bash
    set -euo pipefail
    swift build -c release --product Darkfield
    bin=$(swift build -c release --show-bin-path)
    rm -rf {{app}}
    mkdir -p {{app}}/Contents/MacOS {{app}}/Contents/Resources
    cp "$bin/Darkfield" {{app}}/Contents/MacOS/Darkfield
    cp Support/AppIcon.icns {{app}}/Contents/Resources/AppIcon.icns
    cp {{info_plist}} {{app}}/Contents/Info.plist
    plutil -replace CFBundleShortVersionString -string "$(cat VERSION)" {{app}}/Contents/Info.plist
    plutil -replace CFBundleVersion -string "$(cat VERSION)" {{app}}/Contents/Info.plist
    if [ -n "${APPLE_SIGNING_IDENTITY:-}" ]; then
        codesign --force --options runtime --timestamp --sign "$APPLE_SIGNING_IDENTITY" {{app}}
    else
        codesign --force --sign - {{app}}
    fi

# Build and launch the local bundle
run: bundle quit
    @just launch {{app}}

# Install to /Applications and launch
install: bundle quit
    rm -rf /Applications/darkfield.app
    cp -R {{app}} /Applications/darkfield.app
    @# the commit this build came from: lets a later release (lockstep.sh) tell whether it is newer before replacing it
    xattr -w com.lockyc.build-commit "$(git rev-parse HEAD)$(git status --porcelain | grep -q . && echo -dirty)" /Applications/darkfield.app
    @just launch /Applications/darkfield.app

# Quits any running Darkfield, force-killing one still alive after 3s.
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
