#!/bin/bash

# build-toolchain script based on build-toolchain.sh as found in https://developer.arm.com/-/media/Files/downloads/gnu-rm/8-2019q3/RC1.1/gcc-arm-none-eabi-8-2019-q3-update-src.tar.bz2
# This builds gcc and libc only for armv6, with various libc/libgcc build settings, selectable via different specs files.
# Output is logged to separate files per build step.

# The original disclaimer follows:

# Copyright (c) 2011-2015, ARM Limited
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
#     * Redistributions of source code must retain the above copyright notice,
#       this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#     * Neither the name of Arm nor the names of its contributors may be used
#       to endorse or promote products derived from this software without
#       specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

set -e # exit on any error
# set -x # trace of commands on stdout
set -u # bail out on unknown variables
set -o pipefail # return value of pipeline is rightmost command with nonzero status

ts_start=`date +%s`

echo using build log timestamp $ts_start

# helper function to redirect all output (stdout+stderr) to a logfile, and report it on stdout
# usage: log <action> <target>
# example: log make gcc
log() {
    action=$1
    target=$2
    if [ ! -z ${logfile:-} ]; then unlog; fi
    fn=buildlog.$ts_start.$target.$action
    logfile=$logdir/$fn
    echo "$(date): $action $target, logging to $fn"
    exec 6>&1 # save stdout
    exec 7>&2 # save stderr
    exec > $logfile
    exec 2> $logfile
}

unlog() {
    exec 1>&6 6>&-
    exec 2>&7 7>&-
    logfile=
}

# same stdout output as log, but don't disturb logfile
inform() {
    action=$1
    target=$2
    msg="$(date): $action $target (no logfile)"
    if [ ! -z ${logfile:-} ]
    then
        echo $msg
    else
        echo $msg >&6
    fi
}

umask 022

exec < /dev/null

script_path=`cd $(dirname $0) && pwd -P`
. $script_path/build-common.sh

MULTILIB_LIST="--with-arch=armv6s-m --with-float=soft --with-mode=thumb --disable-multilib"

CXXFLAGS=
if [ "x$BUILD" == "xx86_64-apple-darwin10" ] ; then
    CXXFLAGS="-fbracket-depth=512"
fi

ENV_CFLAGS=" -I$BUILDDIR_NATIVE/host-libs/zlib/include -O2 "
ENV_CPPFLAGS=" -I$BUILDDIR_NATIVE/host-libs/zlib/include "
ENV_LDFLAGS=" -L$BUILDDIR_NATIVE/host-libs/zlib/lib
              -L$BUILDDIR_NATIVE/host-libs/usr/lib "

GCC_CONFIG_OPTS=" --build=$BUILD --host=$HOST_NATIVE
                  --with-gmp=$BUILDDIR_NATIVE/host-libs/usr
                  --with-mpfr=$BUILDDIR_NATIVE/host-libs/usr
                  --with-mpc=$BUILDDIR_NATIVE/host-libs/usr
                  --with-isl=$BUILDDIR_NATIVE/host-libs/usr
                  --with-libelf=$BUILDDIR_NATIVE/host-libs/usr "

BINUTILS_CONFIG_OPTS=" --build=$BUILD --host=$HOST_NATIVE "

NEWLIB_CONFIG_OPTS=" --build=$BUILD --host=$HOST_NATIVE "

GDB_CONFIG_OPTS=" --build=$BUILD --host=$HOST_NATIVE
                  --with-libexpat-prefix=$BUILDDIR_NATIVE/host-libs/usr "

mkdir -p $BUILDDIR_NATIVE
rm -rf $INSTALLDIR_NATIVE && mkdir -p $INSTALLDIR_NATIVE
rm -rf $PACKAGEDIR && mkdir -p $PACKAGEDIR

logdir=$script_path

cd $SRCDIR

log conf binutils

rm -rf $BUILDDIR_NATIVE/binutils && mkdir -p $BUILDDIR_NATIVE/binutils
pushd $BUILDDIR_NATIVE/binutils
saveenv
saveenvvar CFLAGS "$ENV_CFLAGS"
saveenvvar CPPFLAGS "$ENV_CPPFLAGS"
saveenvvar LDFLAGS "$ENV_LDFLAGS"
$SRCDIR/$BINUTILS/configure  \
    ${BINUTILS_CONFIG_OPTS} \
    --target=$TARGET \
    --prefix=$INSTALLDIR_NATIVE \
    --infodir=$INSTALLDIR_NATIVE_DOC/info \
    --mandir=$INSTALLDIR_NATIVE_DOC/man \
    --htmldir=$INSTALLDIR_NATIVE_DOC/html \
    --pdfdir=$INSTALLDIR_NATIVE_DOC/pdf \
    --disable-nls \
    --disable-werror \
    --disable-sim \
    --disable-gdb \
    --enable-interwork \
    --enable-plugins \
    --with-sysroot=$INSTALLDIR_NATIVE/arm-none-eabi \
    "--with-pkgversion=$PKGVERSION"

log make binutils
make -j$JOBS

log inst binutils
make install

copy_dir $INSTALLDIR_NATIVE $BUILDDIR_NATIVE/target-libs
restoreenv
popd

pushd $INSTALLDIR_NATIVE
rm -rf ./lib
popd

build_gcc() {
    local lib_cflags=$1
    local lib_suffix=$2

    log conf gcc-$lib_suffix
    rm -rf $BUILDDIR_NATIVE/gcc-first && mkdir -p $BUILDDIR_NATIVE/gcc-first
    pushd $BUILDDIR_NATIVE/gcc-first
    $SRCDIR/$GCC/configure --target=$TARGET \
        --prefix=$INSTALLDIR_NATIVE \
        --libexecdir=$INSTALLDIR_NATIVE/lib \
        --infodir=$INSTALLDIR_NATIVE_DOC/info \
        --mandir=$INSTALLDIR_NATIVE_DOC/man \
        --htmldir=$INSTALLDIR_NATIVE_DOC/html \
        --pdfdir=$INSTALLDIR_NATIVE_DOC/pdf \
        --enable-languages=c \
        --enable-plugins \
        --disable-decimal-float \
        --disable-libffi \
        --disable-libgomp \
        --disable-libmudflap \
        --disable-libquadmath \
        --disable-libssp \
        --disable-libstdcxx-pch \
        --disable-nls \
        --disable-shared \
        --disable-threads \
        --disable-tls \
        --with-gnu-as \
        --with-gnu-ld \
        --with-newlib \
        --with-headers=yes \
        --with-python-dir=share/gcc-arm-none-eabi \
        --with-sysroot=$INSTALLDIR_NATIVE/arm-none-eabi \
        $GCC_CONFIG_OPTS                              \
        "${GCC_CONFIG_OPTS_LCPP}"                              \
        "--with-pkgversion=$PKGVERSION" \
        ${MULTILIB_LIST}

    # Passing USE_TM_CLONE_REGISTRY=0 via INHIBIT_LIBC_CFLAGS to disable
    # transactional memory related code in crtbegin.o.
    # This is a workaround. Better approach is have a t-* to set this flag via
    # CRTSTUFF_T_CFLAGS
    # MvdS: this workaround does not work, because in fact INHIBIT_LIBC_CFLAGS is used
    # in building gcc (and therefore in building libgcc and therefore in crt*.o) and
    # set to -Dinhibit_libc, because the include headers are not present yet at the target
    # path. This could be fixed by building twice, or by modifying libgcc/Makefile.in.
    log make gcc-$lib_suffix
    make -j$JOBS CXXFLAGS="${CXXFLAGS:-}" INHIBIT_LIBC_CFLAGS="-DUSE_TM_CLONE_REGISTRY=0" CFLAGS_FOR_TARGET="${lib_cflags}"

    log inst gcc-$lib_suffix
    make install

    log copy gcc-$lib_suffix
    pushd $INSTALLDIR_NATIVE/lib/gcc/arm-none-eabi/10.0.0/
    ln -v "libgcc.a" "libgcc_${lib_suffix}.a"
    popd
}

build_libc() {
    local lib_cflags=$1
    local lib_suffix=$2

    log conf libc-$lib_suffix

    saveenv
    prepend_path PATH $INSTALLDIR_NATIVE/bin
    saveenvvar CFLAGS_FOR_TARGET "${lib_cflags}"
    rm -rf $BUILDDIR_NATIVE/newlib-nano && mkdir -p $BUILDDIR_NATIVE/newlib-nano
    pushd $BUILDDIR_NATIVE/newlib-nano

    $SRCDIR/$NEWLIB_NANO/configure  \
        $NEWLIB_CONFIG_OPTS \
        --target=$TARGET \
        --prefix=$INSTALLDIR_NATIVE \
        --disable-newlib-supplied-syscalls    \
        --enable-newlib-reent-small           \
        --enable-newlib-retargetable-locking  \
        --disable-newlib-fvwrite-in-streamio  \
        --disable-newlib-fseek-optimization   \
        --disable-newlib-wide-orient          \
        --enable-newlib-nano-malloc           \
        --disable-newlib-unbuf-stream-opt     \
        --enable-lite-exit                    \
        --enable-newlib-global-atexit         \
        --enable-newlib-nano-formatted-io     \
        --disable-nls

    log make libc-$lib_suffix
    make -j$JOBS

    log inst libc-$lib_suffix
    make install

    popd
    restoreenv

    log copy libc-$lib_suffix
    pushd $INSTALLDIR_NATIVE/arm-none-eabi/lib
    ln -v "libc.a" "libc_nano_${lib_suffix}.a"
    ln -v "libg.a" "libg_nano_${lib_suffix}.a"
    ln -v "librdimon.a" "librdimon_nano_${lib_suffix}.a"
    mv -v "libm.a" "libm_nano_${lib_suffix}.a"

    local newspecs="nano_${lib_suffix}.specs"
    inform gen $newspecs
    cat nano.specs | sed -e "s/_nano/_nano_${lib_suffix}/g" > $newspecs
    rm nano.specs
    popd
}

pushd $INSTALLDIR_NATIVE
rm -rf bin/arm-none-eabi-gccbug
rm -rf ./lib/libiberty.a
rm -rf include
popd

lib_cflags="-g -Os -ffunction-sections -fdata-sections -fno-exceptions -ffixed-r10 -ffixed-fp -ffixed-r9"
lib_suffix="Os_freeregs"

build_gcc "${lib_cflags}" "${lib_suffix}"
build_libc "${lib_cflags}" "${lib_suffix}"

lib_cflags="-g -O2 -ffunction-sections -fdata-sections -fno-exceptions"
lib_suffix="O2"

build_gcc "${lib_cflags}" "${lib_suffix}"
build_libc "${lib_cflags}" "${lib_suffix}"

# It is assumed that the different libc builds all have the same newlib.h
mkdir -p $INSTALLDIR_NATIVE/arm-none-eabi/include/newlib-nano
cp -f $INSTALLDIR_NATIVE/arm-none-eabi/include/newlib.h \
      $INSTALLDIR_NATIVE/arm-none-eabi/include/newlib-nano/newlib.h

unlog

ts_end=$(date +%s)
echo
echo "Build completed in $[ts_end-ts_start] seconds."
echo
echo "This is your new compiler:"
echo $INSTALLDIR_NATIVE/bin/arm-none-eabi-gcc -v
$INSTALLDIR_NATIVE/bin/arm-none-eabi-gcc -v
echo
echo "To use this toolchain by default, add this to your .profile and don't forget to re-open any shells you have:"
echo "export PATH=$INSTALLDIR_NATIVE/bin:\$PATH"

