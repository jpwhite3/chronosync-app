#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
app_dir="$(cd "$script_dir/../.." && pwd)"
output_root="${1:-$app_dir}"
source_svg="$script_dir/chronosync_app_icon.svg"
brand_background="#F7F5EF"

command -v rsvg-convert >/dev/null || {
  echo "rsvg-convert is required to generate brand assets." >&2
  exit 1
}
command -v magick >/dev/null || {
  echo "ImageMagick is required to generate brand assets." >&2
  exit 1
}

temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

rsvg-convert -w 1024 -h 1024 "$source_svg" -o "$temp_dir/source.png"
magick "$temp_dir/source.png" \
  -background "$brand_background" -alpha remove -alpha off \
  -colorspace sRGB -depth 8 -define png:color-type=2 -strip \
  "$temp_dir/icon.png"

render_icon() {
  local size="$1"
  local path="$2"
  mkdir -p "$(dirname "$output_root/$path")"
  magick "$temp_dir/icon.png" -filter Lanczos -resize "${size}x${size}" \
    -depth 8 -define png:color-type=2 -strip "$output_root/$path"
}

render_launch_image() {
  local width="$1"
  local height="$2"
  local icon_size="$3"
  local path="$4"
  mkdir -p "$(dirname "$output_root/$path")"
  magick "$temp_dir/icon.png" -filter Lanczos \
    -resize "${icon_size}x${icon_size}" \
    -background "$brand_background" -gravity center \
    -extent "${width}x${height}" -alpha remove -alpha off \
    -depth 8 -define png:color-type=2 -strip "$output_root/$path"
}

ios_icon_dir="ios/Runner/Assets.xcassets/AppIcon.appiconset"
render_icon 20 "$ios_icon_dir/Icon-App-20x20@1x.png"
render_icon 40 "$ios_icon_dir/Icon-App-20x20@2x.png"
render_icon 60 "$ios_icon_dir/Icon-App-20x20@3x.png"
render_icon 29 "$ios_icon_dir/Icon-App-29x29@1x.png"
render_icon 58 "$ios_icon_dir/Icon-App-29x29@2x.png"
render_icon 87 "$ios_icon_dir/Icon-App-29x29@3x.png"
render_icon 40 "$ios_icon_dir/Icon-App-40x40@1x.png"
render_icon 80 "$ios_icon_dir/Icon-App-40x40@2x.png"
render_icon 120 "$ios_icon_dir/Icon-App-40x40@3x.png"
render_icon 120 "$ios_icon_dir/Icon-App-60x60@2x.png"
render_icon 180 "$ios_icon_dir/Icon-App-60x60@3x.png"
render_icon 76 "$ios_icon_dir/Icon-App-76x76@1x.png"
render_icon 152 "$ios_icon_dir/Icon-App-76x76@2x.png"
render_icon 167 "$ios_icon_dir/Icon-App-83.5x83.5@2x.png"
render_icon 1024 "$ios_icon_dir/Icon-App-1024x1024@1x.png"

mac_icon_dir="macos/Runner/Assets.xcassets/AppIcon.appiconset"
for size in 16 32 64 128 256 512 1024; do
  render_icon "$size" "$mac_icon_dir/app_icon_${size}.png"
done

render_icon 32 "web/favicon.png"
render_icon 192 "web/icons/Icon-192.png"
render_icon 512 "web/icons/Icon-512.png"
render_icon 192 "web/icons/Icon-maskable-192.png"
render_icon 512 "web/icons/Icon-maskable-512.png"

launch_dir="ios/Runner/Assets.xcassets/LaunchImage.imageset"
render_launch_image 168 185 168 "$launch_dir/LaunchImage.png"
render_launch_image 336 370 336 "$launch_dir/LaunchImage@2x.png"
render_launch_image 504 555 504 "$launch_dir/LaunchImage@3x.png"
