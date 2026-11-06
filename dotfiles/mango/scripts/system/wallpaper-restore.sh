#!/usr/bin/env bash
# Starts the awww daemon and re-applies the saved wallpaper.
#
# Called from mango/universal/autostart.conf. Without this the desktop comes up
# with no wallpaper at all: awww-daemon does not survive a session, and
# set-wallpaper.sh is only ever run by hand.
#
# Note the binary is `awww`, not `swww`: nixpkgs renamed the package to the fork
# already in use here. See nixos/modules/system/desktop.nix.

# Moved out of the config tree on 2026-07-30, same reasoning as runtime state:
# ~/.config/mango is now a read-only store path, so a 4.6 MB PNG cannot live
# there — and it never should have, being user data rather than configuration.
WALLPAPER="${XDG_DATA_HOME:-$HOME/.local/share}/mango/wallpaper.png"

# Not in any repo, so a fresh clone has no wallpaper to restore. Nothing to do,
# and not an error.
[ -f "$WALLPAPER" ] || exit 0

# Match comm with the wrapper's leading dot, not the command line: `-x` misses
# `.awww-daemon-wr`, and `-f` would match this script's own guard line.
pgrep '^\.?awww-daemon' >/dev/null || awww-daemon &

# `awww img` fails until the daemon has bound its socket, so poll rather than
# guessing at a sleep. ~4s of headroom; it normally binds well inside 1s.
for _ in $(seq 1 20); do
	awww query >/dev/null 2>&1 && break
	sleep 0.2
done

exec awww img "$WALLPAPER" --transition-type wipe --transition-duration 1
