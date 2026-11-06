#!/usr/bin/env bash
# One key, one action. Every shell.sh row is reached by a bind, and
# checks/static.sh asserts both directions.
set -u

. "$HOME/.config/mango/scripts/lib.sh"

# Functions, not strings: `clipboard` is a pipeline and
# needs a shell, and quoting a command through a variable does not survive it.
# rofi, not fsel-in-foot (docs/adr/0043). Fuzzy matching, fzf sorting and icons
# on the command line, not in config.rasi: those are global, and the hand-built
# menus below want rofi's default matching and already carry their glyphs in the
# entry string — a global `show-icons` would buy them a per-row theme lookup that
# finds nothing. Command line beats config.rasi for all three, unlike `-l`, which
# the theme overrides. docs/gotchas.md -> rofi.
do_launcher() { rofi -show drun -matching fuzzy -sort -sorting-method fzf -show-icons; }
do_lock() { lockscreen -f; }
# 12: cliphist keeps hundreds of entries and this is the menu that would fill
# the screen. Filtering is the way in, as with the access-point list.
do_clipboard() { cliphist list | rofi_menu 12 -no-custom -p "clipboard" | cliphist decode | wl-copy; }
do_emoji() { rofi -show emoji; }
do_network() { "$MANGO_DIR/scripts/menus/network-menu.sh"; }
do_bluetooth() { "$MANGO_DIR/scripts/menus/bluetooth-menu.sh"; }
do_power() { "$MANGO_DIR/scripts/menus/power-menu.sh"; }
# `-sw` on the two that act: swaync-client waits for the daemon by default, so a
# key pressed before it is up would hang rather than fail. `-t` is deliberately
# without it — opening the panel is worth a short wait.
# swaync's own panel is the history; swaync-client offers no list.
do_notify() { swaync-client -t; }
do_notify_clear() { swaync-client -C -sw; }
do_dnd() { swaync-client -d -sw; }
# The "configure the bar" keys.
do_bar_settings() { "$MANGO_DIR/scripts/waybar/waybar-layout.sh"; }
do_bar_toggle() { "$MANGO_DIR/scripts/waybar/waybar-position.sh"; }
# docs/adr/0031.
do_keep_awake() { "$MANGO_DIR/scripts/system/idle-inhibit.sh" toggle; }
# A rofi menu that re-renders after each action. docs/adr/0033.
do_control_center() { "$MANGO_DIR/scripts/menus/control-center.sh"; }
# docs/adr/0058.
do_calendar() { "$MANGO_DIR/scripts/menus/calendar.sh"; }

case "${1:-}" in
launcher)
	do_launcher
	;;
lock)
	do_lock
	;;
clipboard)
	do_clipboard
	;;
emoji)
	do_emoji
	;;
network)
	do_network
	;;
bluetooth)
	do_bluetooth
	;;
power)
	do_power
	;;
notify)
	do_notify
	;;
notify-clear)
	do_notify_clear
	;;
dnd)
	do_dnd
	;;
settings)
	do_bar_settings
	;;
bar)
	do_bar_toggle
	;;
control-center)
	do_control_center
	;;
calendar)
	do_calendar
	;;
keep-awake)
	do_keep_awake
	;;
*)
	echo "usage: ${0##*/} <action> — see the case table in this file" >&2
	exit 1
	;;
esac
