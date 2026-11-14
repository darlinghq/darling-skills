#!/bin/bash
# install-lldb.sh [<work dir>]
# Downloads the lldb build known to work under Darling (lldb-360.99, x86_64,
# debugs x86_64 and i386 processes), unpacks it on the host and copies it into
# the guest at /usr/local/lldb. Darling must be running. Keeps the download in
# <work dir> (default: a new temporary directory) so a rerun can skip it.
set -eu
url=https://darling-misc.s3.eu-central-1.amazonaws.com/lldb.tar.bz2
work=${1:-$(mktemp -d "${TMPDIR:-/tmp}/darling-lldb.XXXX")}
mkdir -p "$work"; work=$(realpath "$work")

if timeout -s KILL 60 darling shell test -x /usr/local/lldb/lldb </dev/null; then
	echo "already installed: /usr/local/lldb"
else
	[ -f "$work/lldb.tar.bz2" ] || curl -fL -o "$work/lldb.tar.bz2" "$url"
	[ -x "$work/lldb/lldb" ] || tar -xjf "$work/lldb.tar.bz2" -C "$work"
	[ -x "$work/lldb/lldb" ] || { echo "unexpected archive layout in $work" >&2; exit 1; }
	# copy with the guest: host writes into a running prefix are not visible inside it
	timeout -s KILL 600 darling shell sudo cp -R "/Volumes/SystemRoot$work/lldb" /usr/local/lldb </dev/null
fi
timeout -s KILL 120 darling shell /usr/local/lldb/lldb --version </dev/null
