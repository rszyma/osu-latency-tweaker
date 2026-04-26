#/usr/bin/env bash

OSU_LATENCY_TWEAKER_FREQ=192000 \
OSU_LATENCY_TWEAKER_PERIOD=-256 \
NIXPKGS_ALLOW_UNFREE=1 \
    nix run --extra-experimental-features 'nix-command flakes' --impure . --show-trace