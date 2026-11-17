#! /bin/sh
#
# Build a cross compiler for A/UX 3 (m68k-apple-aux): binutils and GCC
# (C only) that run on the build machine.
#
# usage: build-cross.sh SYSROOT BINUTILS_SRC PREFIX [WORKDIR]
#
# SYSROOT holds a copy of usr/include, lib and usr/lib from an A/UX
# installation. BINUTILS_SRC is a checkout of the aux branch of
# https://github.com/easybe/binutils-aux, which is binutils 2.16.1, the
# last release that supports m68k COFF, with fixes for A/UX. The toolchain
# is installed to PREFIX, which must be writable. WORKDIR defaults to
# ./aux-build.
#
# The build machine needs a compiler old enough to build GCC 3.2, GCC 3.3
# for instance. Debian 3.1 (sarge) has it, and a container of it will do:
#
#     docker run --rm -it --platform linux/386 -v $PWD:/w -w /w \
#         debian/eol:sarge
#
# with gcc, make, bison-1.35, flex, texinfo, m4, patch and file installed.
#
# build-native.sh builds a compiler that runs on A/UX from the result.

if [ $# -lt 3 ]; then
    echo "usage: $0 SYSROOT BINUTILS_SRC PREFIX [WORKDIR]" >&2
    exit 1
fi

. "$(dirname "$0")/common.sh"

SYSROOT=$(abspath "$1")
BINUTILS_SRC=$(abspath "$2")
mkdir -p "$3" "${4:-aux-build}"
PREFIX=$(abspath "$3")
WORK=$(abspath "${4:-aux-build}")

configure "$WORK/binutils-cross" "$BINUTILS_SRC" --target=$H \
    --prefix="$PREFIX" --disable-nls --disable-werror
make -j"$JOBS"
make install

PATH=$PREFIX/bin:$PATH
export PATH

# configure runs its subdirectories with the arguments split on blanks,
# quotes or not, so --with-libs can only take the one directory. The
# libraries in usr/lib are copied over by hand.
configure "$WORK/gcc-cross" "$GCC_SRC" --target=$H --prefix="$PREFIX" \
    --enable-obsolete --enable-languages=c --disable-nls \
    --with-gnu-as --with-gnu-ld \
    --with-headers="$SYSROOT/usr/include" --with-libs="$SYSROOT/lib"
# The start files fail to build with -j.
make $GCC_BISON
make $GCC_BISON install
cp "$SYSROOT"/usr/lib/*.a "$PREFIX/$H/lib/"

echo "Built $H-gcc $VERSION in $PREFIX"
