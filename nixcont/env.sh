#!/bin/bash

OPERATION="$1"
CONTAINER_NAME="nixcont"
CONTAINER_ARCH="arm64"

set -x
set -e
set -u

cd "$(dirname "${BASH_SOURCE[0]}")"

if [[ "$OPERATION" == "setup" ]]; then
    # create the container, if not exists; todo: Containerfile?
    if ! podman container exists "$CONTAINER_NAME"; then
        mkdir -p data/{nix,root}
        podman create -it --name "$CONTAINER_NAME" \
            -v ${PWD}/conf:/etc/nix \
            -v ${PWD}/data/nix:/nix \
            -v ${PWD}/data/root:/root \
            --arch "$CONTAINER_ARCH" ubuntu:mantic \
            /etc/nix/entry.sh
    fi
elif [[ "$OPERATION" == "clean" ]]; then
    podman rm -f "$CONTAINER_NAME"
    chmod -R 755 data
    rm -rf data
elif [[ "$OPERATION" == "build" ]]; then
    if ! podman container exists "$CONTAINER_NAME"; then
        echo "please run '$0 setup' first"
        exit 1
    fi

    # build
    echo "build-$2.sh" > data/root/.job
    # podman start -a "$CONTAINER_NAME"

    # pack, todo: not only appimage
    result="$(realpath "$(fd -t x -e AppImage $2 data/nix)")"
    if [[ ! -e "$result" ]]; then
        echo "build failed"
        exit 1
    fi
    appimage/repack.sh "$result"
else
    if ! podman container exists "$CONTAINER_NAME"; then
        echo "please run '$0 setup' first"
        exit 1
    fi

    rm -fv data/root/.job
    podman start -a "$CONTAINER_NAME"
fi
