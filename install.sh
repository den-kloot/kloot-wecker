#!/bin/bash
# Installs oma_alarm for the current user.
set -eu
cd "$(dirname "$0")"
bin=$HOME/.local/bin
units=$HOME/.config/systemd/user
install -Dm755 oma_alarm "$bin/oma_alarm"
install -Dm644 qml/shell.qml "$HOME/.local/share/oma_alarm/qml/shell.qml"
install -Dm644 -t "$units" systemd/oma_alarm-ring@.service systemd/oma_alarm-sync.service systemd/oma_alarm-sync.path
install -Dm644 oma_alarm.svg "$HOME/.local/share/icons/hicolor/scalable/apps/oma_alarm.svg"
mkdir -p "$HOME/.local/share/applications" "$HOME/.config/oma_alarm"
sed "s|@BIN@|$bin|" oma_alarm.desktop >"$HOME/.local/share/applications/oma_alarm.desktop"
gtk-update-icon-cache -q -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
# The old always-running scheduler (before timers), if installed.
if [[ -f $units/oma_alarm.service ]]; then
  systemctl --user disable --now oma_alarm.service 2>/dev/null || true
  rm -f "$units/oma_alarm.service"
fi
systemctl --user daemon-reload
systemctl --user enable --now oma_alarm-sync.path
"$bin/oma_alarm" sync
echo "installed; open \"OmaAlarm\" from the app menu"
