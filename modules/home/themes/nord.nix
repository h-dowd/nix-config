# Nord — upstream's values, unmodified.
#
# Selected by `modules/home/scheme.nix`. See modules/home/palette.nix for how
# these files are chosen and what the shared key names mean.
#
# The sixteen `nordN` colours are Nord's published palette. Where a role has to
# pick among them, the pick follows noctalia's shipped
# `Assets/ColorScheme/Nord/Nord.json`.
#
# NORD IS THE DIMMEST SCHEME HERE, and this file ships it that way. `nord3`
# (#4c566a) is Nord's comment colour and it is **1.69:1** on `nord0` — the
# lowest number in this directory by a wide margin, and the scheme's
# best-known complaint. It is not a mistake to correct: it is what Nord is, and
# a "fixed" Nord whose greys have been lifted is a different scheme wearing the
# name. The floor below states the number rather than legislating against it.
#
# If it turns out to be too dim in use, the fix is a `nord-high-contrast`
# sibling that lifts the grey ramp along Nord's own `nord0`→`nord4` line and
# leaves the hues alone — `mocha-high-contrast.nix` is the worked example, and
# it exists because exactly this complaint was made about Mocha. Do that as a
# second file; do not edit this one.
rec {
  # --- Legibility, asserted by checks/static.sh -----------------------------
  # These are MEASURED, not chosen. The assertion is "this theme is as legible
  # as it claims", so a future edit that dims a role below the number here
  # fails the build — and nothing forbids the number being low.
  contrastFloor = 1.69; # `comment`/`brBlack`, #4c566a — nord3
  ansiFloor = 3.0; # normal red, #bf616a — nord11, at 3.05:1

  # --- Canonical Nord names -------------------------------------------------
  # Polar Night, nord0–nord3.
  bg0 = "2e3440"; # nord0
  bg1 = "3b4252"; # nord1
  bg2 = "434c5e"; # nord2
  bg3 = "4c566a"; # nord3

  # Snow Storm, nord6–nord4. noctalia's Nord maps `mOnSurface` to nord6 and
  # `mOnSurfaceVariant` to nord4, which is the arrangement used here: Nord has
  # nothing between nord4 and nord3, so `subtext` is nord4 rather than a dimmer
  # tone that does not exist.
  fg0 = "eceff4"; # nord6
  fg1 = "e5e9f0"; # nord5
  fg4 = "d8dee9"; # nord4

  # One step darker than `bg0`, for Equibop's pressed controls. Nord publishes
  # NOTHING below nord0, so unlike its other values this one is derived — nord0
  # darkened on its own ramp. The alternative is leaving Discord's recessed
  # controls the same tone as its background.
  mantle = "242933";

  black = "3b4252"; # nord1
  red = "bf616a"; # nord11
  green = "a3be8c"; # nord14
  yellow = "ebcb8b"; # nord13
  blue = "81a1c1"; # nord9
  magenta = "b48ead"; # nord15 — Nord's purple
  cyan = "88c0d0"; # nord8
  white = "e5e9f0"; # nord5

  # Nord has no separate bright axis for the Aurora colours: its own terminal
  # ports ship `bright` equal to `normal` for red, green, yellow and purple.
  # Reproduced rather than inventing four lighter values, which would be this
  # repo's hex and not Nord's. The three Frost slots do differ — nord7 and
  # nord10 are where Nord has somewhere else to go.
  brBlack = "4c566a"; # nord3 — 1.69:1, the value the floor above records
  brRed = red;
  brGreen = green;
  brYellow = yellow;
  brBlue = "5e81ac"; # nord10
  brMagenta = magenta;
  brCyan = "8fbcbb"; # nord7
  brWhite = "eceff4"; # nord6

  # --- Semantic roles -------------------------------------------------------
  base = bg0;
  surface = bg1;
  overlay = bg2;
  text = fg1;
  subtext = fg4;
  # nord3, Nord's comment colour, at 1.69:1. Spelled out rather than aliased to
  # `brBlack` so the two can move apart without one silently following the
  # other — which is what a `nord-high-contrast` would want to do.
  comment = "4c566a";
  # nord7, noctalia's `mPrimary` for this scheme.
  accent = "8fbcbb";

  okColor = green;
  warnColor = yellow;
  errColor = red;
  # nord9, not nord10: noctalia maps `mTertiary` to nord10 (#5e81ac), which is
  # 3.10:1 and darker than the red it would sit beside. nord9 is the same hue
  # family one step up and is what Nord's own UI uses for informational text.
  infoColor = blue;

  # --- Terminal aliases -----------------------------------------------------
  bg = bg0;
  fg = fg1;
  selBg = bg2;

  # --- Muted set (ncspot) ----------------------------------------------------
  # ncspot's deliberately desaturated variant: a TUI that fills whole rows with
  # its background colours, where the full-strength palette above is loud enough
  # to read as an error state.
  #
  # THIS SET IS THIS REPO'S DERIVATION, not Nord's — Nord publishes no muted
  # variant — so unlike the values above it is chosen rather than looked up, and
  # it is chosen to be legible. Each is blended toward `bg0` until it clears
  # 4:1 on the raised `surface` below. That is deliberately far above this
  # theme's 1.69 floor: fidelity is a reason to keep `comment` where Nord put
  # it, and no reason at all to invent a dim colour of our own.
  muted = {
    bg = bg0;
    fg = "b9bfcb"; # 6.07:1 on surface
    dim = "959ba8"; # 4.02:1
    accent = "84adad"; # 4.56:1
    ok = "94ac83"; # 4.52:1
    # A BACKGROUND, not text: ncspot draws `error_fg` (= `fg` above) on it, so
    # it is audited as the pair that is actually rendered. 4.52:1.
    err = "58414c";
    surface = "353b4a"; # raised background: status bar, cmdline, playing row
    overlay = "3f4757"; # borders, highlight, progress trough
  };

  # --- Artefacts: one named, three generated --------------------------------
  # All native, no stand-ins. `nordic` used to supply the GTK theme, the Kvantum
  # theme and the cursors between them. All three are generated from the colours
  # above now (docs/adr/0041), so this scheme no longer names `nordic` at all.
  #
  # `name` is read off the built package, never constructed from the attribute.
  packages = {
    gtk = {
      # Generated from this file's colours — docs/adr/0041; see gruvbox.nix.
      attr = "paletteGtk";
      name = "nord-gtk";
      native = true;
    };
    kvantum = {
      # Generated from this file's colours — docs/adr/0041; see gruvbox.nix.
      attr = "paletteKvantum";
      name = "nord-kvantum";
      native = true;
    };
    icons = {
      attr = "nordzy-icon-theme";
      name = "Nordzy-dark";
      native = true;
    };
    cursor = {
      # Generated from this file's colours — docs/adr/0041, and see gruvbox.nix
      # for what `paletteCursors` is and why the name is spelled out.
      attr = "paletteCursors";
      name = "nord-cursors";
      native = true;
    };
  };

  # --- Applications that hold a theme NAME ----------------------------------
  apps = {
    # The plugin IS the scheme, so `palette` is empty and nvim takes upstream's
    # values — including nord3 for comments, at the same 1.69:1 recorded above.
    nvim = {
      spec = "shaunsingh/nord.nvim";
      name = "nord";
      # `auto`, not lualine's built-in `nord`: the built-in is a static copy, and
      # `auto` derives the bar from the colourscheme that actually loaded. A
      # lualine theme that does not resolve throws at startup rather than
      # falling back, so the safe option wins.
      lualine = "auto";
      setup = ''
        vim.g.nord_contrast = true
        vim.g.nord_borders = true
        vim.g.nord_disable_background = true
        vim.g.nord_italic = true
      '';
      palette = { };
    };

  };
}
