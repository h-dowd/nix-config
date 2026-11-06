#!/usr/bin/env bash
# Usage: night-mode.sh <toggle|menu|status>
#
# Drives the wlsunset *user service* rather than the wlsunset process. Only one
# Wayland client can hold a gamma control, so the old pkill-and-respawn fought
# the service and lost ("gamma control of output eDP-1 failed"). The unit is
# declared in nixos/modules/home/default.nix; its ExecStart
# (../system/night-light-run.sh) reads the temperature written here.

. "$HOME/.config/mango/scripts/lib.sh"

UNIT=wlsunset.service
TEMP_FILE="$STATE_DIR/night-temp"
DEFAULT_TEMP=4000
DAY_TEMP="${NIGHT_DAY_TEMP:-6500}"

is_on() {
	systemctl --user is-active --quiet "$UNIT"
}

# Is the screen warm, which is not the same as the unit running. In `auto` before
# sunset the unit runs and the screen is at the day temperature, and that is the
# case the click has to act on. docs/adr/0055.
is_warming() {
	is_on || return 1
	[ "$(state night-mode auto)" = "manual" ] && return 0
	local cur
	cur=$(current_temp)
	[ -n "$cur" ] && [ "$cur" -lt "$DAY_TEMP" ]
}

# The bar push, as weather.sh has it. custom/night-mode declares `signal = 9`
# and its interval is `once`, so without this the module ran at bar start and
# never again: a toggle changed the screen and left the bar stale.
#
# `|| true` because with no bar running the pkill matches nothing. Plain `waybar`, not `bin/waybar` — nixpkgs wraps it so `comm`
# is `.waybar-wrapped`, and it is invoked bare so its cmdline carries no path.
# docs/adr/0054.
push_bar() {
	pkill -RTMIN+9 waybar 2>/dev/null || true
}

# The click is a manual override. It used to start and stop the unit, so in
# `auto` before sunset clicking "on" started a schedule that would do nothing for
# hours, changing neither the screen nor the bar. Warm goes off; anything else
# warms now, by switching to `manual`. The menu's Auto row hands scheduling back.
# docs/adr/0055.
do_toggle() {
	if is_warming; then
		systemctl --user stop "$UNIT"
	else
		state_write night-mode manual
		systemctl --user restart "$UNIT"
	fi
	push_bar
}

# Picking a temperature means now, not after sunset: the menu used to offer only
# the night value of a schedule, so choosing 2700K in daylight changed nothing
# visible. A temperature is a manual hold.
#
# Auto is a toggle row that reports its own state, because it is the only way
# back to scheduling once a click or a temperature has overridden it.
# docs/adr/0055.
do_menu() {
	MODE=$(state night-mode auto)
	TEMP=$(cat "$TEMP_FILE" 2>/dev/null || echo "$DEFAULT_TEMP")

	if [ "$MODE" = "auto" ]; then
		AUTO_ROW="  Auto   on · follows sunset"
	else
		AUTO_ROW="  Auto   off · holding ${TEMP}K"
	fi

	CHOICE=$(printf '%s\n' \
		"$AUTO_ROW" \
		"  2700K   Candlelight" \
		"  3000K   Warm" \
		"  3500K   Evening" \
		"  4000K   Soft white" \
		"  4500K   Neutral" \
		"  Off" |
		rofi_menu 20 -no-custom -p "Night mode")

	[ -z "$CHOICE" ] && exit 0

	case "$CHOICE" in
	*Off*)
		systemctl --user stop "$UNIT"
		push_bar
		exit 0
		;;
	*Auto*)
		# Flip it. `Auto off` means hold the temperature the row just named.
		if [ "$MODE" = "auto" ]; then
			state_write night-mode manual
		else
			state_write night-mode auto
		fi
		;;
	*)
		PICK=$(echo "$CHOICE" | grep -oE '[0-9]+K' | tr -d 'K')
		[ -z "$PICK" ] && exit 0
		state_write night-temp "$PICK"
		state_write night-mode manual
		;;
	esac

	# restart, not reload: wlsunset only reads its temperature from argv, and
	# `restart` starts a stopped unit, so this is also how the menu turns it on.
	systemctl --user restart "$UNIT"
	push_bar
}

# The temperature wlsunset LAST APPLIED, which is the only reading available:
# it has no IPC and takes its schedule from argv, so its own log is the source of
# truth. Empty if the unit has not logged one yet.
current_temp() {
	journalctl --user -u "$UNIT" --no-pager -n 200 2>/dev/null |
		sed -n 's/.*setting temperature to \([0-9]*\) K.*/\1/p' | tail -1
}

# Sunset, out of the same log line wlsunset prints on every start:
#   calculated sun trajectory: dawn 05:42, sunrise 06:44, sunset 20:09, dusk 21:11
sunset_at() {
	journalctl --user -u "$UNIT" --no-pager -n 200 2>/dev/null |
		sed -n 's/.*sun trajectory:.* sunset \([0-9][0-9]:[0-9][0-9]\),.*/\1/p' | tail -1
}

# Four readings over three classes. "The schedule is enabled", "a colour is held"
# and "the screen is warmed" are different facts, and this reported only the
# first: at noon with the unit running it said `on` while the screen sat at
# 6500 K.
#
# The label is the moon alone. It briefly carried the sunset time so that
# enabling night light in daylight produced a visible change; `manual` answers
# that directly, because the moon lights when the screen is warm. The tooltip
# carries the schedule. docs/adr/0055.
do_status() {
	# nf-md-weather-night, as a `$'\U...'` escape like the menus use. It was
	# `printf '\xef\x86\x86'` — Font Awesome's moon, U+F186 — which survived
	# docs/adr/0051's one-glyph-pack pass because that check reads the generated
	# configs and cannot see a glyph a script prints. docs/adr/0054.
	MOON=$'\U000F0594'
	if ! is_on; then
		printf '{"text":"%s","class":"off","tooltip":"Night light off"}\n' "$MOON"
		return
	fi

	TEMP=$(cat "$TEMP_FILE" 2>/dev/null || echo "$DEFAULT_TEMP")
	CUR=$(current_temp)
	DAY="${NIGHT_DAY_TEMP:-6500}"

	MODE=$(state night-mode auto)

	if [ "$MODE" = "manual" ]; then
		printf '{"text":"%s","class":"on","tooltip":"Night light held at %sK"}\n' "$MOON" "$TEMP"
	elif [ -z "$CUR" ]; then
		# Running, but it has logged nothing yet — say so rather than guess.
		printf '{"text":"%s","class":"on","tooltip":"Night light auto · %sK at night"}\n' "$MOON" "$TEMP"
	elif [ "$CUR" -ge "$DAY" ]; then
		SUNSET=$(sunset_at)
		printf '{"text":"%s","class":"armed","tooltip":"Night light auto · warms to %sK at sunset%s"}\n' \
			"$MOON" "$TEMP" "${SUNSET:+ ($SUNSET)}"
	else
		printf '{"text":"%s","class":"on","tooltip":"Night light auto · %sK now"}\n' "$MOON" "$CUR"
	fi
}

case "$1" in
toggle) do_toggle ;;
menu) do_menu ;;
status) do_status ;;
*)
	echo "Usage: $0 <toggle|menu|status>"
	exit 1
	;;
esac
