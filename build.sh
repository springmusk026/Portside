#!/bin/zsh
# Build Portside.app, install it to ~/Applications and launch it.
# With --no-install, only build it into build/ (used by CI).
# With --release, build a universal app into build/Portside.zip; with SIGN_IDENTITY set to a
# "Developer ID Application" certificate and NOTARY_PROFILE to a notarytool keychain profile
# (xcrun notarytool store-credentials), it's also notarized and stapled.
set -euo pipefail
cd "${0:A:h}"

APP=build/Portside.app

# Ad-hoc signature by default; set SIGN_IDENTITY="..." to sign with a certificate.
IDENTITY=${SIGN_IDENTITY:--}
MODE=${1:-}
[[ $MODE == --release ]] && ARCHS=${ARCHS:-"arm64 x86_64"}

# Target the minimum macOS in Info.plist, as Xcode does (swiftc otherwise
# targets the OS it runs on, so the app wouldn't launch on older systems).
# ARCHS="arm64 x86_64" builds a universal app (used for releases).
MIN_OS=$(plutil -extract LSMinimumSystemVersion raw Info.plist)
ARCHS=(${=ARCHS:-$(uname -m)})

rm -rf build
mkdir -p "$APP/Contents/MacOS"
for arch in $ARCHS; do
  swiftc -O -swift-version 5 -parse-as-library -target "$arch-apple-macos$MIN_OS" \
    Sources/*.swift -o "build/Portside-$arch"
done
lipo -create build/Portside-* -output "$APP/Contents/MacOS/Portside"
rm build/Portside-*
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
if [[ $IDENTITY == - ]]; then
  codesign --force --sign - "$APP"
else
  # Notarization needs the hardened runtime and a secure timestamp
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi

if [[ $MODE == --release ]]; then
  ditto -c -k --keepParent "$APP" build/Portside.zip
  if [[ -n ${NOTARY_PROFILE:-} ]]; then
    xcrun notarytool submit build/Portside.zip --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    rm build/Portside.zip
    ditto -c -k --keepParent "$APP" build/Portside.zip
  fi
  echo "Built build/Portside.zip ($(lipo -archs "$APP/Contents/MacOS/Portside"))"
  shasum -a 256 build/Portside.zip
  exit 0
fi

if [[ $MODE == --no-install ]]; then
  echo "Built $APP"
  exit 0
fi

pkill -x Portside 2>/dev/null || true
mkdir -p ~/Applications
rm -rf ~/Applications/Portside.app
ditto "$APP" ~/Applications/Portside.app
open ~/Applications/Portside.app
echo "Installed ~/Applications/Portside.app"
