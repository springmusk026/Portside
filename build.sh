#!/bin/zsh
# Build Portside.app, install it to ~/Applications and launch it.
# With --no-install, only build it into build/ (used by CI and releases).
set -euo pipefail
cd "${0:A:h}"

APP=build/Portside.app

# Ad-hoc signature by default; set SIGN_IDENTITY="..." to sign with a certificate.
IDENTITY=${SIGN_IDENTITY:--}

# Target the minimum macOS in Info.plist, as Xcode does (swiftc otherwise
# targets the OS it runs on, so the app wouldn't launch on older systems).
TARGET="$(uname -m)-apple-macos$(plutil -extract LSMinimumSystemVersion raw Info.plist)"
SWIFTC=(swiftc -O -swift-version 5 -parse-as-library -target "$TARGET")

rm -rf build
mkdir -p "$APP/Contents/MacOS"
"${SWIFTC[@]}" Sources/*.swift -o "$APP/Contents/MacOS/Portside"
cp Info.plist "$APP/Contents/"

# App icon (rendered once from tools/make-icon.swift)
if [[ ! -f Resources/AppIcon.icns ]]; then
  tmp=$(mktemp -d)
  swift tools/make-icon.swift "$tmp/icon.png"
  mkdir "$tmp/AppIcon.iconset"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$tmp/icon.png" --out "$tmp/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) "$tmp/icon.png" --out "$tmp/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
  done
  mkdir -p Resources
  iconutil -c icns "$tmp/AppIcon.iconset" -o Resources/AppIcon.icns
  rm -rf "$tmp"
fi
mkdir -p "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign "$IDENTITY" "$APP"

if [[ ${1:-} == --no-install ]]; then
  echo "Built $APP"
  exit 0
fi

pkill -x Portside 2>/dev/null || true
mkdir -p ~/Applications
rm -rf ~/Applications/Portside.app
ditto "$APP" ~/Applications/Portside.app
open ~/Applications/Portside.app
echo "Installed ~/Applications/Portside.app"
