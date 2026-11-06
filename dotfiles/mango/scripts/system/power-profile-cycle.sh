#!/usr/bin/env bash
# Left-click toggles balanced <-> performance. Fanless is right-click only.
#
# Rewritten 2026-08-12. This wrote /sys/firmware/acpi/platform_profile, which
# moved a thinkpad_acpi dytc hint and nothing else: governor, epp, min freq,
# max freq and boost were byte-identical across all three settings, so the
# toggle changed the bar and not the machine. TLP owns those, and TLP 1.9
# carries a third profile (sav, `tlp power-saver`) beyond its AC/BAT split.
# docs/adr/0017.
#
# `power-mode` is the root wrapper from modules/system/power.nix -- it runs tlp
# and pins the iGPU, which tlp cannot do for sav on its own. wheel may run it
# Nopasswd; nothing else here needs root.
#
# Pass a profile to set it directly. `fanless` is the name the bar and the docs
# use; `power-saver` is TLP's own verb and both are accepted, because the error
# for a wrong one is a notification rather than anything visible in the bar:
#
#   power-profile-cycle.sh fanless
#   power-profile-cycle.sh toggle-fanless   <- waybar right-click

PWRFILE=/run/tlp/last_pwr

fail() {
	notify-send -u critical "Power profile" "$1" 2>/dev/null
	echo "$1" >&2
	exit 1
}

# First field: PP_PRF=0 PP_BAL=1 PP_SAV=2.
read -r pp _ <"$PWRFILE" 2>/dev/null || fail "TLP is not running -- $PWRFILE is unreadable"

# What TLP would pick for the current supply. Leaving fanless has to name a
# profile explicitly: TLP_AUTO_SWITCH=2 holds power-saver across a charger
# change on purpose, so nothing reverts it on its own.
if [ "$(cat /sys/class/power_supply/A*/online 2>/dev/null || echo 0)" = 1 ]; then
	auto=performance
else
	auto=balanced
fi

case "${1:-}" in
# The two everyday modes only. Fanless is deliberately not on this path: it
# caps every core at 418 MHz, which is far too large a penalty to land on by
# clicking one time too many. Right-click is the only way in. From fanless,
# a left-click exits to balanced rather than doing nothing.
"")
	case "$pp" in
	1) next=performance ;;
	*) next=balanced ;;
	esac
	;;
# A right-click that only ever sets fanless is a dead end -- there is no way
# back out of it without cycling through the other two.
toggle-fanless)
	if [ "$pp" = 2 ]; then next="$auto"; else next=power-saver; fi
	;;
fanless) next=power-saver ;;
*) next="$1" ;;
esac

# Not `|| fail` on a bare run: sudo -n prints its own refusal to stderr, and
# swallowing it is how the previous version of this script looked healthy while
# doing nothing.
if ! err=$(sudo -n power-mode "$next" 2>&1); then
	fail "could not switch to $next: ${err:-no output}"
fi

# TLP rewrites last_pwr as part of the switch; repaint from it rather than
# assuming the write landed.
read -r now _ <"$PWRFILE" 2>/dev/null
case "$next:$now" in
performance:0 | balanced:1 | power-saver:2) ;;
*) fail "asked for $next, TLP reports profile code ${now:-none}" ;;
esac

# custom/power-profile declares `signal = 11` and polls every 30 s. `|| true`
# keeps this off the script's exit status: the switch landed and was verified two
# lines above, and with no bar running the pkill matches nothing. docs/adr/0056.
pkill -RTMIN+11 waybar 2>/dev/null || true
