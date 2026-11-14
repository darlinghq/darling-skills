#!/bin/bash
# wayland.sh [-s <output scale>] [stop]
# Starts a headless sway compositor for Wayland GUI tests, in its own runtime
# directory so that a desktop session is never touched, and prints the
# variables a guest program needs. "stop" ends it. Needs sway (wlroots).
#   -s 2     output scale (1, 2, or fractional such as 1.5; default 1)
set -eu
scale=1
while getopts s: o; do
	case $o in s) scale=$OPTARG;; *) exit 2;; esac
done
shift $((OPTIND - 1))

RUN=${DARLING_WAYLAND_RUNTIME:-/tmp/darling-wayland-$(id -u)}
# sway's IPC socket name (sway-ipc.<uid>.<pid>.sock) must fit a Unix socket
# path (108 bytes); sway crashes at start-up when it does not
[ ${#RUN} -le 64 ] || { echo "runtime directory path too long for sway's sockets (max 64): $RUN" >&2; exit 2; }
pidfile=$RUN/sway.pid

if [ "${1:-}" = stop ]; then
	[ -f "$pidfile" ] && kill "$(cat "$pidfile")" 2>/dev/null || true
	rm -rf "$RUN"
	exit 0
fi

command -v sway >/dev/null || { echo "sway is not installed" >&2; exit 2; }
if [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
	# already running: change the scale in place
	SWAYSOCK=$(ls "$RUN"/sway-ipc.*.sock 2>/dev/null | head -1) swaymsg -q "output * scale $scale" || true
else
	mkdir -p "$RUN"; chmod 700 "$RUN"
	# no borders or tiling, so window frames are exactly what the client asked for
	cat > "$RUN/config" <<EOF
output * resolution 1920x1080 scale $scale
# white, so screenshots and transparent window areas are not shown on black
output * bg #FFFFFF solid_color
default_border none
default_floating_border none
for_window [shell=".*"] floating enable
EOF
	XDG_RUNTIME_DIR=$RUN WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1 \
		WAYLAND_DISPLAY= DISPLAY= nohup sway -c "$RUN/config" > "$RUN/sway.log" 2>&1 &
	echo $! > "$pidfile"
	for i in $(seq 50); do
		ls "$RUN"/wayland-[0-9] "$RUN"/sway-ipc.*.sock >/dev/null 2>&1 && break
		sleep 0.1
	done
fi
sock=$(ls "$RUN"/wayland-[0-9] 2>/dev/null | head -1)
[ -n "$sock" ] || { echo "sway did not start; see $RUN/sway.log" >&2; exit 1; }
echo "DARLING_APPKIT_BACKEND=wayland WAYLAND_DISPLAY=$sock XDG_RUNTIME_DIR=$RUN"
