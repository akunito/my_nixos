#!/bin/sh

# Script triggered by SystemD to update User
# Must run as your own user

# Set SCRIPT_DIR based on first parameter or current directory
if [ $# -gt 0 ]; then
    SCRIPT_DIR=$1
else
    SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
fi

echo -e "Nix run home-manager"
nix run home-manager/master --extra-experimental-features nix-command --extra-experimental-features flakes -- switch --flake $SCRIPT_DIR#user --show-trace
