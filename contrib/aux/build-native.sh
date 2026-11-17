#! /bin/sh
#
# Build a native compiler for A/UX 3 (m68k-apple-aux), packed as a tar
# file to be installed on A/UX.
#
# usage: build-native.sh CROSS_PREFIX BINUTILS_SRC [WORKDIR]
#
# CROSS_PREFIX holds a cross compiler made by build-cross.sh from the same
# GCC sources. BINUTILS_SRC is the same binutils-aux checkout as for
# build-cross.sh. WORKDIR defaults to ./aux-build. The build machine needs
# the same tools as for build-cross.sh.
#
# The result is WORKDIR/gcc-3.2.3-aux.tar(.Z). To install, run as root on
# A/UX:
#
#     cd / && zcat /tmp/gcc-3.2.3-aux.tar.Z | tar xf -
#
# It contains GCC (C only) and binutils under /usr/local. GCC uses GNU as
# and GNU ld.

if [ $# -lt 2 ]; then
    echo "usage: $0 CROSS_PREFIX BINUTILS_SRC [WORKDIR]" >&2
    exit 1
fi

. "$(dirname "$0")/common.sh"

CROSS=$(abspath "$1")
BINUTILS_SRC=$(abspath "$2")
mkdir -p "${3:-aux-build}"
WORK=$(abspath "${3:-aux-build}")
STAGE=$WORK/stage

PATH=$CROSS/bin:$PATH
export PATH

# The cross compiler makes libgcc, the start files and the fixed headers
# for the native one below, so it has to come from the same sources.
if ! command -v $H-gcc >/dev/null 2>&1; then
    echo "$0: no $H-gcc in $CROSS/bin" >&2
    exit 1
fi
CROSS_VERSION=$($H-gcc -dumpversion)
if [ "$CROSS_VERSION" != "$VERSION" ]; then
    echo "$0: $H-gcc is $CROSS_VERSION, expected $VERSION" >&2
    exit 1
fi

CC=$H-gcc
AR=$H-ar
RANLIB=$H-ranlib
CC_FOR_BUILD=gcc
export CC AR RANLIB CC_FOR_BUILD
NATIVE="--build=$BUILD --host=$H --target=$H --prefix=/usr/local
    --disable-nls"

configure "$WORK/binutils-native" "$BINUTILS_SRC" $NATIVE --disable-werror
make -j"$JOBS"
make install DESTDIR="$STAGE"

# configure cannot test for mmap when cross compiling and takes it for
# granted. A/UX has none.
configure "$WORK/gcc-native" "$GCC_SRC" $NATIVE \
    --enable-obsolete --enable-languages=c --with-gnu-as --with-gnu-ld \
    --with-gc=simple
# The xgcc built here runs on A/UX only. Let the cross compiler, built
# from the same sources, make specs, libgcc and the start files instead.
# fixincludes would run on the build machine's /usr/include, so skip it
# and take the headers fixed for the cross compiler.
GCC_MAKE="GCC_FOR_TARGET=$H-gcc STMP_FIXINC= $GCC_BISON"
# The build machine's libiberty is needed by the generator programs, but
# all-gcc does not depend on it.
make all-build-libiberty
make $GCC_MAKE
make $GCC_MAKE install DESTDIR="$STAGE"
GCCLIB=lib/gcc-lib/$H/$VERSION
cp -R "$CROSS/$GCCLIB/include/." "$STAGE/usr/local/$GCCLIB/include/"

# Strip and pack for A/UX.

cd "$STAGE/usr/local"
for f in bin/* $GCCLIB/cc1 $GCCLIB/cpp0 $GCCLIB/tradcpp0 $GCCLIB/collect2
do
    if file "$f" | grep COFF >/dev/null; then
        $H-strip "$f"
    fi
done
# strip writes a new file, which breaks the hard links between bin and
# binutils' tool directory. Restore them.
for f in $H/bin/*; do
    ln -f "bin/$(basename "$f")" "$f"
done
ln -f bin/gcc bin/$H-gcc

# A/UX's tar reads the old v7 format.
TAR=$WORK/gcc-$VERSION-aux.tar
cd "$STAGE"
rm -f "$TAR" "$TAR.Z"
tar -o --owner=0 --group=0 -cf "$TAR" usr
if command -v compress >/dev/null 2>&1; then
    compress "$TAR"
    TAR=$TAR.Z
fi
echo "Built $TAR"
