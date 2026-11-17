#!/bin/bash
# set-background.sh: give the running X11 (DISPLAY) or Wayland (sway,
# WAYLAND_DISPLAY + XDG_RUNTIME_DIR) session the standard AppDB background:
# a light gray field with faint, tilted Darling logos (background.png, made by
# make-background.sh). Run it after starting the session with the
# darling-guest-testing scripts. Needs ImageMagick's display on X11 and swaybg
# on sway; without them it sets the background's gray instead.
set -eu
bg="$(cd "$(dirname "$0")" && pwd)/background.png"
gray='#E8E8EA'

if [ -n "${WAYLAND_DISPLAY:-}" ]; then
	sock=$(ls "${XDG_RUNTIME_DIR:?}"/sway-ipc.*.sock 2>/dev/null | head -1)
	[ -n "$sock" ] || { echo "no sway session in $XDG_RUNTIME_DIR" >&2; exit 1; }
	if command -v swaybg >/dev/null; then
		SWAYSOCK=$sock swaymsg -q "output * bg $bg fill"
	else
		echo "swaybg is not installed; using the plain gray" >&2
		SWAYSOCK=$sock swaymsg -q "output * bg $gray solid_color"
	fi
else
	: "${DISPLAY:?set DISPLAY or WAYLAND_DISPLAY}"
	if command -v display >/dev/null; then
		display -window root "$bg" 2>/dev/null || true
	else
		echo "ImageMagick's display is not installed; using the plain gray" >&2
		xsetroot -solid "$gray"
	fi
fi
