#!/bin/bash
# Installs omaalarm for the current user.
set -eu
cd "$(dirname "$0")"
bin=$HOME/.local/bin
install -Dm755 omaalarm "$bin/omaalarm"
install -Dm644 qml/shell.qml "$HOME/.local/share/omaalarm/qml/shell.qml"
install -Dm644 omaalarm.service "$HOME/.config/systemd/user/omaalarm.service"
mkdir -p "$HOME/.local/share/applications"
sed "s|@BIN@|$bin|" omaalarm.desktop >"$HOME/.local/share/applications/omaalarm.desktop"
systemctl --user daemon-reload
systemctl --user enable --now omaalarm.service
systemctl --user restart omaalarm.service
echo "installed; open \"Oma Alarm\" from the app menu"
