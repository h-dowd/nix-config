# tmux, from the desktop's henry/dotfiles (itself henry/macdots). kitty runs it
# in every window; foot stays the terminal without it. docs/adr/0063
{
  pkgs,
  lib,
  ...
}:

let
  p = import ./palette.nix;
  c = x: "#${x}";

  # The ⌘ keys kitty hands to tmux. One table, three consumers: kitty maps the
  # Super combo to "\e[<9000+n>~", tmux binds that as User<n>, and keyd's
  # app.conf sends ⌘ to kitty as Super. Keys mango binds on ⌘ (Space, Q, Tab,
  # ⇧3, ⇧4, ⇧V…) never reach kitty, so they are not here.
  cmdKeys = [
    # Panes
    { n = 0; key = "d"; }
    { n = 1; key = "d"; shift = true; }
    { n = 2; key = "h"; }
    { n = 3; key = "j"; }
    { n = 4; key = "k"; }
    { n = 5; key = "l"; }
    { n = 30; key = "h"; shift = true; }
    { n = 31; key = "j"; shift = true; }
    { n = 32; key = "k"; shift = true; }
    { n = 33; key = "l"; shift = true; }
    { n = 54; key = "h"; shift = true; ctrl = true; }
    { n = 55; key = "j"; shift = true; ctrl = true; }
    { n = 56; key = "k"; shift = true; ctrl = true; }
    { n = 57; key = "l"; shift = true; ctrl = true; }
    { n = 58; key = "c"; shift = true; }
    { n = 48; key = "grave"; }
    { n = 6; key = "a"; }
    { n = 7; key = "s"; shift = true; }
    { n = 9; key = "t"; shift = true; }
    { n = 37; key = "b"; shift = true; }
    { n = 18; key = "r"; }
    { n = 11; key = "w"; }
    { n = 49; key = "enter"; }
    # Windows
    { n = 10; key = "t"; }
    { n = 19; key = "1"; }
    { n = 20; key = "2"; }
    { n = 21; key = "3"; }
    { n = 22; key = "4"; }
    { n = 23; key = "5"; }
    { n = 24; key = "6"; }
    { n = 25; key = "7"; }
    { n = 26; key = "8"; }
    { n = 27; key = "9"; }
    { n = 38; key = "1"; shift = true; }
    { n = 39; key = "2"; shift = true; }
    { n = 42; key = "5"; shift = true; }
    { n = 43; key = "6"; shift = true; }
    { n = 44; key = "7"; shift = true; }
    { n = 45; key = "8"; shift = true; }
    { n = 46; key = "9"; shift = true; }
    { n = 28; key = "["; shift = true; }
    { n = 29; key = "]"; shift = true; }
    { n = 17; key = ","; shift = true; }
    # Sessions
    { n = 34; key = "p"; }
    { n = 35; key = "n"; shift = true; }
    { n = 36; key = "."; shift = true; }
    # Scrollback
    { n = 12; key = "f"; }
    { n = 13; key = "x"; shift = true; }
    { n = 15; key = "up"; }
    { n = 16; key = "down"; }
    { n = 50; key = "page_up"; }
    { n = 51; key = "page_down"; }
    { n = 52; key = "home"; }
    { n = 53; key = "end"; }
  ];

  # ⌘ keys kitty keeps for itself.
  kittyActions = [
    { key = "n"; action = "new_os_window"; }
    { key = "r"; shift = true; action = "load_config_file"; }
  ];

  shift = k: k.shift or false;
  ctrl = k: k.ctrl or false;
  seq = n: "\\x1b[${toString (9000 + n)}~";

  kittyCombo =
    k:
    lib.concatStringsSep "+" (
      lib.optional (ctrl k) "ctrl" ++ [ "super" ] ++ lib.optional (shift k) "shift" ++ [ k.key ]
    );

  keydKey =
    k:
    {
      "[" = "leftbrace";
      "]" = "rightbrace";
      "," = "comma";
      "." = "dot";
      page_up = "pageup";
      page_down = "pagedown";
    }
    .${k.key} or k.key;
  # Composite layers keyd/default.conf defines; `keyd bind` finds them by name.
  keydLayer =
    k:
    if ctrl k then
      "control+cmd+shift"
    else if shift k then
      "cmd+shift"
    else
      "cmd";
  keydOut = k: lib.optionalString (ctrl k) "C-" + "M-" + lib.optionalString (shift k) "S-" + keydKey k;
  keydLine = k: "${keydLayer k}.${keydKey k} = ${keydOut k}";
in
{
  programs.tmux = {
    enable = true;
    prefix = "C-s";
    baseIndex = 1;
    historyLimit = 50000;
    mouse = true;
    keyMode = "vi";
    focusEvents = true;
    # home-manager's defaults are 500ms and `screen`; tmux's own are these.
    escapeTime = 10;
    terminal = "tmux-256color";
    sensibleOnTop = false;

    # Plugins load at the end, by hand: continuum appends its save hook to
    # status-right, so it has to run after the theme sets it.
    extraConfig = ''
      # C-s costs zsh's forward history search, which fzf's C-r replaces.

      # --- Terminal ------------------------------------------------------------
      set -as terminal-features ",xterm-kitty:RGB:hyperlinks:usstyle"
      set -as terminal-features ",foot:RGB:hyperlinks:usstyle"
      # OSC 52 from programs inside, image escapes through to kitty.
      set -g set-clipboard on
      set -g allow-passthrough on

      setw -g pane-base-index 1
      set -g renumber-windows on
      set -g status-interval 5

      # --- Panes ---------------------------------------------------------------
      # hjkl beside the arrow defaults; l was last-window, now on Tab.
      bind -r h select-pane -L
      bind -r j select-pane -D
      bind -r k select-pane -U
      bind -r l select-pane -R
      bind Tab last-window

      # AeroSpace's move and join-with, applied to the layout tree.
      %hidden tree="~/.config/tmux/tree.py"
      bind -r H run-shell "$tree move left #{pane_id}"
      bind -r J run-shell "$tree move down #{pane_id}"
      bind -r K run-shell "$tree move up #{pane_id}"
      bind -r L run-shell "$tree move right #{pane_id}"
      bind C-h run-shell "$tree join left #{pane_id}"
      bind C-j run-shell "$tree join down #{pane_id}"
      bind C-k run-shell "$tree join up #{pane_id}"
      bind C-l run-shell "$tree join right #{pane_id}"

      # --- Splits and windows --------------------------------------------------
      # s below, v right, as :split and :vsplit; shift spans the whole window.
      # Every split opens in the pane's directory.
      bind s split-window -v -c "#{pane_current_path}"
      bind v split-window -h -c "#{pane_current_path}"
      bind S split-window -fv -c "#{pane_current_path}"
      bind V split-window -fh -c "#{pane_current_path}"
      bind | split-window -h  -c "#{pane_current_path}"
      bind - split-window -v  -c "#{pane_current_path}"
      bind \\ split-window -fh -c "#{pane_current_path}"
      bind _ split-window -fv -c "#{pane_current_path}"
      bind % split-window -h -c "#{pane_current_path}"
      bind '"' split-window -v -c "#{pane_current_path}"
      bind c new-window      -c "#{pane_current_path}"

      # Confirm by repeating the key: x x kills the pane, X X the window.
      bind x confirm-before -c x -p "kill pane #P? (x/n)" kill-pane
      bind X confirm-before -c X -p "kill window #W? (X/n)" kill-window
      # The mirror of break-pane (!): pull the last pane back in.
      bind @ join-pane -h -s !
      bind R source-file ~/.config/tmux/tmux.conf \; display-message "tmux.conf reloaded"

      # --- Copy mode -----------------------------------------------------------
      bind Space copy-mode
      bind -T copy-mode-vi v send-keys -X begin-selection
      bind -T copy-mode-vi y send-keys -X copy-pipe-and-cancel "${pkgs.wl-clipboard}/bin/wl-copy"
      bind -T copy-mode-vi Escape send-keys -X cancel

      # --- Sessions, layouts, popup --------------------------------------------
      bind -r C-n switch-client -n
      bind -r C-p switch-client -p
      bind a choose-tree -Zs
      bind C-Space next-layout
      bind e setw synchronize-panes \; display-message "synchronize-panes #{?pane_synchronized,on,off}"
      bind Enter display-popup -E -d "#{pane_current_path}" -w 80% -h 80%

      # Unnamed sessions end with the window that shows them; a named one is kept
      # (cmd+shift+n, ts, tmux new -s, or renamed later). Grouped views stay
      # throwaway, and renaming back to a number makes a session throwaway again.
      set -g destroy-unattached on
      %hidden kept='#{&&:#{!:#{m/r:^[0-9]+$,#{session_name}}},#{!:#{session_grouped}}}'
      set-hook -g session-created "if -F '$kept' 'set destroy-unattached off'"
      set-hook -g session-renamed "if -F '$kept' 'set destroy-unattached off' 'set destroy-unattached on'"

      # --- ⌘ keys --------------------------------------------------------------
      # kitty sends "\e[<9000+n>~" for each; the table is in modules/home/tmux.nix.
      ${lib.concatMapStringsSep "\n" (
        k: ''set -s user-keys[${toString k.n}] "\e[${toString (9000 + k.n)}~"''
      ) cmdKeys}

      # Panes
      bind -n User0  split-window -h -c "#{pane_current_path}"
      bind -n User1  split-window -v -c "#{pane_current_path}"
      bind -n User2  select-pane -L
      bind -n User3  select-pane -D
      bind -n User4  select-pane -U
      bind -n User5  select-pane -R
      bind -n User30 run-shell "$tree move left #{pane_id}"
      bind -n User31 run-shell "$tree move down #{pane_id}"
      bind -n User32 run-shell "$tree move up #{pane_id}"
      bind -n User33 run-shell "$tree move right #{pane_id}"
      bind -n User54 run-shell "$tree join left #{pane_id}"
      bind -n User55 run-shell "$tree join down #{pane_id}"
      bind -n User56 run-shell "$tree join up #{pane_id}"
      bind -n User57 run-shell "$tree join right #{pane_id}"
      bind -n User58 run-shell "$tree flatten #{pane_id}"
      bind -n User48 last-pane
      bind -n User6  resize-pane -Z
      bind -n User7  display-panes -d 0 { swap-pane -t "%%" }
      bind -n User9  break-pane
      bind -n User37 select-layout -E
      bind -n User18 switch-client -T resize
      bind -n User11 kill-pane
      bind -n User49 display-popup -E -d "#{pane_current_path}" -w 80% -h 80%

      # Windows
      bind -n User10 new-window -c "#{pane_current_path}"
      bind -n User19 select-window -t :1
      bind -n User20 select-window -t :2
      bind -n User21 select-window -t :3
      bind -n User22 select-window -t :4
      bind -n User23 select-window -t :5
      bind -n User24 select-window -t :6
      bind -n User25 select-window -t :7
      bind -n User26 select-window -t :8
      bind -n User27 select-window -t :$
      bind -n User38 if -F "#{W:#{?#{==:#{window_index},1},1,}}" "join-pane -t :1" "break-pane -t :1"
      bind -n User39 if -F "#{W:#{?#{==:#{window_index},2},1,}}" "join-pane -t :2" "break-pane -t :2"
      bind -n User42 if -F "#{W:#{?#{==:#{window_index},5},1,}}" "join-pane -t :5" "break-pane -t :5"
      bind -n User43 if -F "#{W:#{?#{==:#{window_index},6},1,}}" "join-pane -t :6" "break-pane -t :6"
      bind -n User44 if -F "#{W:#{?#{==:#{window_index},7},1,}}" "join-pane -t :7" "break-pane -t :7"
      bind -n User45 if -F "#{W:#{?#{==:#{window_index},8},1,}}" "join-pane -t :8" "break-pane -t :8"
      bind -n User46 if -F "#{W:#{?#{==:#{window_index},9},1,}}" "join-pane -t :9" "break-pane -t :9"
      bind -n User28 previous-window
      bind -n User29 next-window
      bind -n User17 command-prompt -I "#W" { rename-window "%%" }

      # Sessions
      bind -n User34 choose-tree -Zs
      bind -n User35 command-prompt -p "new session:" { new-session -d -s "%%" -c "#{pane_current_path}" ; switch-client -t "%%" }
      bind -n User36 command-prompt -I "#S" -p "keep session as:" { rename-session "%%" }

      # Scrollback
      bind -n User12 copy-mode \; command-prompt -T search -p "(search up)" { send -X search-backward "%%" }
      bind -n User13 copy-mode
      bind -n User15 copy-mode \; send -X previous-prompt
      bind -n User16 copy-mode \; send -X next-prompt
      bind -n User50 if -F "#{pane_in_mode}" "send -X page-up" "copy-mode -u"
      bind -n User51 if -F "#{pane_in_mode}" "send -X page-down"
      bind -n User52 copy-mode \; send -X history-top
      bind -n User53 if -F "#{pane_in_mode}" "send -X cancel"

      # Resize mode (⌘R): h/l narrower/wider, j/k taller/shorter, shift for 10,
      # b balances; Esc, q or Enter leaves.
      bind -T resize h if -F "#{pane_at_right}" "resize-pane -R 3" "resize-pane -L 3" \; switch-client -T resize
      bind -T resize H if -F "#{pane_at_right}" "resize-pane -R 10" "resize-pane -L 10" \; switch-client -T resize
      bind -T resize l if -F "#{pane_at_right}" "resize-pane -L 3" "resize-pane -R 3" \; switch-client -T resize
      bind -T resize L if -F "#{pane_at_right}" "resize-pane -L 10" "resize-pane -R 10" \; switch-client -T resize
      bind -T resize j if -F "#{pane_at_bottom}" "resize-pane -U 3" "resize-pane -D 3" \; switch-client -T resize
      bind -T resize J if -F "#{pane_at_bottom}" "resize-pane -U 10" "resize-pane -D 10" \; switch-client -T resize
      bind -T resize k if -F "#{pane_at_bottom}" "resize-pane -D 3" "resize-pane -U 3" \; switch-client -T resize
      bind -T resize K if -F "#{pane_at_bottom}" "resize-pane -D 10" "resize-pane -U 10" \; switch-client -T resize
      bind -T resize b select-layout -E
      bind -T resize Escape switch-client -T root
      bind -T resize q switch-client -T root
      bind -T resize Enter switch-client -T root

      # --- Theme, from the palette ---------------------------------------------
      # The session block is the mode light: accent normally, warn with a prefix
      # pending, info in resize mode, brMagenta in copy mode. The active pane
      # border is mango's focus_color, so pane and window focus look the same.
      set -g status-style "fg=${c p.subtext},bg=${c p.surface}"
      %hidden mode_bg='#{?client_prefix,#[bg=${c p.warnColor}],#{?#{==:#{client_key_table},resize},#[bg=${c p.infoColor}],#{?pane_in_mode,#[bg=${c p.brMagenta}],#[bg=${c p.accent}]}}}'
      set -g status-left "#[fg=${c p.mantle}]#[bold]''${mode_bg} #S #[default] "
      set -g status-left-length 40
      set -g status-right "#{?client_prefix,#[fg=${c p.mantle}]#[bg=${c p.warnColor}]#[bold] PREFIX #[default] ,}#{?#{==:#{client_key_table},resize},#[fg=${c p.mantle}]#[bg=${c p.infoColor}]#[bold] RESIZE #[default] ,}#{?pane_in_mode,#[fg=${c p.mantle}]#[bg=${c p.brMagenta}]#[bold] #{pane_mode} #[default] ,}#[fg=${c p.comment}]%H:%M "
      set -g status-right-length 60

      setw -g window-status-style "fg=${c p.subtext}"
      setw -g window-status-format " #I #W "
      setw -g window-status-current-style "fg=${c p.fg},bg=${c p.overlay},bold"
      setw -g window-status-current-format " #[fg=${c p.accent}]#I #[fg=${c p.fg}]#W#{?window_zoomed_flag, #[fg=${c p.warnColor}]Z,} "
      setw -g window-status-separator ""
      setw -g window-status-bell-style "fg=${c p.mantle},bg=${c p.errColor},bold"

      set -g pane-border-style "fg=${c p.overlay}"
      set -g pane-active-border-style "fg=${c p.accent}"
      set -g message-style "fg=${c p.warnColor},bg=${c p.mantle}"
      set -g message-command-style "fg=${c p.warnColor},bg=${c p.mantle}"
      set -g mode-style "fg=${c p.fg},bg=${c p.selBg}"
      set -g clock-mode-colour "${c p.accent}"
      set -g display-panes-active-colour "${c p.accent}"
      set -g display-panes-colour "${c p.overlay}"

      # --- Plugins -------------------------------------------------------------
      # resurrect saves sessions, layouts and directories; continuum saves every
      # 15 minutes and restores on server start. Only named sessions are saved.
      set -g @resurrect-save 'C-w'
      set -g @resurrect-restore 'C-r'
      set -g @resurrect-hook-post-save-layout '~/.config/tmux/resurrect-keep-named.sh'
      set -g @continuum-restore 'on'
      run-shell ${pkgs.tmuxPlugins.resurrect}/share/tmux-plugins/resurrect/resurrect.tmux
      run-shell ${pkgs.tmuxPlugins.continuum}/share/tmux-plugins/continuum/continuum.tmux
    '';
  };

  xdg.configFile."tmux/tree.py".source = ../../dotfiles/tmux/tree.py;
  xdg.configFile."tmux/resurrect-keep-named.sh".source = ../../dotfiles/tmux/resurrect-keep-named.sh;

  programs.kitty = {
    settings.shell = "tmux new-session";
    keybindings =
      lib.listToAttrs (map (k: lib.nameValuePair (kittyCombo k) "send_text all ${seq k.n}") cmdKeys)
      // lib.listToAttrs (map (k: lib.nameValuePair (kittyCombo k) k.action) kittyActions)
      // {
        # ⌃Tab and ⌃⇧Tab are plain Ctrl and need no keyd line.
        "ctrl+tab" = "send_text all ${seq 29}";
        "ctrl+shift+tab" = "send_text all ${seq 28}";
      };
  };

  # Merged with the [kitty] section in default.nix; the mapper applies both.
  xdg.configFile."keyd/app.conf".text = ''

    # ⌘ to kitty as Super, for the maps above.
    [kitty]
    ${lib.concatMapStringsSep "\n" keydLine (cmdKeys ++ kittyActions)}
  '';
}
