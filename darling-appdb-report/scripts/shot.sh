#!/bin/bash
# shot.sh [-w <window title>] [-m <max bytes>] <out.png|out.jpg>
# Takes an AppDB screenshot of the running X11 (DISPLAY) or Wayland (sway,
# WAYLAND_DISPLAY + XDG_RUNTIME_DIR) session and makes it fit the database's
# size limit.
#   -w   capture only the newest visible window whose title contains this text
#        (default: the whole screen)
#   -m   size limit in bytes (default 153600, the database's 150 KB limit)
# PNG output is colour-quantized (pngquant) and then scaled down until it fits;
# JPEG output lowers the quality first. Needs ImageMagick, pngquant, and grim
# for Wayland.
set -eu
title=""; max=153600
while getopts w:m: o; do
	case $o in w) title=$OPTARG;; m) max=$OPTARG;; *) exit 2;; esac
done
shift $((OPTIND - 1))
[ $# -eq 1 ] || { echo "usage: shot.sh [-w title] [-m bytes] out.png|out.jpg" >&2; exit 2; }
out=$1
im=$(command -v magick || command -v convert || true)
[ -n "$im" ] || { echo "ImageMagick is not installed" >&2; exit 2; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

if [ -n "${WAYLAND_DISPLAY:-}" ]; then
	command -v grim >/dev/null || { echo "grim is not installed" >&2; exit 2; }
	if [ -n "$title" ]; then
		sock=$(ls "${XDG_RUNTIME_DIR:?}"/sway-ipc.*.sock 2>/dev/null | head -1)
		geom=$(SWAYSOCK=$sock swaymsg -t get_tree | python3 -I -c '
import json, sys
title = sys.argv[1]
best = None
def walk(n):
    global best
    if n.get("pid") and title in (n.get("name") or "") and n.get("visible"):
        best = n["rect"]
    for c in n.get("nodes", []) + n.get("floating_nodes", []):
        walk(c)
walk(json.load(sys.stdin))
if best:
    print("%d,%d %dx%d" % (best["x"], best["y"], best["width"], best["height"]))
' "$title")
		[ -n "$geom" ] || { echo "no visible window titled *$title*" >&2; exit 1; }
		grim -g "$geom" "$tmp/s.png"
	else
		grim "$tmp/s.png"
	fi
else
	: "${DISPLAY:?set DISPLAY or WAYLAND_DISPLAY}"
	if [ -n "$title" ]; then
		id=$(xdotool search --onlyvisible --name "$title" | tail -1)
		[ -n "$id" ] || { echo "no visible window titled *$title*" >&2; exit 1; }
		xwd -silent -frame -id "$id" > "$tmp/s.xwd"
	else
		xwd -silent -root > "$tmp/s.xwd"
	fi
	"$im" "$tmp/s.xwd" "$tmp/s.png"
fi

size() { stat -c %s "$1"; }
case $out in
*.png)
	cp "$tmp/s.png" "$tmp/f.png"
	command -v pngquant >/dev/null && pngquant --quality 70-95 --speed 1 --force --output "$tmp/f.png" "$tmp/s.png" || true
	pct=90
	while [ "$(size "$tmp/f.png")" -gt "$max" ] && [ $pct -ge 30 ]; do
		"$im" "$tmp/s.png" -resize ${pct}% "$tmp/r.png"
		cp "$tmp/r.png" "$tmp/f.png"
		command -v pngquant >/dev/null && pngquant --quality 60-90 --speed 1 --force --output "$tmp/f.png" "$tmp/r.png" || true
		pct=$((pct - 10))
	done
	cp "$tmp/f.png" "$out";;
*.jpg)
	q=90
	"$im" "$tmp/s.png" -strip -quality $q "$out"
	while [ "$(size "$out")" -gt "$max" ] && [ $q -gt 50 ]; do
		q=$((q - 10)); "$im" "$tmp/s.png" -strip -quality $q "$out"
	done
	pct=90
	while [ "$(size "$out")" -gt "$max" ] && [ $pct -ge 30 ]; do
		"$im" "$tmp/s.png" -strip -resize ${pct}% -quality $q "$out"; pct=$((pct - 10))
	done;;
*) echo "output must end in .png or .jpg" >&2; exit 2;;
esac
[ "$(size "$out")" -le "$max" ] || { echo "could not get $out under $max bytes" >&2; exit 1; }
echo "$out $(size "$out") bytes"
