#!/bin/bash
# leftovers.sh [-k]
# Lists Darling container processes still alive after a shutdown (the
# container's launchd and daemons, hung test binaries, all running under mldr)
# and with -k kills them. Uses the bracket trick so grep never matches itself;
# do not replace this with pgrep/pkill -f, which can match the calling shell.
kill=0; [ "${1:-}" = -k ] && kill=1
pids=$(ps -eo pid=,args= | grep -E '[m]ldr|[d]arlingserver' | awk '{print $1}')
[ -n "$pids" ] || exit 0
echo "leftover Darling processes:"
ps -o pid=,user=,etime=,args= -p $(echo $pids | tr ' ' ,)
if [ $kill = 1 ]; then
	kill -9 $pids 2>/dev/null
	echo "killed: $pids"
fi
