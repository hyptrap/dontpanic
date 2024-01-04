#!/bin/bash

set -x
set -e
set -u

# proxy, if needed
export HTTPS_PROXY=http://192.168.31.3:7890

# we're in /root
apt install git
git clone https://github.com/iovisor/bpftrace
cd bpftrace

# nix to build
time nix build .#appimage
