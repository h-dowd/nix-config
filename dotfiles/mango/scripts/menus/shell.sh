#!/usr/bin/env bash
# One key, one action, and whichever shell owns that job in the current mode.
# Generalises notify.sh, which did exactly this for the notification panel from
# 2026-08-14 and is now this file's `notify` row. docs/adr/0023.
#
# Why a script and not a per-mode bind= override. mango's binds append and the
# dispatcher stops at the first match (src/mango.c: "only match the first
# keybind"), so a mode conf sourced ahead of universal/bind.conf really would
# override it — but mango also prints a `[warning] Key binding conflict` naming
# both files and lines for every duplicate, and thirteen of those on every start
# is how a real conflict warning stops being read. One bind, one script.
#
# The failure this guards. `noctalia-shell ipc call <target> <fn>` prints
# "Target not found." or "Function not found." and exits 0 — the same shape as
# the dwl-era `mmsg -s -d` that broke five scripts silently. A successful void
# call prints nothing, so output is the signal and the exit status is worthless.
# checks/static.sh asserts every pair below against the shipped shell; this is
# the runtime backstop for the case the check cannot see.
set -u

. "$HOME/.config/mango/scripts/lib.sh"

# The tiling half. Functions, not strings: `clipboard` is a pipeline and
# needs a shell, and quoting a command through a variable does not survive it.
# rofi, not fsel-in-foot (docs/adr/0043). Fuzzy matching, fzf sorting and icons
# on the command line, not in config.rasi: those are global, and the hand-built
# menus below want rofi's default matching and already carry their glyphs in the
# entry string — a global `show-icons` would buy them a per-row theme lookup that
# finds nothing. Command line beats config.rasi for all three, unlike `-l`, which
# the theme overrides. docs/gotchas.md -> rofi.
fb_launcher() { rofi -show drun -matching fuzzy -sort -sorting-method fzf -show-icons; }
fb_lock() { lockscreen -f; }
# 12: cliphist keeps hundreds of entries and this is the menu that would fill
# the screen. Filtering is the way in, as with the access-point list.
fb_clipboard() { cliphist list | rofi_menu 12 -no-custom -p "clipboard" | cliphist decode | wl-copy; }
fb_emoji() { rofi -show emoji; }
fb_network() { "$MANGO_DIR/scripts/menus/network-menu.sh"; }
fb_bluetooth() { "$MANGO_DIR/scripts/menus/bluetooth-menu.sh"; }
fb_power() { "$MANGO_DIR/scripts/menus/power-menu.sh"; }
# SWAYNC AGAIN. It was the daemon here until wayle briefly took
# org.freedesktop.Notifications to wayle, and it is the daemon here again —
# tiling/autostart.conf starts it once wayle is stopped. docs/adr/0051.
#
# `-sw` on the two that act: swaync-client waits for the daemon by default, so a
# key pressed before it is up would hang rather than fail. `-t` is deliberately
# without it — opening the panel is worth a short wait.
#
# THE ROFI HISTORY LIST IS GONE WITH WAYLE. menus/notifications.sh read
# com.wayle.Notifications1, and swaync-client offers no equivalent: count, dnd
# and toggle, but no list. swaync's own panel is the history now, which is what
# `-t` opens and what this key did before wayle.
fb_notify() { swaync-client -t; }
fb_notify_clear() { swaync-client -C -sw; }
fb_dnd() { swaync-client -d -sw; }
# The two keys that used to refuse in noctalia mode. They are the "configure the
# bar" keys, and each mode's bar is configured by its own thing.
fb_bar_settings() { "$MANGO_DIR/scripts/waybar/waybar-layout.sh"; }
fb_bar_toggle() { "$MANGO_DIR/scripts/waybar/waybar-position.sh"; }
# Keep-awake used to be noctalia-only, because the only inhibitor outside it was
# a bool inside the waybar process with no way in from a key. There is a unit
# now, so this key works in both modes. docs/adr/0031.
fb_keep_awake() { "$MANGO_DIR/scripts/system/idle-inhibit.sh" toggle; }
# The control centre stopped being noctalia-only on 2026-08-19, the same way
# keep-awake did: not by reimplementing the panel, but because every toggle it
# shows already had an owner here and only the set of them was missing. It is a
# rofi menu that re-renders after each action rather than a resident surface —
# the state model is not shared, so the honest version is one that rebuilds.
# docs/adr/0033.
fb_control_center() { "$MANGO_DIR/scripts/menus/control-center.sh"; }
# The third `fb=none` row to get a fallback, after keep-awake and the control
# centre, and for the same reason: the surface existed in noctalia and nowhere
# else, so the key reported "Only in noctalia mode" in the mode it is used in.
# The clock's tooltip was the tiling answer and could not be navigated.
# docs/adr/0058.
fb_calendar() { "$MANGO_DIR/scripts/menus/calendar.sh"; }

# The table. `ipc` is a noctalia target and function, two words on purpose —
# checks/static.sh reads this block and asserts both halves exist. `fb=none`
# marks an action noctalia alone has; those keys are bound only in
# noctalia/bind.conf, so reaching one from another mode means the two files
# have drifted, and it says so rather than doing nothing.
case "${1:-}" in
launcher)
	ipc="launcher toggle"
	fb=fb_launcher
	;;
lock)
	ipc="lockScreen lock"
	fb=fb_lock
	;;
clipboard)
	ipc="launcher clipboard"
	fb=fb_clipboard
	;;
emoji)
	ipc="launcher emoji"
	fb=fb_emoji
	;;
network)
	ipc="network togglePanel"
	fb=fb_network
	;;
bluetooth)
	ipc="bluetooth togglePanel"
	fb=fb_bluetooth
	;;
power)
	ipc="sessionMenu toggle"
	fb=fb_power
	;;
notify)
	ipc="notifications toggleHistory"
	fb=fb_notify
	;;
notify-clear)
	ipc="notifications clear"
	fb=fb_notify_clear
	;;
dnd)
	ipc="notifications toggleDND"
	fb=fb_dnd
	;;
settings)
	ipc="settings toggle"
	fb=fb_bar_settings
	;;
bar)
	ipc="bar toggle"
	fb=fb_bar_toggle
	;;
control-center)
	ipc="controlCenter toggle"
	fb=fb_control_center
	;;
calendar)
	ipc="calendar toggle"
	fb=fb_calendar
	;;
dock)
	ipc="dock toggle"
	fb=none
	;;
# Keep-awake. Both halves are a real Wayland inhibitor over
# zwp_idle_inhibit_manager_v1, which mango advertises — quickshell's own
# IdleInhibitor in noctalia, wlinhibit.service elsewhere — so either way it
# suppresses swayidle's ladder, not just noctalia's (pinned-off) idle service.
# Each shell keeps its own indicator honest that way; one mechanism driving
# both would leave the other's icon lying. docs/adr/0031.
keep-awake)
	ipc="idleInhibitor toggle"
	fb=fb_keep_awake
	;;
*)
	echo "usage: ${0##*/} <action> — see the case table in this file" >&2
	exit 1
	;;
esac

if [ "$(current_mode)" = noctalia ]; then
	# The mode can be noctalia while the shell is down — it crash-loops against
	# a stale WAYLAND_DISPLAY and wedges (docs/gotchas.md → Desktop). Then
	# `ipc call` fails to connect and the key would do nothing at all.
	if ! systemctl --user is-active --quiet noctalia; then
		notify-send -u critical "Noctalia" "$1: the shell is not running"
		exit 1
	fi
	# Unquoted on purpose: $ipc is a target and a function, two arguments.
	# shellcheck disable=SC2086
	out=$(noctalia-shell ipc call $ipc 2>&1)
	if [ -n "$out" ]; then
		notify-send -u critical "Noctalia" "$1: $out"
		exit 1
	fi
	exit 0
fi

if [ "$fb" = none ]; then
	notify-send "$1" "Only in noctalia mode"
	exit 0
fi
"$fb"
