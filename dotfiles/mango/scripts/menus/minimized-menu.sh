#!/usr/bin/env bash
# Picks among the windows ⌥I has put away and restores the one chosen.
#
# Two callers: the bar's custom/minimized click, and ⌃⌥I.
#
# The bar shows only a count: a waybar module's label is text and GTK gives it
# one background image, so this is the surface where a window carries its own
# icon. docs/adr/0052.
#
# `mmsg dispatch focusid client,<id>` restores a specific window, onto the tag
# being viewed. `restore_minimized` cannot, which is why docs/adr/0033 refused
# this menu until 0052.
#
# The icon names are read from the file waybar.nix generates, not passed in, so
# both callers get the same menu.

# Not lib.sh's `rofi_menu`: it reads entries with `entries=$(cat)`, and rofi's
# icon syntax needs a NUL, which no bash string carries. The rows go straight
# down the pipe. docs/gotchas.md -> rofi.

ICON_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/mango/waybar/app-icons.json"
# A missing or unparseable table must not be fatal: the menu then lists titles
# without icons rather than not opening at all.
ICONS=$(jq -c . "$ICON_FILE" 2>/dev/null) || ICONS=""
[ -n "$ICONS" ] || ICONS='{}'

# id, title and icon name per minimized window. `@tsv` keeps an empty title from
# collapsing the field count.
mapfile -t rows < <(
	mmsg get all-clients 2>/dev/null |
		jq -r --argjson icons "$ICONS" '
			.clients[]? | select(.is_minimized == true)
			| [ (.id | tostring),
			    (.title // .appid // "?"),
			    ($icons[.appid] // $icons.default // "") ] | @tsv
		' 2>/dev/null
)

# Nothing hidden. The bar module collapses to nothing in that state so it cannot
# be the caller, but the key can — and a key that does nothing is what
# docs/adr/0033 refuses. Say so instead of drawing an empty menu.
if [ "${#rows[@]}" -eq 0 ]; then
	notify-send -a mango "Minimized" "Nothing is minimized" 2>/dev/null
	exit 0
fi

ids=()
for row in "${rows[@]}"; do
	ids+=("${row%%$'\t'*}")
done

# `-theme-str`, not `-l`: on rofi 2.0 the theme beats the command line. Same
# reasoning as lib.sh's, which this cannot call. docs/gotchas.md -> rofi.
lines=${#rows[@]}
[ "$lines" -gt 12 ] && lines=12

# `-show-icons` does beat config.rasi, unlike `-l`. `-format i` returns the row
# index, because titles are not unique: two foot windows are two rows reading
# `foot`, and matching the text back to an id would restore the wrong one.
idx=$(
	for row in "${rows[@]}"; do
		IFS=$'\t' read -r _ title icon <<<"$row"
		if [ -n "$icon" ]; then
			printf '%s\0icon\x1f%s\n' "$title" "$icon"
		else
			printf '%s\n' "$title"
		fi
	done | rofi -dmenu -theme-str "listview { lines: $lines; }" \
		-i -no-custom -format i -show-icons -p "minimized"
) || exit 0
[ -n "$idx" ] || exit 0

id=${ids[$idx]:-}
[ -n "$id" ] || exit 0

# The dispatch answers `{"success":true}` whether or not it restored anything,
# so the reply is not evidence. Read the client back instead.
mmsg dispatch focusid "client,$id" >/dev/null 2>&1
if [ "$(mmsg get all-clients 2>/dev/null |
	jq -r --argjson i "$id" '.clients[]? | select(.id == $i) | .is_minimized')" = "true" ]; then
	notify-send -a mango "Minimized" "Window $id did not come back" 2>/dev/null
fi
