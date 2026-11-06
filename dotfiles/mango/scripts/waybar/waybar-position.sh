#!/usr/bin/env bash
# Move the waybar between the top and bottom screen edge.
#
# Bound to ⌥⇧/ , alongside ⌥/ (waybar layout). That one opens a
# rofi picker over three options; this one is a straight toggle, because with
# exactly two positions a menu is more keystrokes than the thing it selects.
#
# An explicit argument is still accepted (`waybar-position.sh bottom`) so the
# position can be forced from a script without knowing the current value.
#
# This script owns nothing but the state file. Selecting the matching config —
# waybar has no --position flag, so each position is a separate generated file
# — is waybar-restart.sh's job, so that every other caller of it (login
# autostart, layout switch, config reload) lands on the same
# position without having to know this feature exists.

set -u

. "$HOME/.config/mango/scripts/lib.sh"

current=$(bar_position)

case "${1:-}" in
top | bottom)
	next="$1"
	;;
"")
	if [ "$current" = "bottom" ]; then next="top"; else next="bottom"; fi
	;;
*)
	echo "usage: ${0##*/} [top|bottom]" >&2
	exit 1
	;;
esac

state_write bar-position "$next"

exec "$MANGO_DIR/scripts/waybar/waybar-restart.sh"
