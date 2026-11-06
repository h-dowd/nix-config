#!/usr/bin/env bash
# Usage: scratch-toggle.sh <appid> <launch-command>
# A one-line wrapper over the compositor's own verb, for waybar's on-click lines —
# universal/bind.conf dispatches directly.
mmsg dispatch "toggle_named_scratchpad,$1,none,$2"
