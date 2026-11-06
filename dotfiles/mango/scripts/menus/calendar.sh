#!/usr/bin/env bash
# The calendar, in rofi. Left-click on the clock, or ⌥D.
#
# Replaces reading `{calendar}` out of the clock's tooltip: a tooltip cannot be
# navigated, cannot be kept open and appears wherever the pointer happens to be.
# Built on system/weather.sh's panel, which answered the same problem for the
# same reason — one surface, the menus' own, rather than a second kind of popup
# nothing else on the machine uses. docs/adr/0058, docs/adr/0050.
#
# The grid is built here rather than taken from cal(1). `cal -w` prints week
# numbers and marks nothing, and finding today inside its fixed-width output
# means counting columns — so the day that is today would be located by
# arithmetic on a string rather than known. Built here, the cell knows.
set -u

. "$HOME/.config/mango/scripts/lib.sh"

# Offset in months from the current one. Enter returns to 0 before it closes,
# so there is a way back that is not counting keypresses.
offset=0

# `date -d "$1 months"` off the FIRST of this month, never off today: adding a
# month to the 31st lands in the one after next, which is a calendar that skips
# July. The classic version of this bug, and it only appears on 31 days a year.
month_of() { date -d "$(date +%Y-%m-01) $1 months" "+$2"; }

# ISO week, from the Monday of the row — the leading blanks of a first row
# belong to the previous month, so the row's own date is what carries the week.
week_of() { date -d "$1" +%V; }

# One row per week, week number first, seven day cells after it. Today is bold
# and underlined rather than coloured: rofi's colours come from the generated
# colors.rasi and a hex code here would be another copy of the palette with
# nothing holding it in step. docs/adr/0009.
grid() {
	local y=$1 m=$2 today=$3
	local first_dow days d row wk cell mon

	first_dow=$(date -d "$y-$m-01" +%u) # 1 = Monday
	days=$(date -d "$y-$m-01 +1 month -1 day" +%-d)

	d=1
	while [ "$d" -le "$days" ]; do
		row=""
		# The Monday of this row. Only the FIRST row is short at the front, and
		# its Monday is in the month before; every row after it starts on the
		# day it starts on. Backing every row off `first_dow` put rows one and
		# two in the same ISO week.
		if [ "$d" -eq 1 ]; then
			mon=$(date -d "$y-$m-01 -$((first_dow - 1)) days" +%Y-%m-%d)
		else
			mon="$y-$m-$d"
		fi
		wk=$(week_of "$mon")

		local col
		for col in 1 2 3 4 5 6 7; do
			if [ "$d" -gt "$days" ] || { [ "$d" -eq 1 ] && [ "$col" -lt "$first_dow" ]; }; then
				row+="   "
				continue
			fi
			cell=$(printf '%2d' "$d")
			if [ "$d" = "$today" ]; then
				row+="<b><u>$cell</u></b> "
			else
				row+="$cell "
			fi
			d=$((d + 1))
		done
		printf '%s  %s\n' "$wk" "${row% }"
	done
}

while :; do
	y=$(month_of "$offset" %Y)
	m=$(month_of "$offset" %m)

	# Today is only a day of THIS month. Viewing another one, no cell is today
	# — a bold 28 in September is a calendar that lies quietly.
	if [ "$offset" -eq 0 ]; then today=$(date +%-d); else today=""; fi

	mesg="<span size=\"xx-large\">$(date +%-d)</span>  $(date '+%A')"
	mesg+=$'\n'"$(date '+%B %Y') · week $(date +%V) · day $(date +%-j) of $(date -d "31 Dec $(date +%Y)" +%-j)"
	# The month being looked at, named only when it is not the one above.
	[ "$offset" -ne 0 ] && mesg+=$'\n'"<b>$(month_of "$offset" '%B %Y')</b>"

	mapfile -t rows < <(
		printf '    Mo Tu We Th Fr Sa Su\n'
		grid "$y" "$m" "$today"
	)

	# rofi selects a row whether or not the surface wants one, and row 0 is the
	# weekday header — a highlighted `Mo Tu We` reads as a broken list. Landing
	# it on the week containing today makes the selection mean something
	# instead. Viewing another month there is no such week, so it goes to the
	# first: an arbitrary row is fine, a wrong one is not.
	sel=1
	if [ -n "$today" ]; then
		for i in "${!rows[@]}"; do
			[[ ${rows[i]} == *"<b><u>"* ]] && sel=$i && break
		done
	fi

	# rofi's exit status IS the keybinding — every accept key exits 0 on its own
	# binding and only `-kb-custom-N` becomes 10 + n. Both defaults have to be
	# unset first or rofi draws "already bound" as an error dialog where the
	# panel should be. docs/gotchas.md -> rofi.
	#
	# `-markup-rows` so the today cell's bold reaches the row. Rows are inert
	# otherwise: this is a readout, as the weather panel's are.
	printf '%s\n' "${rows[@]}" |
		rofi_menu "${#rows[@]}" -no-custom -markup-rows -p "Calendar" -mesg "$mesg" \
			-selected-row "$sel" \
			-kb-accept-custom "" -kb-accept-alt "" \
			-kb-custom-1 "Control+Return" -kb-custom-2 "Shift+Return" >/dev/null
	case $? in
	10) offset=$((offset + 1)) ;;
	11) offset=$((offset - 1)) ;;
	0)
		# Enter is "back to today" while there is a way back, and closes once
		# there is not. One key, and it never leaves you somewhere you have to
		# count your way out of.
		[ "$offset" -eq 0 ] && exit 0
		offset=0
		;;
	*) exit 0 ;;
	esac
done
