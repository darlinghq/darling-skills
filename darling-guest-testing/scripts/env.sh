# Sourced by the other scripts. Override any of these in the environment.
#   DARLING_SRC    source checkout (default: the Darling checkout containing the current directory)
#   DARLING_BUILD  CMake build dir (default: the newest build*/ under DARLING_SRC with a CMakeCache.txt)
#   DARLING_ROOT   installed tree (default: <prefix>/libexec/darling of the darling launcher on PATH,
#                  else Darling's default /usr/local/libexec/darling)
if [ -z "${DARLING_SRC:-}" ]; then
	# walk up through submodules to the checkout that has the launcher sources
	dir=$(git rev-parse --show-toplevel 2>/dev/null || true)
	while [ -n "$dir" ] && [ ! -f "$dir/src/startup/darling.c" ]; do
		dir=$(git -C "$dir" rev-parse --show-superproject-working-tree 2>/dev/null || true)
	done
	DARLING_SRC=$dir
fi
[ -n "$DARLING_SRC" ] && [ -f "$DARLING_SRC/src/startup/darling.c" ] || { echo "run from inside a Darling checkout or set DARLING_SRC" >&2; exit 2; }
if [ -z "${DARLING_BUILD:-}" ]; then
	DARLING_BUILD=$(ls -dt "$DARLING_SRC"/build*/CMakeCache.txt 2>/dev/null | head -1)
	DARLING_BUILD=${DARLING_BUILD%/CMakeCache.txt}
fi
if [ -z "${DARLING_ROOT:-}" ]; then
	launcher=$(command -v darling 2>/dev/null || true)
	[ -n "$launcher" ] && DARLING_ROOT=$(dirname "$(dirname "$(readlink -f "$launcher")")")/libexec/darling
	[ -d "${DARLING_ROOT:-}" ] || DARLING_ROOT=/usr/local/libexec/darling
fi
DARLING_SDK=${DARLING_SDK:-$DARLING_SRC/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk}
[ -n "$DARLING_BUILD" ] && [ -d "$DARLING_BUILD" ] || { echo "no Darling build dir; set DARLING_BUILD" >&2; exit 2; }
