#!/bin/bash
# guest-cc.sh [-a x86_64|i386] [-t <min macOS>] -o <out> <sources/flags...>
# Cross-compiles a C/ObjC test program (or, with -dynamiclib, a library) for
# the Darling guest with host clang, Darling's ld64 and the source-tree SDK,
# then ad-hoc signs it. Extra arguments go to clang unchanged, e.g.
#   guest-cc.sh -o t t.m -framework Foundation -fobjc-arc
set -eu
. "$(dirname "$0")/env.sh"
arch=x86_64; min=""; out=""
while getopts a:t:o: o; do
	case $o in a) arch=$OPTARG;; t) min=$OPTARG;; o) out=$OPTARG;; *) exit 2;; esac
done
shift $((OPTIND - 1))
[ -n "$out" ] || { echo "usage: guest-cc.sh [-a arch] [-t min] -o out sources..." >&2; exit 2; }

ld=$(ls "$DARLING_BUILD"/src/external/cctools-port/cctools/ld64/src/*-apple-darwin*-ld 2>/dev/null | head -1)
sign=$DARLING_BUILD/src/buildtools/adhoc-sign
[ -x "$ld" ] || { echo "ld64 not built: make -C $DARLING_BUILD ld64" >&2; exit 2; }
[ -x "$sign" ] || { echo "adhoc-sign not built: make -C $DARLING_BUILD adhoc-sign" >&2; exit 2; }
# clang -B looks for a program called "ld"
lddir=$(mktemp -d); trap 'rm -rf "$lddir"' EXIT
ln -s "$ld" "$lddir/ld"

flags=()
# Darling's SDK headers include umbrella subframeworks directly (Foundation's
# NSAppleEventDescriptor.h includes <AE/AE.h>), so put them on the search path
for u in "$DARLING_SDK"/System/Library/Frameworks/*.framework/Frameworks; do
	flags+=(-iframework "$u")
done
# the source-tree SDK has headers but no link stubs for most frameworks and
# libobjc: link against the installed Darling binaries instead
flags+=(-Wl,-syslibroot,"$DARLING_ROOT")
case $arch in
	x86_64) min=${min:-10.15}
		# without it the x86_64 link fails on $UNIX2003 symbols
		flags+=(-D__DARWIN_ONLY_UNIX_CONFORMANCE=1);;
	# never use that define for i386: libsystem_c there has the $UNIX2003 variants
	i386) min=${min:-10.13};;
	arm64) min=${min:-11.0};;
esac
clang -target "$arch-apple-macos$min" -isysroot "$DARLING_SDK" -B "$lddir" "${flags[@]}" -o "$out" "$@"
"$sign" "$out" >/dev/null
