# Heartbox — upstream's values, plus the four things it does not publish.
#
# From `noctalia-dev/noctalia-colorschemes`. docs/adr/0041.
#
# THE FIRST SCHEME THIS REPO COULD NOT HAVE WORN. nixpkgs has no Heartbox GTK
# theme, Kvantum theme or cursor set, and there is no Heartbox nvim plugin,
# Zed theme or yazi flavour anywhere. Under the arrangement `docs/adr/0032`
# described, that made it unadoptable — five of the six artefacts would have
# been stand-ins. All six are generated from the values below now, which is
# what `docs/adr/0041` was written to make possible.
#
# Upstream publishes a full sixteen-slot terminal palette, which the registry
# entry drops and the source file does not — so the ANSI set here is looked up
# rather than invented. Derived here and marked as such: `mantle`, the `muted`
# set, and `bg3`.
rec {
  # --- Legibility, asserted by checks/static.sh -----------------------------
  # MEASURED, not chosen. `brBlack` is upstream's own #4a3a3e and it is 1.72:1,
  # which is what this scheme is — the same situation `nord.nix` records at
  # 1.69. The floor states the number rather than legislating against it.
  contrastFloor = 1.72; # `brBlack`, #4a3a3e
  ansiFloor = 3.8; # normal red, #e02030 — the accent, at 3.87:1

  # --- Canonical Heartbox names ---------------------------------------------
  bg0 = "1a1214"; # mSurface
  bg1 = "2c1f22"; # mSurfaceVariant
  bg2 = "3a2428"; # mHover
  # DERIVED. Upstream publishes nothing between `mHover` and its bright black,
  # and the ramp needs a fourth step for Kvantum's `light.color` and Colloid's
  # `$grey-550`. Its own bright black is that step.
  bg3 = "4a3a3e";

  fg0 = "fff8f0"; # bright white
  fg1 = "f4ebe0"; # mOnSurface
  # mOutline. Cooler than the rest of this scheme by upstream's own choice —
  # Heartbox is warm reds over a near-black, and its one grey is blue.
  fg4 = "b8c0c8";

  # DERIVED, for Equibop's recessed controls. Upstream publishes nothing below
  # `mSurface`, so this is bg0 darkened on its own ramp — the same derivation
  # `nord.nix` records for the same reason.
  mantle = "110c0d";

  black = "1a1214";
  red = "e02030";
  green = "5fbf4a";
  yellow = "e8d45a";
  blue = "5ec8e8";
  magenta = "e86a9a";
  # NOT A TRANSCRIPTION ERROR: upstream gives `cyan` and `blue` the same value.
  # Its bright pair does differ, which is where the two separate.
  cyan = "5ec8e8";
  white = "f4ebe0";

  brBlack = "4a3a3e"; # 1.72:1, the value the floor above records
  brRed = "ff4a58";
  brGreen = "7ad964";
  brYellow = "f0e47a";
  brBlue = "7ad8f0";
  brMagenta = "f08bb0";
  brCyan = "8ae0f5";
  brWhite = "fff8f0";

  # --- Semantic roles -------------------------------------------------------
  base = bg0;
  surface = bg1;
  overlay = bg2;
  text = fg1;
  subtext = fg4;
  # mOnSurfaceVariant, 4.02:1 — high for a comment colour, and upstream's.
  comment = "8a6e78";
  accent = red; # mPrimary

  okColor = brGreen;
  warnColor = yellow;
  # brRed, NOT `red`. Upstream sets `mError` equal to `mPrimary`, so urgent and
  # focused would be the same colour — mango draws `urgent_color` and
  # `focus_color` side by side, and a window demanding attention would look
  # merely focused. The bright red is the same hue one step up.
  errColor = brRed;
  infoColor = blue;

  # --- Terminal aliases -----------------------------------------------------
  bg = bg0;
  fg = fg1;
  selBg = bg2; # upstream's `selectionBg`

  # --- Muted set (ncspot) ----------------------------------------------------
  # THIS REPO'S DERIVATION, as it is for every scheme — nobody publishes one.
  # ncspot fills whole rows with these, and at full strength this palette's red
  # reads as an error state across half the screen.
  #
  # Each is blended toward `bg0` until it clears 4:1 on the raised `surface`
  # below, which is far above this theme's 1.72 floor: a low floor is a fact
  # about upstream's greys and not a licence to invent dim colours here.
  muted = {
    bg = bg0;
    fg = "b3aaa3"; # 6.30:1 on surface
    dim = "9a8188"; # 4.02:1
    accent = "e55760"; # 4.02:1
    ok = "5fbf4a"; # 6.19:1
    # A BACKGROUND: ncspot draws `error_fg` (= `fg` above) on it, so it is
    # audited as the pair that is actually rendered. 4.52:1.
    err = "7d1922";
    surface = "302828"; # raised background: status bar, cmdline, playing row
    overlay = "3d3535"; # borders, highlight, progress trough
  };

  # --- Artefacts: one named, three generated --------------------------------
  # The GTK theme, the Kvantum theme and the cursor are generated from the
  # colours above (docs/adr/0041); the yazi flavour and the Zed theme are
  # written from them too and left this block entirely.
  #
  # The icon set is the only name, and it is this repo's FIRST stand-in — the
  # `native = false` marker that `modules/home/palette.nix` documents and that
  # nothing used until now, because until now the scheme set was chosen to
  # avoid ever needing one.
  packages = {
    gtk = {
      attr = "paletteGtk";
      name = "heartbox-gtk";
      native = true;
    };
    kvantum = {
      attr = "paletteKvantum";
      name = "heartbox-kvantum";
      native = true;
    };
    cursor = {
      attr = "paletteCursors";
      name = "heartbox-cursors";
      native = true;
    };
    icons = {
      # A STAND-IN, and the reason is structural rather than an oversight:
      # upstreams parameterise the folder and accent hue and nothing else, and
      # the rest of an icon set is app BRAND colours that must not follow a
      # scheme. There is no Heartbox icon theme and there is no useful sense in
      # which there could be one.
      attr = "papirus-icon-theme";
      name = "Papirus-Dark";
      native = false;
      why = "no Heartbox icon set exists; neutral dark that does not fight red on near-black";
    };
  };

  # --- Applications that hold a theme NAME ----------------------------------
  apps = {
    # No Heartbox nvim plugin exists, so this drives catppuccin/nvim's
    # `color_overrides` hook with the values above — the mechanism
    # `modules/home/palette.nix` documents for exactly this, and what
    # `mocha.nix` uses to override a plugin that already IS its scheme.
    nvim = {
      spec = "catppuccin/nvim";
      name = "catppuccin";
      lualine = "catppuccin";
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
      # catppuccin/nvim's own vocabulary on the left, this file's roles on the
      # right. `overlay2` is what nvim paints Comment with.
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
