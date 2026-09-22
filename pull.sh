#!/bin/sh

# Automated script to update my non-primary systems
# config to be in sync with upstream git repo while
# preserving local edits to dotfiles via git stash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Stash local edits, pull changes, and re-apply local edits
pushd $SCRIPT_DIR &> /dev/null;
git stash;
git pull;
git stash apply;
popd &> /dev/null;
