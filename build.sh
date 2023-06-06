#!/bin/bash
set -e
export MAKEFLAGS="-j$(nproc)"

# WITH_UPX=1

platform="$(uname -s)"
platform_arch="$(uname -m)"

if [ -x "$(which apt 2>/dev/null)" ]
    then
        apt update && apt install -y \
            build-essential clang pkg-config git squashfs-tools fuse \
            libzstd-dev liblz4-dev liblzo2-dev liblzma-dev zlib1g-dev \
            libfuse-dev libsquashfuse-dev libsquashfs-dev autoconf libtool upx
fi

if [ -d build ]
    then
        echo "= removing previous build directory"
        rm -rf build
fi

if [[ -d release_fuse2 || -d release_fuse3 ]]
    then
        echo "= removing previous release directory"
        rm -rf release_fuse2 release_fuse3
fi

# create build and release directory
mkdir build
mkdir release_fuse2
mkdir release_fuse3
pushd build

# download squashfuse
git clone https://github.com/vasi/squashfuse
squashfuse_version="$(cd squashfuse && git describe --long --tags|sed 's/^v//;s/\([^-]*-g\)/r\1/;s/-/./g')"
# squashfuse_version="$(cd squashfuse && git tag --list|tac|grep '^[0-9]'|head -1|sed 's/^v//;s/\([^-]*-g\)/r\1/;s/-/./g')"
mv squashfuse "squashfuse-${squashfuse_version}"
echo "= downloading squashfuse v${squashfuse_version}"

if [ "$platform" == "Linux" ]
    then
        export CFLAGS="-static"
        NEWLDFLAGS='-all-static'
    else
        echo "= WARNING: your platform does not support static binaries."
        echo "= (This is mainly due to non-static libc availability.)"
fi

echo "= building squashfuse"
pushd squashfuse-${squashfuse_version}
./autogen.sh
env CFLAGS="$CFLAGS -g -O2 -Os -ffunction-sections -fdata-sections" \
    LDFLAGS="-Wl,--gc-sections" ./configure
make DESTDIR="$(pwd)/install2" LDFLAGS="$NEWLDFLAGS" install
make clean

echo "= building squashfuse3"
if [ -x "$(which apt 2>/dev/null)" ]
    then
        apt install -y fuse3 libfuse3-dev
fi
./autogen.sh
env CFLAGS="$CFLAGS -g -O2 -Os -ffunction-sections -fdata-sections" \
    LDFLAGS="$LDFLAGS -Wl,--gc-sections" ./configure
make DESTDIR="$(pwd)/install3" LDFLAGS="$NEWLDFLAGS" install

popd # squashfuse-${squashfuse_version}
popd # build

shopt -s extglob

echo "= extracting squashfuse binary"
mv build/squashfuse-${squashfuse_version}/install2/usr/local/bin/* release_fuse2 2>/dev/null
mv build/squashfuse-${squashfuse_version}/install3/usr/local/bin/* release_fuse3 2>/dev/null

echo "= striptease"
for file in release_fuse2/*
  do
      strip -s -R .comment -R .gnu.version --strip-unneeded "$file" 2>/dev/null
done
for file in release_fuse3/*
  do
      strip -s -R .comment -R .gnu.version --strip-unneeded "$file" 2>/dev/null
done

if [[ "$WITH_UPX" == 1 && -x "$(which upx 2>/dev/null)" ]]
    then
        echo "= upx compressing"
        for file in release_fuse2/*
          do
              upx -9 --best "$file" 2>/dev/null
        done
        for file in release_fuse3/*
          do
              upx -9 --best "$file" 2>/dev/null
        done
fi

echo "= create release tar.xz"
tar --xz -acf squashfuse-static-v${squashfuse_version}-${platform_arch}.tar.xz release_fuse*
# cp squashfuse-static-*.tar.xz /root 2>/dev/null

if [ "$NO_CLEANUP" != 1 ]
    then
        echo "= cleanup"
        rm -rf release_fuse2 release_fuse3 build
fi

echo "= squashfuse v${squashfuse_version} done"
