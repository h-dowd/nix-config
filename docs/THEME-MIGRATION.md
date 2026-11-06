# Migrating the theme

How to change what this machine looks like, given the arrangement
`docs/adr/0028` put in place. It is a runbook because the work splits into two
halves that fail in different ways, and the second half is the one that gets
forgotten.

Companion reading: `docs/SYSTEM.md` §6 (where config lives),
`docs/gotchas.md` → Theming (what has already bitten us), `docs/adr/0028` (why
it is arranged this way).

---

## 0. Decide which kind of change this is

The two cases need different amounts of work. Conflating them leaves a
migration half-done, which looks deliberate.

> Worked example: this repo went gruvbox → Catppuccin Mocha on 2026-08-18, which
> is a **new scheme** — every row in the right-hand column below actually
> happened.

> **Switching between schemes that already exist is one line.** Edit
> `modules/home/scheme.nix`, `nix flake check`, `rebuild`, reload per §5. Five
> schemes ship: `heartbox`, `mocha`, `mocha-high-contrast`, `gruvbox`, `nord`.
> Everything below is about bringing a *new* one in — which since
> `docs/adr/0041` is mostly writing one file, because the artefacts are built
> from it rather than found.

| | **Recolour** | **New scheme** |
|---|---|---|
| Example | mocha → macchiato; a different accent | gruvbox → nord, everforest |
| The theme file | edit values | a new file in `modules/home/themes/` |
| The theme file's `packages` block | usually unchanged | **all four entries renamed** (§2) |
| nvim | keep the plugin, overrides carry the change | **swap the plugin** — see §3 |
| ncspot's `muted` set | re-derive — check whether a formula fits (§1) | re-derive — check whether a formula fits (§1) |
| Realistic effort | one file, one rebuild | one file, plus an icon set |

Since `docs/adr/0032` the packages are declared in the theme file rather than
migrated across six others, and `nix flake check` asserts that every name
resolves. A new scheme is therefore one file, plus whatever nixpkgs does or does
not have. It is no longer the day-long, ungated job it once was.

---

## 1. The palette — one file, twelve consumers

**To switch between schemes that already exist, edit `modules/home/scheme.nix`
— one string — and rebuild.** That is the whole operation; §2 and §3 below are
only for bringing a *new* scheme in.

`modules/home/palette.nix` is a dispatcher over `modules/home/themes/*.nix` and
still evaluates to the same flat attrset it always did, so all twelve
consumers read it unchanged: **kitty, foot, imv, swaylock, waybar, rofi, mango,
nvim, swaync, ncspot, Equibop and the lock-screen background ramp**.

Why a file and not a `local.theme` option: `pkgs/default.nix` builds the lock
ramp and is an **overlay**, so it cannot read `config.*`. An option reaches
eleven consumers and misses the twelfth, which is the one surface nobody looks
at closely. `docs/adr/0030`.

### Where the colours land

One scheme, `scheme.nix`'s, reaches everything. kitty, foot and ncspot take
their colours in `programs.<app>.settings`; rofi's `colors.rasi`, mango's
`universal/colors.conf` and Equibop's `equibop/themes/palette.theme.css` are
generated files (`docs/adr/0061`). Equibop's `enabledThemes` is written by an
activation step, because Equibop rewrites its own `settings.json`.

- **foot reaches new windows only, and ncspot only new processes.** foot 1.27
  has no config re-read; ncspot reads `config.toml` once at startup. kitty takes
  `SIGUSR1`; rofi re-reads on every launch.
- **ncspot's file must be entirely `muted`.** It is the one consumer drawn from
  a single half of the palette, so `checks/static.sh` asserts every hex in it is
  a `muted` value — an accent scan alone cannot see a canonical-ramp colour that
  slipped in.

### Adding a scheme

1. Copy a file in `modules/home/themes/`. Supply **every** key — `rec` makes a
   missing one an eval error, not a default.
2. Declare `contrastFloor` and `ansiFloor` (below).
3. Declare `packages` and `apps` — §2 and §3.
4. Point `scheme.nix` at it and run `nix flake check`.

Contrast is asserted, so an unreadable scheme cannot land quietly the way the
first one did; and every artefact it names must resolve, so a half-packaged one
cannot either.

### Two floors, not one

`contrastFloor` is what **this machine** draws text with — the bar, the menus,
notifications, editor chrome, ncspot's rows. `ansiFloor` is the sixteen terminal
slots, which nothing here draws text in: they are what *other programs* print
with, and they are the scheme's published identity.

They were one number until `docs/adr/0032`. Gruvbox is why they are two — its
normal red is 2.69:1 on its own background, by upstream's design since 2012, and
a single floor would have forced the whole scheme to declare 2.6. `comment`, the
role the check exists for, could then have rotted to the same place unnoticed.

**Declare the number the dimmest role actually measures.** There is no global
minimum under these — there was one, 3.0, and it was removed as an invention: it
arrived with `mocha-high-contrast` out of a request for more readable text and
then read like an external requirement. Nord ships `comment` at 1.69:1, which is
what Nord is. The assertion means only "this theme is as legible as it claims",
which still catches the thing worth catching: an edit that dims a role below the
theme's own declared number.

### Anatomy

It is a `rec` attrset in four colour blocks, plus `packages` and `apps`. `rec`
matters: the semantic roles are defined in terms of the canonical names, so a
**missing key is an eval error**, not a silently-default colour.

| Block | Keys | Who reads it |
|---|---|---|
| Canonical | `bg0`–`bg3`, `fg0`/`fg1`/`fg4`, `mantle`, `mauve`, the 16 ANSI names (`red`…`brWhite`) | the terminals want the full 16; everything else builds from these |
| Semantic roles | `base`, `surface`, `overlay`, `text`, `subtext`, `accent`, `okColor`, `warnColor`, `errColor`, `infoColor` | the bar, the menus, the compositor borders, swaync |
| Terminal aliases | `bg`, `fg`, `selBg` | kitty and foot, which named these first |
| `muted` | `bg`, `fg`, `dim`, `accent`, `ok`, `err`, `surface`, `overlay` | ncspot only |

**Values are bare hex, no leading `#`.** Every consumer spells it differently —
kitty `#rrggbb`, foot bare, GTK CSS `#`, mango `0xrrggbbaa`, swaync decimal
`rgb(r, g, b)` — so the shared form is the one they all build from.

> **Names outside the ramp earn their place by acquiring a consumer.** `mauve`
> is the accent and `mantle` is Equibop's recessed background; both are
> Catppuccin's own names, so they are lookups rather than inventions. Do not add
> the rest of Mocha's 26 to "complete" the set — a colour nothing reads is one
> the next person assumes is live.

### Two constraints that are not obvious

**The lock ramp follows `bg0`'s hue, and the build asserts it.** The background
pool is a ±6 lightness ramp through `bg0`: all three channels move together, so
every tone keeps `bg0`'s exact channel offsets. `pkgs/default.nix` fails the
build if any tone drifts off that hue, with `tones off … the ramp shifts colour,
not just lightness`. Changing `bg0` needs nothing here — the ramp is derived
from it.

> This check read `R = G = B` until 2026-08-18, because gruvbox's `#282828` is
> neutral and the two are the same thing there. Mocha's `#1e1e2e` is not, so it
> was generalised to what it always meant. Wanting to delete it rather than
> generalise it is the signal that the change would make the lock screen the one
> surface wearing a colour the palette never named.

**The `muted` set may or may not have a formula.** It is ncspot's deliberately
desaturated variant. Under gruvbox no function reproduced it (`ebdbb2` →
`c9b890` is not a uniform scale) and the eight values were picked by eye; under
Mocha they are each blended 18% toward `bg0`, which works because Mocha is
even. **Check which case applies** rather than assuming the formula carries
over — if the new scheme's colours vary in saturation the way gruvbox's do, go
back to picking by eye. They live in `palette.nix` rather than next to ncspot
precisely so that this step is visible rather than discovered later.

---

## 2. The artefacts — three built, two written, one named

**This used to be the hard half of a migration and is now the short one.**
Until `docs/adr/0041` a theme file named six upstream artefacts — compiled SCSS,
rendered SVG widget art, cursor bitmaps, a yazi flavour, a Zed theme — and a
scheme with no upstream for one of them could not be adopted. Most of that was a
property of the implementation rather than of the problem.

| What | How | Where |
|---|---|---|
| **GTK theme** | Built — Colloid compiled against a `_color-palette-default.scss` written from the palette | `pkgs/colloid-palette.py` |
| **Kvantum (Qt)** | Built — Kvantum's achromatic `KvantumAlt` art tinted onto the `mantle`→`fg0` ramp, `[GeneralColors]` written from the roles | `pkgs/kvantum-recolour.py` |
| **Cursor** | Built — the Volantes art recoloured through its three sentinel hexes | `paletteCursors` in `pkgs/default.nix` |
| **yazi flavour** | WRITTEN — 220 lines of colour, no upstream involved | `pkgs/yazi-flavor.nix` |
| **Zed theme** | WRITTEN — 135 style keys, 43 syntax keys, at parity with Zed's own | `pkgs/zed-theme.py` |
| **Icon set** | NAMED, and staying that way | `packages.icons` |

The three built ones are named in `packages` as `paletteGtk`, `paletteKvantum`
and `paletteCursors`, with a `name` of `<scheme>-gtk` / `-kvantum` /
`-cursors` — so unlike the names below, those three follow a rule.

**Only the icon set is still a name**, and that is a decision rather than a
gap: upstreams parameterise the folder and accent hue and nothing else, and the
rest of an icon set is app brand colours that must not follow a scheme.

Plus the `apps` block, for settings whose value is a scheme's **name**: `nvim`
(§3).

### Three traps, two still live

> **A name only the toolkit can resolve is a name no check can.** `Adwaita-dark`
> renders fine — GTK3 has it compiled in — and no directory for it exists
> anywhere, so nothing can verify it. If a wanted name passes visually but the
> check cannot find it, that is the check working.

> **`native = false` means a stand-in**, not a broken entry: an artefact that
> does not follow the scheme, only a neutral that does not fight it. Say why in
> the `why` field. The check prints them on every run, because otherwise the
> only way to notice is to look at the screen and already know.
> `heartbox`'s icons are the only one.

> **A name is not guessable from the arguments that build it.** This is still
> true of the icon set, but it is no longer the recurring hazard it was: the
> three built artefacts are named by rule, so there is one name left to read off
> a package instead of five.

### Which schemes are actually available

**Any of them.** The survey that used to stand here is still worth reading for
what it shows about inherited constraints.

Until 2026-08-20 the candidate set was what nixpkgs fully served — Catppuccin,
Gruvbox and Nord. That constraint does not survive: the artefacts are built
rather than found.

`heartbox` is the proof. It exists as a colour scheme in
`noctalia-dev/noctalia-colorschemes` and **nowhere else** — no GTK theme, no
Kvantum theme, no cursor set, no nvim plugin, no Zed theme, no yazi flavour. It
wears all six.

What a new scheme actually needs now:

- **A full sixteen-slot terminal palette.** This is the real constraint, and it
  is the one that is left. A scheme published as material roles only leaves the
  ANSI set to invention.
- **A `muted` set**, which is this repo's derivation for every scheme anyway.
- **An icon set that does not fight it**, or `native = false` and a reason.

## 3. nvim — swap the plugin

**The plugin is named in the theme file, and the spec is generated.** A scheme
declares `apps.nvim`:

```nix
nvim = {
  spec = "ellisonleao/gruvbox.nvim";   # the lazy.nvim spec
  name = "gruvbox";                    # `:colorscheme` argument, and lazy's `name =`
  lualine = "gruvbox";                 # or "auto"
  setup = ''…lua…'';                   # the plugin's own setup call
  palette = { };                       # see below
};
```

Three files are generated into the nvim tree by `modules/home/dotfiles.nix`:
`lua/plugins/colorscheme.lua` (the spec), `lua/config/scheme.lua` (names only)
and, conditionally, `lua/config/palette.lua`. `lazy.lua` and `ui.lua` stay
hand-written and `require("config.scheme")` — so no file under `dotfiles/nvim/`
names a scheme.

### The decision rule, which is what `palette` encodes

- **The plugin IS the scheme** → `palette = { }`. Take upstream's values. This
  is `gruvbox` and `nord`.
- **The theme DEVIATES from its plugin** → supply the map. `mocha-high-contrast`
  lifts Mocha's greys, so it overrides the plugin's values through
  `color_overrides.mocha`. The map's keys are the *plugin's* vocabulary, the
  values are this file's role names.

**Do not override a foreign plugin's palette.** Overriding 16 keys of a Mocha
theme with nord values leaves 10 Catppuccin ones in place and the result is a
visible hybrid, not nord. The gruvbox → Catppuccin migration confirmed the
mirror image: overriding 20 keys of `gruvbox.nvim` with Mocha values would have
left 34 gruvbox ones behind.

Do not close a key gap by adding the plugin's names to the theme file either.
They are one plugin's internal vocabulary, not this machine's colours — and when
the plugin matches the scheme they are *already correct*.

> **lualine is the sharp edge.** A lualine theme that does not resolve **throws
> at startup** rather than falling back. `"auto"` derives the bar from whatever
> colourscheme actually loaded and cannot fail; name a built-in only when
> lualine is known to ship it.

**After a plugin swap, run `:Lazy sync`.** lazy.nvim fetches at runtime, so the
rebuild installs the *config* naming a plugin that is not on disk yet.

---

## 4. Gate it

```sh
nix flake check
```

**What it catches:** eval errors from a missing palette key; a generated file
that is missing or empty; a generated file that no longer contains the accent in
its consumer's own spelling; a mango mode config that stopped `source=`ing its
colours; any palette hex reappearing in a hand-written file under `dotfiles/`;
and a tinted lock ramp.

**Contrast IS caught**, per theme and against **two** declared floors:
`contrastFloor` for what this machine draws text with, `ansiFloor` for the
sixteen terminal slots. Every role is recomputed against what it actually sits
on — including `muted.err`, which is audited as the *background* it is, with
`muted.fg` on top, because that is the pair ncspot renders. The check reads the
palette **resolved by Nix**, so a role written as an alias is audited like any
other; it used to read the file with `sed` and four aliased roles went unaudited
for a release. `docs/adr/0032`.

**The theme packages are caught now too**, which §2 above used to say they were
not: every name a theme declares must resolve to a real directory in the built
closure, toolkit built-ins included.

**What it still does not catch:**

- **Zed.** Both the extension id and the theme name live in Zed's own registry.
  Nothing here can assert Zed resolves either — open it and look.
- **Whether an artefact suits the scheme.** The check asserts `Bibata-Modern-Amber`
  exists, not that it suits the scheme.
- **Colours the palette does not name.** They escape to upstream and are
  invisible here; that is how nvim's comment colour sat outside the palette
  through a whole migration. **Which colour a program actually uses is a
  measurement** — ask it with `nvim_get_hl` or the equivalent, do not read it
  off the theme.

---

## 5. Apply

```sh
rebuild        # sudo nixos-rebuild switch --flake "$HOME/src/nix-config#thinkpad"
```

Quote the flake ref — `EXTENDED_GLOB` makes `#` a pattern operator in zsh.

Then reload, per `CLAUDE.md`'s table. **Rebuild first, always**: everything
under `dotfiles/mango/` is a store path, so reloading alone re-reads the *last*
rebuild's copy, which is indistinguishable from the change having had no effect.

| Surface | Reload |
|---|---|
| mango, waybar | `~/.config/mango/scripts/reload.sh`, `mango-reload`, `waybar-reload` |
| GTK apps | `~/.config/mango/scripts/system/gtk-apply.sh` |
| kitty | `kill -SIGUSR1 $KITTY_PID` |
| foot, imv, yazi, zed, htop | restart the app |
| ncspot | restart the app |
| nvim | restart |
| swaync | `mango-reload` (`autostart.conf` owns its lifecycle — `docs/adr/0005`) |
| Equibop | restart the app; the rebuild's activation step writes `enabledThemes` |

---

## 6. Verify by output

Exit status proves nothing here — a missing theme and a broken theme look
identical, and both look like a theme someone chose. Every command below was run
against this repo and produces readable output.

```sh
# The generated files, as the rebuild will install them.
G=$(nix eval --raw '.#nixosConfigurations.thinkpad.config.home-manager.users.henry.home.activationPackage')
grep -r 'color=' "$G/home-files/.config/mango/universal/colors.conf"
cat "$G/home-files/.config/nvim/lua/plugins/colorscheme.lua"
cat "$G/home-files/.config/nvim/lua/config/scheme.lua"
sed -n '1,16p' "$G/home-files/.config/swaync/style.css"
```

```sh
# GTK / icons / cursor — what the session actually resolved.
for k in gtk-theme icon-theme cursor-theme; do
  printf '%-14s ' "$k"; dconf read /org/gnome/desktop/interface/$k
done
grep -E 'theme-name|cursor' ~/.config/gtk-3.0/settings.ini
```

> **Use `dconf read`, not `gsettings get`.** From a task shell or this repo's
> devShell, `gsettings` reports `No schemas installed` — which reads exactly
> like "the theme is unset" and is not.

```sh
# Qt / Kvantum
head -3 ~/.config/Kvantum/kvantum.kvconfig      # expect theme=<the theme>

# nvim actually loading the generated palette. ONLY schemes that deviate from
# their own plugin generate one — three of the five do not, and its absence is
# correct for those (§3).
nvim --headless '+lua local p=require("config.palette") print("keys="..vim.tbl_count(p).." base="..p.base)' +qa

# …and that the plugin actually applied them, which the above does not show.
# The colourscheme name comes from the theme file — read it out of scheme.lua
# rather than typing one, or the test covers a scheme that is not running.
nvim --headless '+lua vim.cmd("colorscheme " .. require("config.scheme").name)
  local h = vim.api.nvim_get_hl(0, { name = "Keyword", link = false })
  print(vim.g.colors_name .. " Keyword.fg=" .. string.format("#%06x", h.fg))' +qa
```

```sh
# The whole assertion suite, with the palette section visible
SYS=$(nix eval --raw '.#nixosConfigurations.thinkpad.config.system.build.toplevel')
bash checks/static.sh "$PWD" "$G" "$SYS" | sed -n '/Generated palette/,/^$/p'
```

Expect 18 ticks in that last block. A count that has *dropped* is the failure
mode this repo is built around: a scan that stops matching passes by finding
nothing.

One of the 18 exists only to guard that: `read N palette values to scan for`
reports how many hex values the stray-hex scan pulled **out of `palette.nix`**,
and fails below 16. The needles are read from the palette rather than listed in
the check, so changing the scheme does not silently leave the scanner hunting
for the old one — which is the same bug in the check that the check exists to
find.

---

## 7. Traps specific to this operation

- **nvim is broken between the edit and the rebuild.** `colorscheme.lua` does
  `require("config.palette")`, and that file only exists in the generated tree.
  Open nvim after editing but before rebuilding and lazy.nvim reports a failed
  plugin config and there is no colourscheme. Not damage — rebuild and it is
  gone — but it looks alarming and it is expected.
- **Store files are read-only, so one cannot be hand-patched to preview a
  colour.** Edit `palette.nix` and rebuild; there is no faster loop, and trying
  to make one is how `~/.config` acquires a second owner.
- **A GTK `url()` that fails to resolve draws the missing-image box and logs
  nothing.** If a new GTK theme references assets by relative path, they must
  end up beside the stylesheet in the store — see `docs/adr/0009` for the
  wlogout instance of this.
- **Do not run `dbus-update-activation-environment` or `systemctl --user
  import-environment` to make a theme change take effect.** From this repo's
  devShell it writes a scratchpad `XDG_CONFIG_HOME` into every user unit started
  afterwards. `docs/gotchas.md` → Session environment.

---

## 8. Rollback

Colours are cosmetic, so the boot-level safety nets are not needed here — this
is a `git` problem, not a generation problem.

```sh
git diff --stat                      # confirm the blast radius first
git restore modules/home/palette.nix # or the whole change
rebuild
```

If a rebuild has already landed and the previous generation is wanted back,
`nixos-rebuild switch --rollback` works, but reverting the commit and rebuilding
is cleaner and leaves the repo and the running system agreeing about why.

---

## 9. The short version

**Switching to a scheme that already exists:**

1. Edit `modules/home/scheme.nix` — one string.
2. `nix flake check`.
3. `rebuild`, then reload — rebuild first, always.

**Adding a new one:**

1. Copy a file in `modules/home/themes/`. Supply every key — `rec` makes a
   missing one an eval error.
2. Declare `contrastFloor` and `ansiFloor` (§1), the five `packages` (§2) and
   the `apps` block (§2, §3).
3. Point `scheme.nix` at it, `nix flake check`, `rebuild`, reload.
4. Read the output of §6, and the `Theme packages` block — stand-ins are listed
   there on every run.
