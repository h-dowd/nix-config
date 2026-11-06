#!/usr/bin/env bash
# Kde Connect phone status as waybar JSON, and the one place the device ID is
# written. `ring` is a verb here rather than a `kdeconnect-cli -d <id> --ring`
# in waybar.nix's on-click, because that spelled the ID a second time and the
# control-centre row would have made it a third — docs/adr/0005, one owner per
# fact. Bare invocation is `status`.

DEVICE="ca2da407b0d74e098414a3a0d76b1502"
NAME="Galaxy S22+"
DBUS_SVC="org.kde.kdeconnect"
DBUS_DEV="/modules/kdeconnect/devices/$DEVICE"

# `comm`, not `-x` and not `-f`: nixpkgs wraps the binary so `comm` is
# `.kdeconnectd-wrapped`, and `-f` would match this script's own command line.
# CLAUDE.md -> Writing shell here.
daemon_up() { pgrep '^\.?kdeconnectd' >/dev/null 2>&1; }

reachable() {
	[ "$(qdbus "$DBUS_SVC" "$DBUS_DEV" org.kde.kdeconnect.device.isReachable \
		2>/dev/null)" = "true" ]
}

do_status() {
	if ! daemon_up; then
		echo '{"text":"","tooltip":"KDE Connect not running","class":"offline"}'
		return
	fi

	# Empty text, so waybar renders nothing: an unreachable phone is this
	# module's resting state. gotchas.md -> Waybar.
	if ! reachable; then
		printf '{"text":"","tooltip":"%s (offline)","class":"disconnected"}\n' "$NAME"
		return
	fi

	local CHARGE CHARGING ICON CLASS
	CHARGE=$(qdbus "$DBUS_SVC" "$DBUS_DEV/battery" charge 2>/dev/null)
	CHARGING=$(qdbus "$DBUS_SVC" "$DBUS_DEV/battery" isCharging 2>/dev/null)

	if [ -z "$CHARGE" ]; then
		printf '{"text":"","tooltip":"%s","class":"connected"}\n' "$NAME"
		return
	fi

	# nf-md-battery_*, as escapes rather than literals so checks/static.sh reads
	# the codepoint rather than a raw byte sequence. docs/adr/0057.
	if [ "$CHARGING" = "true" ]; then
		ICON=$'\U000F0084'
	elif [ "$CHARGE" -ge 90 ]; then
		ICON=$'\U000F0082'
	elif [ "$CHARGE" -ge 80 ]; then
		ICON=$'\U000F0081'
	elif [ "$CHARGE" -ge 70 ]; then
		ICON=$'\U000F0080'
	elif [ "$CHARGE" -ge 60 ]; then
		ICON=$'\U000F007F'
	elif [ "$CHARGE" -ge 50 ]; then
		ICON=$'\U000F007E'
	elif [ "$CHARGE" -ge 40 ]; then
		ICON=$'\U000F007D'
	elif [ "$CHARGE" -ge 20 ]; then
		ICON=$'\U000F007C'
	elif [ "$CHARGE" -ge 10 ]; then
		ICON=$'\U000F007B'
	else
		ICON=$'\U000F008E'
	fi

	CLASS="connected"
	[ "$CHARGE" -le 15 ] && CLASS="critical"
	[ "$CHARGE" -le 30 ] && [ "$CLASS" != "critical" ] && CLASS="warning"

	printf '{"text":" %s %s%%","tooltip":"%s\\nBattery: %s%%","class":"%s"}\n' \
		"$ICON" "$CHARGE" "$NAME" "$CHARGE" "$CLASS"
}

# Rings the phone, or says why it cannot. Both callers — the bar's on-click and
# the control centre's row — used to get silence when the phone was away, which
# is indistinguishable from the ring having failed.
do_ring() {
	if ! daemon_up; then
		notify-send "Phone" "KDE Connect is not running"
		return 1
	fi
	if ! reachable; then
		notify-send "Phone" "$NAME is not connected"
		return 1
	fi
	kdeconnect-cli -d "$DEVICE" --ring
}

case "${1:-status}" in
status) do_status ;;
ring) do_ring ;;
*)
	echo "Usage: ${0##*/} <status|ring>"
	exit 1
	;;
esac
