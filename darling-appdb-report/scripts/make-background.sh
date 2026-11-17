#!/bin/bash
# make-background.sh: render the standard AppDB background (set-background.sh
# applies it to a session): a light gray field with the Darling logo, gray,
# faint and tilted, repeated in an offset grid. Matches the AppDB placeholder
# for entries without screenshots.
# Usage: make-background.sh [WIDTHxHEIGHT] [output.png]   (default 1920x1080)
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
size=${1:-1920x1080}
out=${2:-$here/background.png}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# one logo: gray, 7% opaque, tilted like the AppDB placeholder
convert -background none -density 192 "$here/darling-logo.svg" -resize 88x \
	-colorspace Gray -alpha set -channel A -evaluate multiply 0.07 +channel \
	-rotate -18 "$tmp/logo.png"

# a 240x200 cell with two logos, the second shifted by half a cell, so the
# repeat reads as an offset grid rather than plain rows and columns
convert -size 240x200 xc:none \
	"$tmp/logo.png" -gravity center -geometry -60-50 -composite \
	"$tmp/logo.png" -gravity center -geometry +60+50 -composite \
	"$tmp/cell.png"

convert -size "$size" -define gradient:angle=135 gradient:'#EEEEF0-#E2E2E5' \
	\( -size "$size" tile:"$tmp/cell.png" \) -composite \
	-depth 8 -strip -define png:compression-level=9 "$out"
