#!/bin/sh
# tmux-resurrect post-save-layout hook. Drops unnamed (numbered) sessions and
# grouped views from the save file, so only kept sessions come back.
f="$1"
awk -F '\t' '
  $1 == "grouped_session" { next }
  ($1 == "pane" || $1 == "window") && $2 ~ /^[0-9]+$/ { next }
  { print }
' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
