#!/bin/bash
# lldb-run.sh [-t <seconds>] <commands file> <output file> <guest program> [args...]
# Runs a guest program under lldb in batch mode with the lldb commands in
# <commands file> (a host file), writing everything lldb prints to <output
# file> (also a host file). The program path is a guest path. Default timeout:
# 300 s; a debugger session that hangs is killed.
set -eu
t=300
while getopts t: o; do
	case $o in t) t=$OPTARG;; *) exit 2;; esac
done
shift $((OPTIND - 1))
[ $# -ge 3 ] || { echo "usage: lldb-run.sh [-t secs] <commands> <output> <guest program> [args...]" >&2; exit 2; }
cmds=$(realpath "$1"); out=$2; shift 2
rc=0
timeout -s KILL "$t" darling shell /usr/local/lldb/lldb --batch -s "/Volumes/SystemRoot$cmds" -- "$@" </dev/null > "$out" 2>&1 || rc=$?
[ $rc -eq 137 ] && echo "lldb-run.sh: killed after $t s (hung debugger session)" >> "$out"
exit $rc
