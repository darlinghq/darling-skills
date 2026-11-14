# Sourced by the other scripts. Override any of these in the environment.
#   DARLING_SRC    source checkout (default ~/darling)
#   DARLING_BUILD  CMake build dir (default: the newest build*/ under DARLING_SRC with a CMakeCache.txt)
#   DARLING_ROOT   installed tree (default /usr/local/libexec/darling)
DARLING_SRC=${DARLING_SRC:-$HOME/darling}
if [ -z "${DARLING_BUILD:-}" ]; then
	DARLING_BUILD=$(ls -dt "$DARLING_SRC"/build*/CMakeCache.txt 2>/dev/null | head -1)
	DARLING_BUILD=${DARLING_BUILD%/CMakeCache.txt}
fi
DARLING_ROOT=${DARLING_ROOT:-/usr/local/libexec/darling}
DARLING_SDK=${DARLING_SDK:-$DARLING_SRC/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk}
[ -n "$DARLING_BUILD" ] && [ -d "$DARLING_BUILD" ] || { echo "no Darling build dir; set DARLING_BUILD" >&2; exit 2; }
