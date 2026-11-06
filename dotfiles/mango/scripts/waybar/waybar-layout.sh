#!/usr/bin/env bash
# Pick the waybar layout (SUPER+/).
. "$HOME/.config/mango/scripts/lib.sh"

LAYOUTS=("full" "focus" "minimal")

menu_entries() {
	local current
	current=$(bar_layout)
	for name in "${LAYOUTS[@]}"; do
		[ "$name" = "$current" ] && echo "$name  •" || echo "$name"
	done
}

CHOICE=$(menu_entries | rofi_menu 20 -no-custom -p "Waybar layout") || exit 0
[[ "$CHOICE" == *"  •" ]] && exit 0
name="${CHOICE//  •/}"
name="${name// /}"
[ -z "$name" ] && exit 0

# Validate
valid=0
for n in "${LAYOUTS[@]}"; do [ "$n" = "$name" ] && valid=1; done
[ $valid -eq 0 ] && exit 0

state_write bar-layout "$name"
"$MANGO_DIR/scripts/waybar/waybar-restart.sh"
