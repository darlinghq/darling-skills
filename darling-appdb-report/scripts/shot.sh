#!/bin/bash
# shot.sh [-w <window title>] [-p <margin>] [-m <max bytes>] <out.png|out.jpg>
# Takes an AppDB screenshot of the running X11 (DISPLAY) or Wayland (sway,
# WAYLAND_DISPLAY + XDG_RUNTIME_DIR) session and makes it fit the database's
# size limit.
#   -w   capture only the newest visible window whose title contains this text
#        (default: the whole screen)
#   -p   with -w, also capture this many pixels of the desktop background
#        around the window, frame included (default 32; 0 for the window alone)
#   -m   size limit in bytes (default 153600, the database's 150 KB limit)
# PNG output is colour-quantized (pngquant) and then scaled down until it fits;
# JPEG output lowers the quality first. Needs ImageMagick, pngquant, and grim
# for Wayland.
set -eu
title=""; max=153600; pad=32
while getopts w:m:p: o; do
	case $o in w) title=$OPTARG;; m) max=$OPTARG;; p) pad=$OPTARG;; *) exit 2;; esac
done
shift $((OPTIND - 1))
[ $# -eq 1 ] || { echo "usage: shot.sh [-w title] [-p margin] [-m bytes] out.png|out.jpg" >&2; exit 2; }
out=$1
im=$(command -v magick || command -v convert || true)
[ -n "$im" ] || { echo "ImageMagick is not installed" >&2; exit 2; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# grow "x y w h" by the margin on every side, kept inside the screen "W H"
grow() {
	local x=$1 y=$2 w=$3 h=$4 sw=$5 sh=$6 x2 y2
	x2=$((x + w + pad)); y2=$((y + h + pad))
	x=$((x - pad)); y=$((y - pad))
	[ $x -ge 0 ] || x=0; [ $y -ge 0 ] || y=0
	[ $x2 -le $sw ] || x2=$sw; [ $y2 -le $sh ] || y2=$sh
	echo "$x $y $((x2 - x)) $((y2 - y))"
}

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
    print(best["x"], best["y"], best["width"], best["height"])
' "$title")
		[ -n "$geom" ] || { echo "no visible window titled *$title*" >&2; exit 1; }
		screen=$(SWAYSOCK=$sock swaymsg -t get_outputs | python3 -I -c '
import json, sys
r = json.load(sys.stdin)[0]["rect"]
print(r["width"], r["height"])')
		set -- $(grow $geom $screen)
		grim -g "$1,$2 ${3}x$4" "$tmp/s.png"
	else
		grim "$tmp/s.png"
	fi
else
	: "${DISPLAY:?set DISPLAY or WAYLAND_DISPLAY}"
	# xshot root|<window id> <out.png>: a window with its frame, or the whole screen
	xshot() {
		if [ "$1" = root ]; then xwd -silent -root; else xwd -silent -frame -id "$1"; fi > "$tmp/x.xwd"
		"$im" "$tmp/x.xwd" "$2"
	}
	if [ -n "$title" ]; then
		# give a window that is still being mapped up to 10 s to appear
		for i in $(seq 20); do
			id=$(xdotool search --onlyvisible --name "$title" 2>/dev/null | tail -1)
			[ -n "$id" ] && break
			sleep 0.5
		done
		[ -n "$id" ] || { echo "no visible window titled *$title*" >&2; exit 1; }
		if [ "$pad" -gt 0 ]; then
			# the window's frame (window manager decorations) plus the margin,
			# cut out of the whole screen
			eval "$(xdotool getwindowgeometry --shell "$id")"
			ext=$(xprop -id "$id" _NET_FRAME_EXTENTS 2>/dev/null | sed -n 's/.*= *//p' | tr -d ,)
			set -- ${ext:-0 0 0 0}
			fx=$((X - $1)); fy=$((Y - $3)); fw=$((WIDTH + $1 + $2)); fh=$((HEIGHT + $3 + $4))
			set -- $(grow $fx $fy $fw $fh $(xdpyinfo | awk '/dimensions:/ { sub(/x/, " ", $2); print $2; exit }'))
			xshot root "$tmp/r.png"
			"$im" "$tmp/r.png" -crop "${3}x$4+$1+$2" +repage "$tmp/s.png"
		else
			xshot "$id" "$tmp/s.png"
		fi
	else
		xshot root "$tmp/s.png"
	fi
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
