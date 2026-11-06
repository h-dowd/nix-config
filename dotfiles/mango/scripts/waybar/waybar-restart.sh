#!/usr/bin/env bash
# Restarts waybar from the current layout and position state.
#
# Called by waybar-layout.sh, waybar-position.sh, and by the `exec=` line in
# universal/autostart.conf — which fires both at login and on every
# `mmsg dispatch reload_config`, so a reload also re-reads both state files. This is the single place that knows how the three combine.
#
# It only SELECTS a file. Every (layout, position) pair is generated as its own
# config by modules/home/waybar.nix; this script used to rewrite the JSON with
# `sed -E` into a temp copy instead, which is why it was four times this long
# and needed a `margin-swap` placeholder to stop the swap undoing itself.
. "$HOME/.config/mango/scripts/lib.sh"

POSITION=$(bar_position)
LAYOUT=$(bar_layout)

# One stylesheet. There were two until hud left: hud was a MODE
# that also forced a layout and a stylesheet, which is why the layout was
# picked here rather than simply read from state. Every mode that has a bar now
# lets the picker choose.
STYLE="$WAYBAR_DIR/style-solid.css"

CONFIG="$WAYBAR_DIR/config-$LAYOUT-$POSITION.jsonc"

# A state file holding a typo would otherwise start waybar with no config and
# no explanation — the empty-module failure one level up. Fall back, but say so.
if [ ! -f "$CONFIG" ]; then
	echo "waybar-restart: no config for layout=$LAYOUT position=$POSITION," \
		"falling back to full/top" >&2
	CONFIG="$WAYBAR_DIR/config-full-top.jsonc"
fi

# stderr is KEPT. waybar catches any exception thrown by a module's update()
# and logs it with spdlog::error, then leaves that module's label at its last
# value — so a module freezes while its CSS classes keep tracking reality, and
# the one line naming the cause went to /dev/null. That is what made the
# battery module reading 81% against a real 27% undiagnosable on 2026-08-08 and
# again on 08-09. One generation is kept so restarting the bar before reading
# the log does not destroy the evidence. stdout stays discarded: 0.15.0 has a
# stray puts() in Battery::update() that would otherwise spam a line every
# `interval`.
mkdir -p "$STATE_DIR"
LOG="$STATE_DIR/waybar.log"
[ -f "$LOG" ] && mv -f "$LOG" "$LOG.1"

pkill waybar
sleep 0.1
nohup waybar -c "$CONFIG" -s "$STYLE" >/dev/null 2>"$LOG" &
