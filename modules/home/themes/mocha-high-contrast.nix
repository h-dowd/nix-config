# Catppuccin Mocha, grey ramp lifted to WCAG AAA.
#
# Selected by `modules/home/scheme.nix`. Mocha's hues, on Mocha's own `crust`
# as the background, with every text-bearing colour at 7:1 or better against
# what it sits on.
#
# WHY THIS EXISTS. Mocha's accents were never the problem — all twelve clear
# AAA on `base` unaided. Its *greys* are. Measured against the running editor
# rather than guessed at: nvim paints Comment with `overlay2` (5.81:1 on Mocha's
# base) and `brBlack`/`overlay1` carries timestamps and inactive labels at
# 4.44:1. Those are the least saturated, most-read colours on the machine, so
# "the text is hard to read" is a precise complaint about them rather than a
# vague one about the scheme.
#
# One thing this theme does NOT fix: nvim's LineNr takes `surface1`, a
# *background* tone used as foreground, and lands near 2:1 here as it does
# upstream. That is Catppuccin's deliberate subtlety, not a palette bug — the
# ramp below is chosen so it is no worse than Mocha's, and making it legible is
# a highlight override rather than a colour.
#
# WHAT CHANGED from `mocha.nix`, and nothing else did:
#   - `bg0` drops from Mocha's `base` to its `crust` (#1e1e2e → #11111b), which
#     buys ~1.14x on everything at once. The old `base` becomes `bg1`, so the
#     background ramp is Mocha's own, shifted one step down.
#   - the greys are lifted until they clear 7:1, by raising HSV value and easing
#     saturation: `brBlack` #7f849c → #999eb7, ncspot's `dim` likewise.
#   - the twelve accents are **byte-identical to Mocha's**. They already passed;
#     changing them would have made this a different scheme rather than a more
#     legible one, and the theme packages below are shared with `mocha`
#     precisely because the hues are.
#
# The numbers are asserted, not asserted-once-and-trusted: `checks/static.sh`
# recomputes every ratio in this file on each `nix flake check`, so a future
# edit that dims a grey fails the build rather than the eye.
rec {
  # --- Legibility, asserted by checks/static.sh -----------------------------
  # Two floors because two different things are being promised. See
  # `docs/adr/0032`; `mocha.nix` carries the long version of why they split.
  contrastFloor = 7.0; # WCAG AAA. The number this whole theme exists to hold.
  ansiFloor = 8.0; # Mocha's ANSI set IS its accent set, so this costs nothing.

  # --- Canonical names ------------------------------------------------------
  bg0 = "11111b"; # crust — the background, one step below Mocha's
  bg1 = "1e1e2e"; # base
  # Mocha's surface1/surface2, NOT its surface0/1. Shifting the whole ramp down
  # with `bg0` was the first attempt and it dropped nvim's LineNr to 1.65:1 —
  # darkening the background while also darkening what is drawn on it. Only
  # `bg0` moves; everything above it stays where Mocha put it.
  bg2 = "45475a"; # surface1
  bg3 = "585b70"; # surface2
  fg0 = "f5e0dc"; # rosewater
  fg1 = "cdd6f4"; # text
  fg4 = "a6adc8"; # subtext0 — 8.42:1 here, where it was 7.37 on Mocha's base

  # Below `bg0`, for Equibop's pressed controls. Mocha's own crust is `bg0`
  # now, so this is darker than anything Catppuccin names.
  mantle = "09090f";

  black = "313244"; # surface0 — lifted with the rest of the ramp
  red = "f38ba8";
  green = "a6e3a1";
  yellow = "f9e2af";
  blue = "89b4fa";
  magenta = "f5c2e7"; # pink
  cyan = "94e2d5"; # teal
  white = "a6adc8"; # subtext0

  # `brBlack` carries nvim's NonText, Conceal and FoldColumn, swaync's
  # timestamps and every inactive label. Mocha puts it at 4.44:1; here it is
  # 7.08:1, and `comment` below shares the value.
  brBlack = "999eb7";
  brRed = red;
  brGreen = green;
  brYellow = yellow;
  brBlue = blue;
  brMagenta = magenta;
  brCyan = cyan;
  brWhite = "bac2de"; # subtext1

  # --- Semantic roles -------------------------------------------------------
  base = bg0;
  surface = bg1;
  overlay = bg2;
  text = fg1;
  subtext = fg4;
  # The dimmest colour that is still TEXT. 7.08:1 — this is the value the
  # complaint was actually about.
  # Spelled out rather than aliased to `brBlack`, for readability — this was
  # once load-bearing, because the check read hex from this file with sed and an
  # alias read as "role absent". It resolves the palette through Nix now.
  comment = "999eb7";
  # Mocha's mauve. The key that used to hold it (`mauve`) is gone, because
  # nothing but the check ever read it, and a name earns its place by acquiring
  # a consumer.
  accent = "cba6f7";

  okColor = green;
  warnColor = yellow;
  errColor = red;
  infoColor = blue;

  # --- Terminal aliases -----------------------------------------------------
  bg = bg0;
  fg = fg1;
  selBg = bg2;

  # --- Muted set (ncspot) ----------------------------------------------------
  # Measured against `surface` below, NOT against `bg0`: ncspot fills whole rows
  # with its raised background, so that is the colour its text actually sits on.
  # Checking these against `bg0` would have passed three values that fail where
  # they are used.
  muted = {
    bg = bg0;
    fg = "b1b8d3"; # 9.01:1 on surface
    dim = "9ea2ba"; # 7.03:1
    accent = "b595dc"; # 7.01:1
    ok = "90c48d"; # 8.84:1
    # A BACKGROUND, not text — ncspot draws `error_fg` (= `fg` above) on it.
    # This was #e488a3 until 2026-08-18, a light pink that put light grey-blue
    # text at **1.28:1** on the running machine. It passed because the check
    # measured it against `surface`, a pair ncspot never draws. Now it is
    # audited as what it is: `fg` on `err` is 7.30:1. docs/adr/0032.
    err = "352532";
    surface = "171724"; # raised background: status bar, cmdline, playing row
    overlay = "1b1b2a"; # borders, highlight, progress trough
  };

  # --- Artefacts: one named, three generated --------------------------------
  # Rendered SVG widget art, compiled SCSS and names other programs resolve
  # internally. No amount of hex here reaches those four, so the
  # scheme names them instead and `checks/static.sh` asserts each one resolves.
  # Identical to `mocha.nix`: this theme changes greys, not hues.
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
      name = "mocha-high-contrast-gtk";
      native = true;
    };
    kvantum = {
      # Generated from this file's colours — docs/adr/0041; see gruvbox.nix.
      attr = "paletteKvantum";
      name = "mocha-high-contrast-kvantum";
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
      name = "mocha-high-contrast-cursors";
      native = true;
    };
  };

  # --- Applications that hold a theme NAME ----------------------------------
  # Not packages and not hex — settings whose value is a scheme's name. None of
  # these show up in a search for colours, which is how the Equibop theme stayed
  # gruvbox through a whole migration.
  apps = {
    # nvim takes the plugin whose scheme this IS, per THEME-MIGRATION §3.
    # `palette` is non-empty only here and in `mocha.nix`: this theme is a
    # *deviation* from what the plugin ships, so it overrides the plugin's own
    # values. A scheme that matches its plugin leaves this empty and takes
    # upstream's.
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
