#!/usr/bin/env bash
# Shared definitions for the mango scripts. Source it, don't run it:
#
#   . "$HOME/.config/mango/scripts/lib.sh"
#
# One definition of the state directory and each default, because a reader and
# a writer that disagree fail silently: the old mode switch went one-way on
# 2026-07-31 that way, with nothing logged.

# shellcheck shell=bash
# SC2034: these are consumed by the scripts that source this file, not here.
# shellcheck disable=SC2034
MANGO_DIR="$HOME/.config/mango"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mango"
# shellcheck disable=SC2034
WAYBAR_DIR="$MANGO_DIR/waybar"

# Read a state file, or echo the default if it is missing or empty. Every
# reader wants exactly this, and the defaults must agree across scripts.
state() {
	local file="$STATE_DIR/$1" fallback="$2" value
	value=$(cat "$file" 2>/dev/null) || true
	[ -n "$value" ] && printf '%s\n' "$value" || printf '%s\n' "$fallback"
}

state_write() {
	mkdir -p "$STATE_DIR"
	printf '%s\n' "$2" >"$STATE_DIR/$1"
}

# The two switches, with their defaults in one place.
bar_layout() { state bar-layout full; }    # full | focus | minimal
bar_position() { state bar-position top; } # top | bottom

# Run `rofi -dmenu` sized to its own input. Entries on stdin, the choice on
# stdout, `$1` the ceiling, everything after it passed through to rofi.
#
# `-theme-str`, not `-l`. On rofi 2.0 the theme overrides the command line, so
# the `-l` menus passed here was accepted and ignored: every menu rendered
# `lines: 12` tall whatever it held — a two-entry picker with ten blank rows
# below it, and the control centre paging silently the moment it grew past
# twelve. `dynamic: true` does not fix that; it governs resize while filtering,
# not fit-to-contents. docs/gotchas.md -> rofi.
#
# The ceiling is per menu and always explicit. A fixed picker wants no cap worth
# hitting; a list that comes from the machine — access points, paired devices,
# the clipboard — must not grow to the height of the screen.
rofi_menu() {
	local max=$1 entries n
	shift
	entries=$(cat)
	# `grep -c ''` counts a final line with no newline, which `wc -l` does not.
	n=$(printf '%s\n' "$entries" | grep -c '')
	if [ "$n" -gt "$max" ]; then n=$max; fi
	# Not zero: rofi draws the prompt and nothing else, which reads as a menu
	# that failed to load rather than one with nothing to offer.
	if [ "$n" -lt 1 ]; then n=1; fi
	# `-i` as well as `case-sensitive: false` in config.rasi: the file is what
	# actually decides on rofi 2.0, and this is the half a reader of a menu
	# script can see.
	printf '%s\n' "$entries" | rofi -dmenu -i -theme-str "listview { lines: $n; }" "$@"
}
