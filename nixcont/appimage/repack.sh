#!/usr/bin/env bash

#
# Repack the AppImage with bubblewrp.
# WARNING: Contains Binary Files
# WARNING: Hard Coded For ARM64
#

set -u

IMAGE="$1"
if [[ ! "$IMAGE" ]] || [[ ! -f "$IMAGE" ]]; then
    echo "usage: $0 [appimage]"
    exit 0
fi

set -e
set -x

cd "$(dirname "${BASH_SOURCE[0]}")"

strip="aarch64-linux-gnu-strip"
if [[ ! -x "$strip" ]]; then
    strip="aarch64-suse-linux-strip"
else
    echo "missing aarch64 strip?"
    exit 1
fi

rm -rf squashfs-root
qemu-aarch64 "$IMAGE" --appimage-extract &> /dev/null

# keep the root clean
pushd squashfs-root
entry="$(readlink entrypoint)"
rm -rfv AppRun entrypoint mountroot
chmod -R 755 nix

# copy only what we needed; todo: more or less?
keeps="$(../depwalk.py ".$entry" .)"
for file in $keeps; do
    base="${file#./nix/store/}"
    mkdir -p "$(dirname "nix/sink/$base")"
    cp --dereference "$file" "nix/sink/$base"
done
rm -rf nix/store
mv nix/sink nix/store

# seems not much useful...
(fd -e '.so' . nix/store/ | xargs realpath | sort | uniq | xargs $strip -s) || true

# in alpine:
#   ./autogen.sh
#   LDFLAGS="-static" ./configure
#   make -j4
cp -v ../bwrap ./

# in alpine:
#   curl -Lo .config https://github.com/buildroot/buildroot/raw/master/package/busybox/busybox-minimal.config
#   yes "" | make oldconfig
#   make -j4 busybox
mkdir -p bin
cp -v ../busybox bin/
ln -s /bin/busybox bin/sh

# entry
bin="$(basename "$entry")"
cat > "$bin" <<EOF
#!/bin/bash

export -n LD_LIBRARY_PATH
export -n LD_PRELOAD
export PATH="/bin:\$PATH"

cd "\$(dirname "\${BASH_SOURCE[0]}")"
case "\$(realpath .)" in
     /root/* | /userdata/* | /home/*)
        opts="--bind \$PWD \$PWD"
        ;;
     *)
        opts=""
        ;;
esac

./bwrap --ro-bind "\$PWD/nix" /nix \\
        --ro-bind "\$PWD/bin" /bin \\
        --bind /sys /sys \\
        --dev /dev \\
        --proc /proc \\
        \$opts \\
        "$entry" "\$@"
EOF
chmod +x "$bin"
popd

# repack
tar --owner root --group root -cJf "$bin.tar.gz" -C squashfs-root .
