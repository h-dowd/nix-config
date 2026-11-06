# Catppuccin Mocha — upstream's values, unmodified.
#
# Selected by `modules/home/scheme.nix`. See modules/home/palette.nix for how
# these files are chosen and what the shared key names mean.
#
# NOT the most legible scheme this machine has: its grey ramp is the weak part,
# and `brBlack` sits at 4.44:1 against `bg0` where 7:1 is the floor the sibling
# theme holds to. Kept faithful anyway — this is what Catppuccin Mocha IS, and a
# "fixed" Mocha that is no longer Mocha is the kind of drift this whole
# arrangement exists to prevent. Pick `mocha-high-contrast` if you want the
# ramp lifted.
rec {
  # --- Legibility, asserted by checks/static.sh -----------------------------
  # TWO floors, because two different promises are being made and collapsing
  # them into one number forces a lie in whichever direction it is set.
  #
  # `contrastFloor` covers what THIS MACHINE'S UI draws text with — the bar, the
  # menus, notifications, editor chrome, ncspot's rows. Declared per theme
  # rather than fixed globally because upstream Mocha genuinely does not reach
  # WCAG AA on its greys (`brBlack` is 4.44:1), and a global 4.5 floor would
  # make it impossible to ship Catppuccin Mocha *as Catppuccin Mocha*. Stating
  # the weak number is more honest than quietly raising it, and the assertion
  # still catches any future edit that dims it further.
  contrastFloor = 4.4;

  # `ansiFloor` covers the sixteen terminal slots, which are a different kind of
  # thing: nothing on this machine draws its own text in them — they are what
  # OTHER programs print with, and they are the scheme's published identity. On
  # Mocha the two sets coincide, so this floor costs nothing here; it exists
  # because on Gruvbox they do not, and gruvbox's normal red is 2.69:1 by
  # upstream's design. Separating them keeps the number that matters high
  # instead of dragging it down to the weakest ANSI slot. docs/adr/0032.
  ansiFloor = 7.0;

  # --- Canonical names ------------------------------------------------------
  # Mocha's monochromatic ramp: base → surface0/1/2 for backgrounds, subtext0 →
  # text → rosewater for foregrounds.
  bg0 = "1e1e2e"; # base
  bg1 = "313244"; # surface0
  bg2 = "45475a"; # surface1
  bg3 = "585b70"; # surface2
  fg0 = "f5e0dc"; # rosewater — the brightest foreground
  fg1 = "cdd6f4"; # text
  fg4 = "a6adc8"; # subtext0 — dimmed / inactive

  # One step DARKER than `bg0`, which the ramp above has no name for: `bg0` is
  # the darkest of it. Discord's theme needs a recessed tone for pressed
  # controls, and inventing one would put a colour on screen that Mocha does
  # not contain. Mocha's own name for it, so it is a lookup and not a choice.
  mantle = "181825";

  black = "45475a"; # surface1
  red = "f38ba8";
  green = "a6e3a1";
  yellow = "f9e2af";
  blue = "89b4fa";
  magenta = "f5c2e7"; # pink
  cyan = "94e2d5"; # teal
  white = "a6adc8"; # subtext0

  # Catppuccin has no bright axis: it is a pastel scheme whose accents are
  # already at full strength, and every upstream Catppuccin terminal theme ships
  # `bright` equal to `normal` for the six chromatic slots. Reproduced here
  # rather than inventing six lighter values, which would be this repo's hex and
  # not Catppuccin's. Only the two achromatic slots differ, where Mocha does
  # have somewhere brighter to go.
  brBlack = "7f849c"; # overlay1 — lighter than bg3, so it reads as a colour
  brRed = red;
  brGreen = green;
  brYellow = yellow;
  brBlue = blue;
  brMagenta = magenta;
  brCyan = cyan;
  brWhite = "bac2de"; # subtext1

  # --- Semantic roles -------------------------------------------------------
  # What a UI surface asks for. The bar, the menus and the compositor borders
  # all speak in these; only the terminals want the 16-colour set above.
  base = bg0; # window background
  surface = bg1; # raised background, mango's unfocused border
  overlay = bg2; # hairlines, selection background, mango's focused-window fill
  text = fg1;
  subtext = fg4; # dimmed / inactive text
  # The dimmest colour that is still TEXT, as distinct from `brBlack`, which is
  # the terminal's bright-black and lives on the background ramp. nvim paints
  # comments with it. Upstream Mocha's `overlay2`, kept as-is: 5.81:1, which
  # clears this theme's floor.
  comment = "9399b2";
  # Mocha's mauve — the single accent: selection, active workspace, prompt.
  #
  # A literal rather than an alias, for readability only — the check resolves
  # the `rec` through Nix now, so it would audit this however it is spelled.
  # This used to be `accent = mauve;` with a separate `mauve` key above it; that
  # key is gone, because nothing but the check ever read it and a name earns its
  # place by acquiring a consumer.
  accent = "cba6f7";

  # Under gruvbox these are the BRIGHT variants, because the normal ones are too
  # dark to sit on `base`. Mocha's accents clear 7:1 against `base` on their own
  # (text 11.3, green 11.0, red 7.1), so they are the normal ones and the `br*`
  # aliases above would be the same values anyway.
  okColor = green;
  warnColor = yellow;
  errColor = red;
  infoColor = blue;

  # --- Terminal aliases -----------------------------------------------------
  # kitty and foot named these before the semantic set existed.
  bg = bg0;
  fg = fg1;
  selBg = bg2;

  # --- Muted set (ncspot) ----------------------------------------------------
  # ncspot's theme is a deliberately desaturated variant: a TUI that fills whole
  # rows with its background colours, where the full-strength palette above is
  # loud enough to read as an error state.
  #
  # Under gruvbox these were picked by eye and no formula reproduced them. Mocha
  # is uniform enough that one does: each is blended 18% toward `bg0`, which is
  # what "dimmed but still itself" means on a pastel scheme. Stated so the next
  # scheme change knows whether it can repeat the trick — it can only if the new
  # scheme is likewise even, and should go back to picking by eye if it is not.
  #
  # They live in this file anyway, because the point of it is that **every
  # colour on this machine has one home**. A muted variant kept next to its one
  # consumer is exactly how the palette came to exist in three places before
  # 2026-08-14: it looks local right up until someone changes the scheme and
  # finds this set still wearing the old one.
  muted = {
    bg = bg0; # ncspot's `background` — the one value shared with the main set
    fg = "aeb5d0"; # dimmed text, used for every foreground role
    # 868ba2, not the 6e7288 the 18% blend produced: that sat at 3.13:1 against
    # `surface` below, under this theme's own declared floor, and the contrast
    # check caught it on its first run. Not a fidelity question — the muted set
    # is this repo's derivation, not Catppuccin's, so lifting it costs nothing.
    dim = "868ba2"; # secondary text
    accent = "ac8ed3"; # dimmed mauve — titles, progress, search matches
    ok = "8ec08c"; # dimmed green — the playing track
    # A BACKGROUND, not text: ncspot draws `error_fg` (= `fg` above) on it. This
    # was #cd7792 until 2026-08-18 — a dimmed pink that put `fg` at 1.55:1 where
    # it is actually rendered. It passed because the check measured it against
    # `surface`, a pair ncspot never draws. Audited as what it is now: `fg` on
    # `err` is 4.65:1. docs/adr/0032.
    err = "5a3d50";
    surface = "262637"; # raised background: status bar, cmdline, playing row
    overlay = "2d2e40"; # borders, highlight, progress trough
  };

  # --- Artefacts: one named, three generated --------------------------------
  # Rendered SVG widget art, compiled SCSS and names other programs resolve
  # internally. No amount of hex here reaches those four, so the
  # scheme names them instead and `checks/static.sh` asserts each one resolves
  # to something real in the built closure.
  #
  # `name` is READ OFF THE BUILT PACKAGE, never constructed from the arguments —
  # `catppuccin-mocha-mauve-standard`, `catppuccin-mocha-mauve-cursors` and
  # `catppuccin-mocha-mauve` are spelled three different ways from each other
  # and from the attribute (`mochaMauve`). A GTK theme name matching nothing
  # falls back to Adwaita and looks merely unstyled.
  #
  # Only the icon set is still a name, and it stays one on purpose. The GTK
  # theme, the Kvantum theme and the cursor are generated from the colours
  # above (docs/adr/0041); the yazi flavour is written from them too, in
  # pkgs/yazi-flavor.nix, and left this block entirely.
  packages = {
    gtk = {
      # Generated from this file's colours — docs/adr/0041; see gruvbox.nix.
      attr = "paletteGtk";
      name = "mocha-gtk";
      native = true;
    };
    kvantum = {
      # Generated from this file's colours — docs/adr/0041; see gruvbox.nix.
      attr = "paletteKvantum";
      name = "mocha-kvantum";
      native = true;
    };
    icons = {
      attr = "papirus-icon-theme";
      # Papirus has no `mauve`; `violet` is its nearest folder colour.
      override.color = "violet";
      name = "Papirus-Dark";
      native = true;
    };
    cursor = {
      # Generated from this file's colours — docs/adr/0041, and see gruvbox.nix
      # for what `paletteCursors` is and why the name is spelled out.
      attr = "paletteCursors";
      name = "mocha-cursors";
      native = true;
    };
  };

  # --- Applications that hold a theme NAME ----------------------------------
  # Not packages and not hex — settings whose value is a scheme's name. None of
  # these show up in a search for colours, which is how the Equibop theme stayed
  # gruvbox through a whole migration.
  apps = {
    # nvim takes the plugin whose scheme this IS, per THEME-MIGRATION §3.
    # `palette` is non-empty only for the two Catppuccin themes, which drive the
    # plugin's `color_overrides` hook. A scheme that matches its own plugin
    # leaves it empty and takes upstream's values.
    nvim = {
      spec = "catppuccin/nvim";
      name = "catppuccin";
      lualine = "catppuccin"; # provided by the plugin itself
      setup = ''
        require("catppuccin").setup({
          flavour = "mocha",
          transparent_background = true,
          term_colors = true,
          styles = {
            comments = { "italic" },
            conditionals = { "italic" },
          },
          color_overrides = { mocha = require("config.palette") },
        })
      '';
      # catppuccin/nvim's OWN palette vocabulary on the left, this file's roles
      # on the right. `overlay2` is what nvim paints Comment with — established
      # by asking the running editor (`nvim_get_hl`), not assumed.
      #
      # Deliberately absent: crust, flamingo, maroon, peach, sky, sapphire and
      # lavender. This file does not name them and the plugin's own Mocha values
      # are correct, because this theme IS Mocha.
      palette = {
        base = "bg0";
        mantle = "mantle";
        surface0 = "bg1";
        surface1 = "bg2";
        surface2 = "bg3";
        rosewater = "fg0";
        text = "fg1";
        subtext0 = "fg4";
        subtext1 = "brWhite";
        overlay0 = "brBlack";
        overlay1 = "brBlack";
        overlay2 = "comment";
        mauve = "accent";
        red = "red";
        green = "green";
        yellow = "yellow";
        blue = "blue";
        pink = "magenta";
        teal = "cyan";
      };
    };

  };
}
