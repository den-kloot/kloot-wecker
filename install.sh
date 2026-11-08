#!/bin/bash
# Installs oma_alarm for the current user.
set -eu
cd "$(dirname "$0")"
bin=$HOME/.local/bin
install -Dm755 oma_alarm "$bin/oma_alarm"
install -Dm644 qml/shell.qml "$HOME/.local/share/oma_alarm/qml/shell.qml"
install -Dm644 oma_alarm.service "$HOME/.config/systemd/user/oma_alarm.service"
install -Dm644 oma_alarm.svg "$HOME/.local/share/icons/hicolor/scalable/apps/oma_alarm.svg"
mkdir -p "$HOME/.local/share/applications"
sed "s|@BIN@|$bin|" oma_alarm.desktop >"$HOME/.local/share/applications/oma_alarm.desktop"
gtk-update-icon-cache -q -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
systemctl --user daemon-reload
systemctl --user enable --now oma_alarm.service
systemctl --user restart oma_alarm.service
echo "installed; open \"OmaAlarm\" from the app menu"
