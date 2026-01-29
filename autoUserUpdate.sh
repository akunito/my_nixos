#!/bin/sh

# Script triggered by SystemD to update User (home-manager)
# Must run as your own user
# $1 = SCRIPT_DIR (optional)
# $2 = HM_BRANCH (optional, default "master")

# Set SCRIPT_DIR based on first parameter or current directory
if [ $# -gt 0 ]; then
    SCRIPT_DIR=$1
else
    SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
fi
HM_BRANCH=${2:-master}

echo -e "Running home-manager switch (branch: $HM_BRANCH)"
nix run home-manager/$HM_BRANCH --extra-experimental-features nix-command --extra-experimental-features flakes -- switch --flake $SCRIPT_DIR#user --show-trace
