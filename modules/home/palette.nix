# The one palette — whichever scheme `./scheme.nix` names.
#
# This file used to be the palette. It is now the dispatcher, and its interface
# is deliberately unchanged where it can be: it still evaluates to a flat `rec`
# attrset of bare hex, so all twelve colour consumers and `pkgs/default.nix`
# read it exactly as before.
#
# THE COLOUR KEY NAMES ARE GRUVBOX'S, and every theme file must supply all of
# them. They outlived the scheme that named them because twelve consumers and
# `checks/static.sh` address colours by them; renaming is a separate change from
# recolouring. Where a name no longer describes its value — Catppuccin's
# `magenta` is its *pink*, `cyan` its *teal*; Nord's `magenta` slot holds its
# Purple — the theme file says so in a comment.
#
# `rec` in each theme file matters: the semantic roles are defined in terms of
# the canonical ones, so a **missing key is an eval error** rather than a
# silently-default colour.
#
# ── What a theme file declares ───────────────────────────────────────────────
#
#   contrastFloor   the ratio every role this machine draws text with clears
#   ansiFloor       the ratio the sixteen terminal slots clear — a separate
#                   number because on gruvbox they are 2.69:1 by upstream's
#                   design, and one combined floor would drag the first down to
#                   meet it (docs/adr/0032)
#   the colours     canonical ramp, semantic roles, terminal aliases, `muted`
#   packages        the GTK, Kvantum and cursor artefacts, which name the
#                   overlay derivations that build them from the colours above,
#                   plus the icon set, which is still a name (docs/adr/0041)
#   apps            nvim, which holds a scheme's name rather than its
#                   colours
#
# `packages` and `apps` were the half the palette could not reach — rendered SVG
# widget art, cursor bitmaps, compiled SCSS, and names other programs resolve
# internally. Most of that turned out to be reachable after all: the GTK theme,
# the Kvantum theme and the cursor set are built from these colours, and yazi's
# flavour and Zed's theme are written from them and left this file entirely
# (docs/adr/0041). What remains here is one artefact nobody can generate — the
# icon set, because upstreams parameterise the folder hue and nothing else, and
# app icons are brand colours — and two names.
#
# `native = false` on a `packages` entry marks a stand-in: an artefact that does
# not follow this scheme at all, only a neutral that does not fight it.
# `heartbox` is the first scheme to use one, for its icons, and
# `checks/static.sh` reports every stand-in on every run rather than passing
# over it.
#
# ── Adding a scheme ─────────────────────────────────────────────────────────
#
# Copy a file in `./themes/`, replace the values, point `scheme.nix` at it, and
# run `nix flake check` — which asserts every artefact it names resolves and
# that every generated one carries these colours, so a half-applied scheme
# cannot land quietly. A scheme no longer has to exist as a package anywhere:
# `heartbox.nix` is the worked example, being a colour scheme and nothing else.
# `docs/theme-migration.md` is the runbook.
import ./themes/${import ./scheme.nix}.nix
