#!/usr/bin/env bash
# The control centre — one menu that shows the state of every toggle, instead of
# ten keys you have to remember and a bar you have to squint at.
#
# Every toggle already had a key and a script; nothing showed the set, or the
# state each one was in. Every fact has a different owner, and this file is a
# reader of those owners, never a second one:
#
#   - five rows take their icon and their state from the waybar module that
#     owns the fact (`night-mode.sh status`, `idle-inhibit.sh status`,
#     `power-profile.sh`, `phone-status.sh status`, `weather.sh read`), parsed
#     out of the JSON those modules already emit. Reproducing the glyph here
#     would be a second owner for it, and the two would drift the first time
#     one changed — docs/adr/0028's failure, one directory over. The ladders
#     behind those glyphs are why it matters: ten battery levels for the phone,
#     thirteen weather glyphs by WMO code and time of day.
#   - the rest read the same command their own menu reads, and nothing here
#     writes state: every action delegates to the script that already owned it.
#
# So a row can only ever be stale, never wrong — it is rebuilt from scratch on
# every open and after every action, which is why the menu re-renders in a loop
# rather than closing. That loop is the feature.
#
# `?` is a state. An unreadable owner renders as `?`, never as "off": "the thing
# is off" and "I could not ask" are the two this repo keeps confusing, and a row
# that quietly reads "off" for a broken module is this codebase's signature bug
# with a nicer font. Every state_* below has that branch, deliberately.
#
# Reached as `shell.sh control-center`. docs/adr/0033.

set -u

. "$HOME/.config/mango/scripts/lib.sh"

# Escapes, not literal glyphs, for the reason power-profile.sh gives at length:
# written literally on 2026-07-31 its icons were lost in transit and every
# branch assigned the empty string, so the module emitted {"text":""} and waybar
# drew nothing. All of these are in Hack Nerd Font — checked with
# `fc-list ':charset=f0f3' family` before they went in; a family that covers
# none of them renders boxes rather than erroring.
#
# ONE PACK, AND THE BAR'S. Twelve of these were nf-fa until 2026-08-28, mixed
# with four nf-md in the same vertical list — and the panel reached by the bar's
# own button gave bluetooth, volume, night mode and the power profile a
# different glyph from the module it mirrors. Each name below says which module
# it echoes; that is the constraint, not decoration. docs/adr/0057.
#
# ICON_ETH is nf-md-ethernet and not nf-fa-network_wired (U+F6FF), which is what
# menus/network-menu.sh reaches for: Hack Nerd Font does not cover U+F6FF, so
# fontconfig falls through to ibm Plex Sans tc and draws a box. Nothing errors.
ICON_WIFI=$'\U000F05A9'     # nf-md-wifi, the bar's own format-wifi glyph
ICON_ETH=$'\U000F0200'      # nf-md-ethernet, waybar's own format-ethernet glyph
ICON_BT=$'\U000F00AF'       # nf-md-bluetooth, as custom/bluetooth wears
ICON_VPN=$'\U000F0498'      # nf-md-shield
ICON_VOL=$'\U000F057E'      # nf-md-volume_high
ICON_MUTE=$'\U000F0581'     # nf-md-volume_off
ICON_MIC=$'\U000F036C'      # nf-md-microphone
ICON_MIC_OFF=$'\U000F036D'  # nf-md-microphone_off
ICON_NIGHT=$'\U000F0594'    # nf-md-weather_night, as night-mode.sh prints
ICON_AWAKE=$'\U000F04B2'    # nf-md-sleep
ICON_POWER=$'\U000F029A'    # nf-md-gauge, as power-profile.sh prints
ICON_BELL=$'\U000F009A'     # nf-md-bell
ICON_BELL_OFF=$'\U000F009B' # nf-md-bell_off
ICON_BAR=$'\U000F035C'      # nf-md-menu
# Only a fallback. When the phone is up, the row's icon is the battery glyph
# custom/phone itself chose — one owner for those ten, as with night/awake/power.
ICON_PHONE=$'\U000F011C' # nf-md-cellphone
# Fallback only — custom/weather picks among thirteen by WMO code and daylight;
# a second copy of that ladder is docs/adr/0028's drift.
ICON_WEATHER=$'\U000F0F2F' # nf-md-weather_cloudy_alert, as weather.sh prints

SEP=$'────────────────────────'

# The one string every "I could not ask" branch prints. Named so the branches
# cannot each invent their own spelling of it.
UNKNOWN='?'

# The rows, in order. `-` is a separator. This list and the label map below are
# the only place a row is declared; checks/static.sh reads this array and
# asserts every id has a label, a state_* and an act_*, because a missing half
# is a bash "command not found" on a stderr nobody reads — the row would render
# and then do nothing at all.
ROWS=(
	network
	bluetooth
	vpn
	volume
	microphone
	-
	night
	awake
	power
	phone
	weather
	-
	dnd
	notify
	bar
)

declare -A LABEL=(
	[network]="Network"
	[bluetooth]="Bluetooth"
	[vpn]="VPN"
	[volume]="Volume"
	[microphone]="Microphone"
	[night]="Night light"
	[awake]="Keep awake"
	[power]="Power profile"
	[phone]="Phone"
	[weather]="Weather"
	[dnd]="Do not disturb"
	[notify]="Notifications"
	[bar]="Bar"
)

# `-l` is computed, and that is the whole point of it being here rather than a
# number. dotfiles/rofi/config.rasi sets `lines: 12` as a shared ceiling — right
# for the clipboard and the ap list, where paging is the honest answer, and
# wrong here: this menu is a set, and a set you have to page through is the
# "nothing showed you the set" problem docs/adr/0033 was written to close,
# rebuilt one layer down. At eleven rows and two separators it rendered 13 and
# paged at 12.
#
# render() prints exactly one line per rows element — separators included, since
# a `-` becomes a sep line — so ${#rows[@]} is the rendered height, and a row
# added later widens the window instead of silently reintroducing page two.
# `dynamic: true` in the theme still shrinks the list to its contents, so this
# is a ceiling being raised for one menu, not a height being forced.
# 24 is a ceiling this menu will not reach — checks/static.sh asserts rows
# stays under it, because growing past it pages again and pages silently.
CC_MAX_LINES=24

# Ctrl+Enter — the modifier on the accept key, so the row's second verb is
# spelled as what it is: the other thing to do with this row.
#
# It is not free, and that is the whole cost of picking it. rofi ships
# `Control+Return` as `kb-accept-custom` ("return what I typed, not what is
# selected"), so binding it without unsetting that first is a startup error
# Dialog where the panel should be. Hence CC_KB_FREE below, and the pair is
# asserted in checks/static.sh — a bind is not a bind until the default holding
# the key lets go. `rofi -list-keybindings` prints the table to check against.
#
# Unsetting costs nothing here and only here: the call passes `-no-custom`, so
# accept-custom had nothing to accept. Today it falls into dmenu.c's
# `only_selected` else-branch, which restarts the view without acting — a key
# that already did nothing and never said so.
#
# On the command line, not in config.rasi: both mean something on this menu
# alone, exactly as `-no-custom` does — and `kb-accept-custom` must keep its
# default in menus/network-menu.sh, where the typed string is the answer. The
# command line wins for a `configuration` setting; it is only the theme that
# overrides it, which is why `lines` is a `-theme-str`. docs/gotchas.md -> rofi.
CC_KB_REFRESH="Control+Return"
CC_KB_FREE="-kb-accept-custom"
# No `-mesg` hint, deliberately. It was here on 2026-08-24 and came straight
# back out: a permanent line of instructions above a list whose whole point is
# that it shows you the state (docs/adr/0033) is the panel explaining itself
# instead of reporting. The keys are in docs/SYSTEM.md §8.

# ── State ─────────────────────────────────────────────────────────────────
#
# Each state_<id> prints "<icon><tab><state>". Two fields because of the three
# rows that take their icon from the module that owns the fact; the renderer
# does not care which kind a row is.

# Pull several fields out of a waybar module's own JSON, in one jq. The three
# module-backed rows want two or three fields each, and a jq per field is three
# processes for one answer — on a menu that re-renders after every action.
#
# Empty rather than `null` on a missing key, and empty on non-JSON (jq exits 5
# and prints nothing), so the callers' `[ -n … ]` guards see the same thing
# however the module failed. That is deliberate: "the module said off" and "the
# module said nothing" must not arrive here looking different, because only the
# second one is allowed to render as anything but a state.
#
# Joined on U+001F, not a tab, and @tsv is gone with it. `IFS=$'\t' read` cannot
# see an empty leading field: tab is IFS *whitespace*, so bash strips it and
# collapses runs of it, and `\toffline` arrives as one field. Every reader here
# then takes the class as its icon and renders `?` for a module that answered
# perfectly — which is exactly the failure this file was written to make
# impossible, hiding inside the helper that was supposed to prevent it. It sat
# here unnoticed because night, awake and power always emit a glyph;
# custom/phone emits an empty text as its resting state, and it bit on the
# first render. U+001F is not whitespace, so empty fields survive.
#
# `gsub` replaces what @tsv used to escape: a tooltip may carry a real newline
# (custom/phone's does), and `read` would stop dead at it.
jfields() {
	jq -r "[$2] | map(. // \"\" | tostring | gsub(\"[\\\\n\\\\t]\"; \" \")) | join(\"\\u001f\")" \
		<<<"$1" 2>/dev/null
}

# Not `nmcli dev wifi`. That is a scan: "by default, nmcli ensures that the
# access point list is no older than 30 seconds and triggers a network scan if
# necessary" (nmcli(1)), and a scan is seconds — 6.4 s measured on the first
# call here, during which the whole menu has not appeared, because this is the
# first row. menus/network-menu.sh carries its cache and its `--warm` verb for
# exactly that reason; this row sidesteps it instead.
#
# `nmcli dev` reads properties and never scans. One call answers the ethernet
# question and the wifi question together, which is also why there is one awk
# rather than two: device, type, state and connection is the whole row.
state_network() {
	local out kind value radio
	out=$(nmcli -t -f DEVICE,TYPE,STATE,CONNECTION dev 2>/dev/null) || {
		printf '%s\t%s' "$ICON_WIFI" "$UNKNOWN"
		return
	}
	# nmcli escapes a colon inside a field, so splitting on `:` mis-parses any
	# row that has one — the paired Bluetooth devices all do, and an SSID may.
	# Hide the escaped ones, split, then put them back.
	IFS=$'\t' read -r kind value < <(awk '
		{
			gsub(/\\:/, "\001")
			n = split($0, f, ":")
			for (i = 1; i <= n; i++) gsub(/\001/, ":", f[i])
			# `connected (externally)` is what loopback reports, and a docked
			# ethernet can too — match the prefix, not the whole word.
			if (f[3] !~ /^connected/) next
			if (f[2] == "ethernet") eth = f[1]
			else if (f[2] == "wifi") wifi = f[4]
		}
		END {
			# Ethernet first: on a dock, "not connected" on the row labelled
			# Network while a cable is up is a lie, and this is the row you
			# would look at to find out why nothing works.
			if (eth != "") print "eth\t" eth
			else if (wifi != "") print "wifi\t" wifi
			else print "none\t"
		}
	' <<<"$out")

	case "$kind" in
	eth) printf '%s\t%s' "$ICON_ETH" "$value" ;;
	wifi) printf '%s\t%s' "$ICON_WIFI" "$value" ;;
	*)
		# Only here is a second call worth making. `dev` cannot tell "radio off"
		# from "on, associated with nothing": both leave the device
		# `unavailable` or `disconnected`, and they are different answers. In
		# the common case — something is connected — this never runs.
		radio=$(nmcli radio wifi 2>/dev/null)
		case "$radio" in
		enabled) printf '%s\t%s' "$ICON_WIFI" "not connected" ;;
		disabled) printf '%s\t%s' "$ICON_WIFI" "off" ;;
		*) printf '%s\t%s' "$ICON_WIFI" "$UNKNOWN" ;;
		esac
		;;
	esac
}

state_bluetooth() {
	local power n
	power=$(bluetoothctl show 2>/dev/null | awk '/Powered:/ { print $2; exit }')
	case "$power" in
	yes)
		n=$(bluetoothctl devices Connected 2>/dev/null | grep -c '^Device ')
		if [ "${n:-0}" -gt 0 ]; then
			printf '%s\t%s' "$ICON_BT" "$n connected"
		else
			printf '%s\t%s' "$ICON_BT" "on"
		fi
		;;
	no) printf '%s\t%s' "$ICON_BT" "off" ;;
	*) printf '%s\t%s' "$ICON_BT" "$UNKNOWN" ;;
	esac
}

state_vpn() {
	local out names
	# Exit status, not emptiness: no VPN up and nmcli not answering both print
	# nothing, and only one of them is "off".
	out=$(nmcli -t -f NAME,TYPE con show --active 2>/dev/null) || {
		printf '%s\t%s' "$ICON_VPN" "$UNKNOWN"
		return
	}
	# Same field handling as menus/vpn-menu.sh, which owns this list.
	names=$(awk -F: '$2 == "vpn" || $2 == "wireguard" { gsub(/\\:/, ":", $1); print $1 }' \
		<<<"$out" | paste -sd, -)
	printf '%s\t%s' "$ICON_VPN" "${names:-off}"
}

state_volume() {
	local info vol
	info=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null) || {
		printf '%s\t%s' "$ICON_VOL" "$UNKNOWN"
		return
	}
	# "Volume: 0.87", or "Volume: 1.20 [muted]" — the shape volume-menu.sh reads.
	vol=$(awk '{ printf "%d", $2 * 100 }' <<<"$info")
	if [[ $info == *"[MUTED]"* ]]; then
		printf '%s\t%s' "$ICON_MUTE" "muted (${vol}%)"
	else
		printf '%s\t%s' "$ICON_VOL" "${vol}%"
	fi
}

# The row that paid for the rest. Every other fact here was already on the bar
# or under a key; mic mute state was on nothing but the ThinkPad led, driven by
# the `micmute-led` user unit (modules/system/audio.nix) — so a dead daemon and
# a live microphone looked the same from the outside, on the one fact whose
# failure mode is being heard when you thought you were not. waybar's
# `{format_source}` now shows it too, and both are readers of PipeWire, which
# owns it — exactly as this row and waybar's pulseaudio module have always both
# read the sink.
#
# Same output shape as the sink, and that is measured rather than assumed:
# checked on 2026-08-19 that a muted source still reports its capture volume, so
# `muted (8%)` is a real reading and not a leftover. Worded like Volume on
# purpose — two adjacent rows that spell one idea two ways make the unfamiliar
# one look broken.
state_microphone() {
	local info vol
	info=$(wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null) || {
		printf '%s\t%s' "$ICON_MIC" "$UNKNOWN"
		return
	}
	vol=$(awk '{ printf "%d", $2 * 100 }' <<<"$info")
	if [[ $info == *"[MUTED]"* ]]; then
		printf '%s\t%s' "$ICON_MIC_OFF" "muted (${vol}%)"
	else
		printf '%s\t%s' "$ICON_MIC" "${vol}%"
	fi
}

state_night() {
	local j icon cls tip temp
	j=$("$MANGO_DIR/scripts/menus/night-mode.sh" status 2>/dev/null)
	IFS=$'\037' read -r icon cls tip < <(jfields "$j" '.text, .class, .tooltip')
	# The module pads its text for the bar; the menu sets its own spacing.
	icon="${icon%"${icon##*[![:space:]]}"}"
	[ -n "$icon" ] || icon=$ICON_NIGHT
	case "$cls" in
	on)
		# The temperature is in the module's tooltip and nowhere else this side
		# of the state file. Read it from there rather than from `state
		# night-temp`, which would put night-mode.sh's DEFAULT_TEMP in a second
		# file — the drift lib.sh exists to foreclose.
		temp=$(grep -oE '[0-9]+K' <<<"$tip" | head -1)
		printf '%s\t%s' "$icon" "${temp:-on}"
		;;
	off) printf '%s\t%s' "$icon" "off" ;;
	*) printf '%s\t%s' "$icon" "$UNKNOWN" ;;
	esac
}

state_awake() {
	local j icon cls
	j=$("$MANGO_DIR/scripts/system/idle-inhibit.sh" status 2>/dev/null)
	IFS=$'\037' read -r icon cls < <(jfields "$j" '.text, .class')
	[ -n "$icon" ] || icon=$ICON_AWAKE
	case "$cls" in
	activated) printf '%s\t%s' "$icon" "on" ;;
	deactivated) printf '%s\t%s' "$icon" "off" ;;
	# Carried through rather than folded into "off", for idle-inhibit.sh's own
	# reason: a restart-limited unit and a deliberately released one look the
	# same otherwise, and only one of them is a problem.
	failed) printf '%s\t%s' "$icon" "FAILED — the idle ladder is live" ;;
	*) printf '%s\t%s' "$icon" "$UNKNOWN" ;;
	esac
}

state_power() {
	local j icon cls
	j=$("$MANGO_DIR/scripts/system/power-profile.sh" 2>/dev/null)
	IFS=$'\037' read -r icon cls < <(jfields "$j" '.text, .class')
	[ -n "$icon" ] || icon=$ICON_POWER
	# `unavailable` and `unknown` are the module's own words for the two ways
	# this can fail, and they are more specific than `?`, so they stand.
	printf '%s\t%s' "$icon" "${cls:-$UNKNOWN}"
}

# The fifth module-backed row, and the one whose `.text` is not a bare glyph:
# custom/phone emits "<battery glyph> <charge>%", so the icon and the number
# arrive in one field and `read` splits them. Taking the glyph from there rather
# than reproducing it is the same rule as night/awake/power, and it matters more
# here — the module picks between ten battery glyphs by charge, and a second
# copy of that ladder would drift on the first edit.
#
# All five of phone-status.sh's classes are handled, enumerated out of the
# script rather than off the one value observed while writing this. `offline`
# and `disconnected` are different answers — the daemon is down, versus the
# daemon is up and the phone is elsewhere — and only the first is a fault, so
# folding them together would hide it.
#
# An empty `.text` is normal here, not a failure: the module renders nothing
# when the phone is away, deliberately (gotchas.md -> Waybar). So the fallback
# icon carries every row that is not a live phone, and `?` stays reserved for
# "the script did not answer at all".
state_phone() {
	local j text cls icon charge
	j=$("$MANGO_DIR/scripts/kdeconnect/phone-status.sh" status 2>/dev/null)
	IFS=$'\037' read -r text cls < <(jfields "$j" '.text, .class')
	# Default IFS: strips the module's leading pad and splits glyph from charge.
	read -r icon charge <<<"$text"
	[ -n "$icon" ] || icon=$ICON_PHONE
	case "$cls" in
	connected | warning | critical)
		# The battery plugin can be absent on a phone that is otherwise up, and
		# the module says so with an empty text and class `connected`.
		printf '%s\t%s' "$icon" "${charge:-connected}"
		;;
	disconnected) printf '%s\t%s' "$icon" "not connected" ;;
	offline) printf '%s\t%s' "$icon" "KDE Connect not running" ;;
	*) printf '%s\t%s' "$icon" "$UNKNOWN" ;;
	esac
}

# The sixth module-backed row, and the only owner here that can be out of date
# rather than merely unreadable — `stale` is a state, not a failure and not `?`.
# docs/adr/0038.
#
# `read`, not `status`: `status` fetches on an expired cache, and this runs
# inside a parallel render. checks/static.sh asserts the verb.
#
# `.alt` carries the phrase as a field — cut out of the tooltip instead it
# rendered "light" for "light drizzle" (gotchas.md -> Waybar).
state_weather() {
	local j text alt cls icon temp
	j=$("$MANGO_DIR/scripts/system/weather.sh" read 2>/dev/null)
	IFS=$'\037' read -r text alt cls < <(jfields "$j" '.text, .alt, .class')
	# "<glyph> 15°C" — same shape as the phone row, and split the same way.
	read -r icon temp <<<"$text"
	[ -n "$icon" ] || icon=$ICON_WEATHER
	case "$cls" in
	# One branch: `alt` already carries the difference. Kept out of `*` all the
	# same — a class weather.sh does not emit is `?`, not a temperature.
	ok | stale) printf '%s\t%s' "$icon" "${temp:-$UNKNOWN}${alt:+, $alt}" ;;
	# The module's own sentence, which says which failure it was — no reading
	# cached, unreachable, or coordinates missing from the generation. More
	# specific than `?`, so it stands, exactly as power's words do.
	error) printf '%s\t%s' "$icon" "${alt:-$UNKNOWN}" ;;
	*) printf '%s\t%s' "$icon" "$UNKNOWN" ;;
	esac
}

# BOTH ROWS READ SWAYNC. `swaync-client` against a daemon nothing started
# prints `NameHasNoOwner` on stderr and EXITS 0, so both rows render `?` and
# both actions do nothing. docs/adr/0047.
#
# `-sw` on both: without it swaync-client WAITS for a daemon that is not there,
# and this menu renders its rows in parallel — one blocking row holds the whole
# panel off the screen. That is the failure state_weather's `read` verb exists
# to avoid, one row over.
state_dnd() {
	case "$(swaync-client -D -sw 2>/dev/null)" in
	true) printf '%s\t%s' "$ICON_BELL_OFF" "on" ;;
	false) printf '%s\t%s' "$ICON_BELL" "off" ;;
	*) printf '%s\t%s' "$ICON_BELL" "$UNKNOWN" ;;
	esac
}

state_notify() {
	local n
	n=$(swaync-client -c -sw 2>/dev/null)
	case "$n" in
	'' | *[!0-9]*) printf '%s\t%s' "$ICON_BELL" "$UNKNOWN" ;;
	0) printf '%s\t%s' "$ICON_BELL" "none waiting" ;;
	1) printf '%s\t%s' "$ICON_BELL" "1 waiting" ;;
	*) printf '%s\t%s' "$ICON_BELL" "$n waiting" ;;
	esac
}

state_bar() {
	# The stored layout is the layout on screen. That was not true until hud left
	#: hud forced its own, so this row had to special-case it or
	# name a bar nobody could see — and `act_bar` still opened a picker whose
	# choice that mode then discarded.
	printf '%s\t%s' "$ICON_BAR" "$(bar_layout), $(bar_position)"
}

# ── Actions ───────────────────────────────────────────────────────────────
#
# Every one delegates. Nothing here toggles anything itself: the script that
# owns a fact is the script that changes it, so the bar, the key and this menu
# cannot end up disagreeing about what a toggle did.
#
# An action that hands the screen to another surface sets `close`; everything
# else falls through to a re-render, which is what makes this feel like a panel
# rather than a key.
close=0

act_network() { "$MANGO_DIR/scripts/menus/network-menu.sh"; }
act_bluetooth() { "$MANGO_DIR/scripts/menus/bluetooth-menu.sh"; }
act_vpn() { "$MANGO_DIR/scripts/menus/vpn-menu.sh"; }
act_volume() { "$MANGO_DIR/scripts/menus/volume-menu.sh"; }
# Character for character what XF86AudioMicMute runs (universal/bind.conf), so
# the key, the led and this row cannot disagree: `micmute-led` watches PipeWire
# rather than the caller, and so needs nothing from either.
act_microphone() { wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle; }
act_night() { "$MANGO_DIR/scripts/menus/night-mode.sh" menu; }
act_awake() { "$MANGO_DIR/scripts/system/idle-inhibit.sh" toggle; }
# Cycles balanced <-> performance, exactly as a left-click on the bar does.
# Fanless is deliberately not reachable from here for power-profile-cycle.sh's
# own reason — it caps every core at 418 MHz, which is too large a penalty to
# land on by pressing Enter one time too many — and offering the three names
# here would put TLP's profile list in a second file.
act_power() { "$MANGO_DIR/scripts/system/power-profile-cycle.sh"; }
# Exactly what a left-click on the bar does, because both now call the one
# script that holds the device ID. It notify-sends when the phone is away
# rather than returning silently — an action that appears to do nothing is the
# one outcome a row must never have.
act_phone() { "$MANGO_DIR/scripts/kdeconnect/phone-status.sh" ring; }
# The one row with two useful verbs, and since 2026-08-24 they are two KEYS
# rather than a sub-picker: Enter opens the forecast, Ctrl+Enter refetches. The
# picker was a second surface drawn over the reading you opened the panel to
# look at, to choose between two things. docs/adr/0044.
#
# `open` hands the screen to a browser, so it closes the panel.
act_weather() {
	"$MANGO_DIR/scripts/system/weather.sh" open
	close=1
}
act_dnd() { swaync-client -d -sw >/dev/null; }
# The history is swaync's OWN PANEL: swaync-client has count, dnd and toggle,
# and no list to build one from. docs/adr/0047.
act_notify() {
	swaync-client -t
	close=1
}
act_bar() { "$MANGO_DIR/scripts/waybar/waybar-layout.sh"; }

# Ctrl+Enter's half, and it is optional. A row without one falls through to the
# re-render every press already does — which re-reads its state, so the key
# reads as a refresh everywhere rather than as dead on twelve rows out of
# thirteen. Weather is the only fact here that lives off this machine and so the
# only one with anything to fetch. checks/static.sh asserts each refresh_* names
# a row: a misspelt one is a key that silently does nothing.
refresh_weather() { "$MANGO_DIR/scripts/system/weather.sh" refresh; }

# ── The floor ─────────────────────────────────────────────────────────────
#
# A row missing its label or either of its functions renders and then does
# nothing — the failure this repo is named after. Checked once, before anything
# is drawn, so it is a visible refusal rather than a dead entry.
# checks/static.sh asserts the same thing without running the file.
incomplete=""
for id in "${ROWS[@]}"; do
	[ "$id" = - ] && continue
	[ -n "${LABEL[$id]:-}" ] || incomplete+=" $id:label"
	declare -F "state_$id" >/dev/null || incomplete+=" $id:state"
	declare -F "act_$id" >/dev/null || incomplete+=" $id:act"
done
if [ -n "$incomplete" ]; then
	notify-send -u critical "Control centre" "incomplete rows:$incomplete"
	echo "incomplete rows:$incomplete" >&2
	exit 1
fi

# ── Render and dispatch ───────────────────────────────────────────────────

# The rows are independent, and each is dominated by one round trip to a daemon
# that is idle — nmcli 50 ms, wpctl 33 ms, bluetoothctl 28 ms, and three of them
# fork a whole module script. Serially that measured **450 ms**, on a menu that
# re-renders after every action, so the cost lands on every press and not just
# the first. In parallel a render costs the slowest single row.
#
# Same shape as menus/network-menu.sh's build_menu, and for the same reason. The
# files are per-row and written once, so there is nothing to interleave.
render() {
	local dir id icon st
	dir=$(mktemp -d) || {
		# Rendering nothing would look like an empty menu, which is a menu that
		# opened and had no rows — indistinguishable from every toggle being
		# gone. Say it instead.
		printf '%s  could not render — mktemp failed\n' "$UNKNOWN"
		return
	}
	# Return, not exit. An exit trap would be this script's only one and would
	# outlive the purpose — see docs/gotchas.md → Scripts for what a trap that
	# replaces a signal's default action costs. network-menu.sh uses return here
	# too.
	trap 'rm -rf "$dir"' RETURN

	for id in "${ROWS[@]}"; do
		[ "$id" = - ] && continue
		# stderr is deliberately not redirected: a module that fails has
		# something to say, and this is a menu you opened by hand.
		"state_$id" >"$dir/$id" &
	done
	wait

	for id in "${ROWS[@]}"; do
		if [ "$id" = - ]; then
			printf '%s\n' "$SEP"
			continue
		fi
		IFS=$'\t' read -r icon st <"$dir/$id"
		# A state_* that printed nothing, or forgot its tab, would otherwise
		# render a row with a blank state — which reads as "off" to anyone
		# looking at it, and is the one reading that must never be free.
		[ -n "$icon" ] || icon=$UNKNOWN
		[ -n "$st" ] || st=$UNKNOWN
		printf '%s  %s  ·  %s\n' "$icon" "${LABEL[$id]}" "$st"
	done
}

# Match on the rendered "  <label>  ·  " rather than on a `case` of hand-typed
# strings: the label is then written once, in label, and a row cannot be
# unreachable because its two spellings drifted.
#
# `$1` is the verb the KEY chose — `act` for Enter, `refresh` for Ctrl+Enter — so
# the two bindings share this one lookup and a row is still declared in exactly
# two places. `act_*` is guaranteed by the floor above; `refresh_*` is not.
dispatch() {
	local verb=$1 choice=$2 id fn
	for id in "${ROWS[@]}"; do
		[ "$id" = - ] && continue
		if [[ $choice == *"  ${LABEL[$id]}  ·  "* ]]; then
			fn="${verb}_$id"
			if declare -F "$fn" >/dev/null; then "$fn"; fi
			return 0
		fi
	done
	# A separator. Re-render, which is visibly nothing happening — the honest
	# outcome for a row that is not a row.
	return 1
}

while [ "$close" -eq 0 ]; do
	# Rofi's exit status is the keybinding, and `-kb-custom-N` is the only way to
	# tell one accept key from another: 0 accept, 1 cancel, 10-28 the custom binds
	# in order (rofi-dmenu(5)). Enter, Shift+Enter and Ctrl+Enter all exit 0 on
	# their own bindings — dmenu.c hands MENU_OK and MENU_CUSTOM_INPUT the same
	# `retv = true`, and only MENU_CUSTOM_COMMAND becomes `10 + n`.
	#
	# So the status is captured rather than tested: the `|| exit 0` that used to
	# close this line would take 10 for a cancel and shut the panel instead of
	# refreshing it.
	choice=$(render | rofi_menu "$CC_MAX_LINES" -no-custom -p "Control" \
		"$CC_KB_FREE" "" -kb-custom-1 "$CC_KB_REFRESH")
	case $? in
	0) verb=act ;;
	10) verb=refresh ;;
	*) exit 0 ;;
	esac
	[ -n "$choice" ] || exit 0
	dispatch "$verb" "$choice" || true
done
