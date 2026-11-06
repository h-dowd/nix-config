{
  config,
  pkgs,
  lib,
  ...
}:

{
  time.timeZone = "Europe/Dublin";

  i18n.defaultLocale = "en_GB.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_GB.UTF-8";
    LC_IDENTIFICATION = "en_GB.UTF-8";
    LC_MEASUREMENT = "en_GB.UTF-8";
    LC_MONETARY = "en_GB.UTF-8";
    LC_NAME = "en_GB.UTF-8";
    LC_NUMERIC = "en_GB.UTF-8";
    LC_PAPER = "en_GB.UTF-8";
    LC_TELEPHONE = "en_GB.UTF-8";
    LC_TIME = "en_GB.UTF-8";
  };

  # From /etc/vconsole.conf
  console.keyMap = "uk";

  # From /etc/vconsole.conf (XKBLAYOUT=gb, XKBOPTIONS=terminate:ctrl_alt_bksp)
  services.xserver.xkb = {
    layout = "gb";
    model = "pc105";
    options = "terminate:ctrl_alt_bksp";
  };

  # keyd: the desktop's Mac positions (Super = ⌥, Alt = ⌘), Caps nav/Esc, Right
  # Alt typst. mango's side and the scheme: docs/adr/0062. Raw keyd syntax;
  # `keyd check` validates it, and the daemon only warns on a bad line.
  services.keyd = {
    enable = true;
    keyboards.default = {
      ids = [ "*" ];
      extraConfig = ''
        [main]

        leftmeta+leftshift+f23 = sysrq

        # ⌥: every combo goes to mango and apps as Alt.
        leftmeta = layer(alt)
        # ⌘: Ctrl for apps (⌘C copies), except the keys mango binds below.
        leftalt = layer(cmd)
        capslock = overload(nav, esc)
        rightalt = layer(typst)

        [cmd:C]
        space = C-M-A-space
        q = C-M-A-q
        , = C-M-A-,
        # Held: the swap keeps Super+Ctrl down until ⌘ is released, which is
        # when mango's switcher selects.
        tab = swapm(cmdtab, C-M-tab)
        # Line start and end, as on the Mac; with ⇧, select to there.
        left = home
        right = end

        [cmdtab:C-M]

        # ⌘⇧
        [cmd+shift]
        3 = C-M-A-S-3
        4 = C-M-A-S-4
        v = C-M-A-S-v
        tab = swapm(cmdtab, C-M-S-tab)
        left = S-home
        right = S-end

        # ⌥⌘
        [alt+cmd]
        h = C-M-A-h
        l = C-M-A-l
        esc = C-M-A-esc

        # ⌃⌘
        [control+cmd]
        q = C-M-A-S-q
        \ = C-M-A-S-\
        backspace = C-M-A-S-backspace

        [nav]
        h = left
        j = down
        k = up
        l = right
        ; = home
        ' = end
        u = pageup
        i = pagedown
        f = backspace
        d = delete

        [typst]
        a = macro(a l p h a)
        b = macro(b e t a)
        e = macro(e p s i l o n)
        g = macro(g a m m a)
        k = macro(k a p p a)
        o = macro(c i r c l e . s m a l l)
        p = macro(p a r t i a l)
        s = macro(s e c t i o n)
        t = macro(t h e t a)
        u = macro(u p s i l o n)
        x = macro(x i)
        z = macro(z e t a)
      '';
    };
  };

  # keyd gives its socket to group `keyd`, which keyd-application-mapper needs.
  # The module creates no such group, and its unit lacks CAP_SETGID to switch to
  # one. docs/gotchas.md → keyd
  users.groups.keyd = { };
  systemd.services.keyd.serviceConfig.CapabilityBoundingSet = [ "CAP_SETGID" ];
}
