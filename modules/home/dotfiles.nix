# Hand-written dotfiles, linked into ~/.config. Tier 2 (store-based) and tier 3
# (out-of-store) only; tier 1 is programs.nix / waybar.nix. Rules in
# docs/adr/0009, history in docs/adr/0002, layout in docs/SYSTEM.md §6.
{
  config,
  pkgs,
  lib,
  ...
}:

let
  # Not ~/.config — xdg.configFile writes there, so every entry would link to
  # itself. Declared in options.nix; shell.nix needs it too.
  dots = config.local.checkout;
  link = path: config.lib.file.mkOutOfStoreSymlink "${dots}/dotfiles/${path}";

  p = import ./palette.nix;
  # The scheme's NAME, for the provenance lines of generated files.
  scheme = import ./scheme.nix;

  # Bare "rrggbb" → { r; g; b; } as integers. swaync wants decimal channels,
  # which is the spelling that let a copy of the palette hide: grepping this
  # repo for `d79921` never found `rgb(215, 153, 33)`.
  rgbOf = c: {
    r = lib.fromHexString (builtins.substring 0 2 c);
    g = lib.fromHexString (builtins.substring 2 2 c);
    b = lib.fromHexString (builtins.substring 4 2 c);
  };

  # `r, g, b` with no wrapper — swaync composes some of these into rgba() with a
  # separate alpha var, so the channels have to stand alone.
  channels =
    c:
    let
      v = rgbOf c;
    in
    "${toString v.r}, ${toString v.g}, ${toString v.b}";

  # mango wants 0xrrggbbaa and has no opacity of its own, so alpha is part of
  # every colour it takes.
  mangoColor = c: "0x${c}ff";

  # One of midnight-discord's five-step colour scales, mixed from a single
  # palette colour. Steps 2 and 3 are the colour itself — that is the framework's
  # own shape, not a mistake, and the status vars read step 2.
  #
  # `color-mix` rather than five hex literals: the gruvbox original hand-tuned
  # twenty-five hsl() values across five scales, where a typo and a considered
  # value look identical. Mixing keeps one source colour per scale, so a palette
  # change moves all five.
  scale =
    name: c:
    lib.concatStringsSep "\n" [
      "  --${name}-1: color-mix(in srgb, #${c} 85%, white);"
      "  --${name}-2: #${c};"
      "  --${name}-3: #${c};"
      "  --${name}-4: color-mix(in srgb, #${c} 88%, black);"
      "  --${name}-5: color-mix(in srgb, #${c} 76%, black);"
    ];

  # The colours mango takes, as a file config.conf `source=`s, so the
  # hand-written configs keep the layout and rules and hold no hex at all.
  mangoColors = ''
    # GENERATED from modules/home/palette.nix — edit that, then rebuild.
    bordercolor=${mangoColor p.surface}
    focuscolor=${mangoColor p.accent}
    rootcolor=${mangoColor p.base}
    maximizescreencolor=${mangoColor p.okColor}
    urgentcolor=${mangoColor p.errColor}
    scratchpadcolor=${mangoColor p.brMagenta}
    globalcolor=${mangoColor p.brMagenta}
    overlaycolor=${mangoColor p.brCyan}
  '';

  # nvim is linked as ONE directory symlink, so unlike mango there is no way to
  # drop a generated file inside it — home-manager would be claiming a path that
  # already has an owner. Merging in the store instead keeps the single-symlink
  # shape and avoids `recursive = true`, whose failure mode here is destroying
  # the checkout (see unlinkStaleConfigDirs below and docs/adr/0002).
  #
  # THREE generated files, and the split matters:
  #
  #   lua/config/scheme.lua       names only — read by the hand-written lazy.lua
  #                               and ui.lua, so those two hold no scheme name
  #   lua/plugins/colorscheme.lua the plugin spec, because a new scheme means a
  #                               new PLUGIN, not overrides on a foreign one
  #   lua/config/palette.lua      colours, and only when the theme declares an
  #                               override map — see below
  #
  # THE PLUGIN IS GENERATED because a new scheme means a new PLUGIN, not
  # overrides on a foreign one: overriding 16 keys of a Mocha theme with gruvbox
  # values leaves 10 Catppuccin ones behind and the result is a visible hybrid.
  # THEME-MIGRATION §3.
  nvimTheme = p.apps.nvim;

  # COMMENTS GO HERE, NOT IN THE STRINGS BELOW. `#` starts no comment inside a
  # Nix `` literal and none in Lua either, so a `#` line in a block below is
  # emitted verbatim and breaks the file at load. That shipped once, past a green
  # `nix flake check`, because the check only grepped for the accent — hence the
  # parse check on the derivation.
  nvimScheme = pkgs.writeText "scheme.lua" ''
    -- GENERATED from modules/home/themes/${import ./scheme.nix}.nix — edit that,
    -- then rebuild. Names only, no colours: lazy.lua needs the colourscheme to
    -- fall back to and ui.lua needs lualine's theme, and neither should carry a
    -- scheme name of its own.
    return {
      name = "${nvimTheme.name}",
      lualine = "${nvimTheme.lualine}",
    }
  '';

  # The plugin's own vocabulary on the left, the palette's roles on the right —
  # the map lives in the theme file because the key names belong to the plugin,
  # not to this machine. Emitted only when that map is non-empty; a scheme that
  # matches its plugin takes upstream's values and this file does not exist.
  nvimPalette = pkgs.writeText "palette.lua" ''
    -- GENERATED from modules/home/palette.nix — edit that, then rebuild.
    -- Consumed by lua/plugins/colorscheme.lua as the plugin's own override hook.
    return {
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (key: role: "  ${key} = \"#${p.${role}}\",") nvimTheme.palette
    )}
    }
  '';

  nvimColorscheme = pkgs.writeText "colorscheme.lua" ''
    -- GENERATED from modules/home/themes/${import ./scheme.nix}.nix — edit that,
    -- then rebuild. Not present in dotfiles/nvim/.
    --
    -- High priority and `lazy = false` so it loads before anything that reads
    -- highlight groups at startup.
    return {
      {
        "${nvimTheme.spec}",
        name = "${nvimTheme.name}",
        priority = 1000,
        lazy = false,
        config = function()
    ${nvimTheme.setup}
          vim.cmd.colorscheme("${nvimTheme.name}")
        end,
      },
    }
  '';

  # Equibop's theme. It enables a theme by FILENAME from its own settings.json,
  # which home.activation.equibopTheme below writes.
  equibopTheme =
    q:
    # The metadata block, PREPENDED. `@name` is what Equibop shows in its theme
    # list. A comment may precede the fragment's `@import` because CSS only
    # requires `@import` to precede RULES.
    ''
      /**
       * @name ${scheme}
       * @description Generated from modules/home/themes/${scheme}.nix, using the
       *   midnight framework.
       * @author henry
       * @version 3.0
       */

    ''
    + builtins.readFile ../../dotfiles/equibop/theme-body.css
    + ''
      /* ---------------------------------------------------------------
         GENERATED from modules/home/themes/${scheme}.nix — edit that, then
         rebuild. The rules above are hand-written and live in
         dotfiles/equibop/theme-body.css.
         --------------------------------------------------------------- */
      :root {
        --colors: on;

        /* Text */
        --text-0: #${q.base}; /* on accent elements */
        --text-1: #${q.text}; /* important */
        --text-2: #${q.text}; /* headings */
        --text-3: #${q.brWhite}; /* normal */
        --text-4: #${q.subtext}; /* icons, channels */
        --text-5: #${q.brBlack}; /* muted, timestamps */

        /* Backgrounds. `mantle` is the one tone darker than `base`, for
           pressed controls; the main surface is `base` itself. */
        --bg-1: #${q.mantle}; /* darkest — clicked buttons */
        --bg-2: #${q.surface}; /* dark buttons */
        --bg-3: #${q.overlay}; /* secondary elements, spacing */
        --bg-4: #${q.base}; /* main background */

        --hover:         rgba(${channels q.text}, 0.04);
        --active:        rgba(${channels q.text}, 0.08);
        --active-2:      rgba(${channels q.text}, 0.05);
        --message-hover: rgba(${channels q.text}, 0.03);

        /* Accents. Only `--accent-3` is a palette colour; hover and pressed
           are mixed from it, so the button scale cannot drift from it. */
        --accent-1: #${q.infoColor}; /* links, accent text */
        --accent-2: #${q.cyan}; /* small accent elements */
        --accent-3: #${q.accent}; /* accent buttons */
        --accent-4: color-mix(in srgb, var(--accent-3) 65%, white);
        --accent-5: color-mix(in srgb, var(--accent-3) 80%, black);
        --accent-new: #${q.errColor}; /* mute/deafen/danger */

        --mention:       linear-gradient(to right, color-mix(in hsl, #${q.accent}, transparent 90%) 40%, transparent);
        --mention-hover: linear-gradient(to right, color-mix(in hsl, #${q.accent}, transparent 95%) 40%, transparent);
        --reply:         linear-gradient(to right, color-mix(in hsl, #${q.overlay}, transparent 90%) 40%, transparent);
        --reply-hover:   linear-gradient(to right, color-mix(in hsl, #${q.overlay}, transparent 95%) 40%, transparent);

        /* Status */
        --online:    var(--green-2);
        --dnd:       var(--red-2);
        --idle:      var(--yellow-2);
        --streaming: var(--purple-2);
        --offline:   var(--text-4);

        /* Borders */
        --border-light:  var(--hover);
        --border:        var(--active);
        --border-hover:  var(--active);
        --button-border: hsla(0, 0%, 100%, 0.1);

        /* Colour scales, mixed from one palette colour each rather than
           hand-tuned hsl() — the gruvbox original had five literals per
           scale and no way to tell a considered value from a typo. */
      ${scale "red" q.errColor}
      ${scale "green" q.okColor}
      ${scale "blue" q.infoColor}
      ${scale "yellow" q.warnColor}
      ${scale "purple" q.accent}
      }

      /* Code blocks */
      .hljs { background: #${q.surface} !important; color: #${q.text} !important; }
      .hljs-keyword, .hljs-selector-tag, .hljs-deletion   { color: #${q.red}; }
      .hljs-string,  .hljs-addition, .hljs-selector-class { color: #${q.green}; }
      .hljs-number,  .hljs-literal                        { color: #${q.magenta}; }
      .hljs-attr,    .hljs-type, .hljs-params             { color: #${q.yellow}; }
      .hljs-built_in, .hljs-title, .hljs-name             { color: #${q.blue}; }
      .hljs-function, .hljs-class, .hljs-tag              { color: #${q.cyan}; }
      .hljs-meta,    .hljs-regexp                         { color: #${q.accent}; }
      .hljs-comment                                       { color: #${q.brBlack}; font-style: italic; }
    '';

  # The parse check is the point of this being a derivation rather than a copy.
  # A malformed generated file is invisible to every other gate here: `nix flake
  # check` builds it happily, the palette scan greps it for the accent and finds
  # one, and nvim reports a failed plugin config at startup and falls back to no
  # colourscheme — which looks like a theme that did not apply, not a syntax
  # error. `luajit -b … /dev/null` compiles without running, so this is a syntax
  # gate and nothing more.
  nvimConfig = pkgs.runCommand "nvim-config" { nativeBuildInputs = [ pkgs.luajit ]; } ''
    cp -r ${../../dotfiles/nvim} $out
    chmod -R u+w $out
    cp ${nvimScheme} $out/lua/config/scheme.lua
    cp ${nvimColorscheme} $out/lua/plugins/colorscheme.lua
    ${lib.optionalString (nvimTheme.palette != { }) "cp ${nvimPalette} $out/lua/config/palette.lua"}
    for f in lua/config/scheme.lua lua/plugins/colorscheme.lua \
             ${lib.optionalString (nvimTheme.palette != { }) "lua/config/palette.lua"}; do
      luajit -b "$out/$f" /dev/null \
        || { echo "generated $f is not valid Lua" >&2; exit 1; }
    done
  '';
in
{
  xdg.configFile = {
    # --- Desktop environment ------------------------------------------------
    # `recursive` so the generated files below can sit inside the hand-written
    # tree.
    # Converting an already-linked directory this way destroys the checkout —
    # see unlinkStaleConfigDirs below and docs/adr/0002.
    "mango" = {
      source = ../../dotfiles/mango;
      recursive = true;
    };

    # The colours, generated. These paths do not exist under dotfiles/mango, so
    # they are new siblings inside the recursive tree rather than a second owner
    # for a linked path — the same arrangement waybar/colors.css already uses.
    "mango/universal/colors.conf".text = mangoColors;

    # Where the machine is, for scripts/system/weather.sh alone. Typed floats
    # from `local.location` (./options.nix), so a transposed sign is an eval
    # error. Missing, it would send `latitude=&longitude=` — which open-meteo
    # answers; the script refuses and the check asserts it. docs/adr/0038.
    "mango/universal/weather-location.env".text = ''
      # Generated by modules/home/dotfiles.nix — edit local.location, not this.
      WEATHER_LAT=${toString config.local.location.latitude}
      WEATHER_LON=${toString config.local.location.longitude}
      # Quoted: "New York" unquoted is an assignment followed by a command.
      WEATHER_NAME=${lib.escapeShellArg config.local.location.name}
      # escapeShellArg, which quotes only when it must: today's default needs
      # none, but an override carrying `&` between query parameters would be a
      # background job in a bare assignment — and would still LOOK right in the
      # file. Read by `weather.sh open` alone.
      WEATHER_URL=${lib.escapeShellArg config.local.location.forecastUrl}
    '';

    # The cursor, generated for the same reason and with a sharper failure. This
    # was a hand-written line in universal/settings.conf and it named
    # `catppuccin-mocha-mauve-cursors` for two schemes after the palette stopped
    # installing it. mango does not warn about a theme it cannot find: it hands
    # the name to wlroots, which falls back to its default, so the pointer
    # merely stops matching. Worse, mango `setenv`s XCURSOR_THEME from this value
    # for every client it spawns (parse_config.h), so one stale line overrides
    # `home.pointerCursor` for the whole session — while a terminal, which
    # re-sources hm-session-vars.sh, keeps showing the correct one.
    #
    # Read off `home.pointerCursor` rather than the palette directly, so the
    # compositor cannot disagree with GTK and ~/.icons/default about which theme
    # or which size this machine wears.
    "mango/universal/cursor.conf".text = ''
      # GENERATED by modules/home/dotfiles.nix. `source=`d by universal/settings.conf.
      cursor_theme=${config.home.pointerCursor.name}
      cursor_size=${toString config.home.pointerCursor.size}
    '';

    # --- Editors ------------------------------------------------------------
    # lazy-lock.json lives in stdpath("state"). Not the bare directory: the
    # generated palette is merged in first, see nvimConfig above.
    "nvim".source = nvimConfig;

    # --- Shell --------------------------------------------------------------
    # Not `zsh` — home-manager owns ~/.config/zsh/.zshrc, and one path cannot
    # have two owners.
    "zsh/conf.d".source = ../../dotfiles/zsh/conf.d;

    # --- Store-based ---------------------------------------------------------
    "glow".source = ../../dotfiles/glow; # no home-manager module at this pin

    # rofi reads ~/.config/rofi/config.rasi and nothing in the mango tree points
    # at it, so this declaration is the only thing that connects the two
    # (docs/adr/0014). Files, not a directory: rofi writes a cache and
    # rofi.png next to them.
    #
    # Split the same way the bar is: the layout rules are hand-tuned
    # presentation and stay written by hand, the palette is data and is derived
    # from modules/home/palette.nix. config.rasi `@import`s this one.
    "rofi/config.rasi".source = ../../dotfiles/rofi/config.rasi;

    # The icon theme NAME, generated for the reason colors.rasi is — one owner,
    # so it cannot drift from what GTK wears.
    #
    # rofi does NOT read GTK's setting. With `icon-theme` unset its fallback
    # chain is {Adwaita, gnome} plus hicolor (rofi-icon-fetcher.c:276), so the
    # launcher drew Adwaita art beside Papirus everywhere else and resolved 90
    # of 97 desktop entries instead of 96. Measured 2026-08-29.
    #
    # docs/adr/0060
    "rofi/icons.rasi".text = ''
      /* GENERATED from modules/home/dotfiles.nix. */
      configuration {
        icon-theme: "${p.packages.icons.name}";
      }
    '';

    # Imported by config.rasi as `@import "colors"`. Names match
    # waybar/colors.css, so bar and menus share one vocabulary.
    "rofi/colors.rasi".text = ''
      /* GENERATED from modules/home/themes/${scheme}.nix — edit that, then rebuild. */
      * {
          base:    #${p.base};
          overlay: #${p.overlay};
          text:    #${p.text};
          subtext: #${p.subtext};
          accent:  #${p.accent};
          urgent:  #${p.errColor};
      }
    '';

    # Not `services.swaync` — autostart.conf owns the lifecycle so a restyle
    # applies on reload. docs/adr/0005.
    #
    # ONE generated file, not a hand-written `:root` plus an `@import` of a
    # generated palette the way waybar and rofi are split. swaync's CSS engine
    # is not GTK's, `@import` is not confirmed to work in it, and a stylesheet
    # whose colours silently fail to load renders as "swaync ignored my theme" —
    # so the palette is concatenated at build time instead, where nothing can
    # fail to resolve at runtime. The body stays a hand-written FRAGMENT.
    #
    # The non-colour vars are carried through as literal text. They are settings
    # rather than data and would be better off in the fragment, but they share
    # the one `:root` block, and splitting it into two would reintroduce exactly
    # the runtime-resolution question this avoids.
    "swaync/style.css".text = ''
      /* The `:root` block below is GENERATED from modules/home/palette.nix —
         edit that, then rebuild. The rules after it are hand-written and live
         in dotfiles/swaync/style-body.css. */
      :root {
        --cc-bg: rgba(${channels p.base}, 0.92);
        --noti-border-color: rgba(255, 255, 255, 0.15);
        --noti-bg: ${channels p.base};
        --noti-bg-alpha: 0.92;
        --noti-bg-darker: rgb(30, 30, 30);
        --noti-bg-hover: rgb(50, 50, 50);
        --noti-bg-focus: rgba(60, 60, 60, 0.6);
        --noti-close-bg: rgba(255, 255, 255, 0.1);
        --noti-close-bg-hover: rgba(255, 255, 255, 0.15);
        --text-color: rgb(${channels p.text});
        --text-color-disabled: rgb(150, 150, 150);
        --bg-selected: rgb(${channels p.accent});
        --notification-icon-size: 64px;
        --notification-app-icon-size: calc(var(--notification-icon-size) / 3);
        --notification-group-icon-size: 32px;
        --border: 1px solid var(--noti-border-color);
        --border-radius: 0px;
        --notification-shadow: 0 0 0 1px rgba(0, 0, 0, 0.3),
          0 1px 3px 1px rgba(0, 0, 0, 0.7), 0 2px 6px 2px rgba(0, 0, 0, 0.3);
        --font-size-body: 13px;
        --font-size-summary: 13px;
        --hover-transition: background 0.15s ease-in-out;
        --group-collapse-transition: opacity 400ms ease-in-out;
      }

    ''
    + builtins.readFile ../../dotfiles/swaync/style-body.css;

    # --- Managed as FILES, not directories -----------------------------------
    # Pins the config read-only while leaving the directory writable for sibling
    # runtime files. Cost: no longer changeable from inside the app.
    #
    # GENERATED, because the theme name is the scheme's. It was a hand-written
    # two-line file naming `catppuccin-mocha-mauve`, which made it one of the
    # places a scheme change had to be remembered — and Kvantum falls back to
    # its default style for a theme it cannot find, without a word.
    "Kvantum/kvantum.kvconfig".text = ''
      # GENERATED from modules/home/palette.nix — edit that, then rebuild.
      [General]
      theme=${p.packages.kvantum.name}
    '';

    # theme.nix owns GTK settings, so nwg-look's own state is pinned read-only
    # to stop the GUI fighting it.
    "nwg-look/config".source = ../../dotfiles/nwg-look/config;

    # settings.ini, gtk.css and bookmarks are generated in theme.nix; assets only
    # here.
    "gtk-3.0/assets".source = ../../dotfiles/gtk-3.0/assets;
    "gtk-3.0/colors.css".source = ../../dotfiles/gtk-3.0/colors.css;
    "gtk-4.0/colors.css".source = ../../dotfiles/gtk-4.0/colors.css;

    # --- The one genuine holdout ---------------------------------------------
    # corectrl writes its config from the GUI, which is the point of it.
    "corectrl".source = link "corectrl";
  }
  # Equibop (Discord). A fixed filename, so a scheme switch cannot strand the
  # name settings.json holds.
  // {
    "equibop/themes/palette.theme.css".text = equibopTheme p;
  }
  # The Kvantum theme itself, from the store — but only when the scheme HAS one.
  # All four shipped schemes do; a scheme that instead names a Kvantum built-in
  # (`KvArcDark` and friends, which the style plugin already ships) has nothing
  # to link, and an entry here would point at a path that does not exist. Kept
  # because `packages.kvantum.attr = null` is a supported shape — Dracula and Ayu
  # used it before they were dropped for needing too many stand-ins.
  #
  # Not vendored under dotfiles/: the gruvbox theme this arrangement replaced was
  # a lone .kvconfig this repo carried because nixpkgs had no package for it, and
  # a Kvantum theme is mostly rendered SVG widget art that does not belong in git.
  // lib.optionalAttrs (p.packages.kvantum.attr != null) {
    "Kvantum/${p.packages.kvantum.name}".source =
      "${pkgs.themeKvantum}/share/Kvantum/${p.packages.kvantum.name}";
  };

  # gh, glab-cli, gpu-screen-recorder and opencode hold credentials and are
  # gitignored, so linking them would rename the real directory aside — see
  # docs/SYSTEM.md §11. ~/.zshenv is written by programs.zsh.dotDir.

  # Store-based, not `link`: nothing writes here, Nix keeps the executable bit,
  # and audio.nix has a unit pointing in.
  home.file.".scripts".source = ../../dotfiles/scripts;

  # Removes a stale out-of-store symlink before anything is linked into it —
  # without this, `recursive = true` writes through it into the checkout
  # (docs/adr/0002). Derived from xdg.configFile, never hardcoded: a
  # hand-maintained list missed a batch and clobbered ten tracked files.
  home.activation.unlinkStaleConfigDirs =
    let
      # First path segment only: "gtk-3.0/assets" guards "~/.config/gtk-3.0".
      topLevel = lib.unique (
        map (n: lib.head (lib.splitString "/" n)) (lib.attrNames config.xdg.configFile)
      );
    in
    lib.hm.dag.entryBefore [ "checkLinkTargets" ] (
      lib.concatMapStrings (d: ''
        if [ -L "${config.xdg.configHome}/${d}" ]; then
          run rm $VERBOSE_ARG "${config.xdg.configHome}/${d}"
        fi
      '') topLevel
    );

  # Paths the retired mode switch kept as runtime symlinks, now owned here or
  # gone. A symlink out of the store is in the way of checkLinkTargets, so it is
  # removed first. docs/adr/0061.
  home.activation.unlinkModeLinks = lib.hm.dag.entryBefore [ "checkLinkTargets" ] (
    lib.concatMapStrings
      (f: ''
        l="${config.xdg.configHome}/${f}"
        if [ -L "$l" ] && [[ $(readlink "$l") != /nix/store/* ]]; then
          run rm $VERBOSE_ARG "$l"
        fi
      '')
      [
        "mango/config.conf"
        "kitty/current-theme.conf"
        "foot/themes/noctalia"
        "rofi/colors.rasi"
        "ncspot/config.toml"
        "wayle/config.toml"
      ]
  );

  # Equibop enables a theme by filename from its own settings.json, which it
  # rewrites, so the name is written here rather than declared. No file until
  # it has been launched once.
  home.activation.equibopTheme =
    let
      apply = pkgs.writeShellScript "equibop-theme" ''
        eq="${config.xdg.configHome}/equibop/settings/settings.json"
        [ -f "$eq" ] || exit 0
        ${pkgs.jq}/bin/jq '.enabledThemes = ["palette.theme.css"]' "$eq" > "$eq.tmp" && mv "$eq.tmp" "$eq"
      '';
    in
    lib.hm.dag.entryAfter [ "linkGeneration" ] "run ${apply}\n";

  # Top-level dirs GTK file managers omit from the ~ view (Ctrl+H to show).
  home.file.".hidden".text = ''
    Android
    Applications
    blender
    colors
    go
    log
    R
    share
    temp
    vaults
    winboat
    Zomboid
  '';
}
