#!/bin/bash

set -xeu

# we're in /root
if [[ ! -d bpftrace ]]; then
    git clone https://github.com/iovisor/bpftrace
    cd bpftrace
else
    cd bpftrace
    git pull --rebase
fi

# nix to build
time nix build .#appimage
