#!/usr/bin/env bash
# WireGuard VPN status/toggle. Emits waybar's `{text,class,tooltip}` JSON.

VPN_STATE="/run/user/$(id -u)/mango-vpn"
DEFAULT_VPN="homelab"

# TWO SHAPES, not one shape in two colours. Both branches printed shield_check
# until 2026-08-28, so a VPN that was down drew a "protected" badge and only the
# grey said otherwise — the same failure the workspace tags were fixed for, where
# shape has to hold what hue cannot. docs/adr/0057.
#
# Escapes rather than raw literals, so checks/static.sh can read the codepoint.
SHIELD_ON=$'\U000F0565'  # nf-md-shield_check
SHIELD_OFF=$'\U000F099E' # nf-md-shield_off

case "$1" in
toggle)
	active=$(nmcli -t -f NAME,TYPE,STATE con show --active 2>/dev/null |
		awk -F: '($2=="wireguard"||$2=="vpn") && $3=="activated"{print $1; exit}')
	if [ -n "$active" ]; then
		nmcli con down "$active" &>/dev/null
	else
		target=$(cat "$VPN_STATE" 2>/dev/null)
		[ -z "$target" ] && target="$DEFAULT_VPN"
		nmcli con up "$target" &>/dev/null
	fi
	# custom/vpn declares `signal = 10` and polls every 5 s. `|| true` because
	# with no bar running the pkill matches nothing.
	# docs/adr/0056.
	pkill -RTMIN+10 waybar 2>/dev/null || true
	;;
*)
	active=$(nmcli -t -f NAME,TYPE,STATE con show --active 2>/dev/null |
		awk -F: '($2=="wireguard"||$2=="vpn") && $3=="activated"{print $1; exit}')
	if [ -n "$active" ]; then
		printf '{"text":"%s %s","class":"connected","tooltip":"VPN: %s — click to disconnect"}\n' \
			"$SHIELD_ON" "$active" "$active"
	else
		target=$(cat "$VPN_STATE" 2>/dev/null)
		[ -z "$target" ] && target="$DEFAULT_VPN"
		printf '{"text":"%s","class":"off","tooltip":"VPN: off — click to connect %s"}\n' \
			"$SHIELD_OFF" "$target"
	fi
	;;
esac
