# 0041 — Artefacts are generated from the palette, not named

**Status:** Accepted (2026-08-20). Implemented the same day. Two artefacts
were added to the scope after it was written: **yazi's flavour and Zed's
theme**. Both met this record's own test — their colour is data in their
source — and both were blocking `heartbox`.

Amends [0032](0032-the-theme-file-owns-its-artefacts.md) and
0034, which both record the
artefact half of a scheme as permanently unreachable. It is not. This record
says what is reachable, what stays named, and what the new failure class is.

## Context

[0032](0032-the-theme-file-owns-its-artefacts.md) split a scheme in two: the
palette reaches colour, and a theme file separately *names* the artefacts the
palette cannot reach — GTK and Kvantum widget art, icons, cursors, the yazi
flavor, the nvim plugin, the Zed theme.
0034 hardened that into a
scope line — "widget art, icons, cursors, plugins: no, permanently" — and
`CLAUDE.md` records the consequence as a constraint on the repo itself: noctalia
ships ten colour schemes, nixpkgs fully serves three, *so those are the three
here*.

That reasoning has one hole, and it is load-bearing: **"it is built" is not the
same as "its colour is baked in".** Three of the six artefacts hold their colour
as *data* in their source, and a build that substitutes that data is an ordinary
derivation. Measured 2026-08-20 against the pinned nixpkgs, not read off
documentation:

| Artefact | Where its colour actually lives |
|---|---|
| **Cursor** | `catppuccin-cursors` builds 64 themes from **one** SVG set of 68 files, each carrying three sentinel hexes — `FF0000` inner, `00FF00` border, `0000FF` special — replaced per flavour, then rendered and assembled. The art is Volantes, from KDE Breeze. |
| **GTK** | Colloid and Orchis compile from SCSS whose colours are named variables; `sassc` is already the nixpkgs build step. Colloid ships `nord`, `gruvbox`, `catppuccin` and `dracula` tweaks — upstream already treats the palette as an argument. |
| **Kvantum** | A theme is an INI `.kvconfig` with explicit colour keys plus near-monochrome `.svg` frame art. The keys are generatable; the art is reusable across palettes. |
| **Icons** | Thousands of SVGs, of which upstreams parameterise only the folder and accent hue. App icons are brand-coloured and must not follow a palette. |

So the recorded constraint was a property of the chosen implementation — name a
prebuilt nixpkgs package — and got generalised into a law about the problem.
`native = false` exists to mark a stand-in, and nothing uses one, because the
scheme set was selected to avoid ever needing one.

## Decision

**Three artefacts move from named to generated: cursor, Kvantum, GTK.** Each is
built from an upstream template set with this repo's palette substituted in, in
`pkgs/default.nix`, alongside the lock-background ramp that already works this
way.

**The scope line is redrawn, and it is sharper than the old one.** An artefact
may be generated when **its colour is data in its source** — a sentinel hex, an
SCSS variable, an INI key. Where colour is inseparable from artwork, or where
the artwork is not ours to recolour, it stays named. That test is checkable;
"it is built" was not.

**Icons stay named, from a neutral pack, and the theme file says so.** Only the
folder and accent hue are parameterised upstream, and app icons are brand
colours that should not follow a scheme. A recoloured folder set is not a
scheme's icon theme, and pretending otherwise would be the drift this repo
exists to stop. `native = false` finally gets its intended use.

**nvim stays named.** [0027](0027-one-editor-nvim.md) settled the editor, and a
hand-tuned scheme's value is concentrated in exactly the treesitter and LSP
groups a generic sixteen-colour mapping flattens. `apps.nvim.palette` already
drives a plugin's own override hook, which is how `heartbox` gets a real nvim
theme without one existing.

**Zed did not stay named, against what this record first said.** It was left
out on the reasoning above, and that was wrong: Zed's theme is JSON, its key
set is published, and leaving it named meant an artefact that could never
follow a new scheme. Generating it also closed a hole this repo had written
down as unclosable — the theme came from Zed's extension *registry*, and
`modules/home/programs.nix` recorded it as "the one pair no check here can
gate". A theme in the generation is gateable.

**`contrastFloor` and `ansiFloor` are demoted from a standard to a tripwire.**
[0032](0032-the-theme-file-owns-its-artefacts.md) presents them as measurement,
and they are — but each theme declares whatever it measured, so the check
**cannot fail a new theme**. Its real and only function is catching a regression
*within* a theme across edits. That is worth keeping and worth one sentence, not
the section it currently has. It does not gate which schemes may be adopted.

## Consequences

- **A new silent-failure class, of exactly the usual kind.** A `sed`
  that stops matching produces a valid, complete, unrecoloured artefact. The
  build succeeds, the theme resolves, the check that asserts the directory
  exists passes, and the cursor is still Catppuccin mauve. Every generator
  therefore asserts **absence of the sentinel** and a **floor on the count of
  files it changed** — 68 for cursors — and pins upstream's internal names with
  `--replace-fail`, as the noctalia patch already does
  (0025).
- **"It compiled" is further from "it looks right" than anywhere else in this
  repo.** Substitution is checkable by grep; a palette mapped badly onto forty
  GTK roles is legible only to a person looking at a window. This is the real
  cost, it is not fully mitigable, and the mitigation that exists is to
  **develop each generator against `gruvbox`** — the scheme currently on screen,
  where wrong is distinguishable from merely unfamiliar.
- **The gate gets slower and the closure larger.** Cached nixpkgs binaries are
  replaced by local `inkscape`, `sassc` and `clickgen` builds, per scheme in
  service. `nix flake check` builds both closures, so this is paid on every run.
- **The dependency moves from an upstream's output to its internals.** SCSS
  variable names, sentinel hexes and install-script flags are now load-bearing.
  `--replace-fail` turns a rename into a build error rather than a silent
  no-op, which is the whole reason it is mandatory here.
- **The scheme set stops being constrained by nixpkgs.** `CLAUDE.md`'s "those
  are the three here" no longer holds, and any palette with a full sixteen-slot
  terminal set becomes adoptable. That is the point of the change.
- **Full consistency remains asymptotic, and this record refuses to imply
  otherwise.** Firefox's icon stays orange. Electron apps, web content and
  anything carrying its own theming stay off-palette. The honest ceiling is
  everything that draws chrome from a config file, plus recoloured cursors and
  widget art.
- **This is dark-only, and that is what makes it tractable.** Widget art embeds
  shadows and gradients tuned to a base lightness; recolouring across the
  light/dark line does not survive a string replace. The machine runs dark
  (`gtk.colorScheme = "dark"`), so the question does not arise — and a future
  light scheme would reopen it.

## Sequencing

Cheapest and most verifiable first — **cursor, Kvantum, GTK** — each landing
independently with its own assertions, developed against `gruvbox`. The scheme change that
motivated this (`heartbox`) is deliberately the **last** step, not the first:
flipping it earlier would mean judging three new generators against a palette
nobody has seen on this machine.
