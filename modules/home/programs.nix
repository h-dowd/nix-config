# Native home-manager program modules — tier 1, and the default.
#
# The counterpart to ./dotfiles.nix, with the direction of travel toward here.
# Why generated beats a file, which configs are deliberately NOT here (nvim,
# mango, swaync, glow, nwg-look, corectrl) and why: docs/SYSTEM.md §6,
# docs/adr/0009.
{
  config,
  pkgs,
  lib,
  ...
}:

let
  # The palette lived here as a `let` binding until 2026-08-14, which was
  # already the second copy (kitty/gruvbox-orange.conf and
  # foot/gruvbox-colors.ini before it) — and the bar carried a third in
  # waybar/colors.css. One file now, shared with the bar and the menus.
  p = import ./palette.nix;

  # The scheme's NAME, not its colours — Zed's generated theme is named for it
  # and `userSettings.theme` has to say the same word. docs/adr/0041.
  scheme = import ./scheme.nix;

  # swaylock wants `rrggbbaa` and has no separate opacity setting, so the alpha
  # is part of every colour it takes. Two are used: solid, and the wash behind
  # the indicator that lets the background pool through.
  opaque = c: "${c}ff";
  wash = c: "${c}55";
in
{
  # ==========================================================================
  # Terminals
  # ==========================================================================

  # kitty. Was home/kitty/{kitty.conf,gruvbox-orange.conf,tabs.conf}; the three
  # files were split only because kitty.conf `include`d the other two, which is
  # not a distinction worth preserving once Nix generates the whole thing.
  programs.kitty = {
    enable = true;

    font = {
      name = "Hack Nerd Font Mono";
      size = 11;
    };

    settings = {
      # Font. `font_family`/`size` come from `font` above; these are the
      # variants, which that option does not cover.
      # Needs `nerd-fonts._0xproto` in fonts.nix, not `_0xproto` — the family
      # name differs. 0xProto ships no bold-italic, so that variant stays Hack.
      bold_font = "0xProto Nerd Font Mono Bold";
      italic_font = "0xProto Nerd Font Mono Italic";
      symbol_map = "U+E000-U+F8FF,U+100000-U+10FFFF Symbols Nerd Font Mono";
      force_ltr = "no";
      modify_font = "underline_position 2";

      # Cursor
      cursor_shape = "beam";
      cursor_beam_thickness = "1.5";
      cursor_blink_interval = 0;

      # Window
      window_padding_width = "15 20";
      wayland_titlebar_color = "background";

      scrollback_lines = 10000;
      enable_audio_bell = "no";

      # Colours. `inactive_tab_foreground` was `#d5c4a1` here, a literal, and it
      # survived two scheme changes: the drift ceiling greps for hexes the
      # current themes declare, and an orphan from a retired scheme matches
      # none. docs/gotchas.md -> Theming.
      color0 = "#${p.black}";
      color1 = "#${p.red}";
      color2 = "#${p.green}";
      color3 = "#${p.yellow}";
      color4 = "#${p.blue}";
      color5 = "#${p.magenta}";
      color6 = "#${p.cyan}";
      color7 = "#${p.white}";
      color8 = "#${p.brBlack}";
      color9 = "#${p.brRed}";
      color10 = "#${p.brGreen}";
      color11 = "#${p.brYellow}";
      color12 = "#${p.brBlue}";
      color13 = "#${p.brMagenta}";
      color14 = "#${p.brCyan}";
      color15 = "#${p.brWhite}";
      background = "#${p.bg}";
      foreground = "#${p.fg}";
      cursor = "#${p.fg}";
      cursor_text_color = "#${p.bg}";
      selection_foreground = "#${p.bg}";
      selection_background = "#${p.selBg}";
      tab_bar_margin_color = "#${p.bg}";
      tab_bar_background = "#${p.bg}";
      active_tab_foreground = "#${p.bg}";
      active_tab_background = "#${p.brMagenta}";
      inactive_tab_foreground = "#${p.subtext}";
      inactive_tab_background = "#${p.bg}";

      # Tab bar (was tabs.conf, renamed from dank-tabs.conf when DMS was
      # dropped — the name was kept deliberately, the file need not be).
      tab_bar_edge = "top";
      tab_bar_style = "powerline";
      tab_powerline_style = "slanted";
      tab_bar_align = "left";
      tab_bar_min_tabs = 2;
      tab_bar_margin_width = "0.0";
      tab_bar_margin_height = "2.5 1.5";
      active_tab_font_style = "bold";
      inactive_tab_font_style = "normal";
      tab_activity_symbol = ''" ● "'';
      # The quotes are part of the VALUE, not Nix syntax — kitty needs them to
      # keep the template as one token.
      tab_title_template = ''"{fmt.fg.red}{bell_symbol}{activity_symbol}{fmt.fg.tab}{title[:30]}{title[30:] and '…'} [{index}]"'';
      active_tab_title_template = ''"{fmt.fg.red}{bell_symbol}{activity_symbol}{fmt.fg.tab}{title[:30]}{title[30:] and '…'} [{index}]"'';
    };
  };

  # foot. The `[colors-dark]` section name is carried over verbatim from
  # home/foot/gruvbox-colors.ini rather than flattened to `[colors]` — that is
  # what the machine runs today, and this pass is meant to change ownership,
  # not appearance.
  programs.foot = {
    enable = true;
    settings = {
      main = {
        shell = "zsh";
        title = "foot";
        font = "Hack Nerd Font Mono:size=11";
        letter-spacing = 0;
        dpi-aware = "no";
        pad = "20x15";
        bold-text-in-bright = "no";
        gamma-correct-blending = "no";
      };

      scrollback.lines = 10000;

      cursor = {
        style = "beam";
        beam-thickness = "1.5";
      };

      # `[colors-dark]`, the section foot 1.27 reads by default.
      colors-dark = {
        foreground = p.fg;
        background = p.bg;
        selection-foreground = p.fg;
        selection-background = p.selBg;
        regular0 = p.black;
        regular1 = p.red;
        regular2 = p.green;
        regular3 = p.yellow;
        regular4 = p.blue;
        regular5 = p.magenta;
        regular6 = p.cyan;
        regular7 = p.white;
        bright0 = p.brBlack;
        bright1 = p.brRed;
        bright2 = p.brGreen;
        bright3 = p.brYellow;
        bright4 = p.brBlue;
        bright5 = p.brMagenta;
        bright6 = p.brCyan;
        bright7 = p.brWhite;
      };

      key-bindings = {
        scrollback-up-page = "Page_Up";
        scrollback-down-page = "Page_Down";
        search-start = "Control+Shift+f";
      };

      search-bindings = {
        cancel = "Escape";
        find-prev = "Shift+F3";
        find-next = "F3 Control+G";
      };
    };
  };

  # ==========================================================================
  # Editors
  # ==========================================================================

  # nvim is the editor; helix was removed 2026-08-17 (docs/adr/0027). Nothing
  # here generates nvim config — it is a store-linked tree, see dotfiles.nix.

  # zed. This one is a straight WIN over the file it replaces, and the reason is
  # worth knowing because it is the technique to reach for elsewhere.
  #
  # dotfiles.nix pinned zed/settings.json as a read-only store file, so Zed's
  # own settings UI could not write to it at all. This module does not link a
  # file: it runs an activation script (`entryAfter [ "linkGeneration" ]`, so
  # after the old symlink is cleaned up) that merges the Nix-declared settings
  # INTO the real, writable ~/.config/zed/settings.json with
  # `jq -n '$dynamic * $static'`. Static wins on conflict.
  #
  # So Zed stays free to persist its own state, while everything declared here
  # is reasserted on every rebuild. Declarative config and a writable file are
  # not actually in tension — that framing was an artefact of only having
  # symlinks to work with.
  programs.zed-editor = {
    enable = true;

    # No theme extension: the theme is GENERATED from the palette and written
    # into ~/.config/zed/themes/ by `themes` below. docs/adr/0041.
    extensions = [ ];

    # The generated theme, named for the scheme. `themes` accepts a store path,
    # so this is the derivation itself rather than an attrset Nix has to
    # re-serialise.
    themes.${scheme} = pkgs.themeZed;

    userSettings = {
      project_panel.dock = "left";
      outline_panel.dock = "left";
      collaboration_panel.dock = "left";
      git_panel.dock = "left";

      agent = {
        dock = "right";
        favorite_models = [ ];
        model_parameters = [ ];
      };

      # MCP agent servers. `type = "registry"` means Zed resolves the command
      # itself; the binaries still have to be on PATH (packages.nix).
      agent_servers = {
        opencode.type = "registry";
        claude-acp.type = "registry";
        github-copilot-cli.type = "registry";
      };

      telemetry = {
        diagnostics = false;
        metrics = false;
      };

      icon_theme = {
        mode = "system";
        light = "Zed (Default)";
        dark = "JetBrains New UI Icons (Dark)";
      };

      # A theme name Zed cannot resolve leaves it on One Dark and logs nothing.
      # That used to be unguardable — the theme came from Zed's own registry,
      # so this file could assert that a name was DECLARED and nothing more,
      # and the first launch after a scheme change showed the fallback while
      # the extension installed. The theme is generated into the generation
      # now, so `checks/static.sh` asserts the file exists, carries this
      # palette, and is named what this names. docs/adr/0041.
      #
      # `light` and `dark` are the same name deliberately: one theme is
      # generated, `appearance` is dark, and this machine runs dark
      # (`gtk.colorScheme = "dark"`), so the light slot is never resolved.
      theme = {
        mode = "system";
        light = scheme;
        dark = scheme;
      };

      buffer_font_family = "Hack Nerd Font Mono";
      buffer_font_size = 16.0;
      ui_font_size = 16;
      vim_mode = true;
      base_keymap = "VSCode";
    };
  };

  # ==========================================================================
  # TUI tools
  # ==========================================================================

  # No `screen:Main=` / `screen:I/O=` blocks: they restate htop's own defaults
  # and are ORDER-SENSITIVE, while the module emits settings sorted by
  # attribute name — expressing them here would break the association. Omitted,
  # htop falls back to exactly these defaults.
  #
  # htoprc is read-only, so UI changes do not persist. Unchanged from before.
  programs.htop = {
    enable = true;
    settings = {
      fields = with config.lib.htop.fields; [
        PID
        USER
        PRIORITY
        NICE
        M_VIRT
        M_RESIDENT
        M_PRIV
        STATE
        PERCENT_CPU
        PERCENT_MEM
        TIME
        COMM
      ];

      hide_kernel_threads = true;
      hide_userland_threads = false;
      hide_running_in_container = false;
      shadow_other_users = false;
      show_thread_names = false;
      show_program_path = true;
      highlight_base_name = false;
      highlight_deleted_exe = true;
      shadow_distribution_path_prefix = false;
      highlight_megabytes = true;
      highlight_threads = true;
      highlight_changes = false;
      highlight_changes_delay_secs = 5;
      find_comm_in_cmdline = true;
      strip_exe_from_cmdline = true;
      show_merged_command = false;
      header_margin = true;
      screen_tabs = true;
      detailed_cpu_time = false;
      cpu_count_from_one = false;
      show_cpu_smt_labels = false;
      show_cpu_usage = true;
      show_cpu_frequency = false;
      show_cpu_temperature = false;
      degree_fahrenheit = false;
      show_cached_memory = true;
      update_process_names = false;
      account_guest_in_cpu_meter = false;
      color_scheme = 0;
      enable_mouse = true;
      delay = 15;
      hide_function_bar = 0;
      header_layout = "two_50_50";

      tree_view = false;
      sort_key = config.lib.htop.fields.PERCENT_CPU;
      tree_sort_key = config.lib.htop.fields.PID;
      sort_direction = -1;
      tree_sort_direction = 1;
      tree_view_always_by_pid = false;
      all_branches_collapsed = false;
    }
    # Meter modes: `bar` is htop mode 1, `text` is mode 2 — the old file's
    # `column_meter_modes_0=1 1 1` / `..._1=1 2 2 2`.
    // (
      with config.lib.htop;
      leftMeters [
        (bar "LeftCPUs2")
        (bar "Memory")
        (bar "Swap")
      ]
    )
    // (
      with config.lib.htop;
      rightMeters [
        (bar "RightCPUs2")
        (text "Tasks")
        (text "LoadAverage")
        (text "Uptime")
      ]
    );
  };

  # yazi. The flavor is a `.yazi` package directory, which is what the `flavors`
  # option takes — so it is assembled in the overlay from upstream's own file
  # rather than transcribed. 916 lines of third-party hex, and not ours to edit.
  programs.yazi = {
    enable = true;

    # The `y` wrapper — run yazi, then cd to wherever it exited. This used to be
    # a hand-written `y()` in zsh/conf.d/10-aliases.zsh while home-manager
    # separately emitted its own `yy()` into ~/.zshrc: two near-identical
    # definitions of one function, coexisting only because their names happened
    # to differ. home-manager is changing this default from `yy` to `y`, which
    # would have made them collide, with the winner decided by source order
    # (conf.d is sourced last, so the hand-written one would have won silently).
    # Set explicitly, and deleted from 10-aliases.zsh — one owner.
    shellWrapperName = "y";

    # `scheme`, not the scheme's name: the flavor package follows
    # modules/home/scheme.nix, so a name here would be wrong four schemes out of
    # five — the same reason Equibop's generated theme file is `scheme.theme.css`.
    flavors.scheme = pkgs.themeYazi;
    theme.flavor = {
      dark = "scheme";
      light = "scheme";
    };
  };

  # Drawn entirely from `muted`, and asserted so. `highlight_fg` / `error_fg`,
  # not `highlight_bg` / `error` — ncspot drops keys it does not know, silently.
  programs.ncspot = {
    enable = true;
    settings.theme =
      let
        m = p.muted;
      in
      {
        background = "#${m.bg}";
        primary = "#${m.fg}";
        secondary = "#${m.dim}";
        title = "#${m.accent}";
        playing = "#${m.ok}";
        playing_selected = "#${m.ok}";
        playing_bg = "#${m.surface}";
        highlight = "#${m.overlay}";
        highlight_fg = "#${m.fg}";
        error_bg = "#${m.err}";
        error_fg = "#${m.fg}";
        statusbar_progress = "#${m.accent}";
        statusbar_progress_bg = "#${m.overlay}";
        statusbar = "#${m.fg}";
        statusbar_bg = "#${m.surface}";
        cmdline = "#${m.fg}";
        cmdline_bg = "#${m.surface}";
        search_match = "#${m.accent}";
        border = "#${m.overlay}";
      };
  };


  # imv. The palette's lightest foreground as the background, so black SVGs and
  # icons stay visible.
  programs.imv = {
    enable = true;
    settings.options.background = p.fg;
  };

  # ==========================================================================
  # Lock screen
  # ==========================================================================

  # The ONE swaylock config. Every hands-off lock path goes through
  # `lockscreen -f` — swayidle on sleep, wlogout, the binds — and that wrapper
  # execs swaylock, so they all still read this file. It replaces the per-mode
  # per-mode mango/*/swaylock.conf files, and an untracked hand-written
  # ~/.config/swaylock/config that had been quietly supplying the theme.
  #
  # `image` is deliberately NOT set here: the wrapper passes `-i` per lock so
  # the pattern varies (docs/adr/0018). `color` stays as the fallback for when
  # the pool is empty.
  #
  # `package = null` is load-bearing: desktop.nix installs swaylock-EFFECTS
  # system-wide and PAM is declared for it. Plain `swaylock` from home-manager
  # would shadow it in PATH and does not have `clock` — which it reports by
  # dumping usage and exiting 0. See docs/gotchas.md for the parse check.
  programs.swaylock = {
    enable = true;
    package = null;

    settings = {
      # A swaylock screen with nothing drawn on it is indistinguishable from a
      # machine that is off or hung. The clock ticks, which is the proof of
      # life; the ring is where typing shows up. Both are swaylock-effects
      # extensions — plain swaylock has neither.
      clock = true;
      indicator = true;
      indicator-idle-visible = true;
      timestr = "%H:%M";
      datestr = "%a %e %b";

      indicator-caps-lock = true;
      show-failed-attempts = true;

      # Colours come from palette.nix, not from hex typed here. Two of them did
      # not: the ring and the keypress highlight were gruvbox ORANGE (d65d0e,
      # fe8019), a shade this machine uses nowhere else, so the lock screen was
      # the one surface whose accent disagreed with the bar, the menus and the
      # window borders — and a drifted palette looks deliberate. `opaque` and
      # `wash` spell the two alpha values the indicator needs.
      color = opaque p.bg0;
      # The pool is generated at the panel's native 1920x1200, so `fill` scales
      # by exactly 1 and the block edges stay hard. swaylock resamples with
      # CAIRO_FILTER_BILINEAR, so an external output at another resolution gets
      # a softened copy — cosmetic, and only on that output.
      scaling = "fill";
      font = "Hack Nerd Font Mono";
      # Sized to the indicator, not to the screen: this is also the "Verifying"
      # and "Wrong" text, which has to fit inside the ring.
      font-size = 20;
      indicator-radius = 100;
      indicator-thickness = 7;

      inside-color = wash p.bg0;
      inside-clear-color = wash p.bg0;
      inside-ver-color = wash p.blue;
      inside-wrong-color = wash p.errColor;

      ring-color = opaque p.accent;
      ring-clear-color = opaque p.okColor;
      ring-ver-color = opaque p.blue;
      ring-wrong-color = opaque p.errColor;

      key-hl-color = opaque p.warnColor;
      bs-hl-color = opaque p.errColor;

      text-color = opaque p.text;
      text-clear-color = opaque p.text;
      text-ver-color = opaque p.infoColor;
      text-wrong-color = opaque p.errColor;
      text-caps-lock-color = opaque p.warnColor;

      # Fully transparent — the ring carries the state, the lines only add
      # edges to it.
      line-color = "00000000";
      line-clear-color = "00000000";
      line-ver-color = "00000000";
      line-wrong-color = "00000000";
      separator-color = "00000000";
    };
  };

  # ==========================================================================
  # Session menu
  # ==========================================================================

  # Each icon is interpolated as its OWN store path, never a relative url():
  # `style` renders to a lone .css with no directory beside it, and GTK draws
  # its missing-image box for a failed url() without logging. docs/gotchas.md
  # → Desktop.
  programs.wlogout = {
    enable = true;

    layout = [
      {
        label = "lock";
        action = "${pkgs.lockscreen}/bin/lockscreen -f";
        text = "Lock";
        keybind = "l";
      }
      {
        label = "logout";
        action = "loginctl terminate-user $USER";
        text = "Logout";
        keybind = "e";
      }
      {
        label = "suspend";
        action = "systemctl suspend";
        text = "Suspend";
        keybind = "u";
      }
      # Same S4 the lid and the power key reach; here for discoverability.
      {
        label = "hibernate";
        action = "systemctl hibernate";
        text = "Hibernate";
        keybind = "h";
      }
      {
        label = "reboot";
        action = "systemctl reboot";
        text = "Reboot";
        keybind = "r";
      }
      {
        label = "shutdown";
        action = "systemctl poweroff";
        text = "Shutdown";
        keybind = "s";
      }
    ];

    style = ''
      * {
          background-image: none;
          box-shadow: none;
          font-family: "Hack Nerd Font", monospace;
      }

      window {
          background-color: rgba(32, 27, 20, 0.88);
      }

      /* padding/margin are deliberately small — the button is sized by the
         wlogout margins in waybar.nix, and these only add dead space to it. */
      button {
          font-size: 20px;
          color: #7a6a50;
          background-color: rgba(46, 39, 32, 0.8);
          border: 2px solid rgba(61, 53, 44, 1.0);
          border-radius: 10px;
          margin: 8px;
          padding: 8px;
          background-repeat: no-repeat;
          background-position: center 30%;
          background-size: 52px 52px;
          transition: background-color 0.15s ease, color 0.15s ease, border-color 0.15s ease;
      }

      button:hover {
          background-color: rgba(61, 53, 44, 0.9);
          border-color: #c9b890;
          color: #c9b890;
      }

      button:active {
          background-color: #c9b890;
          color: #201b14;
      }

      #lock {
          background-image: image(url("${../../dotfiles/wlogout/icons/lock.png}"));
      }

      #logout {
          background-image: image(url("${../../dotfiles/wlogout/icons/logout.png}"));
      }

      #suspend {
          background-image: image(url("${../../dotfiles/wlogout/icons/suspend.png}"));
      }

      #hibernate {
          background-image: image(url("${../../dotfiles/wlogout/icons/hibernate.png}"));
      }

      #reboot {
          background-image: image(url("${../../dotfiles/wlogout/icons/reboot.png}"));
      }

      #shutdown {
          background-image: image(url("${../../dotfiles/wlogout/icons/shutdown.png}"));
      }
    '';
  };
}
