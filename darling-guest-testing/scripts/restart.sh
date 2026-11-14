#!/bin/bash
# restart.sh [stop|start|restart]  (default restart)
# Stops the Darling container, reports leftover processes, and starts it again
# with a trivial command, retrying the first start (right after a shutdown it
# can fail with "Cannot open mnt namespace file").
set -u
what=${1:-restart}
if [ "$what" != start ]; then
	timeout 60 darling shutdown </dev/null >/dev/null 2>&1
	"$(dirname "$0")/leftovers.sh"
fi
if [ "$what" != stop ]; then
	for i in 1 2 3 4 5; do
		out=$(DISPLAY=${DISPLAY:-:99} timeout 120 darling shell /bin/echo up </dev/null 2>&1)
		[ "$out" = up ] && { echo "darling up"; exit 0; }
		sleep 3
	done
	echo "darling did not start: $out" >&2
	exit 1
fi
