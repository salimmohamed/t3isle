#!/bin/bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
CATALOG="$REPO/boringNotch/Assets.xcassets"
APP_ICON="$CATALOG/AppIcon.appiconset"
MENU_BAR="$CATALOG/MenuBarIcon.imageset"
T3_SYMBOL="$CATALOG/t3.blob.symbolset"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

python3 "$HERE/build.py" "$TMP"

rasterize() {
  sips -s format png "$1" --out "$2" >/dev/null
}

resize() {
  sips -s format png -z "$3" "$3" "$1" --out "$2" >/dev/null
}

render_app_icon_sizes() {
  rasterize "$TMP/icon.svg" "$TMP/icon-1024.png"
  for size in 512 256 128 64; do
    resize "$TMP/icon-1024.png" "$TMP/icon-$size.png" "$size"
  done
  rasterize "$TMP/icon-small.svg" "$TMP/icon-small.png"
  for size in 32 16; do
    resize "$TMP/icon-small.png" "$TMP/icon-$size.png" "$size"
  done
}

fill_app_icon_set() {
  rm -rf "$APP_ICON"
  mkdir -p "$APP_ICON"
  for point in 16 32 128 256 512; do
    cp "$TMP/icon-$point.png" "$APP_ICON/icon_${point}x${point}.png"
    cp "$TMP/icon-$((point * 2)).png" "$APP_ICON/icon_${point}x${point}@2x.png"
  done
  cp "$HERE/AppIcon.Contents.json" "$APP_ICON/Contents.json"
}

render_menu_bar_glyph() {
  sed 's/width="18" height="18"/width="1152" height="1152"/' "$TMP/menubar.svg" > "$TMP/menubar-large.svg"
  rasterize "$TMP/menubar-large.svg" "$TMP/menubar.png"
  resize "$TMP/menubar.png" "$MENU_BAR/menubar-18.png" 18
  resize "$TMP/menubar.png" "$MENU_BAR/menubar-18@2x.png" 36
}

render_app_icon_sizes
fill_app_icon_set
cp "$TMP/icon-512.png" "$CATALOG/logo2.imageset/BoringNotch icon.png"
cp "$TMP/icon-256.png" "$CATALOG/logo.imageset/256-mac 1.png"
render_menu_bar_glyph
cp "$TMP/t3.blob.svg" "$T3_SYMBOL/t3.blob.svg"
cp "$TMP/icon.svg" "$REPO/assets/icon.svg"
rasterize "$TMP/social-preview.svg" "$REPO/assets/social-preview.png"
cp "$TMP/banner-light.svg" "$TMP/banner-dark.svg" "$REPO/assets/readme/"
