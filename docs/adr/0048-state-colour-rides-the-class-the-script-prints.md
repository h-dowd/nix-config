# 0048 — State colour rides the class the script prints

**Status:** Accepted (2026-08-26).

Amends the *"One colour, and state is the exception"* clause of
0045. The principle is unchanged; the list
of exceptions grows from two to five.

## Context

0045 took wayle's sixteen per-module `label-color`s down to one pair —
`fg-muted` icons, `fg-default` labels — because with the flat `basic` button
variant those colours show through raw and the bar was sixteen colours
competing, none of them meaning anything. Colour was then reserved for state:
the battery thresholds and the active workspace tag.

That reserved it and then under-spent it. Three modules carry state a glance
should resolve and did not:

- **night light** — on or off, a moon glyph either way
- **idle inhibitor** — held, released, or *failed to take the inhibit*, and the
  failure renders the ON glyph, so a broken inhibitor looked like a working one
- **power profile** — performance, balanced, fanless, or TLP not running

Each is driven by a keybind as well as by its own click, and `SUPER+SHIFT+a`
has no OSD and no notification, so the bar glyph is the only feedback there is.

**The mechanism was already there and unused.** Every custom module here sets
`class-format = "{{ class }}"`, and wayle splits that result on whitespace and
adds each word as a CSS class alongside the `mod-<name>` one — so
`night-mode.sh`'s `on`/`off`, `idle-inhibit.sh`'s
`activated`/`failed`/`deactivated` and `power-profile.sh`'s four profiles have
been live classes on the bar since the day it started. `docs/gotchas.md` -> Wayle
recorded them as live and unused.

Config could not do this. `[[modules.custom]]` takes `label-color` as **one
static value** and has no `thresholds` key — that key exists only on the native
numeric modules, which is why the battery's two states are config and these are
not.

## Decision

**Colour three custom modules by their emitted class, from the palette's
semantic roles.** `dotfiles/wayle/index.scss` gains five rules;
`wayle/styles/_colors.scss` grows from one generated variable to five —
`$sep`, plus `$ok`, `$warn`, `$err`, `$info` from `okColor`, `warnColor`,
`errColor` and `infoColor`.

| Module | State | Colour |
|---|---|---|
| night-mode | `on` | `$warn` — what the night light does to the screen |
| idle-inhibitor | `activated` | `$info` — a deliberate hold, not a fault |
| idle-inhibitor | `failed` | `$err` |
| power-profile | `performance`, `unavailable` | `$err` |
| power-profile | `fanless` | `$ok` |

**Roles, not literal hex.** "The same colour in every theme" was the ask, and
the role is what delivers it: green means the same thing in all five schemes
even though gruvbox's is `#b8bb26` and nord's `#a3be8c`. Four fixed hexes would
be four colours sourced outside `palette.nix`, sitting outside every contrast
floor and outside the assertion that every generated colour is used — the same
objection 0036 made to a
wallpaper-derived palette.

**The resting state of each module keeps no rule** and stays `fg-default`:
night-mode `off`, idle `deactivated`, power-profile `balanced`. Colouring the
default leaves the group permanently lit, and then the deviations stop standing
out — which is the whole of what 0045 bought.

**Battery is unchanged.** It is already the exception 0045 named, at 20/5,
which are upower's own action thresholds and not a second opinion on them
(`checks/static.sh` asserts the two still agree). A green band above 80 would
be colour marking something nobody acts on, and it is the drift that check was
written against. wayle offers a native module no charging state to hook either
— only `charging-icon`.

## Consequences

- **Every rule carries its group id.** These reach `.bar-button-label`, which
  wayle styles at (0,2,2); `.mod-x.state .bar-button-label` is (0,2,1) and
  loses *silently*, exactly as the clock's `font-size` did for the weeks 0045
  records. `checks/static.sh` already asserts the id on any rule touching a
  `.bar-button-*` node, and that assertion now covers five more rules.
- **`palette_pair` gained a `sigil` argument** and a third call site. The scss
  pair fails the way the waybar and rofi pairs do — sass resolves an undefined
  `$var` to nothing and the rule renders in the inherited colour. The used side
  subtracts what `index.scss` defines for itself, so `$groups` does not read as
  a reference to a colour nobody generated.
- **A class that stops being emitted takes its rule out of use, silently.** The
  pairing above is what catches it: the variable goes unused and the check
  fails. That is the only guard, because nothing can assert a script still
  prints a given class without running it in each state.
- **`index.scss` is fourteen rules, from nine.** Past the point where the
  header's count is worth keeping by hand if it grows again.
