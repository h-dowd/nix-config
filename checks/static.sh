#!/usr/bin/env bash
# Static assertion checks — everything decidable from the repo source and the
# build outputs, with no live session. Run by `nix flake check`; the checks
# that need a running compositor stay in verify-claims.sh.
#
#   checks/static.sh <source-root> <home-manager-generation> <system-toplevel>
#
# All three arguments are required. Nothing here is allowed to skip: a check
# that quietly finds nothing is this repo's recurring failure, not a pass.

set -uo pipefail

usage="usage: static.sh <source-root> <home-manager-generation> <system-toplevel> <schemes-json> <packages-json>"
SRC=${1:?$usage}
GEN=${2:?$usage}
SYS=${3:?$usage}
# Every scheme this machine wears, resolved by Nix:
#
#   .artefact          modules/home/scheme.nix — the widget art, icons, cursor,
#                      yazi flavor, nvim plugin and Zed theme
#   .modes.<mode>      modules/home/modes.nix — the colour-only scheme that mode
#                      wears (docs/adr/0034)
#   .schemes.<name>    the resolved theme file for each name either names
#
# Resolved by Nix rather than read out of the theme files with sed, because an
# aliased role (`okColor = green;`) read as "role absent" — four of them did,
# and went unaudited. docs/adr/0032.
#
# Plural, and that is the point of the shape: a legibility floor that only ever
# audited scheme.nix's would pass a mode nobody can read. Whatever `.schemes`
# holds gets audited, so a scheme cannot enter service unaudited.
SCHEMES=${4:?$usage}
# Both package lists, name -> store path, resolved by Nix. Ownership is an eval
# question; see the comment beside this argument in flake.nix.
PACKAGES=${5:?$usage}

# `pal <jq-path>` reads the scheme named by $PAL_SCHEME, which defaults to the
# artefact one. The floor audit re-points it per scheme; nothing else should.
# A path that does not exist yields empty, and every consumer of it has a floor,
# so a renamed key fails loudly rather than scanning for nothing.
PAL_SCHEME=$(jq -r '.artefact // empty' "$SCHEMES" 2>/dev/null)
pal() { jq -r ".schemes.\"$PAL_SCHEME\"$1 // empty" "$SCHEMES" 2>/dev/null; }

WAYBAR_DIR="$GEN/home-files/.config/mango/waybar"
# wayle's own XDG directory, not under the mango tree. Only `layouts/` may be
# here — see the config.toml assertion below.
WAYLE_DIR="$GEN/home-files/.config/wayle"
# What home-manager actually wrote. Anything generated is read from here rather
# than from its source under dotfiles/ — several files have no source any more.
GEN_CFG="$GEN/home-files/.config"
PROFILE="$GEN/home-path/bin"

PASS=0
FAIL=0

ok() {
	PASS=$((PASS + 1))
	printf '  ✓ %s\n' "$1"
}
bad() {
	FAIL=$((FAIL + 1))
	printf '  ✗ %s\n' "$1"
	[[ -n ${2:-} ]] && printf '      %s\n' "$2"
	return 0
}

# Only tracked files reach the flake source, so under `nix flake check` every
# scan below sees exactly what a fresh clone would. Run against a working tree
# the prune list keeps build and tool artefacts out.
prune=(-name .git -o -name .direnv -o -name result)

is_tracked() {
	if [[ -d "$SRC/.git" ]]; then
		git -C "$SRC" ls-files --error-unmatch "$1" >/dev/null 2>&1
	else
		[[ -e "$SRC/$1" ]]
	fi
}

mapfile -t SCRIPTS < <(
	find "$SRC" \( "${prune[@]}" \) -prune -o -type f -print0 |
		while IFS= read -r -d "" f; do
			case "$(head -c 64 "$f" 2>/dev/null | tr -d '\0' | head -1)" in
			'#!'*) printf '%s\n' "$f" ;;
			esac
		done
)
if [[ ${#SCRIPTS[@]} -lt 30 ]]; then
	bad "only ${#SCRIPTS[@]} scripts found — the shebang scan is broken, not the repo"
else
	ok "${#SCRIPTS[@]} scripts found to scan"
fi

printf '\nRepo\n'

# EVERY `docs/adr/NNNN` POINTER RESOLVES.
# The comments here carry a one-line reason and a pointer, so the pointer is
# half the convention — and a record that is deleted or renamed leaves every
# citation of it reading exactly as it did while it worked. Nothing caught that
# until 2026-08-28, when four records were retired and 24 comments named them.
# BOTH CITATION FORMS. Code comments cite the number (`docs/adr/0052`) and the
# records cite each other by filename (`[0052](0052-the-bar-draws....md)`), so a
# scan for one passes over a break in the other — which it did, on the first run
# of this check, with eight dead filename links in docs/adr/.
adrmiss=""
adrseen=0
while read -r n; do
	adrseen=$((adrseen + 1))
	compgen -G "$SRC/docs/adr/$n-*.md" >/dev/null || adrmiss+=" $n"
done < <(
	grep -rhoE 'docs/adr/[0-9]{4}' "$SRC" \
		--exclude-dir=.git --exclude-dir=.direnv 2>/dev/null |
		sed 's|.*/||' | sort -u
)
while read -r f; do
	[[ -n $f ]] || continue
	adrseen=$((adrseen + 1))
	[[ -f "$SRC/docs/adr/$f" ]] || adrmiss+=" $f"
done < <(
	grep -rhoE '\]\(0[0-9]{3}-[a-z0-9-]+\.md\)' "$SRC/docs/adr" 2>/dev/null |
		tr -d ']()' | sort -u
)
if [[ $adrseen -lt 30 ]]; then
	bad "only $adrseen ADR citations found across the repo — the scan is broken, not the repo"
elif [[ -n $adrmiss ]]; then
	bad "a comment cites an ADR that does not exist:$adrmiss" \
		"a dead pointer reads exactly like a live one; retire the citation with the record"
else
	ok "all $adrseen ADR citations resolve, by number and by filename"
fi

# A tracked symlink holds an absolute path that is wrong in every other clone,
# and home-manager fights whatever rewrites it at runtime.
syms=$(find "$SRC" \( "${prune[@]}" \) -prune -o -type l -print)
if [[ -z $syms ]]; then
	ok "no symlinks in the source"
else
	bad "symlinks in the source" "$(echo "$syms" | tr '\n' ' ')"
fi

# Generated at runtime, so tracking them means two owners for one path. A list
# of one since walker left — kept as a loop because the shape
# recurs every time an autostart.conf learns to write something.
GENERATED=(dotfiles/mango/config.conf)
for f in "${GENERATED[@]}"; do
	if is_tracked "$f"; then
		bad "$f is tracked but is generated at runtime"
	elif grep -qF "$f" "$SRC/.gitignore"; then
		ok "$(basename "$f") generated + gitignored"
	else
		bad "$f is untracked but has no .gitignore rule"
	fi
done

printf '\nScripts\n'

# There is no /bin/bash on NixOS; the shebang fails with exit 127, and a waybar
# custom module whose exec exits 127 renders as an empty module.
if bad_sheb=$(grep -l '^#!/bin/bash' "${SCRIPTS[@]}" 2>/dev/null); then
	bad "#!/bin/bash shebang (there is no /bin/bash — exit 127)" "$(echo "$bad_sheb" | tr '\n' ' ')"
else
	ok "every script uses #!/usr/bin/env bash"
fi

# mmsg takes verbs. The dwl-era dash-flags return {"error":...} and exit 0, so
# a script using them reports success while doing nothing.
if mmsg_flags=$(grep -rn 'mmsg[[:space:]]\+-' "$SRC/dotfiles" 2>/dev/null | grep -vE ':[0-9]+:[[:space:]]*#'); then
	bad "mmsg called with dash-flags (unknown command, exit 0)" "$(echo "$mmsg_flags" | head -3)"
else
	ok "no script calls mmsg with dash-flags"
fi

# desktop-mode.sh kept reading $MANGO_DIR/state after the move and the mode
# switch silently became one-way.
stale=$(grep -rn 'MANGO[_A-Z]*/state\|config/mango/state' "$SRC/dotfiles/mango/scripts/" 2>/dev/null |
	grep -vE ':[0-9]+:[[:space:]]*#')
if [[ -z $stale ]]; then
	ok "no script reads the old state path"
else
	bad "scripts still reading ~/.config/mango/state" "$(echo "$stale" | head -3)"
fi

# nixpkgs wraps some binaries, so `comm` becomes .foo-wrapped, truncated to 15
# chars. `-x` matches comm exactly and never fires. `pgrep` is checked alongside
# `pkill` because the read-only form fails just as quietly and in both
# directions: a guard that never matches respawns a running daemon, and a
# liveness test that never matches exits a healthy loop. Resolve each target
# rather than flagging every -x: a check that cries wolf gets ignored.
pk_bad=""
pk_n=0
while read -r line; do
	[[ -z $line ]] && continue
	name=${line##*-x }
	name=${name%% *}
	name=${name%%;*}
	[[ -z $name ]] && continue
	pk_n=$((pk_n + 1))
	# System packages are not in the home profile — mango and elephant live in
	# the system one, so checking only $profile reports "cannot verify" for the
	# targets most likely to be wrapped.
	bin=""
	for d in "$PROFILE" "$SYS/sw/bin"; do
		[[ -e "$d/$name" ]] && {
			bin="$d/$name"
			break
		}
	done
	if [[ -z $bin ]]; then
		pk_bad+="  $name: in neither profile — cannot verify: ${line%%:*}"$'\n'
		continue
	fi
	real=$(readlink -f "$bin")
	[[ -e "$(dirname "$real")/.${name}-wrapped" ]] &&
		pk_bad+="  $name is wrapped — -x will never match: ${line%%:*}"$'\n'
done < <(grep -rnE 'p(kill|grep) -x' "$SRC/dotfiles" 2>/dev/null | grep -vE ':[0-9]+:[[:space:]]*#')

if [[ $pk_n -eq 0 ]]; then
	bad "no 'pkill -x'/'pgrep -x' found at all — the scan is broken, not the repo"
elif [[ -z $pk_bad ]]; then
	ok "all $pk_n 'pkill -x'/'pgrep -x' targets are unwrapped binaries"
else
	bad "'-x' against a nixpkgs wrapper never matches" "$(echo "$pk_bad" | head -4)"
fi

printf '\nSecrets\n'

# An unencrypted secrets file committed to git reads exactly like an encrypted
# one at a glance, and the mistake is unrecoverable once pushed. sops always
# writes the `sops:` metadata block, so its absence means plaintext.
mapfile -t SECRET_FILES < <(find "$SRC/secrets" -type f -name '*.yaml' 2>/dev/null | sort)
if [[ ${#SECRET_FILES[@]} -eq 0 ]]; then
	bad "no secrets/*.yaml found — the scan is broken, not the repo"
else
	plain=""
	for f in "${SECRET_FILES[@]}"; do
		if ! grep -q '^sops:' "$f" || ! grep -q 'age:' "$f"; then
			plain+="  ${f#"$SRC"/}"$'\n'
		fi
	done
	if [[ -z $plain ]]; then
		ok "all ${#SECRET_FILES[@]} secrets/*.yaml are sops-encrypted"
	else
		bad "UNENCRYPTED file under secrets/" "$plain"
	fi
fi

# The plaintext credential file is gone. A script still reading that path would
# find nothing and fall through without saying so.
pia_stale=$(grep -rn 'pia-auth' "$SRC/dotfiles" "$SRC/modules" 2>/dev/null | grep -vE ':[0-9]+:[[:space:]]*#')
if [[ -z $pia_stale ]]; then
	ok "no script reads the old plaintext pia-auth path"
else
	bad "script still reads the old plaintext pia-auth path" "$(echo "$pia_stale" | head -3)"
fi

printf '\nRuntime-selected files\n'

# A file chosen by a shell conditional is never evaluated, so an unreachable
# branch is invisible — four instances so far, the largest 765 lines, every one
# looking maintained and two of them documented as the default. Checked both
# ways per selector: every value the selector can take must have a file, and
# every file must be a value the selector can take. One direction alone misses
# half the class — a missing file is a runtime fallback, a surplus file is dead
# weight that still looks maintained.
MANGO="$SRC/dotfiles/mango"

# The one lock path, checked in two places below: for the noctalia ipc call it
# makes, and for the background pool it points at.
LOCKBIN="$GEN/home-path/bin/lockscreen"

# Desktop mode. desktop-mode.sh validates against this list, so it is the
# complete set of values current-mode can hold.
mapfile -t MODES < <(
	sed -n 's/^MODES=(\(.*\))$/\1/p' "$MANGO/scripts/desktop-mode.sh" | tr -d '"' | tr ' ' '\n' | sed '/^$/d'
)
if [[ ${#MODES[@]} -eq 0 ]]; then
	bad "could not read MODES from desktop-mode.sh — the scan is broken, not the repo"
else
	missing=""
	for m in "${MODES[@]}"; do
		[[ -f "$MANGO/$m/$m.conf" ]] || missing+="  $m/$m.conf"$'\n'
		[[ -f "$MANGO/scripts/modes/$m.sh" ]] || missing+="  scripts/modes/$m.sh"$'\n'
	done
	# And nothing surplus, in both directions: a <m>/<m>.conf naming no mode is
	# a config nothing can select. (walker/configs/<m>.toml was the third
	# per-mode file until 2026-08-14; rofi has one config for every mode.)
	for d in "$MANGO"/*/; do
		n=$(basename "$d")
		[[ -f "$d/$n.conf" ]] || continue
		printf '%s\n' "${MODES[@]}" | grep -qxF "$n" || missing+="  $n/$n.conf names no mode"$'\n'
	done
	if [[ -z $missing ]]; then
		ok "each of the ${#MODES[@]} modes has its conf and its mode script, and no others exist"
	else
		bad "mode/file mismatch" "$missing"
	fi
fi

# And every mode has a colour scheme, both ways. modules/home/dotfiles.nix
# resolves each as `import ./themes/${modes.${mode}}.nix`, so a missing key is
# already an eval error — what this catches is the direction eval cannot see: a
# key naming no mode, which is a colour scheme nothing can ever select while
# reading like a mode that exists. docs/adr/0034.
mapfile -t MODE_KEYS < <(jq -r '.modes | keys[]' "$SCHEMES" 2>/dev/null)
if [[ ${#MODE_KEYS[@]} -eq 0 ]]; then
	bad "no modes read from modules/home/modes.nix — the scan is broken, not the repo"
elif [[ ${#MODES[@]} -gt 0 ]]; then
	memiss=""
	for m in "${MODES[@]}"; do
		printf '%s\n' "${MODE_KEYS[@]}" | grep -qxF "$m" || memiss+="  $m has no entry in modes.nix"$'\n'
	done
	for k in "${MODE_KEYS[@]}"; do
		printf '%s\n' "${MODES[@]}" | grep -qxF "$k" || memiss+="  modes.nix names '$k', which is not a mode"$'\n'
	done
	if [[ -z $memiss ]]; then
		ok "each of the ${#MODES[@]} modes has a colour scheme in modes.nix, and no others do"
	else
		bad "mode/scheme mismatch" "$memiss"
	fi
fi

# The ceiling on how far modes.nix may diverge. wayle is the consumer not on
# the runtime swap — its six layouts are generated once, palette and all, from
# scheme.nix — and noctalia does not run it. So every other mode has to wear
# the artefact scheme, or it gets a bar from a scheme it is not wearing.
# waybar and swaync are what tiling runs. wayle held both jobs between
# 2026-08-24 and 2026-08-27 and is still generated, still wearing this scheme,
# but no mode starts it. docs/adr/0051.
#
#
# noctalia may differ, and does: everything it runs — its own shell, mango's
# chrome, kitty, foot, rofi, ncspot and Equibop — follows modes.nix.
#
# Derived from modes.nix rather than naming `tiling`, so a mode added later is
# asserted with nothing to remember. Until hud left this also
# had to check tiling and hud against each other, because two modes shared one
# generated bar; with one bar-bearing mode that half is gone.
#
# If waybar or swaync ever needs to differ by mode, it joins the swap first;
# this assertion is what makes that a decision rather than a silent half.
barmodes=0
barerr=""
while IFS='|' read -r m msch; do
	[[ -z $m || $m == noctalia ]] && continue
	barmodes=$((barmodes + 1))
	[[ $msch == "$PAL_SCHEME" ]] || barerr+="  $m wears '$msch'"$'\n'
done < <(jq -r '.modes | to_entries[] | "\(.key)|\(.value)"' "$SCHEMES" 2>/dev/null)
if [[ $barmodes -eq 0 ]]; then
	bad "no bar-bearing mode read from modes.nix — the scan is broken, not the repo"
elif [[ -n $barerr ]]; then
	bad "a mode running waybar and swaync does not wear the artefact scheme '$PAL_SCHEME'" \
		"those are generated once, from scheme.nix, so the mode would be half one scheme and half the other:"$'\n'"$barerr"
else
	ok "the $barmodes mode(s) running wayle wear '$PAL_SCHEME', which is what its layouts are generated from"
fi

# no_border_when_single=1 removes every tiled window's border on mango 0.16.0,
# not just a lone one, and nothing says so. docs/gotchas.md → Desktop → mango
nbws=$(grep -rn '^[[:space:]]*no_border_when_single[[:space:]]*=[[:space:]]*1' "$MANGO" --include='*.conf' || true)
if [[ -z $nbws ]]; then
	ok "no mode config sets no_border_when_single=1"
else
	bad "no_border_when_single=1 turns off every tiled border, not just a single window's" "$nbws"
fi

# Same check the waybar configs get below, for the mango tree: a `bind=` or
# `exec=` naming a script that is missing — or present but not executable — is
# a key that does nothing and a daemon that never starts, both exiting 0. Nix
# preserves the mode bit, so a script committed 644 arrives 444 and fails only
# at runtime. That is how notify.sh shipped dead on 2026-08-14.
missing=""
refs=0
while read -r ref; do
	[[ -z $ref ]] && continue
	refs=$((refs + 1))
	# `#*scripts/` covers both spellings — the `~/.config/mango/scripts/` of a
	# conf and the `$MANGO_DIR/scripts/` of a script.
	[[ -x "$MANGO/scripts/${ref#*scripts/}" ]] || missing+="  $ref"$'\n'
done < <(
	{
		# `~/.config/…` in a bind= or exec= line.
		grep -rho '[~]/\.config/mango/scripts/[^ "]*' "$MANGO" --include='*.conf'
		# `"$MANGO_DIR/scripts/…"` from one script to another. Added when
		# shell.sh took over the network and bluetooth menus: their only
		# callers stopped being .conf files, and they fell out of this scan
		# without any count reaching zero to say so.
		# SC2016: `$MANGO_DIR` is the literal text being searched for, not a
		# variable to expand — the scripts spell the path that way.
		# shellcheck disable=SC2016
		grep -rho '\$MANGO_DIR/scripts/[^" ]*' "$MANGO/scripts"
		# mode.sh's `modes/$mode.sh` is decided at runtime and cannot be
		# resolved here — and does not need to be: the mode/file check above
		# already asserts a script exists for every value $mode can hold.
	} | grep -v 'scripts/[^ ]*\$' | sort -u
)

if [[ $refs -eq 0 ]]; then
	bad "no script references found in the mango configs — the scan is broken, not the repo"
elif [[ -z $missing ]]; then
	ok "all $refs scripts named by a bind or autostart exist and are executable"
else
	bad "a mango config names a missing or non-executable script" "$missing"
fi

# `mango-reload` restarts the BAR, and this one line is the whole reason it
# does. Verified 2026-08-26 by PID, not by reading: wayle went 41365 -> 46310
# across a `reload.sh`.
#
# reload.sh and desktop-mode.sh both end in `mmsg dispatch reload_config`, which
# re-fires every `exec=` in the active mode's autostart.conf. NOTHING ELSE
# starts or restarts wayle — `apply_mode` does not touch it and `mode.sh` only
# execs the mode script. So this line silently becoming `exec-once=` leaves the
# bar running its previous config after every reload, with the rest of the mode
# applied around it. That is indistinguishable from the change having had no
# effect, which is the symptom CLAUDE.md's "Rebuild before reload" describes.
#
# It is a plausible edit, not a far-fetched one: universal/autostart.conf is
# `exec-once=` throughout, so making this match reads like tidying.
BAR_AUTOSTART="$MANGO/tiling/autostart.conf"
if [[ ! -s $BAR_AUTOSTART ]]; then
	bad "tiling/autostart.conf is missing or empty — the scan is broken, not the repo" "$BAR_AUTOSTART"
elif grep -qE '^exec=[^=]*waybar/waybar-restart\.sh' "$BAR_AUTOSTART"; then
	ok "tiling/autostart.conf runs waybar-restart.sh as exec=, so reload_config restarts the bar"
elif grep -qE '^exec-once=.*waybar/waybar-restart\.sh' "$BAR_AUTOSTART"; then
	bad "tiling/autostart.conf runs waybar-restart.sh as exec-once=, so mango-reload no longer restarts the bar" \
		"reload_config re-fires exec= lines only — the bar would keep its previous config, silently"
else
	bad "nothing in tiling/autostart.conf runs waybar-restart.sh" \
		"the bar would not start at login and mango-reload would not restart it"
fi

# --- The daemons the scripts assume ------------------------------------------
#
# THREE PROGRAMS, NONE OF THEM A UNIT WantedBy ANYTHING. Each is started by one
# autostart line and each has callers that fail silently without it, which is
# what makes a deleted line invisible rather than fatal. docs/adr/0051.
#
#   swaync      owns org.freedesktop.Notifications AND org.erikreider.swaync.cc.
#               Without it every `swaync-client` in shell.sh and
#               control-center.sh hits a MASKED activation unit, prints
#               `NameHasNoOwner … unit is masked` on stderr and EXITS 0 — two
#               control-centre rows rendering `?` and three dead keys, which is
#               how it sat for a month. The mask is deliberate
#               (modules/home/default.nix) so autostart owns the lifecycle.
#   waybar      the bar, checked above.
#   swayosd     the only OSD in this mode. waybar has none, so volume,
#               brightness and the lock keys have no feedback without it — and
#               no error either, since nothing calls swayosd-client.
daemonbad=""
grep -qE '^exec=.*swaync' "$BAR_AUTOSTART" ||
	daemonbad+="  tiling/autostart.conf does not start swaync — every swaync-client call exits 0 having done nothing"$'\n'
grep -qE '^exec-once=.*swayosd-server' "$MANGO/universal/autostart.conf" ||
	daemonbad+="  universal/autostart.conf does not start swayosd-server — no volume, brightness or caps-lock feedback anywhere"$'\n'
if [[ -n $daemonbad ]]; then
	bad "a daemon the scripts depend on is not started by any autostart line" "$daemonbad"
else
	ok "swaync and swayosd are both started by an autostart line"
fi

# --- Daemons that are not there any more -------------------------------------
#
# Two ways of talking to a program that has been retired, both of which look
# exactly like success. Absence checks, so the floor is on the population: a
# scan over no scripts finds nothing and passes.
#
# WAYLE IS THE RETIRED ONE NOW (docs/adr/0051). It is still installed and its
# CLI still exists, so every call below builds, runs, and fails at a socket that
# nothing is listening on:
#
#   wayle <verb>            `wayle notify`, `wayle wallpaper`. Nothing starts
#                           wayle since tiling/autostart.conf stopped doing so,
#                           and the CLI's failure is a message on a stderr no
#                           keybind reads. Four call sites moved to
#                           swaync-client and awww; this is what keeps a fifth
#                           from arriving.
#
# scripts/wayle/* IS EXCLUDED, deliberately: those three are the by-hand path
# back to wayle and calling it is their entire job — the same exception
# noctalia-start.sh has always had for running `swaync`.
#
# The two patterns this replaced were `pkill -RTMIN+N waybar` and
# `swaync-client`, retired between 2026-08-24 and 2026-08-26. BOTH ARE LIVE
# AGAIN and are asserted above instead, from the other end: that something
# starts the daemon they talk to.
#
# COMMENTS ARE STRIPPED FIRST, and that is the deliberate half. Every one of the
# six removals left a comment saying which line went and why — this repo's whole
# convention — so a scan that matched anywhere in the file would fire on its own
# documentation. A commented-out call is not a call.
retired=""
for f in "${SCRIPTS[@]}"; do
	case "$f" in "$MANGO"/* | "$SRC"/dotfiles/scripts/*) ;; *) continue ;; esac
	code=$(sed 's/#.*//' "$f")
	# `if`, not `grep … && retired+=`: a bare `a && b` whose `a` fails fails the
	# statement, which would exit under a `set -e` this file does not have yet.
	case "$f" in "$MANGO"/scripts/wayle/*) continue ;; esac
	if grep -qE '(^|[^-[:alnum:]_])wayle [a-z]' <<<"$code"; then
		retired+="  ${f#"$SRC"/} calls the wayle CLI, and nothing starts wayle — it fails at a socket, on a stderr no keybind reads"$'\n'
	fi
done
if [[ -n $retired ]]; then
	bad "a script still talks to a daemon this machine does not run" "$retired"
else
	ok "no script outside scripts/wayle/ calls the wayle CLI"
fi

# Two binds on one key: mango prints `[warning] Key binding conflict` naming
# both files and lines, then runs whichever was parsed first (src/mango.c,
# "only match the first keybind"). That warning goes to mango's stderr, where
# nothing reads it — so the second bind looks installed and never fires. Built
# per mode from the `source=` lines of its own conf, which is exactly the set
# mango parses. Keys are lowercased first: the dispatcher compares with
# xkb_keysym_to_lower(), so `SUPER,O` and `SUPER,o` are one key, not two.
if [[ ${#MODES[@]} -gt 0 ]]; then
	duperr=""
	# The floor is on binds seen, not modes seen, and that distinction is the
	# whole point. `srcs` is built by matching the literal `source=./`; change
	# that spelling and it comes back empty, the inner loop does nothing, and a
	# per-mode counter still increments — so the scan would drop from 117 binds
	# to 2 and print `ok`. That is the Phase 4 class inside the gate itself.
	binds_seen=0
	for m in "${MODES[@]}"; do
		conf="$MANGO/$m/$m.conf"
		[[ -f $conf ]] || continue
		mapfile -t srcs < <(sed -n 's|^source=\./||p' "$conf")
		mapfile -t binds < <(
			for s in "${srcs[@]}"; do
				[[ -f "$MANGO/$s" ]] && grep -h '^bind=' "$MANGO/$s"
			done
			grep -h '^bind=' "$conf"
		)
		binds_seen=$((binds_seen + ${#binds[@]}))
		dups=$(
			printf '%s\n' "${binds[@]}" |
				cut -d, -f1,2 | tr '[:upper:]' '[:lower:]' | sort | uniq -d
		)
		[[ -n $dups ]] && duperr+="  $m: $(echo "$dups" | tr '\n' ' ')"$'\n'
	done
	# Set well under today's count so removing a bind is a code change, not a
	# check failure — but far enough above the per-mode residue that a broken
	# `source=` scan cannot clear it.
	if [[ $binds_seen -lt 40 ]]; then
		bad "only $binds_seen binds read across ${#MODES[@]} modes — the scan is broken, not the repo"
	elif [[ -z $duperr ]]; then
		ok "no key is bound twice across the $binds_seen binds in ${#MODES[@]} modes"
	else
		bad "a key is bound twice — mango warns to a stderr nobody reads, then runs the first" "$duperr"
	fi
fi

# scripts/menus/shell.sh is a selector like any other (docs/adr/0014): a bind
# naming an action its case table lacks hits the `usage:` branch on a stderr
# nobody reads, and an action in the table that no bind names is a mode-specific
# path nothing can reach — the shape that hid four unreachable files here. Both
# directions, and both sides must be non-empty.
# `^bind=` first, then the action: an unfiltered scan reads the prose in the
# comments too, and "shell.sh rather than calling" duly arrived as an action
# named `rather`.
mapfile -t BIND_ACTIONS < <(
	grep -rh '^bind=' "$MANGO" --include='*.conf' |
		grep -oE 'menus/shell\.sh [a-z-]+' | awk '{print $2}' | sort -u
)
# awk, not sed: shfmt splits `foo) ipc="x" ;;` onto separate lines, so the arm
# label and its `ipc=` no longer share one. Keyed on the label, which is what
# a bind actually names.
mapfile -t TABLE_ACTIONS < <(
	awk '
		/^[a-z][a-z-]*\)$/ { arm = substr($0, 1, length($0) - 1); next }
		arm != "" && $0 ~ /^[[:space:]]*ipc=/ { print arm; arm = "" }
	' "$MANGO/scripts/menus/shell.sh" | sort -u
)
if [[ ${#BIND_ACTIONS[@]} -eq 0 || ${#TABLE_ACTIONS[@]} -eq 0 ]]; then
	bad "shell.sh actions or the binds naming them came back empty — the scan is broken, not the repo"
else
	acterr=""
	for a in "${BIND_ACTIONS[@]}"; do
		printf '%s\n' "${TABLE_ACTIONS[@]}" | grep -qxF "$a" ||
			acterr+="  a bind calls shell.sh $a, which its case table does not have"$'\n'
	done
	for a in "${TABLE_ACTIONS[@]}"; do
		printf '%s\n' "${BIND_ACTIONS[@]}" | grep -qxF "$a" ||
			acterr+="  shell.sh handles $a, which no bind reaches"$'\n'
	done
	if [[ -z $acterr ]]; then
		ok "all ${#TABLE_ACTIONS[@]} shell.sh actions are reached by a bind, and no bind names another"
	else
		bad "shell.sh action mismatch" "$acterr"
	fi
fi

# menus/control-center.sh builds its rows from one rows array and dispatches by
# calling `state_<id>` and `act_<id>`. A row whose label or either function is
# missing renders and then does nothing: bash reports "command not found" on a
# stderr nobody reads, and the entry sits there looking installed. The script
# checks this itself before drawing, which catches it at the first press — this
# catches it at `nix flake check`, which is before the press.
#
# Floor at zero both ways: a renamed array or a changed function prefix would
# empty one side, and a check that passes by finding nothing is this repo's
# recurring failure, not a pass. docs/adr/0033.
CC="$MANGO/scripts/menus/control-center.sh"
if [[ -f $CC ]]; then
	# The ids between `rows=(` and its closing paren, minus the `-` separators.
	mapfile -t CC_ROWS < <(
		sed -n '/^ROWS=(/,/^)/p' "$CC" | sed -n 's/^\t\([a-z][a-z-]*\)$/\1/p' | sort -u
	)
	mapfile -t CC_LABELS < <(
		sed -n 's/^\t\[\([a-z][a-z-]*\)\]=.*/\1/p' "$CC" | sort -u
	)
	mapfile -t CC_FNS < <(
		sed -n 's/^\(state\|act\)_\([a-z][a-z-]*\)() {.*/\1 \2/p' "$CC" | sort -u
	)
	if [[ ${#CC_ROWS[@]} -eq 0 || ${#CC_LABELS[@]} -eq 0 || ${#CC_FNS[@]} -eq 0 ]]; then
		bad "the control centre's rows, labels or functions came back empty — the scan is broken, not the repo" \
			"rows=${#CC_ROWS[@]} labels=${#CC_LABELS[@]} fns=${#CC_FNS[@]}"
	else
		ccerr=""
		for id in "${CC_ROWS[@]}"; do
			printf '%s\n' "${CC_LABELS[@]}" | grep -qxF "$id" ||
				ccerr+="  row $id has no entry in LABEL"$'\n'
			for half in state act; do
				printf '%s\n' "${CC_FNS[@]}" | grep -qxF "$half $id" ||
					ccerr+="  row $id has no ${half}_$id()"$'\n'
			done
		done
		# The other direction: a function or a label with no row is dead code
		# that reads as a working feature — the shape that hid four unreachable
		# files here (docs/adr/0014).
		for id in "${CC_LABELS[@]}"; do
			printf '%s\n' "${CC_ROWS[@]}" | grep -qxF "$id" ||
				ccerr+="  LABEL has $id, which ROWS does not list"$'\n'
		done
		for pair in "${CC_FNS[@]}"; do
			printf '%s\n' "${CC_ROWS[@]}" | grep -qxF "${pair##* }" ||
				ccerr+="  ${pair// /_}() exists, but ROWS does not list ${pair##* }"$'\n'
		done
		if [[ -z $ccerr ]]; then
			ok "all ${#CC_ROWS[@]} control-centre rows have a label, a state_* and an act_*"
		else
			bad "control-centre row mismatch" "$ccerr"
		fi

		# Ctrl+Enter's half. Not folded into CC_FNS above: that loop demands both
		# halves of every row, and refresh_* is the one a row may lack. Only the
		# reverse direction is checkable, and it is the one that fails silently —
		# a refresh_* whose suffix is not a row is never reached by dispatch(),
		# and a key that does nothing looks exactly like a key with nothing to do.
		#
		# The binding is checked with it: a refresh_* with no `-kb-custom-1` on
		# the rofi call is dead code, and the reverse is a key bound to nothing.
		#
		# And the key it binds has to be free. rofi ships `Control+Return` as
		# `kb-accept-custom`, and a key with two actions is an error dialog where
		# the panel should be — so binding it without `-kb-accept-custom ""` in
		# the same call breaks `SUPER+C` outright. Checked as a pair, because
		# either half alone is wrong: unsetting a default nothing rebinds gives up
		# a key for free.
		#
		# Comments are stripped first, and the first cut of this check did not do
		# that: `grep -c kb-accept-custom` matched the paragraph in control-center.sh
		# that explains the unset, so deleting the unset itself still passed. A scan
		# satisfied by prose about the thing is this file's own signature bug.
		mapfile -t CC_REFRESH < <(
			sed -n 's/^refresh_\([a-z][a-z-]*\)() {.*/\1/p' "$CC" | sort -u
		)
		cc_code=$(grep -v '^[[:space:]]*#' "$CC")
		cc_kb=$(grep -c -- '-kb-custom-1' <<<"$cc_code")
		if [[ ${#CC_REFRESH[@]} -eq 0 || $cc_kb -eq 0 ]]; then
			bad "the control centre has ${#CC_REFRESH[@]} refresh_* and $cc_kb -kb-custom-1 — one half of the refresh key is missing" \
				"a bind with no function is a key that does nothing; a function with no bind is unreachable"
		else
			ccrerr=""
			for id in "${CC_REFRESH[@]}"; do
				printf '%s\n' "${CC_ROWS[@]}" | grep -qxF "$id" ||
					ccrerr+="  refresh_$id() exists, but ROWS does not list $id"$'\n'
			done
			cc_ret_key=$(sed -n 's/^CC_KB_REFRESH="\(.*\)"$/\1/p' "$CC" | head -1)
			# The unset has to be declared and used: the assignment alone leaves it
			# off the rofi call, which is the breakage with none of the protection.
			cc_free_val=$(sed -n 's/^CC_KB_FREE="\(.*\)"$/\1/p' "$CC" | head -1)
			cc_free_used=$(grep -c 'CC_KB_FREE' <<<"$cc_code")
			if [[ $cc_ret_key == *Return* ]]; then
				if [[ $cc_free_val != "-kb-accept-custom" ]]; then
					ccrerr+="  the refresh key is $cc_ret_key, which rofi ships as kb-accept-custom, and CC_KB_FREE ([$cc_free_val]) does not unset it"$'\n'
				elif [[ $cc_free_used -lt 2 ]]; then
					ccrerr+="  CC_KB_FREE unsets kb-accept-custom but is never passed to rofi — $cc_ret_key stays double-bound"$'\n'
				fi
			elif [[ -n $cc_free_val ]]; then
				ccrerr+="  kb-accept-custom is unset, but the refresh key ($cc_ret_key) does not need it freed"$'\n'
			fi
			if [[ -z $ccrerr ]]; then
				ok "the control centre's refresh key ($cc_ret_key) is bound, freed, and its ${#CC_REFRESH[@]} refresh_* all name a row"
			else
				bad "control-centre refresh_* mismatch" "$ccrerr"
			fi
		fi
	fi
fi

# --- rofi menu sizing -------------------------------------------------------
# Every hand-built menu sizes itself through lib.sh's `rofi_menu`, which passes
# `-theme-str`. A caller reaching for `rofi -dmenu` directly gets the theme's
# fixed `lines: 12` instead — blank rows under a short menu, silent paging on a
# long one, and `-l` does not fix it (the theme wins on rofi 2.0).
# docs/gotchas.md -> rofi.
mapfile -t ROFI_RAW < <(
	grep -rn 'rofi -dmenu' "$MANGO/scripts" | grep -v '^\S*:[0-9]*:[[:space:]]*#'
)
# lib.sh's own definition, and network-menu.sh's password prompt, which must not
# take -no-custom and sizes itself to zero rows by hand.
#
# ...and any call that sizes itself the same way rofi_menu does. What this check
# is really about is `-theme-str listview { lines: … }`, not the helper's name:
# minimized-menu.sh cannot use rofi_menu because that reads its entries through
# `entries=$(cat)` and rofi's dmenu ICON syntax needs a NUL byte, which no bash
# string can carry (docs/adr/0052). It passes the same -theme-str by hand, so it
# is not the failure this scan exists to catch.
mapfile -t ROFI_BARE < <(
	printf '%s\n' "${ROFI_RAW[@]}" |
		grep -v '/lib\.sh:' | grep -v -- '-password' |
		grep -v -- '-theme-str' | grep -v '^$'
)
if [[ ${#ROFI_RAW[@]} -eq 0 ]]; then
	bad "no 'rofi -dmenu' call sites found at all — the scan is broken, not the repo"
elif [[ ${#ROFI_BARE[@]} -gt 0 ]]; then
	bad "${#ROFI_BARE[@]} menu(s) call 'rofi -dmenu' directly instead of rofi_menu" \
		"they render at the theme's fixed 12 lines whatever they hold:"$'\n'"$(printf '  %s\n' "${ROFI_BARE[@]}")"
else
	ok "every hand-built rofi menu sizes itself through rofi_menu"
fi

# `-l` is accepted and ignored on rofi 2.0. A caller that reaches for it has
# written a size that does nothing, which is worse than not writing one.
mapfile -t ROFI_DASHL < <(grep -rn -- 'rofi[^|]* -l ' "$MANGO/scripts" | grep -v '^\S*:[0-9]*:[[:space:]]*#')
if [[ ${#ROFI_DASHL[@]} -gt 0 ]]; then
	bad "a rofi call passes -l, which rofi 2.0's theme overrides and ignores" \
		"$(printf '  %s\n' "${ROFI_DASHL[@]}")"
else
	ok "no rofi call relies on -l, which this rofi ignores"
fi

# The control centre's ceiling has to stay above its row count, or it pages —
# and it pages silently, which is how a thirteenth row got added without anyone
# noticing page two had come back.
if [[ -f $CC ]]; then
	cc_cap=$(sed -n 's/^CC_MAX_LINES=\([0-9]\+\).*/\1/p' "$CC" | head -1)
	cc_rendered=$(sed -n '/^ROWS=(/,/^)/p' "$CC" | sed -n 's/^\t\(-\|[a-z][a-z-]*\)$/\1/p' | grep -c '')
	if [[ -z $cc_cap || $cc_rendered -eq 0 ]]; then
		bad "could not read the control centre's ceiling or its rendered height — the scan is broken" \
			"cap=[$cc_cap] rendered=[$cc_rendered]"
	elif [[ $cc_rendered -gt $cc_cap ]]; then
		bad "the control centre renders $cc_rendered lines but caps rofi at $cc_cap" \
			"everything past line $cc_cap is on page two, and nothing says so"
	else
		ok "the control centre renders $cc_rendered lines, under its $cc_cap ceiling"
	fi
fi

# --- Weather ----------------------------------------------------------------
# Four things each invisible when wrong. docs/adr/0038, 0046.
WEATHER_SH="$MANGO/scripts/system/weather.sh"
if [[ -f $WEATHER_SH ]]; then
	# 1. THE COORDINATES REACH THE SCRIPT. Drifted variable names leave
	#    WEATHER_LAT unset and send `latitude=&longitude=` — which open-meteo
	#    answers, with the weather at 0°N 0°E. gotchas.md -> Scripts.
	LOC_ENV="$GEN_CFG/mango/universal/weather-location.env"
	if [[ ! -s $LOC_ENV ]]; then
		bad "weather-location.env is not in the generation" \
			"weather.sh has no coordinates and every reading is an error row: $LOC_ENV"
	else
		locmiss=""
		for v in WEATHER_LAT WEATHER_LON WEATHER_NAME WEATHER_URL; do
			grep -q "^$v=" "$LOC_ENV" || locmiss+="  $v"$'\n'
			grep -q "\$$v" "$WEATHER_SH" || locmiss+="  $v is generated but weather.sh never reads it"$'\n'
		done
		# The path from both ends — two spellings fail as "coordinates missing"
		# pointing at a file that is right there.
		grep -q 'weather-location\.env' "$WEATHER_SH" ||
			locmiss+="  weather.sh does not name weather-location.env"$'\n'
		if [[ -z $locmiss ]]; then
			ok "weather-location.env is generated and weather.sh reads all four of its values"
		else
			bad "the generated coordinates and weather.sh disagree" "$locmiss"
		fi
	fi

	# NO SIGNAL CHECK. It read `pkill -RTMIN+13 waybar` out of this script and
	# matched it against custom/weather's `signal` in the generated waybar
	# config. Both ends are gone: wayle takes no signal, so that line matched
	# nothing and returned 1 (docs/adr/0047). There is nothing left to agree.

	# 2. THE PANEL IS REACHABLE, AND IT IS THIS ONE. `weather.sh panel` replaced
	#    wayle's `dropdown:weather` on 2026-08-26 (docs/adr/0050). Three ways
	#    that goes wrong in silence, so three assertions:
	#
	#      - the verb disappears from weather.sh and every caller opens nothing
	#      - a layout still names `dropdown:weather`, which is a SECOND panel,
	#        complete and plausible and at wayle's default San Francisco once
	#        `[modules.weather]` came out with the click that read it
	#      - the key stops naming the verb, and the only way in is the bar again
	#
	#    wayle's own default for `clock.right-click` IS `dropdown:weather`, so
	#    the second one is what happens by leaving a key unwritten, not by
	#    writing a wrong one.
	panelbad=""
	panelseen=0
	sed -n '/^case "${1:-status}" in$/,/^esac$/p' "$WEATHER_SH" | grep -q '^panel)' ||
		panelbad+="  weather.sh has no 'panel' verb — every caller below opens nothing"$'\n'
	for f in "$WAYLE_DIR"/layouts/*.toml; do
		[[ -s $f ]] || continue
		panelseen=$((panelseen + 1))
		if grep -q 'dropdown:weather' "$f"; then
			panelbad+="  ${f##*/}: still opens wayle's weather dropdown, which is now unconfigured"$'\n'
		fi
		if grep -q '^\[modules\.weather\]' "$f"; then
			panelbad+="  ${f##*/}: carries [modules.weather] for a dropdown nothing opens"$'\n'
		fi
		# A layout without custom-weather (`minimal`) has no click to check, and
		# that is the layout deliberately dropping the module.
		if grep -q 'id = "weather"' "$f" &&
			! grep -A8 'id = "weather"' "$f" | grep -q 'left-click = ".*weather\.sh panel"'; then
			panelbad+="  ${f##*/}: custom-weather's left click no longer opens the panel"$'\n'
		fi
	done
	grep -q 'weather\.sh panel' "$MANGO/universal/bind-shared.conf" ||
		panelbad+="  no key opens the panel — bind-shared.conf does not name the verb"$'\n'
	# WAYBAR IS THE BAR IN SERVICE (docs/adr/0051), so its click is the one that
	# matters. `on-click` ran `refresh` until 2026-08-26 — a fetch whose only
	# output is a two-digit label, i.e. a click that appears to do nothing.
	#
	# jq, not sed: `"format": "{}"` puts a closing brace inside a STRING, so a
	# `/}/` range ends on the format line and never reaches on-click. It read as
	# "no layout opens the panel" for every file that had one.
	wbseen=0
	for f in "$WAYBAR_DIR"/config-*.jsonc; do
		[[ -s $f ]] || continue
		wbclick=$(jq -r '.["custom/weather"]["on-click"] // empty' "$f" 2>/dev/null) || wbclick=""
		# `minimal` carries no weather module, deliberately (docs/adr/0038).
		[[ -n $wbclick ]] || continue
		wbseen=$((wbseen + 1))
		[[ $wbclick == *"weather.sh panel" ]] ||
			panelbad+="  ${f##*/}: custom/weather's left click is '$wbclick', not the panel"$'\n'
	done
	[[ $wbseen -gt 0 ]] ||
		panelbad+="  no waybar config carries custom/weather — the scan is broken, not the repo"$'\n'
	if [[ $panelseen -eq 0 ]]; then
		bad "no wayle layout read — the scan is broken, not the repo" "$WAYLE_DIR/layouts"
	elif [[ -n $panelbad ]]; then
		bad "the weather panel is not the one this repo draws" "$panelbad"
	else
		ok "$wbseen waybar configs, $panelseen wayle layouts and one key open weather.sh's rofi panel"
	fi

	# 3. THE CONTROL-CENTRE ROW MUST NOT FETCH. That render is parallel and
	#    costs its slowest row (73 ms); only `read` never opens a socket. The
	#    symptom of getting it wrong is a menu that does not appear.
	if [[ -f $CC ]]; then
		wverb=$(sed -n '/^state_weather() {/,/^}/p' "$CC" | grep -oE 'weather\.sh" (status|read|refresh)' | awk '{print $2}')
		if [[ -z $wverb ]]; then
			bad "state_weather does not call weather.sh — the scan is broken, not the repo"
		elif [[ $wverb != read ]]; then
			bad "the control-centre weather row calls weather.sh '$wverb'" \
				"only 'read' is cache-only; the others can block the whole menu on a 10s curl"
		else
			ok "the control-centre weather row calls weather.sh read — no socket on the render path"
		fi
	fi

	# 4. EVERY WMO CODE WITH A PHRASE HAS A GLYPH. `icon_for` ends in `*`, so a
	#    code it does not know draws na and nothing complains — the row renders,
	#    wearing the wrong weather.
	mapfile -t wmo_desc < <(
		sed -n '/^describe() {/,/^}/p' "$WEATHER_SH" |
			sed -n 's/^\t\([0-9 |]*[0-9]\)).*/\1/p' | tr -d ' ' | tr '|' '\n' | sort -un
	)
	wmo_icons=$(
		sed -n '/^icon_for() {/,/^}/p' "$WEATHER_SH" |
			sed -n 's/^\t\([0-9 |]*[0-9]\)).*/\1/p' | tr -d ' ' | tr '|' '\n' | sort -un
	)
	if [[ ${#wmo_desc[@]} -eq 0 || -z $wmo_icons ]]; then
		bad "no WMO codes read out of weather.sh — the scan is broken, not the repo" \
			"describe=${#wmo_desc[@]}"
	else
		wmomiss=""
		for c in "${wmo_desc[@]}"; do
			grep -qxF "$c" <<<"$wmo_icons" || wmomiss+=" $c"
		done
		for c in $wmo_icons; do
			printf '%s\n' "${wmo_desc[@]}" | grep -qxF "$c" || wmomiss+=" $c(icon only)"
		done
		if [[ -z $wmomiss ]]; then
			ok "all ${#wmo_desc[@]} WMO codes weather.sh describes also have a glyph"
		else
			bad "weather.sh's describe() and icon_for() cover different WMO codes" \
				"a code with a phrase and no glyph draws nf-weather-na and looks merely unsettled:$wmomiss"
		fi
	fi

	# 5. THE QUERY AND THE TOOLTIP, from both ends. open-meteo returns exactly
	#    the fields asked for and says nothing about the rest, so a name dropped
	#    from the URL is ONE tooltip line that stops rendering while the six
	#    around it stay right — and a field asked for and never read is a fetch
	#    nobody uses. Compared per block, so `is_day` under `hourly` cannot
	#    stand in for `is_day` under `current`.
	wreq=$(
		sed -n 's/.*--data-urlencode "\(current\|hourly\|daily\)=\([^"]*\)".*/\1 \2/p' "$WEATHER_SH" |
			while read -r blk list; do
				tr ',' '\n' <<<"$list" | sed "/^$/d; s/^/$blk./"
			done | sort -u
	)
	# render() reads the cache as `$w.<block>.<field>`; `.time` comes back
	# unasked with every block, so it is the one name not in the URL.
	wused=$(
		grep -oE '[$]w\.(current|hourly|daily)\.[a-z_0-9]+' "$WEATHER_SH" |
			sed 's/^[$]w\.//' | grep -vE '\.time$' | sort -u
	)
	if [[ -z $wreq || -z $wused ]]; then
		bad "could not read the open-meteo field lists from weather.sh — the scan is broken, not the repo" \
			"requested=$(wc -l <<<"$wreq") read=$(wc -l <<<"$wused")"
	else
		wfmiss=""
		for f in $wused; do
			grep -qxF "$f" <<<"$wreq" || wfmiss+="  $f is read out of the cache and never asked for"$'\n'
		done
		for f in $wreq; do
			grep -qxF "$f" <<<"$wused" || wfmiss+="  $f is asked for and never read"$'\n'
		done
		if [[ -z $wfmiss ]]; then
			ok "all $(wc -l <<<"$wreq") open-meteo fields weather.sh requests are read by render(), and no others"
		else
			bad "weather.sh's request and its tooltip disagree about fields" "$wfmiss"
		fi
	fi

	# 6. EVERY VERB A CALLER PASSES EXISTS. `weather.sh open` with no `open`
	#    branch prints usage to a stderr nobody reads and exits 1 — a
	#    right-click that does nothing whatever, which is the outcome
	#    menus/control-center.sh refuses to have. docs/adr/0038.
	wverbs=$(sed -n '/^case /,/^esac/p' "$WEATHER_SH" | sed -n 's/^\([a-z]\+\)).*/\1/p' | sort -u)
	wcallers=$(
		{
			jq -r '.["custom/weather"] | to_entries[] | .value | strings' \
				"$WAYBAR_DIR/config-full-top.jsonc" 2>/dev/null |
				grep -oE 'weather\.sh [a-z]+'
			# WAYLE'S LAYOUTS TOO, and they are the bar in service — the waybar
			# config above is the one this scan read alone until 2026-08-26,
			# which left every click on the running bar unchecked. Four of the
			# five verbs are reached from here.
			grep -hoE 'weather\.sh [a-z]+' "$WAYLE_DIR"/layouts/*.toml 2>/dev/null
			# The closing quote is load-bearing here: "a class weather.sh does
			# not emit" is a sentence in that file, and `does` is not a verb.
			grep -oE 'weather\.sh" [a-z]+' "$CC" 2>/dev/null
		} | awk '{print $2}' | sort -u
	)
	if [[ -z $wverbs || -z $wcallers ]]; then
		bad "could not read weather.sh's verbs from both sides — the scan is broken, not the repo" \
			"implemented=[${wverbs//$'\n'/ }] called=[${wcallers//$'\n'/ }]"
	else
		wvmiss=""
		for v in $wcallers; do
			grep -qxF "$v" <<<"$wverbs" || wvmiss+=" $v"
		done
		if [[ -z $wvmiss ]]; then
			ok "every weather.sh verb the bar and the control centre call is implemented: ${wcallers//$'\n'/ }"
		else
			bad "weather.sh is called with a verb it does not implement:$wvmiss" \
				"it prints usage and exits 1, so the click does nothing at all"
		fi
	fi

	# 7. THE BROWSER `open` REACHES. xdg-open resolves this through
	#    mimeapps.list and falls back to whatever else claims the scheme when
	#    the .desktop it names is not installed — silently, which is how
	#    SUPER+b opened chromium for a month (universal/bind.conf).
	whandler=$(
		sed -n 's|^x-scheme-handler/https=||p' "$GEN_CFG/mimeapps.list" 2>/dev/null |
			tr ';' '\n' | sed '/^$/d' | head -1
	)
	if [[ -z $whandler ]]; then
		bad "no https handler in the generated mimeapps.list" \
			"weather.sh open lands wherever xdg-open guesses"
	elif [[ -e "$GEN/home-path/share/applications/$whandler" || -e "$SYS/sw/share/applications/$whandler" ]]; then
		ok "https opens $whandler, which this generation installs — weather.sh open reaches it"
	else
		bad "mimeapps.list hands https to $whandler and nothing installs it" \
			"xdg-open falls back to another browser without saying so"
	fi
fi

# --- noctalia mode ----------------------------------------------------------
# All of this is gated on the mode's directory existing, so removing noctalia
# (docs/SYSTEM.md §6) removes the checks with it rather than leaving three
# failures behind. Inside the gate nothing is allowed to skip.
if [[ -d "$MANGO/noctalia" ]]; then
	# The mode without the package is a mode that starts nothing. Resolve the
	# store path off the binary rather than looking under $SYS/sw/share:
	# environment.pathsToLink does not link share/noctalia-shell, so the QML
	# and the Assets are reachable only through the package itself.
	NOCT_BIN="$SYS/sw/bin/noctalia-shell"
	NOCT_SHARE=""
	if [[ ! -x $NOCT_BIN ]]; then
		bad "the noctalia mode exists but noctalia-shell is not in the system profile" "$NOCT_BIN"
	else
		NOCT_SHARE="$(readlink -f "$NOCT_BIN")"
		NOCT_SHARE="${NOCT_SHARE%/bin/noctalia-shell}/share/noctalia-shell"
		[[ -d $NOCT_SHARE ]] || {
			bad "noctalia-shell has no share/noctalia-shell — the scan is broken, not the repo" "$NOCT_SHARE"
			NOCT_SHARE=""
		}
	fi

	# noctalia IGNORES a settings key it does not know, in silence, so a key
	# renamed upstream stops applying and reads exactly like a key that was
	# never set. Both halves of docs/adr/0022 are checked: the first-run seed
	# and the pin merged on every mode entry.
	if [[ -n $NOCT_SHARE ]]; then
		defaults="$NOCT_SHARE/Assets/settings-default.json"
		if [[ ! -f $defaults ]]; then
			bad "noctalia ships no Assets/settings-default.json — the scan is broken, not the repo"
		else
			# settings.json is hand-written under dotfiles/; settings-pinned.json
			# is GENERATED, because one of its keys is the colour scheme's name.
			# Both are read from where they actually land, not from one place.
			keyerr=""
			keys=0
			for f in "$MANGO/noctalia/settings.json" \
				"$GEN_CFG/mango/noctalia/settings-pinned.json"; do
				n=$(jq -r '[paths] | length' "$f" 2>/dev/null || echo 0)
				keys=$((keys + n))
				while read -r p; do
					[[ -z $p ]] && continue
					keyerr+="  $(basename "$f"): $p is not a key noctalia has"$'\n'
				done < <(
					jq -r --slurpfile d "$defaults" \
						'paths as $p | select(($d[0] | getpath($p)) == null) | $p | join(".")' \
						"$f" 2>/dev/null
				)
			done
			if [[ $keys -eq 0 ]]; then
				bad "no keys read from the noctalia settings files — the scan is broken, not the repo"
			elif [[ -z $keyerr ]]; then
				ok "all $keys noctalia settings keys exist in the shipped defaults"
			else
				bad "noctalia settings key mismatch" "$keyerr"
			fi

			# A scheme name that resolves to no file leaves the shell on
			# whatever it last loaded — the machine ends up half this palette and
			# half noctalia purple, which looks like a theme, not a fault.
			# Resolution mirrors ColorSchemeService.resolveSchemePath().
			scheme=$(jq -r '.colorSchemes.predefinedScheme // empty' \
				"$GEN_CFG/mango/noctalia/settings-pinned.json" 2>/dev/null)
			case "$scheme" in
			"Noctalia (default)") schemedir="Noctalia-default" ;;
			"Noctalia (legacy)") schemedir="Noctalia-legacy" ;;
			"Tokyo Night") schemedir="Tokyo-Night" ;;
			"Rose Pine") schemedir="Rosepine" ;;
			*) schemedir="$scheme" ;;
			esac
			# TWO places it may live, because a scheme no longer has to be one
			# noctalia ships: `ColorSchemeService` scans the package's Assets AND
			# `~/.config/noctalia/colorschemes`, and dotfiles.nix writes the mode
			# scheme into the second (docs/adr/0041). Heartbox is the first scheme
			# here that exists only in the generation.
			noct_gen="$GEN_CFG/noctalia/colorschemes/$schemedir/$schemedir.json"
			if [[ -z $scheme ]]; then
				bad "no predefinedScheme pinned — noctalia would keep its own palette while the rest of the machine follows palette.nix"
			elif [[ -f "$NOCT_SHARE/Assets/ColorScheme/$schemedir/$schemedir.json" ]]; then
				ok "noctalia's pinned colour scheme ($scheme) ships with the package"
			elif [[ -s $noct_gen ]]; then
				# Generated, so it is worth asserting it is a SCHEME and not just a
				# file: noctalia reads `.dark` or `.light` by darkMode and renders
				# whatever it finds, so an object missing the half in use leaves the
				# shell on its last palette without a word.
				nsch_bg=$(jq -r '.dark.mSurface // empty' "$noct_gen" 2>/dev/null)
				nsch_keys=$(jq -r '(.dark | keys | length) // 0' "$noct_gen" 2>/dev/null)
				want_bg="#$(pal '.bg0')"
				if [[ $nsch_keys -lt 16 ]]; then
					bad "noctalia's generated scheme ($scheme) has $nsch_keys keys under .dark, expected at least 16" \
						"$noct_gen — noctalia renders what it finds and falls back for the rest"
				elif [[ ${nsch_bg,,} != "${want_bg,,}" ]]; then
					bad "noctalia's generated scheme ($scheme) has mSurface $nsch_bg, not $want_bg" \
						"the shell would be a different scheme from the mango chrome around it"
				else
					ok "noctalia's pinned colour scheme ($scheme) is generated into the config, with $nsch_keys keys"
				fi
			else
				bad "noctalia has no colour scheme named $scheme" \
					"neither Assets/ColorScheme/$schemedir/$schemedir.json nor $noct_gen"
			fi

			# And it must be the scheme modes.nix gives the noctalia MODE, not the
			# artefact one. Both halves of that mode's colour now come from the same
			# line — the shell's own palette here, mango's chrome in
			# colors-noctalia.conf — and they are generated in different languages in
			# different files, which is the gap a scheme change walks into. A drift
			# here is a shell in one scheme inside borders in another, and that reads
			# as a design rather than a fault. docs/adr/0034.
			nsch=$(jq -r '.modes.noctalia // empty' "$SCHEMES" 2>/dev/null)
			nwant=$(jq -r ".schemes.\"$nsch\".apps.noctalia // empty" "$SCHEMES" 2>/dev/null)
			if [[ -z $nsch || -z $nwant ]]; then
				bad "could not read the noctalia mode's scheme from modes.nix" \
					"mode='$nsch' name='$nwant' — the agreement below would be asserted about nothing"
			elif [[ $scheme != "$nwant" ]]; then
				bad "noctalia pins '$scheme' but modes.nix gives its mode '$nsch' (= '$nwant')" \
					"the shell and the mango chrome drawn around it would be in different schemes"
			else
				ok "noctalia's pinned scheme matches modes.nix's '$nsch' for its mode"
			fi

			# noctalia's TEMPLATE engine stays off, and that is a decision with a
			# record: docs/adr/0036. Asserted rather than merely written, because
			# its symptom is not an error — a template renders a sidecar and its
			# post-hook edits the app's real config to point at it, so enabling
			# one puts a second writer on `kitty/current-theme.conf` and
			# `foot/themes/noctalia` (both apply_theme's, docs/adr/0034), and the
			# gtk/mango/yazi hooks REPLACE a read-only store symlink with a local
			# copy. Nothing crashes; the repo just stops owning the file.
			#
			# Blunt on purpose: any non-empty list fails, not a blocklist of the
			# harmful names. A blocklist needs updating whenever upstream adds a
			# template and passes by finding nothing when one is renamed.
			tmpl_on=$(jq -r '.templates.enableUserTheming // false' \
				"$GEN_CFG/mango/noctalia/settings-pinned.json" 2>/dev/null)
			tmpl_n=$(jq -r '(.templates.activeTemplates // []) | length' \
				"$GEN_CFG/mango/noctalia/settings-pinned.json" 2>/dev/null)
			if [[ -z $tmpl_on || -z $tmpl_n ]]; then
				bad "could not read noctalia's templates pin — the scan is broken, not the repo" \
					"enableUserTheming='$tmpl_on' activeTemplates='$tmpl_n'"
			elif [[ $tmpl_on != false ]]; then
				bad "noctalia pins enableUserTheming=$tmpl_on" \
					"its templates write kitty's and foot's colours, which apply_theme owns — docs/adr/0036"
			elif [[ $tmpl_n -ne 0 ]]; then
				bad "noctalia pins $tmpl_n active template(s)" \
					"every one either writes a path apply_theme owns or a file nothing here reads — docs/adr/0036"
			else
				ok "noctalia's template engine is off and its template list is empty"
			fi
		fi
	fi

	# `noctalia-shell ipc call <target> <fn>` prints "Target not found." or
	# "Function not found." and EXITS 0 — the dwl-era `mmsg -s -d` shape, which
	# broke five scripts here without a word. The names live in shell.sh's case
	# table and in the `lockscreen` wrapper; the shell declares them as
	# `IpcHandler { target: … function x() }` in its QML. Neither side can see
	# the other, so pair them here.
	#
	# The wrapper is scanned as a BUILT script rather than as a source file:
	# it is generated in pkgs/default.nix, and the unattended lock is the one
	# caller nobody is watching when it fails (docs/adr/0024).
	if [[ -n $NOCT_SHARE ]]; then
		SHELL_SH="$MANGO/scripts/menus/shell.sh"
		mapfile -t IPC_WRAPPER < <(
			sed -n 's/.*noctalia-shell ipc call \([A-Za-z]* [A-Za-z]*\).*/\1/p' \
				"$LOCKBIN" 2>/dev/null
		)
		mapfile -t IPC_PAIRS < <(
			{
				# Anchored on `ipc=` alone: the arm label it used to share a
				# line with moved when shfmt split the case arms, and it was
				# never what this scan wanted anyway.
				sed -n 's/^[[:space:]]*ipc="\([^"]*\)".*/\1/p' "$SHELL_SH"
				printf '%s\n' "${IPC_WRAPPER[@]}"
			} | grep . | sort -u
		)
		if [[ ${#IPC_PAIRS[@]} -eq 0 ]]; then
			bad "no ipc pairs read from shell.sh — the scan is broken, not the repo"
		elif [[ ${#IPC_WRAPPER[@]} -eq 0 ]]; then
			# The wrapper's own floor. Without it the pairs all come from
			# shell.sh and the check passes by finding nothing, while the
			# unattended lock has quietly gone back to swaylock in noctalia mode
			# — a difference you only see at 3am, on the screen you are trying
			# to unlock.
			bad "lockscreen makes no noctalia ipc call — the sleep lock is no longer noctalia's in noctalia mode" \
				"$LOCKBIN"
		else
			mapfile -t IPC_QML < <(grep -rl 'IpcHandler' "$NOCT_SHARE")
			ipcerr=""
			for pair in "${IPC_PAIRS[@]}"; do
				t=${pair%% *}
				f=${pair##* }
				# The function must be inside THAT target's block. Two
				# independent greps would pass `dock clear`, since some other
				# target does declare `clear`. `intgt` is recomputed on every
				# `target:` line, so it closes at the next one.
				awk -v t="$t" -v f="$f" '
					/target: "/ { intgt = ($0 ~ "target: \"" t "\"") }
					intgt && $0 ~ "function " f "\\(" { found = 1; exit }
					END { exit !found }
				' "${IPC_QML[@]}" ||
					ipcerr+="  $t $f is called by shell.sh but noctalia has no such handler"$'\n'
			done
			if [[ -z $ipcerr ]]; then
				ok "all ${#IPC_PAIRS[@]} noctalia ipc calls name a handler the shell declares"
			else
				bad "noctalia ipc mismatch" "$ipcerr"
			fi
		fi
	fi

	# The overlay rewrites noctalia's dwl-era `mmsg -s -d <func>` to mango's verb
	# form (docs/adr/0025). Both halves of that can rot in silence: the patch
	# could stop applying, and a verb could stop being a function mango has —
	# `mmsg` answers an unknown one with `{"error":…}` and exits 0, which is the
	# failure the patch exists to remove, not a new one.
	if [[ -n $NOCT_SHARE ]]; then
		MANGO_BIN="$SYS/sw/bin/mango"
		mapfile -t MMSG_FUNCS < <(
			grep -ohE 'mmsg", "dispatch", "[a-z_]+|mmsg dispatch [a-z_]+' \
				"$NOCT_SHARE/Services/Compositor/MangoService.qml" 2>/dev/null |
				grep -oE '[a-z_]+$' | sort -u
		)
		if [[ ${#MMSG_FUNCS[@]} -lt 5 ]]; then
			# The floor. An unapplied patch leaves every call in the flag form,
			# so this list empties rather than mismatching — the launcher would
			# go back to doing nothing at all, reported by nobody.
			bad "only ${#MMSG_FUNCS[@]} mmsg verb calls in MangoService.qml, expected 5 — the overlay patch is not applied" \
				"$NOCT_SHARE/Services/Compositor/MangoService.qml"
		elif [[ ! -e $MANGO_BIN ]]; then
			bad "no mango binary to check the verbs against — the scan is broken, not the repo" "$MANGO_BIN"
		else
			# mango's own strings are the function table. Extracting whole
			# tokens rather than grepping for each name means `quit` cannot
			# match inside `quitting`.
			#
			# Through a FILE, not a pipe into `grep -q`: `-q` exits at the first
			# match, which SIGPIPEs the writer part-way through a 2,000-line
			# list. That is noise on a hit and a WRONG ANSWER on a miss, since
			# the reader never sees the rest.
			mango_words="${TMPDIR:-/tmp}/mango-words.$$"
			grep -aoE '[a-z_]{3,}' "$MANGO_BIN" | sort -u >"$mango_words"
			mmsgerr=""
			for f in "${MMSG_FUNCS[@]}"; do
				grep -qxF "$f" "$mango_words" ||
					mmsgerr+="  $f is dispatched by noctalia but mango declares no such function"$'\n'
			done
			rm -f "$mango_words"
			if [[ -z $mmsgerr ]]; then
				ok "all ${#MMSG_FUNCS[@]} mmsg verbs noctalia dispatches are functions mango has"
			else
				bad "noctalia dispatches a function mango does not have" "$mmsgerr"
			fi
		fi

		# The lock wrapper calls `noctalia-shell ipc call` by absolute path, and
		# quickshell resolves an instance by the shell.qml PATH it was started
		# from — so a wrapper built against a DIFFERENT derivation than the unit
		# runs finds "No running instances" and hands every unattended lock back
		# to swaylock (docs/adr/0024, 0025). One `prev.` where a `final.` belongs
		# is all it takes, and at runtime that is indistinguishable from noctalia
		# simply being down.
		lock_noct=$(grep -oE '/nix/store/[^ :"]*noctalia-shell[^ :"]*/bin' "$LOCKBIN" 2>/dev/null | head -1)
		sys_noct=$(readlink -f "$SYS/sw/bin/noctalia-shell" 2>/dev/null)
		if [[ -z $lock_noct ]]; then
			bad "lockscreen has no noctalia-shell on its PATH — its ipc call would exit 127" "$LOCKBIN"
		elif [[ ${sys_noct%/bin/noctalia-shell} != "${lock_noct%/bin}" ]]; then
			bad "lockscreen and the system disagree on which noctalia-shell — the lock ipc will never find the running shell" \
				"$lock_noct vs $sys_noct"
		else
			ok "lockscreen's noctalia-shell is the one the unit runs"
		fi
	fi

	# Three files must agree on one unit name — the home-manager unit,
	# night-mode.sh's `UNIT=`, and the stop in noctalia-start.sh — and nothing
	# errors when they stop: `is-active` answers "inactive" for a unit that does
	# not exist, so the guard silently stops matching. docs/adr/0037.
	NOCT_START="$MANGO/scripts/modes/noctalia-start.sh"
	NIGHT_SH="$MANGO/scripts/menus/night-mode.sh"
	nl_unit=$(sed -n 's/^UNIT=\([A-Za-z0-9@._-]*\).*/\1/p' "$NIGHT_SH" | head -1)
	if [[ -z $nl_unit ]]; then
		bad "no UNIT= read from night-mode.sh — the scan is broken, not the repo" "$NIGHT_SH"
	elif [[ ! -f "$GEN_CFG/systemd/user/$nl_unit" ]]; then
		bad "night-mode.sh drives $nl_unit but the generation has no such user unit" \
			"$GEN_CFG/systemd/user/$nl_unit"
	elif ! grep -q "systemctl --user stop ${nl_unit%.service}" "$NOCT_START"; then
		bad "noctalia mode does not stop $nl_unit — night light would stay on in the one mode that cannot reach it" \
			"$NOCT_START"
	elif grep -v '^[[:space:]]*#' "$NOCT_START" | grep -q "pkill.*${nl_unit%.service}"; then
		# Restart=always undoes a kill three seconds later — docs/gotchas.md →
		# night light. Comments stripped first: the script explains that
		# noctalia pkills wlsunset, and this matched that sentence.
		bad "noctalia-start.sh pkills ${nl_unit%.service}; Restart=always brings it straight back" \
			"$NOCT_START"
	else
		ok "noctalia mode stops $nl_unit, the unit night-mode.sh drives"
	fi

	# `layerrule=…,layer_name:X` naming a namespace nothing creates is a rule
	# that never fires and never says so — the same class as the rofi layer
	# rules that matched nothing for months. noctalia's
	# namespaces are `<name>-<screen>`, so the configs carry an anchored prefix
	# and this asserts the prefix still matches a namespace the shipped QML
	# declares.
	if [[ -n $NOCT_SHARE ]]; then
		mapfile -t NOCT_LAYERS < <(
			grep -rhoE 'layer_name:\^?noctalia[a-z-]*' "$MANGO" --include='*.conf' |
				sed 's/^layer_name:\^\?//' | sort -u
		)
		if [[ ${#NOCT_LAYERS[@]} -eq 0 ]]; then
			bad "no noctalia layer rules found — mango would double every panel animation noctalia plays"
		else
			layererr=""
			for l in "${NOCT_LAYERS[@]}"; do
				grep -rqF "namespace: \"$l" "$NOCT_SHARE" ||
					layererr+="  $l matches no namespace noctalia declares"$'\n'
			done
			if [[ -z $layererr ]]; then
				ok "every noctalia layer rule (${#NOCT_LAYERS[@]}) matches a namespace the shell declares"
			else
				bad "noctalia layer rule mismatch" "$layererr"
			fi
		fi
	fi
fi

# --- power profiles ---------------------------------------------------------
# power-profiles-tlp translates between three things that live in three files
# and have no compiler between them: TLP's numeric state, `power-mode`'s
# argument list, and the PPD bus name. Every one of them fails silently when it
# drifts — a wrong profile name is exit 2 at click time, a wrong code renders a
# stale profile forever, a wrong bus name is a service nothing finds, which is
# indistinguishable from the state this daemon was written to fix.
# docs/adr/0026.
PPD_SRC="$SRC/pkgs/power-profiles-tlp/daemon.py"
PPD_POLICY="$SRC/pkgs/power-profiles-tlp/dbus-policy.conf"
if [[ ! -f $PPD_SRC || ! -f $PPD_POLICY ]]; then
	bad "power-profiles-tlp is missing a source or policy file" "$PPD_SRC $PPD_POLICY"
else
	# 1. The daemon and power-mode must accept the same three profile names.
	#    power-mode rejects anything else with exit 2, which reaches the user as
	#    a slider that snaps back.
	mapfile -t PPD_PROFILES < <(
		sed -n 's/^PROFILES = (\(.*\))$/\1/p' "$PPD_SRC" |
			grep -oE '"[a-z-]+"' | tr -d '"' | sort -u
	)
	mapfile -t MODE_PROFILES < <(
		sed -n 's/^[[:space:]]*\(performance | balanced | power-saver\)) ;;$/\1/p' \
			"$SRC/modules/system/power.nix" | tr -d ' ' | tr '|' '\n' | sort -u
	)
	if [[ ${#PPD_PROFILES[@]} -eq 0 || ${#MODE_PROFILES[@]} -eq 0 ]]; then
		bad "no profile names read from the daemon or from power-mode — the scan is broken, not the repo"
	elif [[ ${PPD_PROFILES[*]} != "${MODE_PROFILES[*]}" ]]; then
		bad "power-profiles-tlp and power-mode disagree on the profile names" \
			"daemon: ${PPD_PROFILES[*]} / power-mode: ${MODE_PROFILES[*]}"
	else
		ok "power-profiles-tlp and power-mode accept the same ${#PPD_PROFILES[@]} profiles"
	fi

	# 2. The daemon and the waybar module both decode /run/tlp/last_pwr, and
	#    nothing makes them agree. `fanless` is this repo's name for TLP's
	#    `power-saver` (docs/adr/0017) and is the ONE deliberate difference, so
	#    it is normalised here rather than tolerated by a looser comparison.
	mapfile -t PPD_CODES < <(
		sed -n 's/^CODE_TO_PROFILE = {\(.*\)}$/\1/p' "$PPD_SRC" |
			grep -oE '"[0-9]": "[a-z-]+"' | tr -d '"' | tr -d ' ' | sort -u
	)
	mapfile -t BAR_CODES < <(
		sed -nE 's/^[[:space:]]*([0-9])\) name=([a-z-]+).*$/\1:\2/p' \
			"$MANGO/scripts/system/power-profile.sh" | sed 's/fanless/power-saver/' | sort -u
	)
	if [[ ${#PPD_CODES[@]} -eq 0 || ${#BAR_CODES[@]} -eq 0 ]]; then
		bad "no last_pwr codes read from the daemon or the waybar module — the scan is broken, not the repo"
	elif [[ ${PPD_CODES[*]} != "${BAR_CODES[*]}" ]]; then
		bad "power-profiles-tlp and the waybar module decode last_pwr differently" \
			"daemon: ${PPD_CODES[*]} / bar: ${BAR_CODES[*]}"
	else
		ok "power-profiles-tlp and the waybar module decode all ${#PPD_CODES[@]} last_pwr codes alike"
	fi

	# 3. One bus name, spelled the same in the daemon and in every rule of the
	#    policy. PPD's name is a fixed external contract, so it is asserted
	#    literally too — a typo made consistently in both files still reaches
	#    no client.
	PPD_NAME=org.freedesktop.UPower.PowerProfiles
	mapfile -t PPD_NAMES < <(
		{
			sed -n 's/^BUS_NAME = "\(.*\)"$/\1/p' "$PPD_SRC"
			grep -oE '(own|send_destination)="[^"]+"' "$PPD_POLICY" | cut -d'"' -f2
		} | sort -u
	)
	if [[ ${#PPD_NAMES[@]} -eq 0 ]]; then
		bad "no bus name read from the daemon or the policy — the scan is broken, not the repo"
	elif [[ ${#PPD_NAMES[@]} -ne 1 || ${PPD_NAMES[0]} != "$PPD_NAME" ]]; then
		bad "the daemon and its dbus policy do not all name $PPD_NAME" "${PPD_NAMES[*]}"
	else
		ok "the daemon and its dbus policy all name $PPD_NAME"
	fi

	# 4. dbus rejects a malformed policy file, and an XML comment containing a
	#    double hyphen is malformed — which this file's first draft was. The
	#    file is loaded by the system bus, so the blast radius is every service
	#    on it, not just this one.
	if ! command -v xmllint >/dev/null; then
		bad "xmllint is absent — the dbus policy went unchecked, which is not a pass"
	elif ! xmllint --noout "$PPD_POLICY" 2>/dev/null; then
		bad "the dbus policy is not well-formed XML — the system bus would reject it" "$PPD_POLICY"
	else
		ok "the dbus policy parses as XML"
	fi

	# 5. The unit must exist in the built system and must pass --power-mode.
	#    Left to a PATH lookup the daemon refuses to start, which is honest but
	#    is a boot-time failure for a thing decided at build time.
	PPD_UNIT="$SYS/etc/systemd/system/power-profiles-tlp.service"
	PPD_PKG=""
	if [[ ! -f $PPD_UNIT ]]; then
		bad "power-profiles-tlp is packaged but no unit runs it — the PPD name would stay unowned" "$PPD_UNIT"
	else
		ppd_exec=$(sed -n 's/^ExecStart=//p' "$PPD_UNIT")
		# The store path the unit actually runs, so check 6 reads the same
		# package rather than one the overlay merely could produce.
		PPD_PKG=${ppd_exec%%/bin/power-profiles-tlp*}
		ppd_mode=$(grep -oE '\-\-power-mode [^ ]+' <<<"$ppd_exec" | awk '{print $2}')
		if [[ -z $ppd_mode ]]; then
			bad "the power-profiles-tlp unit passes no --power-mode — it would start and switch nothing" "$ppd_exec"
		elif [[ ! -x $ppd_mode ]]; then
			bad "the power-profiles-tlp unit names a power-mode that is not executable" "$ppd_mode"
		else
			ok "the power-profiles-tlp unit runs an executable power-mode"
		fi
	fi

	# 6. A running unit is NOT the same as an activatable name, and the
	#    difference is invisible from `systemctl status`. quickshell probes the
	#    name at startup and, finding it unowned, tries to ACTIVATE it — then
	#    gives up for the life of the process when that fails. Observed exactly
	#    once, on the first live run: "The name is not activatable", after which
	#    every noctalia profile call returned early and printed nothing.
	PPD_ACT="$PPD_PKG/share/dbus-1/system-services/$PPD_NAME.service"
	if [[ -z $PPD_PKG ]]; then
		bad "could not resolve the power-profiles-tlp package from the unit — the scan is broken, not the repo"
	elif [[ ! -f $PPD_ACT ]]; then
		bad "power-profiles-tlp ships no dbus activation file — a client that starts first gives up permanently" "$PPD_ACT"
	else
		act_name=$(sed -n 's/^Name=//p' "$PPD_ACT")
		act_unit=$(sed -n 's/^SystemdService=//p' "$PPD_ACT")
		act_exec=$(sed -n 's/^Exec=//p' "$PPD_ACT")
		if [[ $act_name != "$PPD_NAME" ]]; then
			bad "the activation file names $act_name, not $PPD_NAME — dbus would activate nothing"
		elif [[ $act_unit != power-profiles-tlp.service ]]; then
			bad "the activation file names unit $act_unit, which is not the one that serves the name" "$PPD_ACT"
		elif [[ ! -x $act_exec ]]; then
			bad "the activation file's Exec is not executable — the non-systemd fallback would 127" "$act_exec"
		else
			ok "the dbus activation file names $PPD_NAME and an executable power-profiles-tlp.service"
		fi
	fi

	# 7. Two owners for one bus name is docs/adr/0005 verbatim, and the loser
	#    here is whichever starts second — silently, since ours exits 1 into the
	#    journal and PPD would simply serve profiles TLP never applied.
	if [[ -f "$SYS/etc/systemd/system/power-profiles-daemon.service" ]]; then
		bad "power-profiles-daemon is enabled alongside power-profiles-tlp — two owners for $PPD_NAME"
	else
		ok "power-profiles-daemon is absent, so power-profiles-tlp owns $PPD_NAME alone"
	fi
fi

# rofi reads ~/.config/rofi/config.rasi, which is in a different tree from the
# mango configs that use it — the .rasi landing in the repo says nothing about
# rofi finding it. Same shape as elephant's menus.toml before it (docs/adr/0014).
rasi_decl=$(grep -rh 'rofi/config.rasi' "$SRC/modules/home/dotfiles.nix" 2>/dev/null)
if [[ -z $rasi_decl ]]; then
	bad "nothing declares rofi/config.rasi — rofi would fall back to its built-in theme"
elif [[ ! -f "$SRC/dotfiles/rofi/config.rasi" ]]; then
	bad "config.rasi is declared but absent from the source — the scan is broken"
else
	ok "rofi's config.rasi is declared and present"
fi

# config.rasi's `terminal:` is a bare binary name that only run mode's
# Shift+Enter and ssh mode ever reach, so a name that stops resolving is a key
# that does nothing rather than an error. rofi's own default hides it further:
# `rofi-sensible-terminal` probes eighteen names and execs whichever resolves
# first, which here was not the wanted one. docs/gotchas.md -> rofi.
rofi_term=$(sed -n 's/^ *terminal: *"\([^"]*\)".*/\1/p' "$SRC/dotfiles/rofi/config.rasi")
if [[ -z $rofi_term ]]; then
	bad "config.rasi names no terminal, so rofi falls back to probing for one"
elif [[ $rofi_term == rofi-sensible-terminal ]]; then
	# It resolves, so a name check alone would pass this. It is the default, and
	# the default is the defect: it probes eighteen names in its own order and
	# picked kitty here.
	bad "rofi's terminal is back to rofi-sensible-terminal, which probes and picked the wrong one"
elif [[ -x "$PROFILE/$rofi_term" || -x "$SYS/sw/bin/$rofi_term" ]]; then
	ok "rofi's terminal is $rofi_term, and it resolves"
else
	bad "rofi's terminal is $rofi_term, which is in neither profile — run mode's Shift+Enter would do nothing"
fi

# rofi's modes come from two places that cannot see each other: the built-ins,
# and the plugins listed in modules/system/desktop.nix. A mode named by
# config.rasi or by a `-show` bind whose plugin is not built makes rofi print
# "Mode <x> is not found" to a stderr nobody is reading and exit 1 — a key that
# does nothing, which is this repo's signature failure. Read what the BUILT
# binary reports rather than the Nix that asked for it: `-h` lists exactly what
# dlopens, so a plugin that builds but fails to load is caught too. `-no-config`
# so the check does not depend on a home directory.
ROFI="$SYS/sw/bin/rofi"
if [[ ! -x $ROFI ]]; then
	bad "no rofi in the system profile — every menu bind would exit 127" "$ROFI"
else
	# 2>&1, not 2>/dev/null: if rofi cannot start, its reason is the only thing
	# separating "the config is wrong" from "the scan is broken", and throwing
	# it away is how a check comes to pass by finding nothing.
	# HOME/XDG_CACHE_HOME: rofi creates a runtime directory before it does
	# anything else, and under the build sandbox `$HOME` is /homeless-shelter.
	# It cannot, warns, and prints no help at all — so the list came back empty
	# and the check read as "the scan is broken", which is exactly what it said.
	rofi_help=$(HOME="$TMPDIR" XDG_CACHE_HOME="$TMPDIR" "$ROFI" -no-config -h 2>&1)
	mapfile -t DETECTED < <(
		printf '%s\n' "$rofi_help" | sed -n '/Detected modes/,/^$/p' |
			sed -n 's/^[[:space:]]*• *+\?\([a-z]*\).*/\1/p'
	)
	mapfile -t WANTED < <(
		{
			# config.rasi's `modes:` list, comma-separated.
			sed -n 's/^ *modes: *"\([^"]*\)".*/\1/p' "$SRC/dotfiles/rofi/config.rasi" | tr ',' '\n'
			# `rofi -show <mode>` in a bind, a script or a waybar click.
			grep -rhoE -- '-show [a-z]+' "$MANGO" "$SRC/modules/home/waybar.nix" 2>/dev/null |
				cut -d' ' -f2
		} | tr -d ' ' | sort -u | sed '/^$/d'
	)
	# The reverse direction needs the Nix: `-h` cannot say which of the modes it
	# lists came from a plugin, so a plugin nothing reaches would hide among the
	# built-ins.
	mapfile -t PLUGINS < <(
		sed -n '/plugins = \[/,/\];/p' "$SRC/modules/system/desktop.nix" |
			sed -n 's/^ *rofi-\([a-z]*\).*/\1/p'
	)
	if [[ ${#DETECTED[@]} -lt 5 ]]; then
		bad "rofi reports only ${#DETECTED[@]} modes — the scan is broken, not the config" \
			"$(printf '%s\n' "$rofi_help" | head -3)"
	elif [[ ${#WANTED[@]} -eq 0 || ${#PLUGINS[@]} -eq 0 ]]; then
		bad "no rofi modes or plugins found in the source — the scan is broken, not the repo"
	else
		moderr=""
		for w in "${WANTED[@]}"; do
			printf '%s\n' "${DETECTED[@]}" | grep -qxF "$w" ||
				moderr+="  $w is named by config.rasi or a bind but rofi does not have it"$'\n'
		done
		for p in "${PLUGINS[@]}"; do
			printf '%s\n' "${DETECTED[@]}" | grep -qxF "$p" ||
				moderr+="  rofi-$p is built but rofi does not load it"$'\n'
			printf '%s\n' "${WANTED[@]}" | grep -qxF "$p" ||
				moderr+="  rofi-$p is built but nothing reaches it"$'\n'
		done
		if [[ -z $moderr ]]; then
			ok "all ${#WANTED[@]} rofi modes reached are loaded, and both ${#PLUGINS[@]} plugins are reached"
		else
			bad "rofi mode mismatch" "$moderr"
		fi
	fi
fi

printf '\nMango config parse\n'

# Every mango config, parsed by the binary that will run it. The case this
# catches: a broken `source=` makes mango print [ERROR] to stderr, exit 0, and
# start without that file's binds. The keys just stop working.
#
# So fail on any stderr, not on the exit status. Confirmed against planted
# defects — a renamed universal/*.conf gives stderr with exit 0, an unknown
# keyword gives stderr with exit 1.
#
# Fake HOME and NO `-c`, which reproduces production exactly. Two traps this
# sidesteps rather than manages:
#   -c FILE  relative sources resolve against dirname(cli_config_path), so
#            pointing it at a mode conf reports all 20 source= lines missing.
#   -p -c    getopt returns on -p mid-parse (mango.c:7797), so `mango -p -c F`
#            validates the LIVE config and exits 0 having never seen F.
# The binary comes from the system profile, not a build input: this has to be
# the mango that will actually run.
MANGO_BIN="$SYS/sw/bin/mango"
if [[ ! -x $MANGO_BIN ]]; then
	bad "no mango in the system profile — there is no compositor" "$MANGO_BIN"
elif [[ ${#MODES[@]} -eq 0 ]]; then
	bad "no modes to parse — the scan is broken, not the repo"
else
	MHOME=$(mktemp -d)
	mkdir -p "$MHOME/.config"
	# --no-preserve=mode because the copied DIRECTORY is 0555 otherwise, and
	# nothing — not even a symlink — can be created inside it.
	cp -r --no-preserve=mode "$GEN_CFG/mango" "$MHOME/.config/mango"

	parse_err=""
	parsed=0
	for m in "${MODES[@]}"; do
		src="$MHOME/.config/mango/$m/$m.conf"
		if [[ ! -f $src ]]; then
			parse_err+="  $m/$m.conf is not in the generation"$'\n'
			continue
		fi
		# A link, matching apply_mode (docs/adr/0040). Staging a copy would test
		# a shape production no longer has. Checked, because a failed stage
		# leaves the previous mode's config.conf in place and mango would parse
		# that one again, passing for a file it never read.
		if ! ln -sfn "$src" "$MHOME/.config/mango/config.conf"; then
			parse_err+="  $m: could not stage config.conf"$'\n'
			continue
		fi
		err=$(HOME="$MHOME" "$MANGO_BIN" -p 2>&1 >/dev/null)
		parsed=$((parsed + 1))
		if [[ -n $err ]]; then
			# Strip the colour escapes mango emits, so the report is readable.
			parse_err+="  $m: $(printf '%s' "$err" | sed 's/\x1b\[[0-9;]*m//g' | tr '\n' ' ')"$'\n'
		fi
	done

	if [[ $parsed -lt 1 ]]; then
		bad "no mango config was parsed — the scan is broken, not the repo"
	elif [[ -n $parse_err ]]; then
		bad "mango rejected a config it will start on anyway" "$parse_err"
	else
		ok "all $parsed mango mode configs parse with no diagnostics"
	fi
fi

printf '\nGenerated palette\n'

# waybar/colors.css and rofi/colors.rasi are derived from
# modules/home/palette.nix; the stylesheets that consume them are hand-written
# and reference the names. Both sides fail quietly when they disagree — GTK
# drops a rule naming an undefined @colour and carries on, so the module simply
# renders in the inherited colour, and rofi falls back to its built-in
# Solarized role rather than erroring. Neither writes anywhere anyone reads.
# So: every name used must be defined, and every name defined must be used —
# an unused entry is a colour someone will later assume is live.
# `sigil` is the reference character in the consumer's own language — `@` for
# CSS and rasi, `$` for scss — so the failure names something greppable.
palette_pair() {
	local label=$1 defined=$2 used=$3 sigil=${4:-@} err=""
	# `@import`, `@keyframes` and friends are CSS/rasi at-rules, not colours.
	used=$(printf '%s\n' "$used" | grep -vxE 'import|keyframes|media|theme|define-color')
	if [[ -z $defined ]]; then
		bad "$label: no colours defined — the generated file is missing or the scan is broken"
		return
	fi
	if [[ -z $used ]]; then
		bad "$label: no colour references found in the stylesheets — the scan is broken"
		return
	fi
	while IFS= read -r n; do
		[[ -z $n ]] && continue
		printf '%s\n' "$defined" | grep -qxF "$n" || err+="  $sigil$n is used but not defined"$'\n'
	done <<<"$used"
	while IFS= read -r n; do
		[[ -z $n ]] && continue
		printf '%s\n' "$used" | grep -qxF "$n" || err+="  $sigil$n is defined but nothing uses it"$'\n'
	done <<<"$defined"
	if [[ -z $err ]]; then
		ok "$label: all $(printf '%s\n' "$defined" | grep -c .) generated colours are used, and every reference resolves"
	else
		bad "$label palette mismatch" "$err"
	fi
}

palette_pair "waybar" \
	"$(sed -n 's/^@define-color \([a-z-]*\) .*/\1/p' "$WAYBAR_DIR/colors.css" 2>/dev/null | sort -u)" \
	"$(grep -ohE '@[a-z-]+' "$SRC"/dotfiles/mango/waybar/style-*.css 2>/dev/null | tr -d '@' | sort -u)"

# rofi, ONCE PER MODE. `colors.rasi` is a runtime symlink since docs/adr/0034
# and does not exist in the generation at all; what home-manager writes is one
# `colors-<mode>.rasi` per mode, and each is a separate file that could
# separately drop a name. `config.rasi` is shared by every menu in every mode
# (and holds behaviour as well as colour), so the USED side is the same for all.
rofi_used=$(grep -ohE '@[a-z-]+' "$SRC/dotfiles/rofi/config.rasi" 2>/dev/null | tr -d '@' | sort -u)
for m in "${MODE_KEYS[@]}"; do
	palette_pair "rofi ($m)" \
		"$(sed -n 's/^ *\([a-z-]*\): *#[0-9a-f]*;.*/\1/p' "$GEN_CFG/rofi/colors-$m.rasi" 2>/dev/null | sort -u)" \
		"$rofi_used"
done

# wayle, the same pairing in scss. `_colors.scss` is generated from the palette
# and `index.scss` is hand-written, so both halves fail the way the two above
# do: sass resolves an undefined `$var` to nothing and the rule renders in the
# inherited colour. Since docs/adr/0048 four of the five are state colour for
# the three custom modules, which is the half that would rot unnoticed — a
# module whose class stops being emitted takes its rule out of use and the bar
# still renders.
#
# The USED side subtracts what `index.scss` defines for itself: `$groups` is a
# local, not a palette name, and would read as a reference to a colour nobody
# generated.
wayle_scss=$SRC/dotfiles/wayle/index.scss
palette_pair "wayle" \
	"$(sed -n 's/^[$]\([a-z-]*\):.*/\1/p' "$WAYLE_DIR/styles/_colors.scss" 2>/dev/null | sort -u)" \
	"$(comm -23 \
		<(grep -ohE '[$][a-z-]+' "$wayle_scss" 2>/dev/null | tr -d '$' | sort -u) \
		<(sed -n 's/^[$]\([a-z-]*\):.*/\1/p' "$wayle_scss" 2>/dev/null | sort -u))" \
	'$'

# Every file that is supposed to be derived from the palette, and the colour it
# must contain. A generated file that goes missing or renders empty is this
# repo's signature bug: the app falls back to its own defaults and looks merely
# unstyled, which is indistinguishable from a theme someone chose.
#
# The value checked is the accent in each consumer's own spelling, because the
# spelling is where copies hid — `d79921` is `0xd79921ff` to mango and
# `rgb(215, 153, 33)` to swaync, and a repo-wide grep for the hex found neither.
# Read the accent from the RESOLVED palette, not from a hex typed here — a
# check carrying its own copy of the value it is checking passes forever and
# proves nothing. It used to be read back out of `rofi/colors.rasi`, one of the
# generated consumers, because that was the only Nix-resolved value available;
# `$SCHEMES` is now that value at the source, and `colors.rasi` stopped being a
# generated file when it became a runtime symlink (docs/adr/0034). Nothing is
# lost by moving up: the scans below are what prove the generation, and they
# prove it in each consumer's own spelling.
ACCENT=$(pal .accent)

# Everything else comes from the RESOLVED palette, via `pal` (defined at the top
# of this file, alongside the schemes JSON it reads).

# The name is still read out of scheme.nix by hand, and cross-checked against
# what Nix resolved. Nix would fail to import a theme file that does not exist,
# so this cannot catch a typo — what it catches is the two drifting apart: a
# scheme.nix that stopped being the file the build actually read, which would
# make every message below name the wrong scheme while passing.
SCHEME=$(sed -n 's/^"\(.*\)"$/\1/p' "$SRC/modules/home/scheme.nix" 2>/dev/null | tail -1)
THEME_FILE="$SRC/modules/home/themes/$SCHEME.nix"
if [[ -z $SCHEME || ! -s $THEME_FILE ]]; then
	bad "scheme.nix names '$SCHEME', which is not a file in modules/home/themes/" \
		"every palette scan below would read an empty file"
elif [[ $SCHEME != "$PAL_SCHEME" ]]; then
	bad "scheme.nix says '$SCHEME' but the build resolved '$PAL_SCHEME'" \
		"every scan below would audit a scheme this machine is not wearing"
else
	ok "scheme.nix selects '$SCHEME' as the artefact scheme, and themes/$SCHEME.nix exists"
fi
# The artefact scheme's muted accent used to be read here too, for ncspot. It
# is per mode now (docs/adr/0034 phase 3) and resolved per scheme inside the
# swap loop; a copy here would only be a value nothing reads.
if [[ $ACCENT =~ ^[0-9a-f]{6}$ ]]; then
	ACCENT_RGB="rgb($((16#${ACCENT:0:2})), $((16#${ACCENT:2:2})), $((16#${ACCENT:4:2})))"
else
	bad "could not read the accent from the palette" \
		"accent='$ACCENT' — every scan below would pass on an empty needle"
	ACCENT="__unreadable__"
	ACCENT_RGB="__unreadable__"
fi

while IFS='|' read -r path want label; do
	[[ -z $path ]] && continue
	if [[ ! -s "$GEN_CFG/$path" ]]; then
		bad "$label: $path is missing or empty — the consumer falls back to its own theme, silently"
	elif ! grep -qF "$want" "$GEN_CFG/$path"; then
		bad "$label: $path does not contain $want" "generated, but not from modules/home/palette.nix"
	else
		ok "$label: $path is generated from the palette"
	fi
done <<-EOF
	swaync/style.css|${ACCENT_RGB}|swaync
EOF
# ncspot and Equibop used to be two more rows here, against the ARTEFACT accent.
# They are per mode since docs/adr/0034 phase 3 and are checked in the swap loop
# below instead — a row here would now audit whichever mode `tiling` happens to
# be, and pass a mode nobody had looked at.

# mango's chrome, per mode, each in the scheme modes.nix gives that mode
# (docs/adr/0034). Deliberately NOT a row in the table above: the needle differs
# per file now, and checking all three against the artefact accent would pass a
# mode whose generated colours had silently stayed on the wrong scheme — which
# is the whole drift the split exists to make visible.
#
# `focuscolor`, not `bordercolor`. The border role differs by mode BY DESIGN
# (surface in tiling, overlay in noctalia — docs/adr/0022), so it is the
# one line that proves nothing about which scheme produced the file. The accent
# is the same role in all three.
modes_seen=0
while IFS='|' read -r m mscheme; do
	[[ -z $m ]] && continue
	modes_seen=$((modes_seen + 1))
	macc=$(jq -r ".schemes.\"$mscheme\".accent // empty" "$SCHEMES" 2>/dev/null)
	mconf="$GEN_CFG/mango/universal/colors-$m.conf"
	if [[ ! $macc =~ ^[0-9a-f]{6}$ ]]; then
		bad "mango ($m): modes.nix names '$mscheme', which has no accent in the resolved schemes" \
			"the scan below would pass on an empty needle"
	elif [[ ! -s $mconf ]]; then
		bad "mango ($m): colors-$m.conf is missing or empty" \
			"mango skips a source= it cannot resolve without a word and keeps its own built-in colours"
	elif ! grep -qxF "focuscolor=0x${macc}ff" "$mconf"; then
		bad "mango ($m): colors-$m.conf does not carry the accent of '$mscheme' (0x${macc}ff)" \
			"generated, but not from the scheme modes.nix gives this mode"
	else
		ok "mango ($m): colors-$m.conf is generated from '$mscheme'"
	fi
done < <(jq -r '.modes | to_entries[] | "\(.key)|\(.value)"' "$SCHEMES" 2>/dev/null)
if [[ $modes_seen -eq 0 ]]; then
	bad "no modes read from modules/home/modes.nix — the scan is broken, not the repo"
fi

# The runtime colour swap — docs/adr/0034. Three things have to hold, each
# silent on its own:
#
#   1. the sidecar exists and carries THAT mode's accent in that consumer's own
#      spelling — copies have hidden in the spelling before;
#   2. the config that reads it still contains the include;
#   3. the LINK path is not also an xdg.configFile — two owners for one path is
#      an activation failure, and `rofi/colors.rasi` was one until adr/0034.
swap_seen=0
while IFS='|' read -r m mscheme; do
	[[ -z $m ]] && continue
	macc=$(jq -r ".schemes.\"$mscheme\".accent // empty" "$SCHEMES" 2>/dev/null)
	if [[ ! $macc =~ ^[0-9a-f]{6}$ ]]; then
		bad "swap ($m): no accent resolved for '$mscheme' — the scans below would pass on an empty needle"
		continue
	fi
	# ncspot draws its rows in the `muted` set, not the canonical ramp, so its
	# needle is a different colour from the same scheme — the one row here where
	# the main accent would pass a file generated from the wrong palette half.
	mmacc=$(jq -r ".schemes.\"$mscheme\".muted.accent // empty" "$SCHEMES" 2>/dev/null)
	if [[ ! $mmacc =~ ^[0-9a-f]{6}$ ]]; then
		bad "swap ($m): no muted accent resolved for '$mscheme' — the ncspot scan would pass on an empty needle"
		continue
	fi
	# <path>|<needle>|<label>. The needle differs by consumer on purpose.
	while IFS='|' read -r path want label; do
		[[ -z $path ]] && continue
		swap_seen=$((swap_seen + 1))
		if [[ ! -s "$GEN_CFG/$path" ]]; then
			bad "swap ($m): $path is missing or empty" \
				"apply_theme refuses to link a target it cannot find, so the mode switch would leave the colours where they were and say so"
		elif ! grep -qF "$want" "$GEN_CFG/$path"; then
			bad "swap ($m): $path does not carry '$mscheme'\''s accent as $want" \
				"generated, but not from the scheme modes.nix gives this mode"
		else
			ok "swap ($m): $label is generated from '$mscheme'"
		fi
	done <<-EOF
		kitty/colors-$m.conf|#${macc}|kitty
		foot/colors-$m|${macc}|foot
		rofi/colors-$m.rasi|#${macc}|rofi
		ncspot/colors-$m.toml|#${mmacc}|ncspot
		equibop/themes/$m.theme.css|#${macc}|equibop
	EOF

	# Equibop displays `@name`, and a name is not a colour — it read `Catppuccin
	# Mocha` through two scheme changes because every scan here greps for hex.
	eqfile="$GEN_CFG/equibop/themes/$m.theme.css"
	if [[ ! -s $eqfile ]]; then
		: # already reported as missing by the loop above
	elif grep -qF "@name $m ($mscheme)" "$eqfile"; then
		ok "swap ($m): equibop announces itself as '$m ($mscheme)'"
	else
		bad "swap ($m): equibop's @name is not '$m ($mscheme)'" \
			"the name Equibop shows has drifted from the mode and scheme that generated the file"
	fi

	# ncspot is drawn entirely from `muted`, and the needle above only proves
	# that half was reached. `p.accent` where `m.accent` was meant is the right
	# scheme and the wrong half — measured, it passed every other check here.
	# So every hex in the file must be a `muted` value.
	nfile="$GEN_CFG/ncspot/colors-$m.toml"
	mapfile -t mvals < <(jq -r ".schemes.\"$mscheme\".muted | to_entries[] | .value" "$SCHEMES" 2>/dev/null)
	if [[ ${#mvals[@]} -eq 0 ]]; then
		bad "swap ($m): '$mscheme' resolved no muted colours — the scan below would call every hex a stray"
	elif [[ ! -s $nfile ]]; then
		: # already reported as missing by the loop above
	else
		stray=""
		while read -r hex; do
			[[ -z $hex ]] && continue
			printf '%s\n' "${mvals[@]}" | grep -qxF "$hex" || stray+=" $hex"
		done < <(grep -oE '#[0-9a-f]{6}' "$nfile" | tr -d '#' | sort -u)
		if [[ -z $stray ]]; then
			ok "swap ($m): every colour in ncspot's config is from '$mscheme''s muted set"
		else
			bad "swap ($m): ncspot's config carries colours outside '$mscheme''s muted set:$stray" \
				"the right scheme and the wrong half of it — the accent scan above cannot see this"
		fi
	fi
done < <(jq -r '.modes | to_entries[] | "\(.key)|\(.value)"' "$SCHEMES" 2>/dev/null)
if [[ $swap_seen -eq 0 ]]; then
	bad "no per-mode colour sidecars scanned — the scan is broken, not the repo"
else
	ok "$swap_seen per-mode colour sidecars scanned"
fi

# 2. The include lines. A sidecar nothing reads is the same as no sidecar, and
# neither kitty nor foot says anything about a colour file it never opened.
while IFS='|' read -r path want label; do
	[[ -z $path ]] && continue
	if [[ ! -s "$GEN_CFG/$path" ]]; then
		bad "$label: $path is missing — the swap has nothing to reach it through"
	elif ! grep -qF "$want" "$GEN_CFG/$path"; then
		bad "$label: $path does not contain '$want'" \
			"the per-mode colours are generated and then read by nothing; the app keeps its built-in palette"
	else
		ok "$label: reads its colours through the runtime link"
	fi
done <<-EOF
	kitty/kitty.conf|include current-theme.conf|kitty
	foot/foot.ini|include=~/.config/foot/themes/noctalia|foot
	rofi/config.rasi|@import "colors"|rofi
EOF

# 3. The runtime link paths must not be in the generation. home-manager would
# own a path the mode scripts re-point on every switch, which is two owners for
# one file — and the rebuild after would either fight it or back it up forever.
#
# Four are apply_theme's colour links; mango/config.conf is apply_mode's, and
# joined the family when it stopped being a copy (docs/adr/0040). Same rule,
# same failure, so one list.
ownerr=""
for link in kitty/current-theme.conf foot/themes/noctalia rofi/colors.rasi ncspot/config.toml mango/config.conf; do
	[[ -e "$GEN_CFG/$link" ]] && ownerr+="  $link"$'\n'
done
if [[ -z $ownerr ]]; then
	ok "the five runtime links are owned by the mode scripts alone, not by home-manager"
else
	bad "a runtime link is also an xdg.configFile — two owners for one path" "$ownerr"
fi

# And apply_mode must select rather than duplicate. `install`/`cp` here is the
# thing docs/adr/0040 replaced: it worked, so a revert would look fine and would
# quietly reintroduce a config.conf that no longer tracks its mode.
# shellcheck disable=SC2016
if grep -qE '^\s*ln -sfn "\$MANGO_DIR/\$mode/\$mode\.conf" "\$MANGO_DIR/config\.conf"' "$MANGO/scripts/lib.sh"; then
	ok "apply_mode selects config.conf with a link, not a copy"
else
	bad "apply_mode no longer links config.conf" \
		"a copy stops tracking its mode the moment the mode conf is rebuilt"
fi

# And apply_mode has to call it. The rows above prove every file exists; this is
# the one that proves anything reads them at a mode switch. Same shape as the
# idle-inhibitor assertion, and for the same reason: a mode switch that quietly
# skips a step looks exactly like a mode switch.
# SC2016: `$mode` is the literal text being searched for in lib.sh, not a
# variable to expand here.
# shellcheck disable=SC2016
if grep -qE '^\s*apply_theme "\$mode"' "$MANGO/scripts/lib.sh"; then
	ok "apply_mode re-points the colour links on every mode switch"
else
	bad "apply_mode does not call apply_theme" \
		"the per-mode colours would be generated and the links would never move"
fi

# nvim is the one consumer whose generated file is conditional. A scheme that
# matches its own plugin takes upstream's colours and emits no palette.lua at
# all (theme-migration §3) — so "the file is missing" is correct for the two
# schemes that match their plugin (gruvbox, nord) and a failure for the two that
# deviate (mocha, mocha-high-contrast). Which case applies is read from the
# theme, not assumed.
#
# The plugin spec is checked either way, because that file is always generated
# and naming the wrong plugin is the failure that produces a hybrid.
NVIM_SPEC=$(pal .apps.nvim.spec)
NVIM_NAME=$(pal .apps.nvim.name)
NVIM_OVERRIDES=$(jq -r "(.schemes.\"$PAL_SCHEME\".apps.nvim.palette | length) > 0" "$SCHEMES" 2>/dev/null)
CS="$GEN_CFG/nvim/lua/plugins/colorscheme.lua"

if [[ -z $NVIM_SPEC || -z $NVIM_NAME ]]; then
	bad "could not read apps.nvim from the palette" \
		"spec='$NVIM_SPEC' name='$NVIM_NAME' — the scans below would pass on an empty needle"
elif [[ ! -s $CS ]]; then
	bad "nvim: lua/plugins/colorscheme.lua is missing or empty" \
		"lazy.nvim would load no colourscheme and nvim would look merely unstyled"
elif ! grep -qF "\"$NVIM_SPEC\"" "$CS"; then
	bad "nvim: colorscheme.lua does not name $NVIM_SPEC" "generated, but not from the theme file"
elif ! grep -qF "vim.cmd.colorscheme(\"$NVIM_NAME\")" "$CS"; then
	bad "nvim: colorscheme.lua never applies '$NVIM_NAME'" \
		"the plugin loads and the scheme is never set — nvim falls back in silence"
else
	ok "nvim: colorscheme.lua loads $NVIM_SPEC and applies '$NVIM_NAME'"
fi

# lualine throws at startup on a theme name it cannot resolve, rather than
# falling back, so the generated names file has to carry one.
if [[ -z $(sed -n 's/.*lualine = "\([^"]*\)".*/\1/p' "$GEN_CFG/nvim/lua/config/scheme.lua" 2>/dev/null) ]]; then
	bad "nvim: lua/config/scheme.lua carries no lualine theme" \
		"lualine errors on an unresolvable theme instead of falling back"
else
	ok "nvim: scheme.lua names a lualine theme"
fi

if [[ $NVIM_OVERRIDES == true ]]; then
	if [[ ! -s "$GEN_CFG/nvim/lua/config/palette.lua" ]]; then
		bad "nvim: '$SCHEME' declares palette overrides but no palette.lua was generated"
	elif ! grep -qF "#${ACCENT}" "$GEN_CFG/nvim/lua/config/palette.lua"; then
		bad "nvim: palette.lua does not contain #${ACCENT}" "generated, but not from the palette"
	else
		ok "nvim: palette.lua is generated from the palette"
	fi
elif [[ -e "$GEN_CFG/nvim/lua/config/palette.lua" ]]; then
	bad "nvim: '$SCHEME' declares no palette overrides, but palette.lua exists" \
		"a stale override file would recolour the plugin behind the scheme's back"
else
	ok "nvim: '$SCHEME' takes its plugin's own colours, and no palette.lua is generated"
fi

# The mode configs must actually `source=` the generated file. mango skips an
# include it cannot resolve without a word, so a renamed file or a dropped line
# leaves the colours at mango's built-in defaults — which are also dark, also
# plausible, and nowhere stated to be wrong.
for mode in "${MODES[@]}"; do
	if grep -qxF "source=./universal/colors-$mode.conf" "$SRC/dotfiles/mango/$mode/$mode.conf" 2>/dev/null; then
		ok "mango: $mode.conf sources its generated colours"
	else
		bad "mango: $mode/$mode.conf does not source ./universal/colors-$mode.conf" \
			"the generated palette is built and then never read"
	fi
done

# Equibop enables its theme by filename and ignores a name matching no file,
# without logging. The name apply_theme writes must be one home-manager
# generates — two languages, two directories, one string. The name is the
# Mode's since adr/0034, so what must agree is the suffix, for every mode.
# SC2016: `$mode` is the literal text being searched for in lib.sh, not a
# variable to expand here.
# shellcheck disable=SC2016
eq_suffix=$(sed -n 's/.*--arg t "\$mode\(\.[^"]*\)".*/\1/p' \
	"$SRC/dotfiles/mango/scripts/lib.sh" 2>/dev/null | head -1)
if [[ -z $eq_suffix ]]; then
	bad "could not read the Equibop theme name from lib.sh" \
		"it is no longer '--arg t \"\$mode<suffix>\"' — the agreement check would pass on an empty needle"
else
	eqmiss=""
	for m in "${MODES[@]}"; do
		[[ -s "$GEN_CFG/equibop/themes/$m$eq_suffix" ]] || eqmiss+="  $m$eq_suffix"$'\n'
	done
	if [[ -z $eqmiss ]]; then
		ok "equibop: lib.sh enables <mode>$eq_suffix, and every mode has one generated"
	else
		bad "equibop: lib.sh enables '<mode>$eq_suffix', which home-manager does not generate for every mode" \
			"Equibop ignores a missing theme silently — Discord just stays unstyled:"$'\n'"$eqmiss"
	fi
fi

# The ceiling. Every palette hex has exactly one home now; a copy reappearing
# in a hand-written file is the drift the whole arrangement exists to prevent,
# and it reads as deliberate once it is there.
#
# The needles are read from palette.nix rather than listed here. A hardcoded
# list is fine until the scheme changes, at which point it scans for colours the
# machine no longer uses, matches nothing, and reports success — this repo's
# signature bug, in the check that exists to catch it. Whoever changes the
# palette should not also have to remember to change the scanner.
#
# Hence the floor immediately below: an empty or short list means the sed
# stopped matching (a reformat, a renamed block), and every scan after it would
# pass on an empty needle.
#
# Exempt, deliberately (docs/SYSTEM.md §6): the Kvantum theme and the GTK
# colors.css files, which are Breeze's palette and not this one. The yazi flavor
# used to be exempt too and is now fetched into the store instead, so it is no
# longer under dotfiles/ to be scanned.
#
# Tracked files only, via is_tracked — mango/config.conf is written at runtime
# by the mode scripts from the generated file, so it legitimately holds a copy
# of the colours and is deliberately untracked (docs/adr/0002). Without this
# filter a working-tree run reports a failure that `nix flake check`, which sees
# only tracked files, does not — and a check that disagrees with the gate is
# worse than no check.
PALETTE_HEX=$(
	sed -n 's/.*= "\([0-9a-f]\{6\}\)";.*/\1/p' "$SRC"/modules/home/themes/*.nix 2>/dev/null |
		sort -u
)
PALETTE_N=$(printf '%s\n' "$PALETTE_HEX" | grep -c . || true)
if ((PALETTE_N < 16)); then
	bad "only $PALETTE_N hex values read from modules/home/themes/, expected at least 16" \
		"the scan below would pass by finding nothing"
	PALETTE_HEX="__unreadable__"
else
	ok "read $PALETTE_N palette values to scan for"
fi

stray=$(
	grep -rlniE "($(printf '%s\n' "$PALETTE_HEX" | paste -sd'|'))" \
		"$SRC/dotfiles" 2>/dev/null |
		grep -vE '/(Kvantum|gtk-3\.0|gtk-4\.0)/' |
		grep -vE '/rofi/config\.rasi$' |
		while IFS= read -r f; do
			rel=${f#"$SRC"/}
			is_tracked "$rel" && printf '%s\n' "$f"
		done || true
)
if [[ -z $stray ]]; then
	ok "no palette hex outside modules/home/themes/ and the exempt theme data"
else
	bad "palette hex found in hand-written files" "$(printf '%s\n' "$stray" | sed "s|^$SRC/||")"
fi

# The ceiling above has a blind spot, and it is structural rather than a bug:
# it greps for the hexes the current themes declare, so a colour no theme names
# matches nothing and reads as a pass. `#d5c4a1` — gruvbox's `fg2`, which this
# palette does not have a role for — sat in programs.nix as kitty's inactive tab
# foreground through gruvbox -> Catppuccin -> gruvbox, wearing a scheme the
# machine had stopped running. Found by hand on 2026-08-19 while moving kitty's
# colours out; nothing in the repo could have found it.
#
# So: no six-digit hex literal in any .nix outside modules/home/themes/, which
# is where colours are declared and the only place they may be spelled. The pass
# state is zero matches, so the floor is on the number of files scanned.
mapfile -t NIXSCAN < <(
	find "$SRC/modules" "$SRC/pkgs" -name '*.nix' -not -path '*/themes/*' 2>/dev/null
)
if [[ ${#NIXSCAN[@]} -lt 10 ]]; then
	bad "only ${#NIXSCAN[@]} .nix files found outside themes/ — the scan is broken, not the repo"
else
	lithex=$(grep -nHoE '"#?[0-9a-fA-F]{6}"' "${NIXSCAN[@]}" 2>/dev/null | sed "s|^$SRC/||")
	if [[ -z $lithex ]]; then
		ok "no hex literal in ${#NIXSCAN[@]} .nix files outside modules/home/themes/"
	else
		bad "a colour is spelled outside modules/home/themes/" \
			"$(printf '%s\n' "$lithex" | tr '\n' ' ') — a hex no theme declares is invisible to the drift ceiling above"
	fi
fi

# The artefacts the palette cannot colour: GTK, Kvantum, icon and cursor themes.
# Each is a name some other program resolves internally, and every one of them
# fails the same way — the program falls back to its own default and looks
# merely unstyled, which is indistinguishable from a theme someone chose. GTK
# drops to Adwaita, Kvantum to its built-in style, and a cursor name that
# matches nothing leaves the X11 default.
#
# So: the name a theme declares must exist as a real directory in the built
# closure. `attr = null` means a toolkit built-in with nothing to install — that
# is not checkable here and is exempt, which is exactly why the count of them is
# reported rather than passed over.
printf '\nTheme packages\n'

# Where each artefact actually lands, which is not one place — and for Kvantum
# it is not one place either. A scheme's own Kvantum theme is linked into
# ~/.config/Kvantum by dotfiles.nix (Kvantum reads that, not XDG_DATA_DIRS),
# while the built-ins the stand-in schemes name ship inside the style plugin on
# the profile. Both are searched, so a built-in is verified rather than waved
# through — which is the whole point of having this check at all.
pkg_roots() {
	case $1 in
	gtk) printf '%s\n' "$GEN/home-path/share/themes" ;;
	kvantum) printf '%s\n%s\n' "$GEN_CFG/Kvantum" "$GEN/home-path/share/Kvantum" ;;
	icons | cursor) printf '%s\n' "$GEN/home-path/share/icons" ;;
	esac
}

declared=0
standins=""
for kind in gtk kvantum icons cursor; do
	name=$(pal ".packages.$kind.name")
	attr=$(pal ".packages.$kind.attr")
	native=$(pal ".packages.$kind.native")
	if [[ -z $name ]]; then
		bad "theme packages: '$SCHEME' declares no name for $kind" \
			"the consumer would fall back to its own default, silently"
		continue
	fi
	declared=$((declared + 1))
	[[ $native == true ]] || standins+="  $kind → $name ($(pal ".packages.$kind.why"))"$'\n'

	# Search where the running session reads, not the store path the theme file
	# implies: a package that is declared but never installed fails here. This
	# runs for `attr = null` too — a toolkit built-in still has to be there, and
	# "Adwaita-dark" was caught by exactly this: GTK3 renders it from compiled-in
	# resources, so it works and no directory for it exists anywhere. A name only
	# GTK can resolve is a name no check can, so the theme files name a real
	# package instead.
	#
	# `find -L`, and the -L is load-bearing. buildEnv collapses a share/
	# subdirectory with a single contributor into a symlink to that package, and
	# merges it into a real directory when several contribute. So share/themes is
	# a symlink (only the GTK theme provides one) while share/icons is a real
	# directory — and a plain `find` silently returns nothing for the first and
	# works for the second. Which of the two you get depends on the scheme, which
	# is the worst possible way for a check to fail.
	hit=""
	hit_path=""
	while IFS= read -r root; do
		[[ -z $root ]] && continue
		found=$(find -L "$root" -maxdepth 1 -name "$name" 2>/dev/null | head -1)
		if [[ -n $found ]]; then
			hit=${root#"$GEN/"}
			hit_path=$found
			break
		fi
	done < <(pkg_roots "$kind")

	# Kept for the two cursor-specific assertions after the loop, which need
	# the resolved path and not just the fact that one was found. An `if` and
	# not `[[ … ]] && …`: the bare form returns 1 for every other `kind`, which
	# is a landmine for the next person who adds `set -e` (CLAUDE.md → shell).
	if [[ $kind == cursor ]]; then
		cursor_path=$hit_path
		cursor_theme=$name
	fi
	if [[ $kind == kvantum ]]; then
		kvantum_path=$hit_path
		kvantum_theme=$name
	fi
	if [[ $kind == gtk ]]; then
		gtk_path=$hit_path
		gtk_theme=$name
	fi

	if [[ -n $hit ]]; then
		ok "$kind: '$name' resolves in $hit"
	else
		bad "$kind: '$name' is in none of $(pkg_roots "$kind" | tr '\n' ' ')" \
			"declared by themes/$SCHEME.nix from '${attr:-a toolkit built-in}' — the app falls back in silence"
	fi

	# One level below the scan above, and the level that actually bit: GTK4
	# ignores `gtk-theme-name` outright, so home-manager themes it by writing an
	# `@import` of `<theme>/gtk-4.0/gtk.css` into ~/.config/gtk-4.0/gtk.css.
	# A theme with no gtk-4.0 directory makes that import fail at parse time and
	# drops every libadwaita app to Adwaita — with GTK3 still themed, so the two
	# toolkits merely look different. `gruvbox-dark-gtk` shipped exactly that,
	# and the directory check above passed it. docs/gotchas.md → Theming.
	if [[ $kind == gtk && -n $hit_path ]]; then
		if [[ -r "$hit_path/gtk-4.0/gtk.css" ]]; then
			ok "gtk: '$name' ships gtk-4.0/gtk.css, so GTK4 apps are themed too"
		else
			bad "gtk: '$name' has no gtk-4.0/gtk.css" \
				"the @import home-manager writes into ~/.config/gtk-4.0/gtk.css fails and libadwaita apps fall back to Adwaita, while GTK3 stays themed"
		fi
	fi
done

if [[ $declared -lt 4 ]]; then
	bad "only $declared of 4 theme packages declared by '$SCHEME'" \
		"the scan above would pass by finding nothing"
elif [[ -z $standins ]]; then
	ok "all 4 theme packages follow '$SCHEME'"
else
	# Not a failure. A stand-in is a deliberate, declared choice — but it is one
	# nobody can see on screen without knowing to look, so it is stated on every
	# run rather than left to be discovered.
	ok "$declared theme packages declared for '$SCHEME'; stand-ins:"$'\n'"$standins"
fi

# The cursor is generated from the palette now (docs/adr/0041), which buys two
# failures the "does the directory exist" scan above cannot see. Both were found
# by hand on 2026-08-20, which is why they are assertions and not a paragraph.
#
#   index.theme      copied by upstream's outer build script, not by the
#                    `scripts/build-cursors` this repo calls — and that one
#                    `rm -rf`s its output directory first. Without it the
#                    directory exists, holds all 46 cursors, passes the scan
#                    above, and resolves to nothing in GTK and wlroots.
#   the colours      a substitution that stops matching leaves a complete,
#                    valid, unrecoloured set. The build asserts its own
#                    sentinels; this asserts the installed theme belongs to the
#                    palette this machine is actually wearing.
if [[ -n ${cursor_path:-} ]]; then
	if [[ -s "$cursor_path/index.theme" ]]; then
		ok "cursor: '$cursor_theme' ships index.theme, so GTK and wlroots can resolve it"
	else
		bad "cursor: '$cursor_theme' has no index.theme" \
			"the directory resolves and holds every cursor, and every consumer falls back in silence"
	fi

	# `cursors_scalable/default/default.svg` is the plain pointer, which carries
	# `fg0` as its body and `base` as its outline — the two roles paletteCursors
	# substitutes into all 68 files. Reading the SVG rather than the xcursor
	# binary: the bitmaps are rendered from these, so a match here proves the
	# substitution ran, and the binaries cannot disagree with their own source.
	cur_svg="$cursor_path/cursors_scalable/default/default.svg"
	cur_body=$(pal '.fg0')
	cur_edge=$(pal '.base')
	if [[ ! -r $cur_svg ]]; then
		bad "cursor: no cursors_scalable/default/default.svg to read colours from" \
			"$cur_svg — the scan is broken, not the repo"
	elif [[ -z $cur_body || -z $cur_edge ]]; then
		bad "cursor: could not read fg0/base from the resolved palette" \
			"body='$cur_body' edge='$cur_edge' — the check below would pass on nothing"
	elif grep -qi "$cur_body" "$cur_svg" && grep -qi "$cur_edge" "$cur_svg"; then
		ok "cursor: the built theme carries '$PAL_SCHEME''s own #$cur_body on #$cur_edge"
	else
		bad "cursor: the built theme does not carry this palette's colours" \
			"expected #$cur_body (fg0) and #$cur_edge (base) in $cur_svg — the recolour did not reach the artefact"
	fi
fi

# The Kvantum theme is generated too (docs/adr/0041, phase 2), and it fails in
# the same shape as the cursor: a substitution that stops matching leaves a
# complete, valid theme that Kvantum renders without a word — in somebody
# else's scheme. The build asserts its own subset; this asserts that what got
# INSTALLED belongs to the palette this machine is wearing.
#
# Two files, and both have to be checked. The `.kvconfig` is where the text and
# highlight colours live; the `.svg` is the widget art, which is where a
# recolour that silently did nothing would be least visible.
if [[ -n ${kvantum_path:-} ]]; then
	kv_cfg="$kvantum_path/$kvantum_theme.kvconfig"
	kv_svg="$kvantum_path/$kvantum_theme.svg"
	kv_accent=$(pal '.accent')
	kv_text=$(pal '.text')

	if [[ ! -r $kv_cfg || ! -r $kv_svg ]]; then
		bad "kvantum: '$kvantum_theme' is missing its .kvconfig or its .svg" \
			"$kv_cfg / $kv_svg — Kvantum falls back to its built-in style in silence"
	elif [[ -z $kv_accent || -z $kv_text ]]; then
		bad "kvantum: could not read accent/text from the resolved palette" \
			"accent='$kv_accent' text='$kv_text' — the checks below would pass on nothing"
	else
		if grep -qi "highlight.color=#$kv_accent" "$kv_cfg" &&
			grep -qi "^text.color=#$kv_text" "$kv_cfg"; then
			ok "kvantum: '$kvantum_theme' takes its highlight and text from '$PAL_SCHEME'"
		else
			bad "kvantum: '$kvantum_theme' does not carry this palette's colours" \
				"expected highlight.color=#$kv_accent and text.color=#$kv_text in $kv_cfg"
		fi

		# The art is tinted onto `mantle`→`fg0`, so every colour in it should be
		# off that axis and NONE should be a neutral grey — which is what the
		# source was, and therefore what an unrecoloured file looks like. A
		# floor on the count, because a regex that stops matching finds nothing
		# and nothing is what a pass looks like here.
		#
		# THREE-digit hex is checked separately and expected to be absent: the
		# generator only ever writes the six-digit form, and KvantumAlt holds
		# eight short ones (`fill:#fff`) that the first version of this scan
		# and of the generator both walked straight past — leaving pure white
		# in a theme with no white in it.
		kv_short=$(grep -oE '#[0-9a-fA-F]{3}\b' "$kv_svg" 2>/dev/null | grep -c . || true)
		if [[ $kv_short -ne 0 ]]; then
			bad "kvantum: $kv_short three-digit colour(s) left in the widget art" \
				"the generator writes six-digit only, so these are the source's own — $kv_svg"
		fi
		kv_n=$(grep -oE '#[0-9a-fA-F]{6}' "$kv_svg" 2>/dev/null | sort -u | grep -c . || true)
		kv_grey=$(grep -oE '#[0-9a-fA-F]{6}' "$kv_svg" 2>/dev/null | sort -u |
			while IFS= read -r h; do
				[[ ${h:1:2} == "${h:3:2}" && ${h:3:2} == "${h:5:2}" ]] && printf '%s\n' "$h"
			done | grep -c . || true)
		if [[ $kv_n -lt 15 ]]; then
			bad "kvantum: only $kv_n distinct colours read from $kv_svg" \
				"the grey scan below would pass by finding nothing"
		elif [[ $kv_grey -eq 0 ]]; then
			ok "kvantum: all $kv_n colours in the widget art are off '$PAL_SCHEME''s own ramp"
		else
			bad "kvantum: $kv_grey of $kv_n colours in the widget art are still neutral grey" \
				"the source is greyscale, so a grey here is a colour the tint did not reach"
		fi
	fi
fi

# The GTK theme is generated too (docs/adr/0041, phase 3): Colloid compiled
# against a `_color-palette-default.scss` written from the palette. A variable
# renamed upstream is loud — sassc stops with `Undefined variable` — but the
# file being written and never imported is not: Colloid changing which palette
# `_tweaks.scss` pulls in gives a theme that builds, installs, resolves by
# name, ships its gtk-4.0/gtk.css, and is Colloid's own blue. Every check above
# passes it, and this one does not.
#
# Both toolkits are read, because they are compiled from the same SCSS into two
# separate files and only one of them is checked for existence above.
if [[ -n ${gtk_path:-} ]]; then
	gtk_bg=$(pal '.bg0')
	gtk_accent=$(pal '.accent')
	if [[ -z $gtk_bg || -z $gtk_accent ]]; then
		bad "gtk: could not read bg0/accent from the resolved palette" \
			"bg0='$gtk_bg' accent='$gtk_accent' — the checks below would pass on nothing"
	else
		gtkerr=""
		for css in "$gtk_path/gtk-3.0/gtk.css" "$gtk_path/gtk-4.0/gtk.css"; do
			if [[ ! -r $css ]]; then
				gtkerr+="  ${css#"$gtk_path/"}: not readable"$'\n'
				continue
			fi
			grep -qi "$gtk_bg" "$css" || gtkerr+="  ${css#"$gtk_path/"}: no #$gtk_bg (bg0)"$'\n'
			grep -qi "$gtk_accent" "$css" || gtkerr+="  ${css#"$gtk_path/"}: no #$gtk_accent (accent)"$'\n'
		done
		if [[ -z $gtkerr ]]; then
			ok "gtk: '$gtk_theme' compiles '$PAL_SCHEME''s own colours into both toolkits"
		else
			bad "gtk: '$gtk_theme' does not carry this palette's colours" \
				"the generated palette compiled, but nothing imported it:"$'\n'"$gtkerr"
		fi
	fi
fi

# yazi's flavour is written from the palette now (docs/adr/0041) rather than
# fetched, so it joins the three artefacts above in the one failure mode they
# share: a generator that stops reaching its consumer leaves a complete, valid
# file that the app reads without complaint, in the wrong scheme. yazi is the
# quietest of the four — an unresolvable flavour just leaves its built-in theme.
#
# `flavors/scheme.yazi/flavor.toml` is where `programs.yazi.flavors.scheme`
# lands it.
yazi_flavor="$GEN_CFG/yazi/flavors/scheme.yazi/flavor.toml"
if [[ ! -s $yazi_flavor ]]; then
	bad "yazi: no flavour at flavors/scheme.yazi/flavor.toml" \
		"$yazi_flavor — yazi falls back to its built-in theme and says nothing"
else
	yz_bg=$(pal '.bg0')
	yz_accent=$(pal '.accent')
	yz_n=$(grep -oE '#[0-9a-f]{6}' "$yazi_flavor" 2>/dev/null | sort -u | grep -c . || true)
	if [[ -z $yz_bg || -z $yz_accent ]]; then
		bad "yazi: could not read bg0/accent from the resolved palette" \
			"the check below would pass on nothing"
	elif [[ $yz_n -lt 10 ]]; then
		bad "yazi: only $yz_n distinct colours in the generated flavour" \
			"the scan is broken, not the generator — $yazi_flavor"
	elif grep -qi "#$yz_bg" "$yazi_flavor" && grep -qi "#$yz_accent" "$yazi_flavor"; then
		ok "yazi: the generated flavour carries '$PAL_SCHEME''s own $yz_n colours"
	else
		bad "yazi: the generated flavour does not carry this palette's colours" \
			"expected #$yz_bg (bg0) and #$yz_accent (accent) in $yazi_flavor"
	fi

	# The glyphs, by codepoint. yazi draws its status bar, its border and its
	# which-key list out of five characters, and every one of them renders as
	# nothing in a terminal without the font — so a glyph dropped in transit
	# looks like a faithful copy and reaches the screen as a gap.
	#
	# That happened twice writing this file. The powerline separators went
	# first and were caught; `which.separator` (U+EA9C) went the same way and
	# was not, shipping as two spaces. Both were "verified" by reading the line.
	#
	# So: the flavour holds escapes, not characters — TOML resolves them, and
	# an escape is ASCII, which cannot be lost by anything that mangles UTF-8.
	# Both halves are asserted: every escape present, and no raw non-ASCII byte
	# anywhere in the file.
	glyphmiss=""
	for esc in '\\u2502' '\\u2588' '\\ue0be' '\\ue0b8' '\\uea9c'; do
		grep -q -- "$esc" "$yazi_flavor" || glyphmiss="$glyphmiss ${esc#\\\\}"
	done
	raw=$(LC_ALL=C grep -c -P '[^\x00-\x7F]' "$yazi_flavor" 2>/dev/null || true)
	if [[ -n $glyphmiss ]]; then
		bad "yazi: the generated flavour is missing glyph(s):$glyphmiss" \
			"each renders as nothing without the font, so the gap looks like a design"
	elif [[ ${raw:-0} -ne 0 ]]; then
		bad "yazi: $raw line(s) of the generated flavour hold a raw non-ASCII byte" \
			"pkgs/yazi-flavor.nix writes \\uXXXX escapes; a literal glyph there is one transcription away from being lost"
	else
		ok "yazi: all 5 glyphs are present as escapes, and the flavour is pure ASCII"
	fi
fi

# Zed's theme is generated now (docs/adr/0041). This is the check
# modules/home/programs.nix used to say could not exist: the theme came from
# Zed's extension registry, so this file could assert that a name was declared
# and nothing else — both halves lived on Zed's servers. A theme written into
# the generation is gateable like every other artefact.
#
# Three things, and the third is the one that used to be impossible: the theme
# file is there, it carries this palette, and the name `settings.json` will ask
# for is the name the theme actually declares.
zed_theme="$GEN_CFG/zed/themes/$PAL_SCHEME.json"
if [[ ! -s $zed_theme ]]; then
	bad "zed: no generated theme at zed/themes/$PAL_SCHEME.json" \
		"$zed_theme — Zed falls back to One Dark and logs nothing"
else
	zd_bg=$(pal '.bg0')
	zd_accent=$(pal '.accent')
	zd_name=$(jq -r '.themes[0].name // empty' "$zed_theme" 2>/dev/null)
	zd_keys=$(jq -r '(.themes[0].style | keys | length) // 0' "$zed_theme" 2>/dev/null)

	# 136 = 135 style keys plus `syntax`. A floor, not an equality: Zed adding
	# keys should not fail this, but a generator that stopped emitting must.
	if [[ -z $zd_name || $zd_keys -lt 136 ]]; then
		bad "zed: the generated theme is not shaped like one" \
			"name='$zd_name' style keys=$zd_keys (expected 136) — $zed_theme"
	elif [[ $zd_name != "$PAL_SCHEME" ]]; then
		bad "zed: the generated theme calls itself '$zd_name', not '$PAL_SCHEME'" \
			"settings.json asks for the scheme name, so Zed would resolve nothing"
	elif ! grep -qi "$zd_bg" "$zed_theme" || ! grep -qi "$zd_accent" "$zed_theme"; then
		bad "zed: the generated theme does not carry this palette's colours" \
			"expected #$zd_bg (bg0) and #$zd_accent (accent) in $zed_theme"
	else
		ok "zed: '$zd_name' is generated, carries '$PAL_SCHEME''s colours, and has $zd_keys style keys"
	fi

	# And the settings that will actually be merged ask for that theme. Both
	# come from scheme.nix in the same file, so this cannot drift today — it is
	# here because the pair is what broke before, on a name nothing checked.
	zed_settings=$(grep -oE '/nix/store/[a-z0-9]+-zed-user-settings' "$GEN/activate" 2>/dev/null | head -1)
	if [[ -z $zed_settings || ! -r $zed_settings ]]; then
		bad "zed: could not find the zed-user-settings store path in the activation script" \
			"the scan is broken, not the repo"
	else
		zd_dark=$(jq -r '.theme.dark // empty' "$zed_settings" 2>/dev/null)
		if [[ $zd_dark == "$zd_name" ]]; then
			ok "zed: settings.json asks for '$zd_dark', which is the theme that ships"
		else
			bad "zed: settings.json asks for '$zd_dark' but the theme is '$zd_name'" \
				"Zed leaves itself on One Dark and logs nothing"
		fi
	fi
fi

# The cursor has a second consumer the scan above cannot see. mango takes the
# theme by name in its own config and, finding nothing, hands the name to
# wlroots and carries on — then `setenv`s XCURSOR_THEME from it for every client
# it spawns, so a stale name silently overrides home.pointerCursor for the whole
# session. It sat at `catppuccin-mocha-mauve-cursors` through two scheme changes
# because nothing here read it. So: the compositor's name must be the same name
# that just resolved, and no hand-written mango file may set it again.
cursor_name=$(pal '.packages.cursor.name')
cursor_conf="$GEN_CFG/mango/universal/cursor.conf"
if [[ ! -f $cursor_conf ]]; then
	bad "mango cursor: $cursor_conf is not in the built closure" \
		"universal/settings.conf source=s it; mango would leave the wlroots default"
else
	mango_cursor=$(sed -n 's/^cursor_theme=//p' "$cursor_conf")
	if [[ $mango_cursor == "$cursor_name" ]]; then
		ok "mango cursor: '$mango_cursor' matches the scheme's cursor theme"
	else
		bad "mango cursor: names '$mango_cursor', scheme declares '$cursor_name'" \
			"the pointer falls back in silence and XCURSOR_THEME follows it"
	fi
fi

stray_cursor=$(grep -rln '^[[:space:]]*cursor_theme=' "$SRC/dotfiles/mango" 2>/dev/null || true)
if [[ -z $stray_cursor ]]; then
	ok "no hand-written cursor_theme under dotfiles/mango"
else
	bad "cursor_theme hardcoded in a hand-written mango file" \
		"$(printf '%s\n' "$stray_cursor" | sed "s|^$SRC/||") — generate it from home.pointerCursor instead"
fi

# Contrast. The one property nothing used to check — docs/theme-migration.md §4
# said so in as many words: "what it does not catch: whether the new colours are
# legible". That gap shipped a scheme whose comments sat at 3.36:1, which reads
# as a considered choice rather than a mistake, because every colour in it was
# individually plausible.
#
# Ratios are wcag 2.x relative luminance, recomputed here from the resolved
# palette on every run rather than copied from whoever last did the arithmetic.
#
# Two floors, because two different promises are being made:
#
#   contrastFloor  what this machine draws text with — the bar, the menus,
#                  notifications, editor chrome, ncspot's rows
#   ansiFloor      the sixteen terminal slots, which nothing here draws text in;
#                  they are what other programs print with, and they are the
#                  scheme's published identity
#
# They were one number until 2026-08-18, which worked only because Catppuccin's
# Ansi set is its accent set. Gruvbox's normal red is 2.69:1 by upstream's
# design, so one combined floor would have had to be 2.6 for that scheme — and
# `comment`, the role the whole check exists for, could then have rotted to the
# same place unnoticed. docs/adr/0032.
#
# Both floors are declared by the theme, and there is no global minimum under
# them. There was one — 3.0 — and it was removed on 2026-08-18 as an invention:
# it came in with `mocha-high-contrast`, out of a request for more readable text,
# and then read like an external requirement. It is not one. Nord ships its
# comment colour at 1.69:1 and that is Nord; a floor that forbids it is this
# repo overruling upstream rather than recording it.
#
# What the assertion means is therefore exactly and only: **this theme is as
# legible as it claims to be**. That still catches the thing worth catching — a
# future edit that dims a role below what its own theme file declares — without
# deciding for anyone which schemes are allowed to exist.

contrast() {
	awk -v a="$1" -v b="$2" '
		function lin(c) { c = c / 255; return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ^ 2.4 }
		function lum(h,   r, g, b) {
			r = lin(strtonum("0x" substr(h, 1, 2)))
			g = lin(strtonum("0x" substr(h, 3, 2)))
			b = lin(strtonum("0x" substr(h, 5, 2)))
			return 0.2126 * r + 0.7152 * g + 0.0722 * b
		}
		BEGIN {
			la = lum(a); lb = lum(b)
			hi = la > lb ? la : lb; lo = la > lb ? lb : la
			printf "%.2f", (hi + 0.05) / (lo + 0.05)
		}'
}

# Audited for every scheme this machine wears, not only the artefact one.
# modes.nix can put a second scheme on screen (docs/adr/0034), and a floor that
# only ever measured scheme.nix's would report a clean bill of health for a mode
# nobody can read — the check passing by never looking, which is the failure
# this whole file is built against. `.schemes` holds exactly the in-use set, so
# a scheme cannot enter service unaudited.
#
# Each scheme is measured against its own declared floors. There is no global
# minimum under them: the assertion is "this theme is as legible as it claims",
# and Nord's comment colour is 1.69:1 and that is Nord (docs/adr/0032).
mapfile -t IN_USE < <(jq -r '.schemes | keys[]' "$SCHEMES" 2>/dev/null)
if [[ ${#IN_USE[@]} -eq 0 ]]; then
	bad "no schemes read from the resolved schemes JSON — the scan is broken, not the repo"
fi
for PAL_SCHEME in "${IN_USE[@]}"; do
	FLOOR=$(pal .contrastFloor)
	AFLOOR=$(pal .ansiFloor)
	THEME_BG=$(pal .bg0)
	MUTED_SURFACE=$(pal .muted.surface)
	MUTED_FG=$(pal .muted.fg)
	MUTED_ERR=$(pal .muted.err)

	if [[ -z $FLOOR || -z $AFLOOR || -z $THEME_BG || -z $MUTED_SURFACE || -z $MUTED_FG || -z $MUTED_ERR ]]; then
		bad "could not read the floors or reference colours from themes/$PAL_SCHEME.nix" \
			"floor='$FLOOR' ansi='$AFLOOR' bg0='$THEME_BG' muted.surface='$MUTED_SURFACE' muted.fg='$MUTED_FG' muted.err='$MUTED_ERR' — every ratio below would be computed against nothing"
	else
		worst=""
		worst_n=""
		fails=""

		audit() { # <ratio> <label> <floor>
			awk -v r="$1" -v f="$3" 'BEGIN { exit !(r < f) }' &&
				fails+="  $2: $1 < $3"$'\n'
			if [[ -z $worst ]] || awk -v r="$1" -v w="$worst" 'BEGIN { exit !(r < w) }'; then
				worst=$1
				worst_n=$2
			fi
		}

		# What this machine draws text with, against `bg0`.
		for role in fg0 fg1 fg4 brBlack brWhite comment accent okColor warnColor errColor infoColor; do
			h=$(pal ".$role")
			if [[ ! $h =~ ^[0-9a-f]{6}$ ]]; then
				fails+="  $role: not a colour in the resolved palette ('$h')"$'\n'
				continue
			fi
			audit "$(contrast "$h" "$THEME_BG")" "$role #$h on bg0" "$FLOOR"
		done

		# ncspot's muted set against its own surface — ncspot fills whole rows with
		# that colour, so bg0 is the wrong reference and using it passes values that
		# fail where they are actually drawn.
		for role in fg dim accent ok; do
			h=$(pal ".muted.$role")
			if [[ ! $h =~ ^[0-9a-f]{6}$ ]]; then
				fails+="  muted.$role: not a colour in the resolved palette ('$h')"$'\n'
				continue
			fi
			audit "$(contrast "$h" "$MUTED_SURFACE")" "muted.$role #$h on muted.surface" "$FLOOR"
		done

		# `muted.err` is a background — ncspot sets `error_bg` from it and draws
		# `error_fg` (= `muted.fg`) on top. Auditing it as a foreground against
		# `surface` is a pair ncspot never draws, and it passed a live theme whose
		# error row was **1.28:1**: light grey-blue text on light pink. The check was
		# not lenient, it was measuring the wrong two colours. docs/adr/0032.
		audit "$(contrast "$MUTED_FG" "$MUTED_ERR")" "muted.fg on muted.err (ncspot's error row)" "$FLOOR"

		if [[ -n $fails ]]; then
			bad "themes/$PAL_SCHEME.nix has text below its own declared floor of $FLOOR:1" "$fails"
		else
			ok "contrast: every UI text role in '$PAL_SCHEME' clears its floor of $FLOOR:1 (worst: $worst_n at $worst)"
		fi

		# The sixteen terminal slots. `black` is excluded — it is ansi 0, a
		# background tone, and nothing prints text in it.
		aworst=""
		aworst_n=""
		afails=""
		for role in red green yellow blue magenta cyan white \
			brRed brGreen brYellow brBlue brMagenta brCyan brWhite; do
			h=$(pal ".$role")
			if [[ ! $h =~ ^[0-9a-f]{6}$ ]]; then
				afails+="  $role: not a colour in the resolved palette ('$h')"$'\n'
				continue
			fi
			r=$(contrast "$h" "$THEME_BG")
			awk -v r="$r" -v f="$AFLOOR" 'BEGIN { exit !(r < f) }' &&
				afails+="  $role #$h on bg0: $r < $AFLOOR"$'\n'
			if [[ -z $aworst ]] || awk -v r="$r" -v w="$aworst" 'BEGIN { exit !(r < w) }'; then
				aworst=$r
				aworst_n=$role
			fi
		done
		if [[ -n $afails ]]; then
			bad "themes/$PAL_SCHEME.nix has ANSI colours below its own declared ansiFloor of $AFLOOR:1" "$afails"
		else
			ok "contrast: every ANSI slot in '$PAL_SCHEME' clears its floor of $AFLOOR:1 (worst: $aworst_n at $aworst)"
		fi
	fi
done
# Back to the artefact scheme, so anything added after this reads the same
# palette as everything before it.
PAL_SCHEME=$(jq -r '.artefact // empty' "$SCHEMES" 2>/dev/null)

printf '\nNetworkManager profiles\n'

# Read the keyfiles the unit will actually write, not the option that produced
# them — the envsubst placeholders only survive to /run if they survive here.
NM_UNIT="$SYS/etc/systemd/system/NetworkManager-ensure-profiles.service"
mapfile -t NM_PROFILES < <(
	if [[ -f $NM_UNIT ]]; then
		exec=$(grep -m1 '^ExecStart=' "$NM_UNIT" | cut -d= -f2- | awk '{print $1}')
		[[ -f $exec ]] && grep -o 'envsubst -i [^ ]*' "$exec" | cut -d' ' -f3
	fi
)

if [[ ${#NM_PROFILES[@]} -lt 9 ]]; then
	bad "expected 9 declared NM profiles (8 PIA exits + homelab), found ${#NM_PROFILES[@]}"
else
	ok "${#NM_PROFILES[@]} declared NM profiles"

	# A VPN that autoconnects grabs the default route and pushes a nameserver
	# onto every link, which presents as total DNS failure naming nothing.
	on=""
	for p in "${NM_PROFILES[@]}"; do
		grep -q '^autoconnect=false$' "$p" || on+="  $(basename "$p")"$'\n'
	done
	if [[ -z $on ]]; then
		ok "every declared profile sets autoconnect=false"
	else
		bad "declared profile without autoconnect=false" "$on"
	fi

	# /nix/store is world-readable, so an inlined credential is a leak that
	# looks identical to a working profile. Every one must be an envsubst
	# placeholder resolved at runtime from the sops-rendered env file.
	leaked=""
	creds=0
	for p in "${NM_PROFILES[@]}"; do
		while IFS= read -r line; do
			creds=$((creds + 1))
			[[ ${line#*=} == \$* ]] || leaked+="  $(basename "$p"): ${line%%=*}"$'\n'
		done < <(grep -E '^(password|private-key|psk|preshared-key)=' "$p")
	done
	if [[ $creds -eq 0 ]]; then
		bad "no credential fields found in the profiles — the scan is broken"
	elif [[ -z $leaked ]]; then
		ok "all $creds profile credentials are \$-placeholders, not literals"
	else
		bad "PLAINTEXT credential in a world-readable store path" "$leaked"
	fi
fi

printf '\nGenerated wayle layouts\n'

# 1. config.toml must not be in the generation.
#
# scripts/wayle/wayle-restart.sh owns that path as a link, re-pointing it per
# (layout, position). `services.wayle.settings` holding one value makes the
# home-manager module claim it, and two owners for one path is an activation
# failure — the same trap that keeps `programs.ncspot.settings` empty
# (docs/adr/0034). The failure is loud at switch time and invisible in review,
# which is why it is asserted rather than commented. docs/adr/0051.
if [[ -e "$WAYLE_DIR/config.toml" ]]; then
	bad "home-manager claims wayle/config.toml, which wayle-restart.sh owns as a link" \
		"set services.wayle.settings back to { } — one value in it claims the path"
else
	ok "wayle/config.toml is absent from the generation, so the runtime link has one owner"
fi

# 2. Every layout, in both positions. Named rather than counted: a count alone
# passes when one layout vanishes and another is added twice, and the names are
# what wayle-restart.sh builds its filename from — a missing one falls back to
# full/top, which notifies but keeps running.
mapfile -t WLAYOUTS < <(find "$WAYLE_DIR/layouts" -name '*.toml' 2>/dev/null | sort)
wmiss=""
for l in full focus minimal; do
	for pos in top bottom; do
		[[ -s "$WAYLE_DIR/layouts/$l-$pos.toml" ]] || wmiss+="  $l-$pos.toml"$'\n'
	done
done
if [[ -n $wmiss ]]; then
	bad "a generated wayle layout is missing" "$wmiss"
elif [[ ${#WLAYOUTS[@]} -ne 6 ]]; then
	bad "expected 6 generated wayle layouts (3 layouts x 2 positions), found ${#WLAYOUTS[@]}" \
		"$(printf '%s ' "${WLAYOUTS[@]##*/}")"
else
	ok "6 generated wayle layouts — full, focus and minimal, each top and bottom"
fi

if [[ ${#WLAYOUTS[@]} -gt 0 ]]; then
	# 3. Every custom module's `command` names a script that exists and is
	# Executable. wayle discards a custom module's stderr and renders nothing
	# when the command fails, so a moved script is an empty widget and no more —
	# this repo's signature bug, and the same check the waybar configs get.
	# Nix preserves the mode bit, so a script committed 644 arrives 444 and
	# fails only at runtime.
	wrefs=0
	wmissing=""
	while read -r ref; do
		[[ -z $ref ]] && continue
		wrefs=$((wrefs + 1))
		[[ -x "$MANGO/scripts/${ref#*scripts/}" ]] || wmissing+="  $ref"$'\n'
	done < <(
		# The array, not the directory: every entry under it is a symlink into
		# the store, and `grep -r` skips symlinks while recursing. The floor
		# below caught exactly that, which is what it is for.
		grep -hoE '[~]/\.config/mango/scripts/[^ "'"'"']*' "${WLAYOUTS[@]}" | sort -u
	)
	if [[ $wrefs -eq 0 ]]; then
		bad "no script references read from the wayle layouts — the scan is broken, not the repo"
	elif [[ -n $wmissing ]]; then
		bad "a wayle custom module names a missing or non-executable script" "$wmissing"
	else
		ok "all $wrefs script references in the wayle layouts resolve and are executable"
	fi

	# 4. Every module a layout carries has a definition.
	#
	# wayle.nix asserts this at eval for its own names, which is the loud half.
	# This is the other half: a custom module is defined by an `id` and referred
	# To as `custom-<id>`, so the two spellings can come apart in a way the Nix
	# assertion cannot see — it compares the list it just built against itself.
	# wayle renders an unknown module id as nothing at all.
	undef=""
	seen_ids=0
	for cfg in "${WLAYOUTS[@]}"; do
		mapfile -t ids < <(
			sed -n '/^\[\[bar.layout\]\]/,/^\[[a-z]/p' "$cfg" |
				grep -oE '"[a-z0-9-]+"' | tr -d '"' | sort -u
		)
		mapfile -t defined < <(
			grep -oE '^id = "[a-z0-9-]+"' "$cfg" | sed 's/id = "/custom-/;s/"$//' | sort -u
		)
		for id in "${ids[@]}"; do
			case "$id" in
			top | bottom) continue ;;
			custom-*)
				seen_ids=$((seen_ids + 1))
				printf '%s\n' "${defined[@]}" | grep -qxF "$id" ||
					undef+="  $(basename "$cfg"): $id has no [[modules.custom]] with that id"$'\n'
				;;
			esac
		done
	done
	# The floor. The layout section moved from a flat `left = [...]` to
	# `[[bar.layout.left]]` group tables when grouping became wayle's own
	# (docs/adr/0051), and an extraction that stops matching passes by finding
	# nothing — which is exactly what this check exists to stop.
	if [[ $seen_ids -eq 0 ]]; then
		bad "no custom-* ids read from the wayle layouts — the scan is broken, not the repo"
	elif [[ -n $undef ]]; then
		bad "a wayle layout carries a custom module id nothing defines" "$undef"
	else
		ok "all $seen_ids custom-* ids across the wayle layouts have a [[modules.custom]] definition"
	fi

	# 5. A custom module with no `icon-name` shows no icon.
	#
	# `icon-show` defaults true, so one without an icon still gets the widget and
	# draws 22px of nothing between its neighbours — the whole of why the bar read
	# as loose whatever the spacing knobs said. Every script here already puts its
	# glyph in the text. wayle.nix derives the key from the definition; this is the
	# floor under that, because an empty slot looks like spacing, not like a bug.
	slotted=""
	cblocks=0
	for cfg in "${WLAYOUTS[@]}"; do
		while IFS='|' read -r cid hasname hasshow; do
			cblocks=$((cblocks + 1))
			[[ $hasname == 1 || $hasshow == 1 ]] ||
				slotted+="  $(basename "$cfg"): custom-$cid has neither icon-name nor icon-show = false"$'\n'
		done < <(
			awk '
				function flush() { if (inblk) { print id "|" hn "|" hs; inblk = 0 } }
				/^\[\[modules\.custom\]\]/ { flush(); inblk = 1; id = ""; hn = 0; hs = 0; next }
				/^\[/ { flush() }
				inblk && /^id = / { id = $3; gsub(/"/, "", id) }
				inblk && /^icon-name = / { hn = 1 }
				inblk && /^icon-show = false/ { hs = 1 }
				END { flush() }
			' "$cfg"
		)
	done
	if [[ $cblocks -eq 0 ]]; then
		bad "no [[modules.custom]] blocks read from the wayle layouts — the scan is broken, not the repo"
	elif [[ -n $slotted ]]; then
		bad "a wayle custom module reserves an icon slot it never fills" "$slotted"
	else
		ok "all $cblocks wayle custom module definitions either name an icon or hide the slot"
	fi

	# 5b. The one custom module whose resting state is empty text hides itself —
	# and BOTH halves are needed, which is the whole reason this is a check.
	#
	# `hide-if-empty` tests the command's OUTPUT. `phone-status.sh status`
	# answers `{"text":"","tooltip":…}` whenever the phone is unreachable, which
	# is most of the time — a JSON object, and so not empty. The key was set on
	# its own first and changed nothing: the module kept its button and ~10px of
	# bar with nothing in it, which read as bluetooth's padding for two rounds of
	# tuning the wrong key. The `bar` verb exists to make that output actually
	# empty, and the control centre still calls `status` because it needs
	# `.class` to tell `offline` from `disconnected`.
	#
	# So: the key without the verb is inert, and the verb without the key draws
	# an empty button. Neither half fails loudly.
	hidemiss=""
	phoneblocks=0
	for cfg in "${WLAYOUTS[@]}"; do
		while IFS='|' read -r cid hashide hasbar; do
			[[ $cid == "phone" ]] || continue
			phoneblocks=$((phoneblocks + 1))
			[[ $hashide == 1 ]] ||
				hidemiss+="  $(basename "$cfg"): custom-phone has no hide-if-empty = true"$'\n'
			[[ $hasbar == 1 ]] ||
				hidemiss+="  $(basename "$cfg"): custom-phone's command is not phone-status.sh's \`bar\` verb, so hide-if-empty sees a JSON object and never fires"$'\n'
		done < <(
			awk '
				function flush() { if (inblk) { print id "|" hd "|" hb; inblk = 0 } }
				/^\[\[modules\.custom\]\]/ { flush(); inblk = 1; id = ""; hd = 0; hb = 0; next }
				/^\[/ { flush() }
				inblk && /^id = / { id = $3; gsub(/"/, "", id) }
				inblk && /^hide-if-empty = true/ { hd = 1 }
				inblk && /^command = .*phone-status\.sh bar"$/ { hb = 1 }
				END { flush() }
			' "$cfg"
		)
	done
	if [[ $phoneblocks -eq 0 ]]; then
		bad "no custom-phone block read from any wayle layout — the scan is broken, or the module left without this check"
	elif [[ -n $hidemiss ]]; then
		bad "wayle's custom-phone holds its gap when the phone is away" "$hidemiss"
	else
		ok "custom-phone pairs hide-if-empty with the \`bar\` verb in all $phoneblocks layouts that carry it"
	fi

	# 6. `bar.padding` is zero, so the active workspace tag reaches the bar's
	# edges. The key is a margin on the section: any value insets every module
	# from the bar's top and bottom, and the one widget on this bar that draws a
	# background — the active tag — then stops short at both ends. index.scss
	# takes the height back as vertical padding on `.mod`, which the workspaces
	# module opts out of. Nothing about that is visible in a diff of the value.
	ppad=""
	for cfg in "${WLAYOUTS[@]}"; do
		grep -qE '^padding = 0(\.0+)?$' "$cfg" ||
			ppad+="  $(basename "$cfg"): $(grep -E '^padding = ' "$cfg" || echo 'no padding key')"$'\n'
	done
	if [[ -n $ppad ]]; then
		bad "a wayle layout sets bar.padding, which insets the active workspace tag" "$ppad"
	else
		ok "all ${#WLAYOUTS[@]} wayle layouts leave bar.padding at 0, so the active tag is full height"
	fi

	# 6a. The three surfaces that are NOT the bar are declared.
	#
	# wayle is a shell: it draws the bar, eight dropdowns, notification popups
	# and the OSD. Leave a key out and that surface silently takes wayle's own
	# default — `styling.rounding` comes up `sm` against a square bar, and with
	# no `[osd]` block at all the machine's ONLY on-screen display (swayosd went
	# in docs/adr/0047) is whatever wayle picked. Nothing renders wrong; it
	# renders like a different machine's shell. docs/adr/0049.
	surf=""
	for cfg in "${WLAYOUTS[@]}"; do
		b=$(basename "$cfg")
		# WITHIN `[styling]`. A bare grep for the key matches `[bar]`'s own
		# `rounding`, which is also "none" — so dropping the styling one would
		# pass on the bar's line. That is the shape of silent pass this file exists to
		# refuse.
		awk '/^\[styling\]$/{f=1;next} /^\[/{f=0} f' "$cfg" |
			grep -qE '^rounding = "none"$' || surf+="  $b: styling.rounding is not \"none\""$'\n'
		grep -qE '^\[osd\]$' "$cfg" || surf+="  $b: no [osd] block"$'\n'
		grep -qE '^popup-urgency-bar = "critical"$' "$cfg" ||
			surf+="  $b: popup-urgency-bar is not \"critical\" — the bar marks every notification"$'\n'
	done
	if [[ -n $surf ]]; then
		bad "a wayle layout leaves a non-bar surface on wayle's defaults" "$surf"
	else
		ok "all ${#WLAYOUTS[@]} wayle layouts declare styling.rounding, [osd] and the urgency threshold"
	fi

	# 6b. Every icon name a layout references resolves THROUGH THE THEME CHAIN.
	#
	# A name that does not resolve is not an error anywhere: GTK draws its
	# missing-image glyph and the module renders, so the bar carries a circle
	# with a slash where an icon should be.
	#
	# THE CHAIN IS THE WHOLE POINT, and the first version of this check did not
	# have it — it searched every icon tree on the machine, found
	# `bluetooth-acquiring-symbolic` in Adwaita and passed, while GTK never
	# looked there. `Papirus-Dark` inherits `breeze-dark,hicolor`; Adwaita is in
	# neither, and is only present at all because other packages pull it in. A
	# check that resolves names GTK cannot is worse than no check: it reports a
	# clean bill on a bar with a missing glyph on it.
	#
	# `hicolor` terminates every chain, which is why pkgs/default.nix installs
	# the `adw-` prefixed set there.
	#
	# `find -L`: both trees are symlink farms, and without it Adwaita's
	# `symbolic/status/` is never entered and every name in it reads as missing.
	iconnames=$(
		grep -hoE '"[a-z][a-z0-9_-]*-symbolic"' "${WLAYOUTS[@]}" 2>/dev/null |
			tr -d '"' | sort -u
	)
	icon_count=$(printf '%s\n' "$iconnames" | grep -c .)

	# The theme in service, read off the generation rather than off palette.nix:
	# this is the name GTK is actually given.
	icon_theme=$(sed -n 's/^gtk-icon-theme-name=//p' "$GEN_CFG/gtk-3.0/settings.ini" 2>/dev/null)

	# Walk `Inherits=` breadth-first, ending at hicolor.
	icon_dirs=()
	if [[ -n $icon_theme ]]; then
		queue=("$icon_theme" hicolor)
		seen=""
		while [[ ${#queue[@]} -gt 0 ]]; do
			th=${queue[0]}
			queue=("${queue[@]:1}")
			[[ $seen == *"|$th|"* ]] && continue
			seen+="|$th|"
			for root in "$GEN/home-path/share/icons" "$SYS/sw/share/icons"; do
				[[ -d "$root/$th" ]] || continue
				icon_dirs+=("$root/$th")
				while IFS= read -r parent; do
					[[ -n $parent ]] && queue+=("$parent")
				done < <(sed -n 's/^Inherits=//p' "$root/$th/index.theme" 2>/dev/null | tr ',' '\n')
			done
		done
	fi

	if [[ -z $icon_theme ]]; then
		bad "no gtk-icon-theme-name in the generation — the icon check cannot know what GTK resolves against"
	elif [[ ${#icon_dirs[@]} -lt 2 ]]; then
		bad "icon theme '$icon_theme' resolved to ${#icon_dirs[@]} directories — the chain walk is broken, not the config"
	elif [[ $icon_count -lt 5 ]]; then
		bad "only $icon_count icon names extracted from the wayle layouts — the scan is broken, not the config"
	else
		imissing=()
		while IFS= read -r n; do
			[[ -z $n ]] && continue
			# wayle's own 361 ship inside the package under five prefixes and are
			# resolved by wayle, not by GTK. `wayle icons list` enumerates them.
			[[ $n == ld-* || $n == si-* || $n == tb-* || $n == md-* || $n == cm-* ]] && continue
			find -L "${icon_dirs[@]}" -name "$n.svg" -print -quit 2>/dev/null | grep -q . || imissing+=("$n")
		done <<<"$iconnames"
		if [[ ${#imissing[@]} -gt 0 ]]; then
			bad "wayle icon names GTK cannot resolve through '$icon_theme' and its inherits" "${imissing[*]}"
		else
			ok "all $icon_count icon names in the wayle layouts resolve through $icon_theme (${#icon_dirs[@]} themes in the chain)"
		fi
	fi
	# 7. The sheet's `$groups` list is exactly the set of groups the layouts
	# declare. Every rule in index.scss is built from that one variable — the
	# within-group gap and the separator both need an ID to out-specify wayle's
	# own rules, so a group missing from the list keeps wayle's spacing while
	# every other group loses it. That is invisible: the bar renders, and one
	# group is merely roomier.
	#
	# The same shape as the waybar module/CSS check above, and for the reason
	# docs/adr/0042 gives.
	SCSS="$GEN_CFG/wayle/styles/index.scss"
	if [[ ! -s $SCSS ]]; then
		bad "wayle/styles/index.scss is missing from the generation" \
			"the bar falls back to wayle's own spacing, which renders and looks merely loose"
	else
		# index.scss carries no descendant `*` selector. GTK4 parents a
		# menubutton's popover inside the menubutton, so `.mod *` matches every
		# widget in every dropdown — the calendar, the notification list, the
		# dashboard — and flattens wayle's own styling of them. The bar looks
		# exactly as intended while everything it opens looks broken, which is
		# why this is a check and not a comment. `> *` is fine: a popover is a
		# child of the module, so a direct-child selector stops one short of it.
		# `+` and `~` are sibling combinators and equally safe — a module's
		# sibling is another module, never something inside one.
		#
		# It lives here, after `$SCSS` is assigned and checked. Its first cut
		# sat above that line and grepped an empty path — passing by finding
		# nothing, over a mutation that added `.mod *` deliberately.
		mapfile -t STARS < <(
			sed 's|//.*||' "$SCSS" | grep -nE '(^|[^>+~[:space:]])[[:space:]]+[*]|^[*]' || true
		)
		if [[ ${#STARS[@]} -gt 0 ]]; then
			bad "index.scss uses a descendant \`*\`, which reaches inside every dropdown" \
				"$(printf '  %s\n' "${STARS[@]}")"
		else
			ok "index.scss uses no descendant \`*\`, so no rule here reaches into a dropdown"
		fi

		# Every rule here that touches a `.bar-button-*` node carries an id.
		#
		# wayle styles those nodes itself, at (0,2,2) for `.bar-button-label`
		# and (0,3,1) for `.bar-button-content`. A selector built from our own
		# classes tops out at (0,2,1) and loses — and a rule that loses is a
		# rule that renders, so the bar looks deliberate and one value is
		# wayle's. `.mod-clock .bar-button-label { font-size }` sat here inert
		# from the day it was written; the clock wore the bar default and
		# nothing said so. An id beats anything wayle can write.
		mapfile -t WEAKBTN < <(
			sed 's|//.*||' "$SCSS" |
				grep -nE '\.bar-button-[a-z]+' |
				grep -v '#' || true
		)
		if [[ ${#WEAKBTN[@]} -gt 0 ]]; then
			bad "index.scss styles a .bar-button-* node without an id, so wayle's own rule wins and this one is inert" \
				"$(printf '  %s\n' "${WEAKBTN[@]}")"
		else
			ok "every index.scss rule touching a .bar-button-* node carries an id, so it out-specifies wayle's own"
		fi

		# The declaration wraps across lines and is joined with `+`, so this
		# reads the whole statement rather than one line of it.
		mapfile -t SCSS_IDS < <(
			sed -n '/^[$]groups:/,/;[[:space:]]*$/p' "$SCSS" |
				grep -oE '#[a-z][a-z0-9-]*' | tr -d '#' | sort -u
		)
		mapfile -t GROUP_IDS < <(
			# `(^|[^-])name`: a module's `icon-name = "ld-power-symbolic"` also
			# ends in `name = "…"` and was read as a group nobody had styled.
			# The `^` alternative is load-bearing — the group names sit at the
			# Start of a line, so requiring a preceding character matched the
			# icon names and nothing else.
			grep -hoE '(^|[^-])name = "[a-z][a-z0-9-]*"' "${WLAYOUTS[@]}" |
				sed 's/.*name = "//;s/"//' | sort -u
		)
		if [[ ${#SCSS_IDS[@]} -eq 0 || ${#GROUP_IDS[@]} -eq 0 ]]; then
			bad "no group ids read from index.scss or the layouts — the scan is broken, not the repo"
		else
			gmiss=""
			for g in "${GROUP_IDS[@]}"; do
				printf '%s\n' "${SCSS_IDS[@]}" | grep -qxF "$g" ||
					gmiss+="  layout group '$g' is missing from index.scss's \$groups"$'\n'
			done
			for c in "${SCSS_IDS[@]}"; do
				printf '%s\n' "${GROUP_IDS[@]}" | grep -qxF "$c" ||
					gmiss+="  index.scss's \$groups names '#$c', which no layout groups"$'\n'
			done
			if [[ -n $gmiss ]]; then
				bad "wayle group/stylesheet mismatch" "$gmiss"
			else
				ok "all ${#GROUP_IDS[@]} wayle layout groups are named in index.scss's \$groups, and no others are"
			fi
		fi
	fi

	# 8. The palette reaches them. A wayle layout with no [styling.palette] wears
	# wayle's own default colours, which is a complete, plausible theme and not
	# this machine's — the drifted-palette failure docs/adr/0028 gets a check for
	# rather than a convention. Checked against the artefact scheme's own bg.
	wbg=$(pal '.bg0')
	pmiss=""
	for cfg in "${WLAYOUTS[@]}"; do
		grep -qF "bg = \"#$wbg\"" "$cfg" || pmiss+="  $(basename "$cfg")"$'\n'
	done
	if [[ -z $wbg ]]; then
		bad "no bg0 read from the scheme — the scan is broken, not the repo"
	elif [[ -n $pmiss ]]; then
		bad "a wayle layout does not carry this scheme's background (#$wbg)" \
			"it would wear wayle's own palette, which looks deliberate:"$'\n'"$pmiss"
	else
		ok "all ${#WLAYOUTS[@]} wayle layouts carry the '$PAL_SCHEME' background #$wbg"
	fi
fi

printf '\nGenerated waybar configs\n'

# Every layout, in both positions. Named rather than counted: a count alone
# passes when one layout vanishes and another is added twice, and the layout
# Names are what waybar-restart.sh builds its filename from — a missing one is
# the fallback-to-full path, which logs but keeps running. Was 4 layouts until
# hud left.
# Configs stays full paths — every scan below this point reads the files.
mapfile -t CONFIGS < <(find "$WAYBAR_DIR" -name 'config-*.jsonc' | sort)
cfgmiss=""
for l in full focus minimal; do
	for pos in top bottom; do
		[[ -s "$WAYBAR_DIR/config-$l-$pos.jsonc" ]] || cfgmiss+="  config-$l-$pos.jsonc"$'\n'
	done
done
if [[ -n $cfgmiss ]]; then
	bad "a generated waybar config is missing" "$cfgmiss"
elif [[ ${#CONFIGS[@]} -ne 6 ]]; then
	bad "expected 6 generated waybar configs (3 layouts x 2 positions), found ${#CONFIGS[@]}" \
		"$(printf '%s ' "${CONFIGS[@]##*/}")"
else
	ok "6 generated waybar configs — full, focus and minimal, each top and bottom"
fi

# Every module a layout carries needs a CSS rule, and every `format` needs
# something in it. Both are invisible — waybar renders the bar either way — and
# both were made in one sitting adding `custom/control-center`: the glyph was
# dropped writing the Nix (no \uXXXX escape, so it is literal UTF-8), and a new
# module has no rule until someone writes one. docs/gotchas.md -> Waybar.
#
# Ids are waybar's own: `custom/foo` -> `#custom-foo`, other prefixes dropped.
css_seen=0
cssmiss=""
fmtempty=""
STYLE_CSS="$WAYBAR_DIR/style-solid.css"
if [[ ! -s $STYLE_CSS ]]; then
	bad "style-solid.css is missing from the generation — every rule scan below would find nothing"
else
	for cfg in "${CONFIGS[@]}"; do
		while IFS= read -r m; do
			[[ -z $m ]] && continue
			css_seen=$((css_seen + 1))
			case $m in
			custom/*) id="#custom-${m#custom/}" ;;
			*/*) id="#${m#*/}" ;;
			*) id="#$m" ;;
			esac
			grep -qE "^\s*${id}[ ,{:]" "$STYLE_CSS" ||
				grep -qxF "$id," "$STYLE_CSS" ||
				cssmiss+="  $m -> $id (${cfg##*/})"$'\n'
			# Quoted keys: `.modules-left` is jq for `.modules` minus `left`,
			# which yields null rather than an error and would empty the scan.
			#
			# `sub("#.*$";"")` drops the group tag a layout appends to the first
			# module of each group (`network#sep`, docs/adr/0042). Without it
			# every tagged module derives the id `#network#sep`, matches no rule
			# and is reported missing.
		done < <(jq -r '(.["modules-left"] // []) + (.["modules-center"] // []) + (.["modules-right"] // []) | .[] | sub("#.*$"; "")' "$cfg" 2>/dev/null)

		while IFS= read -r m; do
			[[ -z $m ]] && continue
			fmtempty+="  $m has an empty format (${cfg##*/})"$'\n'
		done < <(jq -r 'to_entries[] | select(.value | type == "object") | select(.value.format? == "") | .key' "$cfg" 2>/dev/null)
	done
	cssmiss=$(printf '%s' "$cssmiss" | sort -u)
	fmtempty=$(printf '%s' "$fmtempty" | sort -u)

	if [[ $css_seen -eq 0 ]]; then
		bad "no modules read from the generated waybar configs — the scan is broken, not the repo"
	elif [[ -n $cssmiss ]]; then
		bad "a waybar module a layout carries has no rule in style-solid.css" \
			"it renders in the bar's defaults, which looks like a styling choice:"$'\n'"$cssmiss"
	else
		ok "$css_seen module slots across the layouts all have a rule in style-solid.css"
	fi

	if [[ -n $fmtempty ]]; then
		bad "a waybar module has an empty format string" \
			"it renders as an empty module, which is indistinguishable from one that is merely missing:"$'\n'"$fmtempty"
	else
		ok "no waybar module renders an empty format"
	fi

	# --- ONE GLYPH PACK -------------------------------------------------------
	#
	# Every glyph the bar prints is nf-md (Material Design), which lives in plane
	# 15 at U+F0000 and above. Font Awesome, Octicons, nf-linux and nf-weather
	# all sit in the BMP private-use area at U+E000-U+F8FF, and bare arrows and
	# crosses at U+2190-U+2BFF — so a glyph from another pack is a codepoint
	# BELOW U+F0000, and that is the whole test.
	#
	# It is worth a check rather than a convention because the failure is not an
	# error: a Font Awesome bell renders perfectly well, at a different stroke
	# weight from everything beside it, and reads as the bar being untidy rather
	# than as a mistake. The bar carried four packs until 2026-08-27.
	# docs/adr/0051.
	#
	# jq -r piped to a codepoint dump, never by eye — CLAUDE.md's rule for
	# glyphs in Nix, and the same reason applies to reading them back out.
	# Values only: a KEY may legitimately be an appid or a state name.
	packbad=""
	packseen=0
	for cfg in "$WAYBAR_DIR"/config-*.jsonc; do
		[[ -s $cfg ]] || continue
		# `explode` is jq's own codepoint dump, and jq is already a build input
		# here — the check sandbox has no python. Values only: a KEY may
		# legitimately be an appid or a state name.
		while read -r cp; do
			[[ -n $cp ]] || continue
			if [[ $cp -ge 983040 ]]; then
				packseen=$((packseen + 1))
			else
				packbad+="  ${cfg##*/}: U+$(printf '%04X' "$cp")"$'\n'
			fi
		done < <(
			jq -r '[.. | strings] | join("") | explode | unique | .[]
			       | select((. >= 8592 and . <= 11263)
			             or (. >= 57344 and . <= 63743)
			             or (. >= 983040))' "$cfg" 2>/dev/null
		)
	done
	if [[ $packseen -eq 0 ]]; then
		bad "no bar glyphs read at all — the scan is broken, not the repo" "$WAYBAR_DIR"
	elif [[ -n $packbad ]]; then
		packbad=$(printf '%s' "$packbad" | sort -u)
		bad "a bar glyph comes from a pack other than nf-md" \
			"it renders fine, at a different stroke weight from everything beside it:"$'\n'"$packbad"
	else
		ok "all $packseen bar glyphs are nf-md, one pack across every layout"
	fi

	# A module that declares `signal = N` and has nothing sending RTMIN+N updates
	# only on its poll interval. The key or click changes the state immediately and
	# the bar shows the old value for up to 30 s, which reads as the binding not
	# working. Four modules were in that state: the pushes were removed when waybar
	# was retired for wayle, and docs/adr/0051 restored waybar without them.
	#
	# `^[^#]*` so the comment explaining a removed push does not count as one.
	# docs/adr/0056.
	sigbad=""
	sigseen=0
	while read -r mod num; do
		[[ -n $num ]] || continue
		sigseen=$((sigseen + 1))
		grep -rqE "^[^#]*pkill -RTMIN\+$num waybar" "$SRC/dotfiles/mango/scripts" 2>/dev/null ||
			sigbad+="  $mod declares signal $num and nothing sends RTMIN+$num"$'\n'
	done < <(
		jq -r 'to_entries[] | select(.value | type == "object")
		       | select(.value.signal != null)
		       | "\(.key | sub("#.*$"; ""))\t\(.value.signal)"' \
			"${CONFIGS[0]}" 2>/dev/null | sort -u
	)
	if [[ $sigseen -eq 0 ]]; then
		bad "no waybar module declares a signal — the scan is broken, not the repo"
	elif [[ -n $sigbad ]]; then
		bad "a waybar module declares a refresh signal nothing sends" \
			"it updates only on its poll interval, so a key press looks inert:"$'\n'"$sigbad"
	else
		ok "all $sigseen waybar refresh signals have a sender in the scripts"
	fi

	# --- ...and the glyphs scripts print --------------------------------------
	#
	# The pack scan above reads the generated configs, so it cannot see a glyph a
	# script emits. One hid there through docs/adr/0051's one-pack pass:
	# night-mode.sh wrote Font Awesome's moon as `printf '\xef\x86\x86'`
	# (U+F186), and raw UTF-8 bytes are not a codepoint anyone reads.
	#
	# Two halves, both needed. Scripts declare a glyph as `$'\UXXXXXXXX'`, the
	# convention network-menu.sh already documented for its ethernet icon, which
	# puts the codepoint where this can check it. And no script may carry a raw
	# private-use character, which would bypass the escape scan.
	#
	# BOTH HALVES MATCHED TOO LITTLE AND PASSED. The escape scan read only
	# `\U` + eight digits, so all 39 of the Font Awesome and nf-weather glyphs
	# written the other legal way — `$'\uXXXX'`, four digits — were invisible to
	# it, including the very nf-fa moon (U+F186) this check was added to catch.
	# It reported "all N are nf-md" over a bar carrying three packs. The floor
	# assertion could not save it: idle-inhibit.sh supplied two matches, so the
	# count was never zero. A scan that stops matching passes by finding nothing;
	# this one had never matched. docs/adr/0057.
	#
	# So: both widths, either case. A 4-digit escape cannot reach U+F0000, which
	# is the point — every one of them is a glyph from another pack, except the
	# sub-U+E000 escapes that are not glyphs at all (`\u001f`, window-title.sh's
	# field separator). U+E000 is where the private use area starts and is the
	# line between the two.
	#
	# The raw-literal half is a byte test, now over all three lead bytes a
	# private-use character can have: 0xEE and 0xEF carry U+E000-U+F8FF, and
	# plane 15 leads with 0xF3 — which the bracket omitted, so raw nf-md
	# literals in vpn.sh and phone-status.sh sat outside the convention the
	# paragraph above states. `^[^#]*` excludes a comment about a codepoint;
	# idle-inhibit.sh has one. docs/adr/0054, docs/adr/0057.
	glyphbad=""
	glyphseen=0
	for f in "${SCRIPTS[@]}"; do
		# This file is in SCRIPTS by its shebang, and it holds the powerline
		# separators the yazi flavour check above expects. They are not glyphs
		# anything here prints, and yazi is not the bar.
		[[ $f == "$SRC/checks/static.sh" ]] && continue
		while read -r hex; do
			[[ -n $hex ]] || continue
			cp=$((16#$hex))
			# Below the private use area it is an escape, not a glyph.
			[[ $cp -ge 57344 ]] || continue
			if [[ $cp -ge 983040 ]]; then
				glyphseen=$((glyphseen + 1))
			else
				glyphbad+="  ${f#"$SRC"/}: U+$(printf '%04X' "$cp") is not nf-md"$'\n'
			fi
		done < <(grep -oE '\\[Uu][0-9A-Fa-f]{4}([0-9A-Fa-f]{4})?' "$f" 2>/dev/null | sed 's/^\\[Uu]//')

		if LC_ALL=C grep -q $'^[^#]*[\xee\xef\xf3]' "$f" 2>/dev/null; then
			glyphbad+="  ${f#"$SRC"/}: a raw private-use character — write it as \$'\\UXXXXXXXX'"$'\n'
		fi
	done
	# 40, not 0. A zero floor is what let the old scan pass: it matched 12 of the
	# 51 escapes here and reported a clean bill, because 12 is not zero. The
	# floor has to sit above the largest count a broken pattern can still
	# return, which that one proved is not small. docs/adr/0057.
	if [[ $glyphseen -lt 40 ]]; then
		bad "only $glyphseen glyph escapes read from ${#SCRIPTS[@]} scripts — the scan is broken, not the repo" \
			"the pattern reads both \$'\\uXXXX' and \$'\\UXXXXXXXX'; a count this low means it stopped matching"
	elif [[ -n $glyphbad ]]; then
		bad "a glyph a script prints is not nf-md, or is not readable as a codepoint" \
			"it renders fine, at a different stroke weight from everything beside it:"$'\n'"$glyphbad"
	else
		ok "all $glyphseen glyph escapes in ${#SCRIPTS[@]} scripts are nf-md, and none is a raw literal"
	fi

	# --- EVERY THEMED ICON NAME RESOLVES --------------------------------------
	#
	# The bar draws real icon-theme art through `-gtk-icontheme("name")` in its
	# stylesheet: the window title's per-app icon, the minimized indicator and
	# the whole battery ladder (docs/adr/0052). An icon NAME is the half of a
	# theme that fails silently — GTK draws nothing and logs nothing, so the
	# module reads as empty rather than as wrong. Same failure adr/0041 gave the
	# GTK, Kvantum and cursor names their own check for, and the same answer.
	#
	# Resolved against the scheme's own icon theme and the themes it inherits,
	# not against the whole of share/icons: a name that exists only in some
	# other installed theme resolves here and draws nothing in the session.
	icon_theme_dirs() {
		local iroot="$GEN/home-path/share/icons" iseen="" iqueue="$1" inext icur iidx
		while [[ -n $iqueue ]]; do
			icur=${iqueue%%:*}
			if [[ $iqueue == *:* ]]; then iqueue=${iqueue#*:}; else iqueue=""; fi
			[[ -n $icur && ":$iseen:" != *":$icur:"* ]] || continue
			iseen="$iseen:$icur"
			[[ -d "$iroot/$icur" ]] || continue
			printf '%s\n' "$iroot/$icur"
			# `find -L`: buildEnv leaves a single-contributor share/ subdirectory
			# as a symlink, and a plain find returns nothing through it.
			inext=$(find -L "$iroot/$icur" -maxdepth 1 -name index.theme -print -quit 2>/dev/null)
			[[ -n $inext ]] || continue
			iidx=$(sed -n 's/^Inherits=//p' "$inext" | head -1 | tr ',' ':')
			[[ -n $iidx ]] && iqueue="$iqueue:$iidx"
		done
	}

	ICONS_CSS_FOR_OWNER="$WAYBAR_DIR/icons.css"
	ICON_THEME=$(pal ".packages.icons.name")
	mapfile -t ICON_DIRS < <(icon_theme_dirs "$ICON_THEME:hicolor")

	# Values only, and from the GENERATION rather than the source tree: what the
	# session reads is what is linked, and icons.css exists only there.
	mapfile -t ICON_NAMES < <(
		grep -ho -- '-gtk-icontheme("[^"]*")' "$WAYBAR_DIR"/*.css 2>/dev/null |
			sed 's/.*("//; s/")$//' | sort -u
	)

	iconmiss=""
	if [[ ${#ICON_DIRS[@]} -eq 0 ]]; then
		bad "no icon theme directory for '$ICON_THEME' — the scan is broken, not the repo" \
			"$GEN/home-path/share/icons"
	elif [[ ${#ICON_NAMES[@]} -eq 0 ]]; then
		bad "no -gtk-icontheme() names read from the bar's stylesheets — the scan is broken" \
			"$WAYBAR_DIR"
	else
		for n in "${ICON_NAMES[@]}"; do
			found=""
			for d in "${ICON_DIRS[@]}"; do
				found=$(find -L "$d" \( -name "$n.svg" -o -name "$n.png" \) -print -quit 2>/dev/null)
				[[ -n $found ]] && break
			done
			[[ -n $found ]] || iconmiss+="  $n"$'\n'
		done
		if [[ -n $iconmiss ]]; then
			bad "the bar names an icon '$ICON_THEME' does not have" \
				"GTK draws nothing and logs nothing, so the module reads as empty:"$'\n'"$iconmiss"
		else
			ok "all ${#ICON_NAMES[@]} themed icon names the bar draws resolve in $ICON_THEME"
		fi
	fi

	# --- EVERY CURATED APPID IS ALSO A WINDOW-MODE ICON -----------------------
	#
	# `rofi -show window -show-icons` (SUPER+w) resolves art from the LOWERCASE
	# APPID against the icon theme and takes no desktop-file step, unlike drun
	# (rofi's wayland-window.c:610). An appid that is not itself an icon name
	# draws a blank column and logs nothing, so modules/home/waybar.nix aliases
	# the ones the theme has no name for into hicolor.
	#
	# This asserts the FLOOR rather than the alias list: every appid the bar
	# curates must resolve, however it resolves — by the theme, by the app's own
	# hicolor icon, or by an alias. So an appid added to `appIcons` and forgotten
	# here fails, and an alias that stops being needed does not.
	#
	# Read from the GENERATION, and the same chain rofi walks: `icon-theme` plus
	# hicolor. rofi does NOT read GTK's setting — with it unset the chain is
	# {Adwaita, gnome} (rofi-icon-fetcher.c:276), which is why dotfiles.nix
	# generates rofi/icons.rasi at all.
	mapfile -t WIN_APPIDS < <(
		jq -r 'keys[] | select(. != "default")' "$WAYBAR_DIR/app-icons.json" 2>/dev/null
	)
	if [[ ${#WIN_APPIDS[@]} -eq 0 ]]; then
		bad "no appids read from app-icons.json — the scan is broken, not the repo" \
			"$WAYBAR_DIR/app-icons.json"
	elif [[ ${#ICON_DIRS[@]} -eq 0 ]]; then
		: # already reported by the check above; do not say it twice
	else
		winmiss=""
		for a in "${WIN_APPIDS[@]}"; do
			low=${a,,}
			found=""
			for d in "${ICON_DIRS[@]}"; do
				found=$(find -L "$d" \( -name "$low.svg" -o -name "$low.png" \) -print -quit 2>/dev/null)
				[[ -n $found ]] && break
			done
			[[ -n $found ]] || winmiss+="  $a (looked up as '$low')"$'\n'
		done
		if [[ -n $winmiss ]]; then
			bad "an appid the bar curates has no window-mode icon" \
				"SUPER+w draws a blank column for it and logs nothing; alias it in modules/home/waybar.nix:"$'\n'"$winmiss"
		else
			ok "all ${#WIN_APPIDS[@]} curated appids resolve as window-mode icons in $ICON_THEME"
		fi
	fi

	# --- ONE OWNER PER ICONED SELECTOR ----------------------------------------
	#
	# icons.css is @imported at the top of style-solid.css, so when both declare
	# `background-image` for the SAME selector the hand-written sheet wins and
	# the generated one does nothing. Both files are valid CSS and GTK reports
	# neither, which is how `#custom-minimized`'s generated icon spent a render
	# being ignored — the same shape as the duplicate `#custom-weather`
	# font-size, one file further out. docs/adr/0052.
	#
	# Selectors, not properties: the two sheets are MEANT to style the same ids,
	# and the split is that icons.css owns the icon and style-solid.css owns the
	# geometry around it.
	bg_selectors() {
		# A rule's selector is what precedes `{`, and every generated rule is one
		# line. Multi-selector blocks (`#battery.l0.charging,` on its own line)
		# carry the previous line, exactly as the bare-rule scan does.
		awk '
			/^[^{]*,[[:space:]]*$/ { pend = pend $0; next }
			/background-image/ {
				line = pend $0
				sub(/\{.*/, "", line)
				n = split(line, parts, ",")
				for (i = 1; i <= n; i++) {
					gsub(/^[[:space:]]+|[[:space:]]+$/, "", parts[i])
					if (parts[i] != "") print parts[i]
				}
			}
			{ pend = "" }
		' "$1" | sort -u
	}

	SOLID_CSS="$WAYBAR_DIR/style-solid.css"
	if [[ ! -f $ICONS_CSS_FOR_OWNER || ! -f $SOLID_CSS ]]; then
		bad "icons.css or style-solid.css is missing from the generation — the scan is broken" \
			"$WAYBAR_DIR"
	else
		dupsel=$(comm -12 <(bg_selectors "$ICONS_CSS_FOR_OWNER") <(bg_selectors "$SOLID_CSS"))
		gen_n=$(bg_selectors "$ICONS_CSS_FOR_OWNER" | grep -c '')
		if [[ $gen_n -eq 0 ]]; then
			bad "no background-image rules read from the generated icons.css — the scan is broken" \
				"$ICONS_CSS_FOR_OWNER"
		elif [[ -n $dupsel ]]; then
			bad "icons.css and style-solid.css both set background-image for a selector" \
				"style-solid.css is imported later and wins, so the generated icon does nothing:"$'\n'"$dupsel"
		else
			ok "all $gen_n generated icon selectors are the generated sheet's alone"
		fi

		# ...and none of them may be a BARE id. style-solid.css gives every
		# module `background: transparent` — the shorthand, which resets
		# `background-image` — at one-id specificity, after this file's @import.
		# So a generated `#custom-minimized { background-image: … }` loses and the
		# module draws no icon, with both sheets valid and nothing logged. Every
		# rule here must out-specify that block, which means carrying a class.
		# docs/adr/0052.
		bare=$(bg_selectors "$ICONS_CSS_FOR_OWNER" | grep -v '\.' || true)
		if [[ -n $bare ]]; then
			bad "a generated icon rule is a bare id, so the shared block's 'background: transparent' wins" \
				"the module draws no icon at all, and no sheet is invalid:"$'\n'"$bare"
		else
			ok "every generated icon rule carries a class, so none is reset by the shared block"
		fi
	fi

	# --- THE TWO HALVES OF THE APPID CLASS AGREE ------------------------------
	#
	# waybar.nix writes the selector `#custom-window.<class>` and
	# window-title.sh emits the class at runtime. Neither can see the other, and
	# a class that stops matching its rule is not an error: the module keeps its
	# label and quietly wears the default icon. So the shell half is RUN here,
	# over the appids Nix declared, and its answer must have a rule.
	WT_SH="$SRC/dotfiles/mango/scripts/waybar/window-title.sh"
	ICONS_CSS="$WAYBAR_DIR/icons.css"
	classbad=""
	classseen=0
	if [[ ! -f $WT_SH || ! -f $ICONS_CSS ]]; then
		bad "window-title.sh or the generated icons.css is missing — the scan is broken" \
			"$WT_SH  $ICONS_CSS"
	else
		# The appid table as the generated file carries it — the same file the
		# picker reads, so this checks what both callers actually get.
		appid_json=$(jq -c . "$WAYBAR_DIR/app-icons.json" 2>/dev/null)
		# Source only the function, not the script: window-title.sh runs an
		# `mmsg watch` loop that would never return.
		eval "$(sed -n '/^css_class() {/,/^}/p' "$WT_SH")"
		while IFS= read -r appid; do
			[[ -n $appid && $appid != default ]] || continue
			classseen=$((classseen + 1))
			grep -q "^#custom-window\.$(css_class "$appid") " "$ICONS_CSS" ||
				classbad+="  $appid -> .$(css_class "$appid") has no rule"$'\n'
		done < <(printf '%s' "$appid_json" | jq -r 'keys[]?' 2>/dev/null)

		if [[ $classseen -eq 0 ]]; then
			bad "no appids read out of the generated app-icons.json — the scan is broken" \
				"$WAYBAR_DIR/app-icons.json"
		elif [[ -n $classbad ]]; then
			bad "window-title.sh and waybar.nix disagree on an appid's CSS class" \
				"the module keeps its label and silently wears the default icon:"$'\n'"$classbad"
		else
			ok "all $classseen appid classes window-title.sh emits have a rule in icons.css"
		fi
	fi

	# ...and the inverse direction, which was missing. A rule outlives the module
	# it styles in silence: `#custom-scratch-spotify` and `#custom-scratch-equibop`
	# sat here with no definition in waybar.nix, no layout carrying them and no
	# other mention anywhere in the repo, because the scan above only ever ran
	# module -> rule. Same shape as the both-ways palette check, docs/adr/0028.
	declare -A live=()
	for cfg in "${CONFIGS[@]}"; do
		while IFS= read -r m; do
			[[ -z $m ]] && continue
			case $m in
			custom/*) live["#custom-${m#custom/}"]=1 ;;
			*/*) live["#${m#*/}"]=1 ;;
			*) live["#$m"]=1 ;;
			esac
		done < <(jq -r '(.["modules-left"] // []) + (.["modules-center"] // []) + (.["modules-right"] // []) | .[] | sub("#.*$"; "")' "$cfg" 2>/dev/null)
	done

	# Comments out, newlines out: both scans below have to see rules, and a `#id`
	# written in prose is not one. `#custom-scratch-*` were found through comment
	# text on the first attempt at this check, which passed for the wrong reason.
	#
	# Not `sed '/\/\*/,/\*\//d'`. A sed range looks for its end pattern from the
	# Next line on, so a one-line `/* ── Tooltip ── */` header opens a range that
	# only closes at the following comment's `*/` — that ate two thirds of this
	# sheet, and both scans below passed on the remains. Flatten first, then the
	# standard non-greedy-by-construction C comment match.
	css_flat=$(tr '\n' ' ' <"$STYLE_CSS" | sed 's|/\*[^*]*\*\+\([^/*][^*]*\*\+\)*/| |g')

	# Module ids only: `#waybar` is the bar window, not a module.
	orphan=""
	rules=0
	while IFS= read -r id; do
		[[ -z $id || $id == "#waybar" ]] && continue
		rules=$((rules + 1))
		[[ -n ${live[$id]:-} ]] || orphan+="  $id"$'\n'
	done < <(printf '%s' "$css_flat" | grep -oE '#[a-z][a-z-]*' | sort -u)

	orphan=$(printf '%s' "$orphan" | sort -u)
	if [[ $rules -eq 0 ]]; then
		bad "no #id rules read from style-solid.css — the scan is broken, not the sheet"
	elif [[ -n $orphan ]]; then
		bad "style-solid.css styles a module no layout carries" \
			"the module is gone and its rule is not, which nothing else reports:"$'\n'"$orphan"
	else
		ok "all $rules styled ids in style-solid.css belong to a module some layout carries"
	fi

	# --- ONE BARE RULE PER ID -------------------------------------------------
	#
	# `#custom-weather { font-size }` was written twice on 2026-08-27, once
	# beside the clock and once in the weather section. Same specificity, so the
	# LATER one won and the earlier one did nothing — the size did not change, a
	# rebuild was spent on it, and the sheet reported nothing because both rules
	# are perfectly valid.
	#
	# Bare `#id {` only, and only where it OPENS the rule. A state rule
	# (`#custom-weather.ok`) is a different selector on purpose and there are a
	# dozen of them; and the shared blocks at the top of the sheet are ONE rule
	# over many selectors, so their last line is `#custom-power-profile {` with
	# `#custom-phone,` above it. Counting that as a bare rule reported a
	# duplicate that is not one, which is what the first version of this check
	# did. The awk carries the previous line for exactly that. docs/adr/0051.
	dupids=$(
		awk '
			/^[[:space:]]*($|\/\*|\*)/ { next }
			/^#[a-z0-9-]+ \{$/ && prev !~ /,$/ { sub(/ \{$/, ""); print }
			{ prev = $0 }
		' "$STYLE_CSS" 2>/dev/null | sort | uniq -d
	)
	if [[ -n $dupids ]]; then
		bad "an id is styled by two bare rules in style-solid.css" \
			"same specificity, so the later one wins and the earlier does nothing, silently:"$'\n'"$(printf '  %s\n' "$dupids")"
	else
		ok "no id in style-solid.css carries two bare rules"
	fi

	# Separators are declared by the layout now (docs/adr/0042): a group's first
	# module is emitted as `name#sep` and `.sep` draws the line. Both halves are
	# silent on their own — a tag with no rule draws nothing, and the old
	# module-keyed `border-left` rules would draw lines the layout never asked
	# for, which is the drift this replaced.
	tagged=$(jq -r '(.["modules-left"] // []) + (.["modules-right"] // []) | .[] | select(test("#sep$"))' "${CONFIGS[@]}" 2>/dev/null | wc -l)
	strays=$(printf '%s' "$css_flat" | grep -oE '[^{}]*\{[^{}]*\}' |
		grep -E 'border-(left|right):' | grep -c '#' || true)
	if [[ $tagged -eq 0 ]]; then
		bad "no waybar module carries a #sep tag — every group separator is missing from the bar"
	elif ! grep -qE '^\.sep \{' "$STYLE_CSS"; then
		bad "modules carry a #sep tag but style-solid.css has no .sep rule" \
			"the tags are inert and the bar renders with no separators at all"
	elif [[ $strays -gt 0 ]]; then
		bad "a module-keyed border-left/right is back in style-solid.css" \
			"grouping belongs to the layout — a module-keyed border moves when a layout drops a neighbour (docs/adr/0042)"
	else
		ok "$tagged group separators, all drawn by the one .sep rule"
	fi

	# `#mpris.sep { margin-left: 0 }` closes one boundary, the one after the
	# workspace buttons. It is keyed by module because GTK cannot say "the .sep
	# after workspaces", so if mpris stops following workspaces the closed gap
	# moves to whatever module took its place. style-solid.css claimed this was
	# asserted since docs/adr/0042; nothing asserted it. docs/adr/0053.
	sepafter_bad=""
	sepafter_seen=0
	for cfg in "${CONFIGS[@]}"; do
		after=$(jq -r '
			(.["modules-left"] // []) as $l
			| ($l | index("ext/workspaces#sep")) as $i
			| if $i == null then empty else ($l[$i + 1] // "<nothing>") end
		' "$cfg" 2>/dev/null)
		[[ -z $after ]] && continue
		sepafter_seen=$((sepafter_seen + 1))
		[[ $after == "mpris#sep" ]] ||
			sepafter_bad+="  ${cfg##*/}: ext/workspaces is followed by $after"$'\n'
	done
	if [[ $sepafter_seen -eq 0 ]]; then
		bad "no waybar layout carries a tagged ext/workspaces — the scan is broken, not the layouts"
	elif [[ -n $sepafter_bad ]]; then
		bad "mpris no longer follows the workspace buttons, and #mpris.sep still trims their boundary" \
			"the 3px comes off some other group's gap instead, which reads as that group being written wrong:"$'\n'"$sepafter_bad"
	else
		ok "mpris follows ext/workspaces in all $sepafter_seen layouts, so #mpris.sep closes the boundary it was written for"
	fi

	# @accent means selection. On the bar it draws the active tag's underline and,
	# mixed toward @text, the media tint — nothing else, because on some schemes
	# it is also the alarm hue (heartbox: dE2000 10.9 from errColor). It drew the
	# balanced power profile and a connected bluetooth until docs/adr/0053, two
	# benign states in the alarm colour.
	#
	# `mix(...)` is exempt: a tint is not the accent. Comments are already gone
	# from css_flat, so prose mentioning @accent cannot trip this.
	accent_bad=$(printf '%s' "$css_flat" | grep -oE '[^{}]*\{[^{}]*\}' |
		sed 's/mix([^)]*)//g' |
		grep '@accent' |
		grep -vE '#workspaces button\.active' || true)
	if [[ -n $accent_bad ]]; then
		bad "@accent is used outside the active workspace tag" \
			"it is the selection colour, and on heartbox it is one step from errColor — a benign state wearing it reads as an alarm:"$'\n'"$accent_bad"
	else
		ok "@accent draws the active tag and the media tint, and nothing else"
	fi

	# The resting power profile takes no colour. `balanced` is what the machine
	# reports almost always, so a hue there marks the ordinary state as an alarm.
	# Read as a value, because the regression is a rule that exists and is wrong.
	bal=$(printf '%s' "$css_flat" |
		grep -oE '#custom-power-profile\.balanced[^{}]*\{[^{}]*\}' |
		sed -n 's/.*color:[[:space:]]*\([^;}]*\).*/\1/p' | tr -d ' ')
	if [[ $bal != "@subtext" ]]; then
		bad "the balanced power profile draws '${bal:-nothing}', not @subtext" \
			"it is the resting state and it is on almost always; a colour there is a permanent indicator for nothing happening"
	else
		ok "the resting power profile takes the bar's neutral, so only performance and fanless speak"
	fi

	# Three rules the tag strip depends on, each silent when it goes.
	#
	# The tag is an underline since docs/adr/0053, because @accent and the alarm
	# colours are one hue apart under some schemes. The border is reserved on
	# every button and only its colour changes, or the active button is 2px taller
	# and its label shifts on every tag switch.
	#
	# The strip is flush to the line on both sides: `#workspaces { padding: 0 }`
	# is (1,0,0) and beats `.sep`'s (0,1,0) padding-left, and
	# `#mpris.sep { margin-left: 0 }` closes the other side. Both are deliberate
	# and both look like mistakes next to the 11px after every other separator, so
	# a later pass that "restores" either has to fail here.
	ws_bad=""
	grep -qE '^\s*border-bottom: 2px solid transparent;' "$STYLE_CSS" ||
		ws_bad+="  #workspaces button reserves no transparent border, so activating a tag changes its height"$'\n'
	grep -qE '^#workspaces button\.active \{' "$STYLE_CSS" ||
		ws_bad+="  #workspaces button.active has no rule, so the focused tag looks like every other"$'\n'
	grep -qE '^#workspaces \{' "$STYLE_CSS" ||
		ws_bad+="  #workspaces sets no padding of its own, so .sep's 11px reopens the gap before the tags"$'\n'
	grep -qE '^#workspaces\.sep \{' "$STYLE_CSS" &&
		ws_bad+="  #workspaces.sep is back, which reopens the gap between the line and the first tag"$'\n'
	# The rule's BODY, not just its presence: it existed with `margin-left: 3px`
	# for one commit, which is the value this is here to keep out.
	mpris_margin=$(awk '/^#mpris\.sep \{/ { inr = 1; next } inr && /^\}/ { inr = 0 } inr' "$STYLE_CSS" |
		sed -n 's/^[[:space:]]*margin-left:[[:space:]]*\(.*\);/\1/p')
	[[ $mpris_margin == "0" ]] ||
		ws_bad+="  #mpris.sep sets margin-left to '${mpris_margin:-nothing}', not 0, so the tag strip is flush on one side only"$'\n'
	if [[ -n $ws_bad ]]; then
		bad "the workspace tag strip lost a rule its shape depends on" "$ws_bad"
	else
		ok "the active tag underlines a reserved border, and the tag strip is flush to the line on both sides"
	fi

	# One canonical group order, and a layout may only drop a module from it
	# (docs/adr/0042). Two layouts that disagree about the order of a module they
	# both carry make SUPER+/ rearrange the bar under you — which is what the
	# note "so SUPER+/ does not move it" used to ask a reader to maintain by
	# hand, on a file where a module is one line in a list.
	order_bad=""
	order_pairs=0
	for a in "${CONFIGS[@]}"; do
		for b in "${CONFIGS[@]}"; do
			[[ $a < $b ]] || continue
			A=$(jq -r '(.["modules-left"] // []) + (.["modules-center"] // []) + (.["modules-right"] // []) | .[] | sub("#.*$"; "")' "$a" 2>/dev/null)
			B=$(jq -r '(.["modules-left"] // []) + (.["modules-center"] // []) + (.["modules-right"] // []) | .[] | sub("#.*$"; "")' "$b" 2>/dev/null)
			shared=$(comm -12 <(sort <<<"$A") <(sort <<<"$B"))
			[[ -z $shared ]] && continue
			order_pairs=$((order_pairs + 1))
			oa=$(grep -xF -f <(printf '%s\n' "$shared") <<<"$A")
			ob=$(grep -xF -f <(printf '%s\n' "$shared") <<<"$B")
			[[ $oa == "$ob" ]] ||
				order_bad+="  ${a##*/} vs ${b##*/}"$'\n'
		done
	done
	if [[ $order_pairs -eq 0 ]]; then
		bad "no pair of waybar layouts shares a module — the order scan is broken, not the layouts"
	elif [[ -n $order_bad ]]; then
		bad "two waybar layouts order a shared module differently" \
			"SUPER+/ then moves it, which reads as the bar rearranging itself:"$'\n'"$order_bad"
	else
		ok "$order_pairs layout pairs agree on the order of every module they share"
	fi

	# The bar's base padding has to sit on `.module` — waybar's own class, on the
	# same widget as the #id and the #sep tag. Both plausible alternatives were
	# tried and both fail silently: on `*` it stacks onto the padding of the label
	# inside a workspace button and the icon inside a tray item, and on
	# `.modules-right > *` it lands on the EventBox wrapper, which never draws it,
	# so modules render flush against each other. docs/adr/0042.
	if ! grep -qE '^\.module \{' "$STYLE_CSS"; then
		bad "style-solid.css sets no padding on .module" \
			"the bar has no base spacing, or it is on a widget that does not draw it"
	elif printf '%s' "$css_flat" | grep -oE '(^|\})[^{}]*\{[^{}]*\}' |
		grep -E 'padding' | grep -qE '(\*|modules-(left|center|right) >)[^{}]*\{'; then
		bad "style-solid.css sets padding through \`*\` or \`.modules-* > *\`" \
			"neither is the module widget: one stacks onto the button and icon padding inside a module, the other lands on the EventBox wrapper and draws nothing"
	else
		ok "the bar's base padding is on .module, the widget that carries the #id"
	fi

	# Reverting the font stack is invisible: the icons still render, just with
	# their ink hanging out of the cell to the right.
	# docs/gotchas.md -> Waybar.
	if grep -qE '^\s*font-family: "Symbols Nerd Font Mono", "3270 Nerd Font", monospace;' "$STYLE_CSS"; then
		ok "the bar asks for Symbols Nerd Font Mono before 3270, so icon ink sits inside its cell"
	else
		bad "style-solid.css no longer names Symbols Nerd Font Mono ahead of 3270 Nerd Font" \
			"3270 patches the icons in at a 0.54em advance, so their ink overflows to the right and padding cannot centre it"
	fi

	# The size and the weight move together. 3270's regular goes thin and uneven
	# under 14px, so dropping `bold` while keeping 13.5 makes the bar look blurry
	# rather than small — and it is the kind of edit that looks like tidying.
	# docs/adr/0059.
	if grep -qE '^\s*font-size: 13\.5px;' "$STYLE_CSS" && grep -qE '^\s*font-weight: bold;' "$STYLE_CSS"; then
		ok "the bar is 13.5px and bold, the pair 3270 needs at this size"
	else
		bad "style-solid.css changed the bar's size or weight without the other" \
			"3270 is bitmap-derived; at 13.5px its regular is thin and uneven, and the two settings are one decision"
	fi

	# TWO FACES, BY ROLE, and the roles are asserted rather than remembered.
	# 3270 is the bar's display face; Hack is body text — the rofi menus, GTK,
	# the terminal and the editor. docs/adr/0058 collapsed them into one face and
	# docs/adr/0059 split them again, so this is the assertion that keeps a
	# well-meant "unify the fonts" from landing a third time.
	#
	# Declarations, not prose: the comment above each stack says why the face is
	# what it is, and a check that cannot tell a reason from a setting makes the
	# reason unwritable.
	facebad=""
	grep -qE '^\s*font: "Hack Nerd Font 11";' "$SRC/dotfiles/rofi/config.rasi" ||
		facebad+="  dotfiles/rofi/config.rasi is not Hack"$'\n'
	grep -qE 'font-family: "Hack Nerd Font", monospace;' "$SRC/modules/home/programs.nix" ||
		facebad+="  wlogout in modules/home/programs.nix is not Hack"$'\n'
	grep -qE 'font-sans = "Symbols Nerd Font Mono, 3270 Nerd Font";' "$SRC/modules/home/wayle.nix" ||
		facebad+="  modules/home/wayle.nix does not mirror the bar's stack"$'\n'
	if [[ -n $facebad ]]; then
		bad "a surface is on the wrong face" \
			"3270 is the bar's, Hack is body text; an undeclared family is a silent fallback:"$'\n'"$facebad"
	else
		ok "3270 for the bar and wayle, Hack for the menus and wlogout"
	fi
fi

# A module whose exec is missing or non-executable renders as an empty module,
# which reads as the module being absent from the bar.
missing=""
refs=0
for cfg in "${CONFIGS[@]}"; do
	while read -r ref; do
		[[ -z $ref ]] && continue
		refs=$((refs + 1))
		script="$SRC/dotfiles/mango/scripts/${ref#*mango/scripts/}"
		[[ -x $script ]] || missing+="  $(basename "$cfg"): $ref"$'\n'
	done < <(jq -r '..|strings' "$cfg" | grep -o '[~]/\.config/mango/scripts/[^ "]*' | sort -u)
done

if [[ $refs -eq 0 ]]; then
	bad "no script references found in the generated configs — the scan is broken"
elif [[ -z $missing ]]; then
	ok "all $refs referenced scripts exist and are executable"
else
	bad "waybar references a missing or non-executable script" "$(echo "$missing" | sort -u | head -4)"
fi

printf '\nBattery\n'

# `full-at` rescales the reading as shown = real / full-at * 100, so the bar
# disagrees with fastfetch, upower and sysfs by a constant factor. Dropped on
# 2026-08-09 because that mismatch masked a frozen module twice. Reintroducing
# it is silent, hence the assertion.
checked=0
rescaled=""
for cfg in "${CONFIGS[@]}"; do
	jq -e 'has("battery")' "$cfg" >/dev/null || continue
	checked=$((checked + 1))
	full=$(jq -r '.battery["full-at"] // empty' "$cfg")
	[[ -z $full ]] || rescaled+="  $(basename "$cfg"): full-at=$full"$'\n'
done

if [[ $checked -eq 0 ]]; then
	bad "no generated config carries a battery module — the scan is broken"
elif [[ -z $rescaled ]]; then
	ok "battery shows the raw percentage in all $checked configs (no full-at)"
else
	bad "generated waybar config rescales the battery reading" "$rescaled"
fi

# upower is what acts on a low battery; waybar only recolours. The two drifted —
# waybar warned at 30/15 while upower acted at 20/5 — so the colour change marked
# nothing in particular. Read from the built /etc, not from the Nix.
#
# `l20` and `l0` are the rungs of the icon ladder that also carry the warning
# and critical colours — the names `warning` and `critical` are gone, because a
# battery module gets ONE state class and the ladder needs all of them
# (docs/adr/0052). The pairing is the point: an icon rung and a colour threshold
# that could move independently are two facts to keep in step, and this is one.
UPOWER_CONF="$SYS/etc/UPower/UPower.conf"
low="" crit=""
if [[ -f $UPOWER_CONF ]]; then
	while IFS='=' read -r key value; do
		case $key in
		PercentageLow) low=$value ;;
		PercentageCritical) crit=$value ;;
		esac
	done <"$UPOWER_CONF"
fi

checked=0
drifted=""
for cfg in "${CONFIGS[@]}"; do
	jq -e 'has("battery")' "$cfg" >/dev/null || continue
	warn=$(jq -r '.battery.states.l20 // empty' "$cfg")
	critical=$(jq -r '.battery.states.l0 // empty' "$cfg")
	if [[ -z $warn || -z $critical ]]; then
		drifted+="  $(basename "$cfg"): battery module has no states"$'\n'
		continue
	fi
	checked=$((checked + 1))
	[[ $warn == "$low" && $critical == "$crit" ]] ||
		drifted+="  $(basename "$cfg"): waybar $warn/$critical, upower $low/$crit"$'\n'
done

if [[ -z $low || -z $crit ]]; then
	bad "no PercentageLow/Critical in the built UPower.conf — the scan is broken" "$UPOWER_CONF"
elif [[ $checked -eq 0 ]]; then
	bad "no generated config carries battery states — the scan is broken"
elif [[ -z $drifted ]]; then
	ok "waybar's battery states match upower's $low/$crit in all $checked configs"
else
	bad "waybar's battery states have drifted from upower" "$drifted"
fi

# Night light is killed from outside this repo: noctalia runs `pkill -x wlsunset`
# in `Component.onCompleted`, unconditionally, on every start. systemd counts a
# Sigterm as a clean exit, so `Restart=on-failure` did not bring it back and one
# entry into noctalia mode ended night light for the session, silently.
# docs/gotchas.md → night light.
NIGHT_UNIT="$GEN/home-files/.config/systemd/user/wlsunset.service"
if [[ ! -f $NIGHT_UNIT ]]; then
	bad "no generated wlsunset.service — the scan is broken" "$NIGHT_UNIT"
elif ! grep -qx 'Restart=always' "$NIGHT_UNIT"; then
	bad "wlsunset is not Restart=always — an outside SIGTERM ends night light for the session" \
		"$(grep -m1 '^Restart=' "$NIGHT_UNIT" || echo 'no Restart= at all')"
else
	ok "wlsunset restarts even when something else SIGTERMs it"
fi

# `mmsg watch` is a long-lived stream, and the script running it is killed from
# outside — `pkill waybar` on every mode switch and every waybar-reload. The
# watcher does not go with it: four orphans were alive at once on 2026-08-16, up
# to fourteen hours old, each holding an IPC socket to a compositor nothing was
# reading from. A trap that reaps this script's own children is the fix, and its
# absence is invisible until you count processes.
mapfile -t WATCHERS < <(grep -rl 'mmsg watch' "$SRC/dotfiles" 2>/dev/null | sort)
if [[ ${#WATCHERS[@]} -eq 0 ]]; then
	bad "no script runs 'mmsg watch' — the scan is broken, not the repo"
else
	watcherr=""
	for w in "${WATCHERS[@]}"; do
		grep -q 'pkill -P \$\$' "$w" ||
			watcherr+="  ${w#"$SRC"/} streams mmsg watch but never reaps it"$'\n'
	done
	if [[ -z $watcherr ]]; then
		ok "all ${#WATCHERS[@]} 'mmsg watch' streams are reaped when their script exits"
	else
		bad "an mmsg watch stream outlives its script" "$watcherr"
	fi
fi

printf '\nIdle\n'

# swayidle carried no timeouts at all until 2026-08-11 while the docs described
# an idle ladder, so this is the floor for the reverse: with none, nothing dims,
# locks or sleeps on idle and an open lid costs ~7 W until the 3% hibernate.
IDLE_UNIT="$GEN/home-files/.config/systemd/user/swayidle.service"
if [[ ! -f $IDLE_UNIT ]]; then
	bad "no generated swayidle.service — the scan is broken" "$IDLE_UNIT"
else
	# -o then `wc -l`, not `grep -c`: the whole ExecStart is one line, so `grep -c`
	# reports 1 however many timeouts are on it, and a ladder cut to a single
	# timeout would still pass.
	timeouts=$(grep -o ' timeout ' "$IDLE_UNIT" | wc -l)
	if [[ $timeouts -eq 0 ]]; then
		bad "swayidle carries no idle timeouts — nothing dims, locks or sleeps on idle"
	else
		ok "swayidle carries $timeouts idle timeouts"
	fi

	# `&&` skips the blank whenever the lock exits non-zero, which is every time
	# the screen was already locked by hand — only one client may hold an
	# ext-session-lock-v1 lock. docs/gotchas.md → swaylock.
	#
	# `lockscreen`, not `swaylock`: the wrapper is what swayidle calls now
	# (docs/adr/0018). Matching the old name here would pass by finding nothing.
	if ! grep -q 'wlopm' "$IDLE_UNIT"; then
		bad "swayidle never calls wlopm — the panel stays lit through the idle blank"
	elif ! grep -q 'lockscreen' "$IDLE_UNIT"; then
		bad "swayidle does not lock via lockscreen — the idle lock has lost its background pool"
	elif grep -qE 'lockscreen[^;]*&&[^;]*wlopm' "$IDLE_UNIT"; then
		bad "swayidle chains lockscreen to wlopm with && — a manual lock leaves the panel lit"
	else
		ok "swayidle's idle blank is not gated on the lock's exit status"
	fi
fi

# The background pool is invisible when it is missing: lockscreen falls back to
# the solid colour deliberately, so an empty pool looks exactly like the config
# before this existed. Assert the floor — the pool the wrapper actually points
# at, not merely that some pool was built.
if [[ ! -x $LOCKBIN ]]; then
	bad "no lockscreen on PATH — the mango binds call it by name and would exit 127" "$LOCKBIN"
else
	pool_dir=$(grep -oE '/nix/store/[^ )"]*/share/lock-backgrounds' "$LOCKBIN" | head -1)
	if [[ -z $pool_dir ]]; then
		bad "lockscreen references no background pool" "$LOCKBIN"
	else
		members=$(find "$pool_dir" -name '*.png' 2>/dev/null | wc -l)
		if [[ $members -eq 0 ]]; then
			bad "lockscreen's background pool is empty — every lock falls back to flat #282828" "$pool_dir"
		else
			ok "lockscreen's background pool carries $members members"
		fi
	fi
fi

# The only in-session way to hold the ladder off: swayidle takes its idle signal
# from the compositor, so `systemd-inhibit --what=idle` does not reach it and a
# long build on battery hits the 30-minute suspend regardless. Dropping the
# module from every layout is silent — the bar is just one icon shorter.
inhibitor=0
for cfg in "${CONFIGS[@]}"; do
	jq -e '[.["modules-right"][] | sub("#.*$"; "")] | index("custom/idle-inhibitor")' "$cfg" >/dev/null 2>&1 &&
		inhibitor=$((inhibitor + 1))
done
if [[ $inhibitor -eq 0 ]]; then
	bad "no generated waybar config carries custom/idle-inhibitor — nothing can hold the idle ladder off"
else
	ok "custom/idle-inhibitor is on the bar in $inhibitor of ${#CONFIGS[@]} layouts"
fi

# ...and the module only reports the inhibitor now; the unit is what holds it.
# Two ways that pairing breaks silently, so both are asserted. An [Install]
# section would arm the inhibitor at every login, which is the failure the
# whole thing exists to prevent and looks from the bar exactly like someone
# having pressed the key. docs/adr/0031.
INHIBIT_UNIT="$GEN/home-files/.config/systemd/user/wlinhibit.service"
if [[ ! -f $INHIBIT_UNIT ]]; then
	bad "no generated wlinhibit.service — the keep-awake key and the bar toggle both do nothing" "$INHIBIT_UNIT"
elif grep -q '^WantedBy=' "$INHIBIT_UNIT"; then
	bad "wlinhibit.service is wanted by a target — the machine would come up already inhibited" \
		"$(grep -m1 '^WantedBy=' "$INHIBIT_UNIT")"
else
	ok "wlinhibit.service exists and starts only on request"
fi

# ...and apply_mode hands it over on the way into noctalia, which holds its own
# inhibitor over quickshell with no getter to read it back. Dropping this line
# is invisible: both inhibitors are real, so the machine still stays awake — it
# is the other shell's indicator that starts lying. docs/adr/0031.
LIBSH="$MANGO/scripts/lib.sh"
if ! grep -q 'idle-inhibit\.sh' "$LIBSH"; then
	bad "apply_mode does not hand the idle inhibitor over — entering noctalia would leave wlinhibit holding behind its indicator" \
		"$LIBSH"
elif ! grep -q 'idle-inhibit\.sh" off' "$LIBSH"; then
	bad "lib.sh names idle-inhibit.sh but never stops it — the handover tests a state it does not act on" "$LIBSH"
else
	ok "apply_mode releases the inhibitor entering noctalia"
fi

printf '\nFonts\n'

# A font family that resolves to nothing renders as a silent fallback: bold text
# just looks normal, a bar glyph just looks like a box. It has bitten twice —
# "3270 Nerd Font" undeclared, then `_0xproto` (family "0xProto") standing in for
# `nerd-fonts._0xproto` (family "0xProto Nerd Font Mono"). fc-match cannot check
# this: it matches on family alone, so a "<family> Bold" spelling always looks
# like a fallback. Match family+style out of fc-scan instead.
mapfile -t FONT_DIRS < <(
	grep -rhoE '<dir>[^<]+</dir>' "$SYS/etc/fonts/conf.d/"*.conf "$SYS/etc/fonts/fonts.conf" 2>/dev/null |
		sed -E 's#</?dir>##g' | grep '^/nix/store' | sort -u
)
if [[ ${#FONT_DIRS[@]} -lt 5 ]]; then
	bad "only ${#FONT_DIRS[@]} font dirs found in the system closure — the scan is broken, not the config"
else
	FAMILIES=$(fc-scan --format '%{family}|%{style}\n' "${FONT_DIRS[@]}" 2>/dev/null | sort -u)
	fam_count=$(printf '%s\n' "$FAMILIES" | grep -c .)
	if [[ $fam_count -lt 100 ]]; then
		bad "fc-scan returned only $fam_count families — the scan is broken, not the config"
	else
		ok "$fam_count font family/style pairs across ${#FONT_DIRS[@]} dirs"

		# Every family name the terminals and the bar ask for by name.
		KITTY="$GEN/home-files/.config/kitty/kitty.conf"
		FOOT="$GEN/home-files/.config/foot/foot.ini"
		wanted=$(
			# font_family/bold_font/italic_font/bold_italic_font: rest of line.
			sed -nE 's/^(font_family|bold_font|italic_font|bold_italic_font)[[:space:]]+(.*)$/\2/p' "$KITTY" 2>/dev/null
			# symbol_map: codepoint ranges first, family last.
			sed -nE 's/^symbol_map[[:space:]]+[^[:space:]]+[[:space:]]+(.*)$/\1/p' "$KITTY" 2>/dev/null
			# foot: font=<family>:size=N
			sed -nE 's/^font=([^:]+).*$/\1/p' "$FOOT" 2>/dev/null
			# waybar CSS font-family, comma-separated, quoted or bare.
			grep -rhoE 'font-family:[^;]+;' "$WAYBAR_DIR"/*.css 2>/dev/null |
				sed -E 's/font-family://; s/;//' | tr ',' '\n' | sed -E 's/^[[:space:]]*"?//; s/"?[[:space:]]*$//'
			# rofi: `font: "<family> <size>";`. Every menu entry carries Font
			# Awesome glyphs in the string itself, so a fallback here is a
			# window full of boxes rather than a slightly different typeface.
			sed -nE 's/^[[:space:]]*font:[[:space:]]*"(.*) [0-9]+"[[:space:]]*;.*/\1/p' \
				"$SRC/dotfiles/rofi/config.rasi" 2>/dev/null
			# wayle: `font-sans`/`font-mono` under [general], one per layout.
			# It falls back to its own default without a word, so a name this
			# machine lacks looks merely unstyled — `Inter` was written here and
			# is not installed. docs/adr/0051.
			sed -nE 's/^font-(sans|mono) = "(.*)"$/\2/p' \
				"$WAYLE_DIR"/layouts/*.toml 2>/dev/null
		)
		# A config may name a stack — wayle's `font-sans` is
		# "Symbols Nerd Font Mono, 3270 Nerd Font", the same two-family fallback
		# style-solid.css uses, because 3270's advance is too narrow for the
		# glyphs it patches in. Split it, or the whole stack is looked up as one
		# family name and reported missing.
		wanted=$(printf '%s\n' "$wanted" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
		wanted=$(printf '%s\n' "$wanted" | grep -vE '^(auto|monospace|sans-serif|serif|inherit)?$' | sort -u)

		want_count=$(printf '%s\n' "$wanted" | grep -c .)
		if [[ $want_count -lt 3 ]]; then
			bad "only $want_count font names extracted from the configs — the scan is broken, not the config"
		else
			missing=()
			while IFS= read -r name; do
				[[ -z $name ]] && continue
				# Either a bare family, or "<family> <style>".
				#
				# `%{family}` is a comma-separated alias list — JetBrainsMono
				# scans as "JetBrainsMono Nerd Font,JetBrainsMono NF,…" and any
				# of those resolve. Matching the whole field reported a font
				# that is installed as missing, which is a false positive, and a
				# check that cries wolf is one nobody reads. Split on commas and
				# try each alias.
				if ! printf '%s\n' "$FAMILIES" | awk -F'|' -v n="$name" '
					{
						c = split($1, fams, ",")
						for (i = 1; i <= c; i++) {
							gsub(/^[ \t]+|[ \t]+$/, "", fams[i])
							if (fams[i] == n || fams[i] " " $2 == n) { found = 1 }
						}
					}
					END { exit !found }'; then
					missing+=("$name")
				fi
			done <<<"$wanted"

			if [[ ${#missing[@]} -gt 0 ]]; then
				bad "font names that resolve to nothing (silent fallback)" "${missing[*]}"
			else
				ok "all $want_count font names referenced by kitty, foot, rofi and wayle resolve"
			fi
		fi
	fi
fi

printf '\nShell completions\n'

# `programs.zsh.enableCompletion = false` is deliberate (it drops a duplicate
# compinit) but it also gates `pathsToLink`, so it silently unlinks share/zsh
# from both profiles. A missing fpath entry is not an error — completion keeps
# working on zsh's bundled functions, so nothing reports the loss. Assert a
# floor on each profile. docs/gotchas.md → nixpkgs and NixOS.
for spec in "home:$GEN/home-path/share/zsh/site-functions:100" \
	"system:$SYS/sw/share/zsh/site-functions:20"; do
	IFS=: read -r label dir floor <<<"$spec"

	if [[ ! -d $dir ]]; then
		bad "$label profile has no share/zsh/site-functions" \
			"pathsToLink is missing /share/zsh — every package completion is gone"
		continue
	fi

	count=$(find "$dir" -maxdepth 1 -name '_*' -printf . | wc -c)
	if [[ $count -lt $floor ]]; then
		bad "$label profile ships only $count completions (floor $floor)" "$dir"
	else
		ok "$label profile ships $count completions"
	fi
done

# The two that motivated the floor: both came from the NixOS module and both
# vanished with it.
for fn in _nix-shell _nixos-option; do
	if [[ -e "$GEN/home-path/share/zsh/site-functions/$fn" ]]; then
		ok "$fn is in fpath"
	else
		bad "$fn missing — nix-zsh-completions is not in home.packages"
	fi
done

# --- display firmware -------------------------------------------------------
# linux-firmware 20260910's yellow_carp_dmcub fails to load and breaks the panel,
# with the build still succeeding. docs/gotchas.md → Power.
FW="$SYS/firmware/amdgpu"
dmcub=$(readlink -f "$FW/yellow_carp_dmcub.bin.zst" 2>/dev/null)
lfw=$(readlink -f "$FW/yellow_carp_pfp.bin.zst" 2>/dev/null | grep -oE 'linux-firmware-[0-9]+')
if [[ -z $dmcub || -z $lfw ]]; then
	bad "yellow_carp firmware not found in the system firmware — the scan is broken, not the repo" "$FW"
elif [[ $dmcub != *-yellow-carp-dmcub-* ]]; then
	bad "yellow_carp_dmcub comes from ${dmcub#/nix/store/*-}, not the 20260810 pin"
elif [[ $lfw != linux-firmware-20260910 ]]; then
	ok "yellow_carp_dmcub is pinned; nixpkgs now ships $lfw — retest without the pin"
else
	ok "yellow_carp_dmcub is pinned over $lfw"
fi

# --- signal traps -----------------------------------------------------------
# A handler trapped on a terminating signal replaces that signal's default
# action — bash runs it and then resumes. Two mango watchers written that way
# ignored logind's sigterm, kept looping, and held the session scope open until
# systemd SIGKILLed them 90 s later, on every shutdown and reboot. The shape is
# one line from the correct one and reads as the more careful of the two, so it
# gets a check rather than a convention. docs/gotchas.md → Scripts.
printf '\nSignal traps\n'

# The body of function `$2` in file `$1`, by brace depth — the handlers here are
# one-liners, so a `sed` range ending at `^}` would run past them into the next
# function and find its `exit` instead.
fn_body() {
	awk -v fn="$2" '
		!open && $0 ~ "^[[:space:]]*(function[[:space:]]+)?" fn "[[:space:]]*\\(\\)" { open = 1 }
		open {
			print
			depth += gsub(/\{/, "{") - gsub(/\}/, "}")
			if (depth > 0) seen = 1
			if (seen && depth <= 0) exit
		}
	' "$1"
}

traps_seen=0
traps_bad=()
for f in "${SCRIPTS[@]}"; do
	# Read once rather than redirecting the loop: `fn_body` below opens the same
	# file, and a loop whose stdin is that file is one refactor away from having
	# its input consumed out from under it (SC2094).
	mapfile -t lines <"$f"
	for line in "${lines[@]}"; do
		# `trap action sigspec...`. `trap -p` and `trap - sig` reset rather than
		# handle, so they carry no obligation to exit.
		[[ $line =~ ^[[:space:]]*trap[[:space:]]+(\'[^\']*\'|\"[^\"]*\"|[^[:space:]]+)[[:space:]]+([A-Za-z0-9[:space:]]+)$ ]] || continue
		action=${BASH_REMATCH[1]}
		signals=${BASH_REMATCH[2]}

		# Only signals whose default action terminates. Exit is the right home
		# for cleanup and must not exit. The `[A-Za-z0-9…]` above also drops the
		# `RTMIN+8` form on purpose: a real-time signal here is waybar asking a
		# module to refresh, where carrying on is the point.
		[[ $signals == *TERM* || $signals == *INT* || $signals == *HUP* || $signals == *QUIT* || $signals == *PIPE* ]] || continue
		traps_seen=$((traps_seen + 1))

		action=${action#[\'\"]}
		action=${action%[\'\"]}
		[[ $action == - || -z $action ]] && continue
		[[ $action == *exit* ]] && continue

		# A bare function name — resolve it and look for `exit` in the body.
		if [[ $action =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] &&
			fn_body "$f" "$action" | grep -qw exit; then
			continue
		fi

		traps_bad+=("${f#"$SRC"/}: ${line#"${line%%[![:space:]]*}"}")
	done
done

# The scan finding nothing is the failure mode it exists to catch. The floor
# guards the regex, not the population, and above 0 so a regex that stops
# matching cannot pass by finding nothing.
#
# 1, not 2, since scratch-watch.sh went (docs/adr/0047): the population is now
# waybar/window-title.sh alone, so retiring waybar takes this check's last
# subject with it. Re-base on the next long-running script rather than deleting
# the scan — the failure it catches cost 90 s on every shutdown.
if [[ $traps_seen -lt 1 ]]; then
	bad "only $traps_seen terminating-signal traps found — the scan is broken, not the repo"
elif [[ ${#traps_bad[@]} -gt 0 ]]; then
	bad "${#traps_bad[@]} signal trap(s) never exit, so the signal no longer kills the script" \
		"$(printf '%s; ' "${traps_bad[@]}")"
else
	ok "$traps_seen terminating-signal traps all exit"
fi

printf '\nPackage ownership\n'

# One owner per package (modules/home/packages.nix header). Asserted as
# Divergence, not duplication: 20 names are in both lists and 19 resolve to the
# same store path, because environment.systemPackages is mostly NixOS module
# defaults rather than this repo's doing. Flagging all 20 would be noise.
# Flagging the one whose paths differ is useful: there the binary you get
# depends on PATH order.
#
# <name>|<why> — a divergence that is real, understood and not ours to fix.
# Same shape statix.toml uses. Keep this list short and give every entry a
# reason.
PKG_EXCEPTIONS=(
	# The system carries bind's `host` output as a NixOS default; packages.nix
	# declares `dnsutils` for `dig`. Different outputs of one derivation, so
	# which `host` you get is PATH order — real, but upstream's arrangement.
	"bind|system has the host output as a NixOS default, home declares dnsutils for dig"
)

pkg_both=0
pkg_bad=""
if [[ ! -s $PACKAGES ]]; then
	bad "no package map — the scan is broken, not the repo" "$PACKAGES"
else
	while IFS=$'\t' read -r name spath hpath; do
		[[ -z $name ]] && continue
		pkg_both=$((pkg_both + 1))
		[[ $spath == "$hpath" ]] && continue
		# Match on the name with its version stripped, so a version bump does
		# not silently retire an exception.
		base=${name%-[0-9]*}
		keep=""
		for e in "${PKG_EXCEPTIONS[@]}"; do
			[[ $base == "${e%%|*}" ]] && keep=1 && break
		done
		[[ -n $keep ]] && continue
		pkg_bad+="  $name"$'\n    system: '"$spath"$'\n    home:   '"$hpath"$'\n'
	done < <(
		jq -r '
			.system as $s | .home as $h
			| $s | keys_unsorted[] as $n
			| select($h | has($n))
			| [ $n, $s[$n], $h[$n] ] | @tsv
		' "$PACKAGES"
	)

	# The floor. The intersection is 21 today and is mostly NixOS defaults, so it
	# does not go to zero on its own — if it does, the jq stopped matching.
	if [[ $pkg_both -lt 10 ]]; then
		bad "only $pkg_both packages in both lists — the scan is broken, not the repo"
	elif [[ -n $pkg_bad ]]; then
		bad "a package is declared in two places that resolve DIFFERENTLY — which binary you get is PATH order" "$pkg_bad"
	else
		ok "$pkg_both packages sit in both lists; all resolve to one store path, ${#PKG_EXCEPTIONS[@]} recorded exception aside"
	fi
fi

# Every scan above has a floor; this file had none, so deleting a whole section
# printed a smaller number and exited green. A floor, not a ratchet: adding
# assertions stays a one-line change, and this number is raised in the commit
# that adds them.
# 117 on 2026-08-20. docs/adr/0039.
ASSERTION_FLOOR=117

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"

run=$((PASS + FAIL))
if [[ $run -lt $ASSERTION_FLOOR ]]; then
	printf '  ✗ only %d assertions ran, floor is %d — a section stopped running\n' \
		"$run" "$ASSERTION_FLOOR"
	exit 1
fi

[[ $FAIL -eq 0 ]]
