#!/usr/bin/env bash

export TZ=Asia/Shanghai
export USER=root

if [[ ! -f /.setup ]]; then
    # install deps
    sed -i 's@//.*ports.ubuntu.com@//mirrors.tuna.tsinghua.edu.cn@g' /etc/apt/sources.list
    apt update
    apt upgrade -y
    apt install -y build-essential sudo curl git python3

    # workaround, https://github.com/NixOS/nix/issues/1559
    groupadd -r -g 30000 nixbld
    for i in $(seq 1 30); do
    useradd -r -d /var/empty -c "Nix build user $i" -u $((30000 + $i)) -G nixbld nixblkd$i
    done

    # rock the nix
    sh <(curl -L https://nixos.org/nix/install) --no-daemon

    # replace dash
    ln -sfv /bin/bash /bin/sh

    # done
    touch /.setup
fi

# proxy, if needed
# export HTTPS_PROXY=http://192.168.31.3:7890

source /root/.nix-profile/etc/profile.d/nix.sh
cd /root

if [[ -e .job ]]; then
    bash "/etc/nix/$(cat .job)" || exit $?
    rm -fv .job
else
    exec bash
fi
