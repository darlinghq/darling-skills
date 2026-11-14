#!/bin/bash
# rebuild.sh [-f] <target>...
# Builds only the given CMake targets, installs only their directories and
# restarts Darling so the new binaries are loaded.
#   -f  use <target>/fast (skip dependency checks; only when nothing the
#       target depends on has changed)
set -eu
. "$(dirname "$0")/env.sh"
fast=""
[ "${1:-}" = -f ] && { fast=/fast; shift; }
[ $# -gt 0 ] || { echo "usage: rebuild.sh [-f] <target>..." >&2; exit 2; }

cd "$DARLING_BUILD"
make -j"$(nproc)" $(printf "%s$fast " "$@")

dirs=()
for t in "$@"; do
	d=$(find . -type d -name "$t.dir" -path '*/CMakeFiles/*' -print -quit)
	[ -n "$d" ] || { echo "cannot find the build dir of $t" >&2; exit 1; }
	dirs+=("${d%/CMakeFiles/*}")
done
"$(dirname "$0")/restart.sh" stop
for d in $(printf '%s\n' "${dirs[@]}" | sort -u); do
	(cd "$d" && sudo -n cmake -P cmake_install.cmake >/dev/null)
	echo "installed $d"
done
"$(dirname "$0")/restart.sh" start
