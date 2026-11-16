#!/bin/bash
# audio-capture.sh <out.raw> <command...>: record what <command> plays.
#
# Loads a PulseAudio null sink (Darling's tests/coreaudio/fixture.sh), makes it
# the default sink while <command> runs, records its monitor as raw s16le mono
# 44100 Hz into <out.raw>, then restores the old default sink and unloads the
# fixture. The launcher does not pass PULSE_SINK into the guest, so the
# default sink is the way to route a guest program's output.
#
# <command> is run as given, e.g.
#   audio-capture.sh cap.raw timeout -s KILL 60 darling shell afplay /Volumes/SystemRoot$PWD/ramp.wav
# Host audio of other programs also goes to the null sink while it runs.
set -u
OUT=${1:?usage: audio-capture.sh <out.raw> <command...>}
shift
[ $# -gt 0 ] || { echo "usage: audio-capture.sh <out.raw> <command...>" >&2; exit 2; }
. "$(dirname "$0")/env.sh"
FIXTURE=$DARLING_SRC/tests/coreaudio/fixture.sh
OLD_SINK=$(pactl get-default-sink) || exit 1
PAREC=

cleanup() {
	[ -n "$PAREC" ] && kill "$PAREC" 2>/dev/null
	pactl set-default-sink "$OLD_SINK"
	"$FIXTURE" down
}
trap cleanup EXIT

"$FIXTURE" up >/dev/null || exit 1
pactl set-default-sink darling-test-sink
parec -d darling-test-sink.monitor --format=s16le --rate=44100 --channels=1 --raw > "$OUT" &
PAREC=$!
# the monitor needs a moment before it delivers data
sleep 1
"$@"
RC=$?
# let the sink render what the player handed over before it exited
sleep 1
echo "command rc=$RC, capture in $OUT"
exit $RC
