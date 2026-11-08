#!/bin/bash
# Installs kloot-wecker for the current user.
set -eu
cd "$(dirname "$0")"
bin=$HOME/.local/bin
install -Dm755 kloot-wecker "$bin/kloot-wecker"
install -Dm644 qml/shell.qml "$HOME/.local/share/kloot-wecker/qml/shell.qml"
install -Dm644 kloot-wecker.service "$HOME/.config/systemd/user/kloot-wecker.service"
mkdir -p "$HOME/.local/share/applications"
sed "s|@BIN@|$bin|" kloot-wecker.desktop >"$HOME/.local/share/applications/kloot-wecker.desktop"
systemctl --user daemon-reload
systemctl --user enable --now kloot-wecker.service
systemctl --user restart kloot-wecker.service
echo "installed; open \"Wecker\" from the app menu"
