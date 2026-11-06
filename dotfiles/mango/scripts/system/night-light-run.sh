#!/usr/bin/env bash
# ExecStart for the wlsunset user service (nixos/modules/home/default.nix).
#
# wlsunset has no runtime IPC — the only way to change temperature is to
# restart it with new arguments. So the *service* owns the process (geo
# scheduling, lifecycle, survives login) and this wrapper reads the chosen
# strength from a state file at start. night-mode.sh writes that file and
# restarts the unit, which is what makes the waybar temperature picker work
# without the script ever owning wlsunset itself.
#
# Location and day temperature come from the unit's Environment=, so they stay
# declared in Nix; only the user-tunable night temperature lives in state.

#
# Sourcing lib.sh is safe from inside the unit: it only defines things, and the
# unit's PATH (bash, coreutils, wlsunset) covers everything it runs at source
# time.
. "$HOME/.config/mango/scripts/lib.sh"

DEFAULT_NIGHT_TEMP=4000

LAT="${NIGHT_LAT:-53.35}"
LONG="${NIGHT_LONG:--6.26}"
DAY_TEMP="${NIGHT_DAY_TEMP:-6500}"

NIGHT_TEMP=$(state night-temp "$DEFAULT_NIGHT_TEMP")
# Guard the state file: a stray value would make wlsunset exit and the unit
# restart-loop. Must be numeric and no warmer-than-day.
if ! [[ $NIGHT_TEMP =~ ^[0-9]+$ ]] || [ "$NIGHT_TEMP" -lt 1000 ] || [ "$NIGHT_TEMP" -gt "$DAY_TEMP" ]; then
	NIGHT_TEMP=$DEFAULT_NIGHT_TEMP
fi

# Two modes. `auto` is the schedule: day temperature until sunset, night
# temperature after. `manual` holds one colour all day, which wlsunset has no
# flag for, so it is a one-kelvin spread — `-T x -t x` exits with "high temp (x)
# must be higher than low (x)". One kelvin is not visible, so day and night are
# the same colour and the sun's position cannot move it. docs/adr/0055.
if [ "$(state night-mode auto)" = "manual" ]; then
	exec wlsunset -l "$LAT" -L "$LONG" -T "$((NIGHT_TEMP + 1))" -t "$NIGHT_TEMP"
fi

exec wlsunset -l "$LAT" -L "$LONG" -T "$DAY_TEMP" -t "$NIGHT_TEMP"
