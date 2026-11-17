# Shared by build-cross.sh and build-native.sh. Not to be run directly.

set -e

abspath() {
    (cd "$1" && pwd)
}

H=m68k-apple-aux
GCC_SRC=$(abspath "$(dirname "$0")/../..")
VERSION=$(sed -n 's/.*version_string = "\([^ "]*\).*/\1/p' "$GCC_SRC/gcc/version.c")
BUILD=$(sh "$GCC_SRC/config.guess")
JOBS=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)

# A checkout has no c-parse.c, unlike a release. The parsers of bison 1.875
# and later call malloc, which system.h poisons, so make it with 1.35.
GCC_BISON=
if command -v bison-1.35 >/dev/null 2>&1; then
    GCC_BISON=BISON=bison-1.35
fi

# configure DIR SRC ARGS... runs configure once, so that an interrupted
# build can be resumed by running the script again.
configure() {
    dir=$1 src=$2
    shift 2
    mkdir -p "$dir"
    cd "$dir"
    [ -f config.status ] || "$src/configure" "$@"
}
