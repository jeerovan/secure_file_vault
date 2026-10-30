#!/bin/sh
set -eu
# Install only FiFe's authentication declaration. It grants no privileged action
# and never retains authentication. Run explicitly with sudo during setup;
# distributions can instead install this file through their package manager.
if [ "$(id -u)" -ne 0 ]; then
  echo 'Run this installer with sudo to enable Linux system authentication.' >&2
  exit 1
fi
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
install -o root -g root -m 0644 "$script_dir/com.jeerovan.fife.policy" \
  /usr/share/polkit-1/actions/com.jeerovan.fife.policy
