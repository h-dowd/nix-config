#!/usr/bin/env bash

# Refuse to run as root. Under sudo, `~` becomes /root and mmsg cannot reach
# the session's compositor — errors that read like a broken install rather
# than "you used sudo".
if [ "$(id -u)" -eq 0 ]; then
	echo "reload.sh: run as your normal user, not root — mango runs in your session." >&2
	exit 1
fi

# `mmsg dispatch`, not the dwl-era `mmsg -s -d`, which prints
# `{"error":"unknown command"}` and exits 0. The return value is the only
# signal: `{"success":true}`.
mmsg dispatch reload_config
