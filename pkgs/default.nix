# Overlay for packages absent from nixpkgs, plus overrides.
{ inputs }:

# `final`, not `_final`: `lockscreen` below composes `lock-backgrounds` from
# this same overlay, and only the fixpoint argument sees it.
final: prev:

let
  # The selected scheme, as data. Same `import` the modules use — an overlay
  # runs before any module evaluates, so this is the only way in (docs/adr/0030).
  themeData = import ../modules/home/palette.nix;

  # The palette as JSON, for the two generators written in Python. ONE
  # definition: `colloid-palette.py` and `zed-theme.py` both index it by role
  # name, and a role present for one and absent for the other is a KeyError at
  # build time in whichever runs second. docs/adr/0041.
  paletteJson = prev.writeText "palette.json" (
    builtins.toJSON {
      inherit (themeData)
        bg0
        bg1
        bg2
        bg3
        fg0
        fg1
        fg4
        mantle
        comment
        accent
        black
        red
        green
        yellow
        blue
        magenta
        cyan
        white
        brBlack
        brRed
        brGreen
        brYellow
        brBlue
        brMagenta
        brCyan
        brWhite
        okColor
        warnColor
        errColor
        infoColor
        ;
    }
  );

  # One of the theme file's `packages.*` entries → a package, or `null` when the
  # name belongs to a toolkit built-in and there is nothing to install.
  #
  # `final.${d.attr}` rather than a lookup table: an attribute that does not
  # exist is an eval error naming the attribute, which is the loud failure this
  # repo wants. `base` is lazy, so the null guard runs first.
  #
  # `final`, not `prev`: `paletteGtk` and its two siblings below are defined by
  # THIS overlay, and `prev` is nixpkgs before it — a theme file naming an
  # attribute the overlay adds would not resolve.
  themePkg =
    d:
    let
      base = if (d.sub or null) == null then final.${d.attr} else final.${d.attr}.${d.sub};
      ov = d.override or { };
    in
    if d.attr == null then
      null
    else if ov == { } then
      base
    else
      base.override ov;
in

{

  # nixpkgs removed buildGo125Module on 2026-09-15 (Go 1.25 EOL); sops-nix still
  # calls it, so `sops.package` throws before the system closure evaluates. Drop
  # when upstream migrates. docs/gotchas.md -> nixpkgs and NixOS.
  buildGo125Module = prev.buildGoModule;

  # ==========================================================================
  # theme* — the artefacts the palette cannot colour
  # ==========================================================================
  # Rendered SVG widget art, cursor bitmaps and compiled SCSS. No hex reaches
  # them, so the selected theme file NAMES them and this block resolves those
  # names to packages — one place, so a scheme is still one file to add.
  #
  # AN OVERLAY, not call-site overrides: `themeIcons` is a Papirus recolour for
  # two of the four schemes, and two references to `papirus-icon-theme.override`
  # would put two Papirus derivations on XDG_DATA_DIRS with the colour decided
  # by lookup order. That is what this was before, and it is why it stays here.
  #
  # The overlay reads the palette by `import`, which is the same reason
  # `scheme.nix` is a file rather than a home-manager option — an overlay is
  # applied before any module evaluates and cannot see `config.*` (docs/adr/0030).
  #
  # `attr = null` means "no package": the name is a GTK or Kvantum built-in that
  # ships with the toolkit. Resolving it to `null` here is what lets theme.nix
  # and dotfiles.nix set the name without installing anything.
  themeGtk = themePkg themeData.packages.gtk;
  themeKvantum = themePkg themeData.packages.kvantum;
  themeIcons = themePkg themeData.packages.icons;
  themeCursor = themePkg themeData.packages.cursor;

  # The yazi flavour: a `.yazi` PACKAGE — a directory whose entry point is
  # `flavor.toml` — and 220 lines of colour with nothing else in it, so it is
  # WRITTEN rather than fetched (docs/adr/0041).
  #
  # It used to be four unrelated upstreams — `stepbrobd/nord.yazi`,
  # `bennyyip/gruvbox-dark.yazi` and two more — that agreed on the schema and
  # on nothing else, each pinned by rev and hash, and a scheme with no flavour
  # published could not be adopted at all. `packages.yazi` is gone from the
  # theme files with them.
  themeYazi = prev.writeTextDir "flavor.toml" (import ./yazi-flavor.nix themeData);

  # Zed's theme, written from the palette. Zed loads user themes from
  # ~/.config/zed/themes/, so this replaces an EXTENSION from Zed's registry —
  # which `modules/home/programs.nix` recorded as the one pair no check here
  # could gate, both halves living on Zed's servers. A theme in the generation
  # is gateable like everything else. docs/adr/0041.
  themeZed =
    let
      scheme = import ../modules/home/scheme.nix;
    in
    prev.runCommand "zed-theme-${scheme}.json" { } ''
      ${prev.python3}/bin/python3 ${./zed-theme.py} ${paletteJson} "${scheme}" "$out"
    '';

  # ==========================================================================
  # paletteCursors — the cursor set, recoloured from the palette
  # ==========================================================================
  # docs/adr/0041. catppuccin/cursors carries the Volantes art (GPL-2) as 68
  # SVGs in which every colour is one of three sentinel hexes, so the recolour
  # is a string replace and any palette can wear it. Upstream reaches that
  # through `whiskers` and three Tera templates — a layer whose whole job is
  # resolving Catppuccin FLAVOUR NAMES, which this repo does not have.
  #
  # The build half is upstream's own `scripts/`, run unpatched: hotspots, the
  # eleven scales, xcursorgen and the 113 aliases. The hotspot is a hidden
  # `<path id="hotspot">` read through QSvgRenderer's element TRANSFORM — a
  # regex over its `d=` gets it wrong wherever there is one, and the symptom is
  # a click point a pixel off that nobody reports.
  #
  # THE SENTINEL COUNTS ARE ASSERTED, before and after. A `sed` that stops
  # matching leaves a complete, valid, UNRECOLOURED set: the build succeeds,
  # the theme resolves, the artefact check finds its directory, and the pointer
  # is still Catppuccin mauve. Exact numbers rather than a floor because the
  # source is pinned by rev — they can only move when it is bumped, which is
  # exactly when they should be looked at again.
  paletteCursors =
    let
      p = themeData;
      themeName = "${import ../modules/home/scheme.nix}-cursors";

      # A light body over a dark outline, which is what this machine already
      # wears (capitaine) — so phase 1 changes the SOURCE of the colour and not
      # the look, and can be judged against a cursor already on screen.
      # `inner = accent` is the bolder alternative and is this one line.
      inner = p.fg0;
      border = p.base;

      # Upstream's own `special_map`, in this palette's roles: the accent that
      # marks what a cursor MEANS — red on `not-allowed`, green on `copy`.
      # Anything unlisted takes `accent`, which covers the 24 progress and wait
      # frames (upstream gives them `lavender`, its accent).
      special = {
        alias = p.magenta;
        "context-menu" = p.warnColor;
        copy = p.okColor;
        "dnd-no-drop" = p.errColor;
        help = p.infoColor;
        "no-drop" = p.errColor;
        "not-allowed" = p.errColor;
        pirate = p.errColor;
        "wayland-cursor" = p.warnColor;
        "x-cursor" = p.errColor;
      };
    in
    prev.stdenvNoCC.mkDerivation {
      pname = "palette-cursors";
      version = "2.0.0";

      src = prev.fetchFromGitHub {
        owner = "catppuccin";
        repo = "cursors";
        rev = "v2.0.0";
        hash = "sha256-qis6p+/m7+DdRDYzLq9yB2eZGpfZe5z5xRsa/1HoIG4=";
      };

      nativeBuildInputs = [
        prev.inkscape
        prev.xcursorgen
        prev.zip
        (prev.python3.withPackages (ps: [ ps.pyside6 ]))
      ];

      # inkscape and fontconfig both write under HOME and the sandbox has none.
      buildPhase = ''
        runHook preBuild
        export HOME="$TMPDIR"
        patchShebangs scripts

        # The source still speaks in sentinels. Checked BEFORE substituting, so
        # a bumped rev that recolours the art upstream fails here rather than
        # producing a set this palette never touched.
        # `|| true` on every grep here, and it is load-bearing: stdenv runs
        # this under `set -eo pipefail`, and grep exits 1 when it matches
        # NOTHING — which is the passing case for the second check below.
        # Without it the assertion kills the build precisely when it succeeds,
        # with no output at all. Cost one debugging round on 2026-08-20.
        while read -r sentinel want; do
          have=$(grep -lr "$sentinel" src/svgs/ | wc -l || true)
          if [ "$have" -ne "$want" ]; then
            echo "paletteCursors: $sentinel is in $have of the source SVGs, expected $want." >&2
            echo "  The upstream art has changed. Re-check the mapping before bumping the rev." >&2
            exit 1
          fi
        done <<'EOF'
        FF0000 68
        00FF00 52
        0000FF 34
        EOF

        declare -A special=(
        ${prev.lib.concatStringsSep "\n" (prev.lib.mapAttrsToList (n: v: "  [${n}]=\"${v}\"") special)}
        )

        mkdir -p "svgs/${themeName}"
        for f in src/svgs/*.svg; do
          b=$(basename "$f" .svg)
          # `progress-01` and `wait-07` are frames of one cursor, so the map is
          # keyed by the cursor rather than the frame.
          key="''${b%-[0-9][0-9]}"
          sp="''${special[$key]-${p.accent}}"
          sed -e "s/FF0000/${inner}/g" \
              -e "s/00FF00/${border}/g" \
              -e "s/0000FF/$sp/g" \
              "$f" > "svgs/${themeName}/$b.svg"
        done

        # Nothing unrecoloured survived, and all 68 arrived.
        left=$(grep -lr 'FF0000\|00FF00\|0000FF' "svgs/${themeName}/" | wc -l || true)
        n=$(find "svgs/${themeName}" -name '*.svg' | wc -l)
        if [ "$left" -ne 0 ] || [ "$n" -ne 68 ]; then
          echo "paletteCursors: $left file(s) still hold a sentinel, and $n of 68 SVGs were written." >&2
          exit 1
        fi

        cat > "svgs/${themeName}/index.theme" <<EOF
        [Icon Theme]
        Name=${themeName}
        Comment=Volantes cursors, recoloured from modules/home/palette.nix
        EOF

        scripts/build-cursors \
          "svgs/${themeName}" "pngs/${themeName}" "hl/${themeName}" "dist/${themeName}"
        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall
        install -dm755 "$out/share/icons"
        cp -r "dist/${themeName}" "$out/share/icons/${themeName}"
        cp -f AUTHORS LICENSE "$out/share/icons/${themeName}/"

        # `index.theme` is copied by upstream's OUTER `build` script, not by
        # `scripts/build-cursors` — which `rm -rf`s the output directory first,
        # so it has to land after. Without it the directory exists and holds
        # every cursor, the artefact check in checks/static.sh finds it by
        # name, and GTK and wlroots resolve NOTHING and fall back in silence.
        # Found exactly that way on 2026-08-20.
        cp -f "svgs/${themeName}/index.theme" "$out/share/icons/${themeName}/"
        test -s "$out/share/icons/${themeName}/index.theme"
        runHook postInstall
      '';

      meta = {
        description = "Volantes cursors recoloured from this repo's palette";
        license = prev.lib.licenses.gpl2Only;
        platforms = prev.lib.platforms.linux;
      };
    };

  # ==========================================================================
  # paletteKvantum — the Qt widget theme, recoloured from the palette
  # ==========================================================================
  # docs/adr/0041, phase 2. A Kvantum theme is two files: a `.kvconfig` whose
  # `[GeneralColors]` block is plain INI, and a `.svg` holding the widget art.
  # The INI half was always generatable; the art was the open question, and it
  # was answered by measuring all 37 themes Kvantum ships:
  #
  #   KvantumAlt   21 distinct colours, 25 KB — 18 of them EXACT greys and the
  #                other three off by one channel step
  #   the rest     39 to 97 colours, 75 to 182 KB, all of them scheme art
  #
  # So the base is chosen for being achromatic, not for being pretty: a
  # greyscale source has a lightness ramp and nothing else, and a lightness
  # ramp can be mapped onto THIS palette's own `mantle`→`fg0` axis without
  # inventing a single relationship. `gruvbox-kvantum`, which this replaces,
  # is 31 colours of somebody else's gruvbox and could only ever be gruvbox.
  #
  # Not pinned by rev — the source is nixpkgs' own Kvantum, which moves with
  # `nix flake update`. So the assertions are a FLOOR on how many colours were
  # recoloured plus an exact subset test on the result, rather than phase 1's
  # exact count: a bump that retouches the art must not break the build, and a
  # substitution that stops working still must.
  paletteKvantum =
    let
      p = themeData;
      themeName = "${import ../modules/home/scheme.nix}-kvantum";
      base = prev.kdePackages.qtstyleplugin-kvantum;

      # `[GeneralColors]`, by key. KvantumAlt's own values order themselves
      # dark→light as dark < base < alt.base < mid < window < button <
      # mid.light < light, and that order is what is reproduced here on this
      # palette's ramp — the block is a ramp with names, so mapping it any
      # other way would flatten the art it sits behind.
      colors = {
        "dark.color" = p.mantle;
        "base.color" = p.bg0;
        "alt.base.color" = p.bg1;
        "mid.color" = p.bg1;
        "window.color" = p.bg1;
        "button.color" = p.bg2;
        "mid.light.color" = p.bg2;
        "light.color" = p.bg3;

        "highlight.color" = p.accent;
        "inactive.highlight.color" = p.comment;
        "tooltip.base.color" = p.mantle;

        # `text.color` and three of its siblings are the literal word `white`
        # upstream, not hex. Replacing the whole line by key rather than
        # substituting a value is what makes that irrelevant.
        "text.color" = p.text;
        "window.text.color" = p.text;
        "button.text.color" = p.text;
        "tooltip.text.color" = p.text;
        "disabled.text.color" = p.comment;
        # Drawn ON the accent, so it takes the background rather than the text
        # colour — the one entry here that is not the role its name suggests.
        "highlight.text.color" = p.base;

        "link.color" = p.infoColor;
        "link.visited.color" = p.magenta;

        # These two live in per-widget sections rather than [GeneralColors] and
        # appear more than once. Keyed the same way, so both are reached.
        "text.focus.color" = p.accent;
        "text.shadow.color" = p.mantle;
      };
    in
    prev.stdenvNoCC.mkDerivation {
      pname = "palette-kvantum";
      inherit (base) version;

      dontUnpack = true;
      nativeBuildInputs = [ prev.python3 ];

      buildPhase = ''
        runHook preBuild
        src="${base}/share/Kvantum/KvantumAlt"
        if [ ! -r "$src/KvantumAlt.kvconfig" ] || [ ! -r "$src/KvantumAlt.svg" ]; then
          echo "paletteKvantum: KvantumAlt is not where it was in ${base}." >&2
          echo "  Kvantum moved or renamed it; pick the base again by measuring, not by guessing." >&2
          exit 1
        fi

        mkdir -p "${themeName}"
        cp "$src/KvantumAlt.kvconfig" "${themeName}/${themeName}.kvconfig"
        cp "$src/KvantumAlt.svg"      "${themeName}/${themeName}.svg"
        chmod u+w "${themeName}"/*

        # --- the INI half ---------------------------------------------------
        # Whole-line by key, so a value spelled as a NAME (`white`, `black`)
        # replaces as cleanly as one spelled as hex. Every key must already
        # exist: a key Kvantum has dropped would otherwise be written nowhere
        # and the colour would quietly stay upstream's.
        miss=""
        while IFS='|' read -r key value; do
          [ -n "$key" ] || continue
          esc=$(printf '%s' "$key" | sed 's/\./\\./g')
          if ! grep -q "^$esc=" "${themeName}/${themeName}.kvconfig"; then
            miss="$miss $key"
            continue
          fi
          sed -i "s|^$esc=.*|$key=#$value|" "${themeName}/${themeName}.kvconfig"
        done <<'EOF'
        ${prev.lib.concatStringsSep "\n" (prev.lib.mapAttrsToList (k: v: "${k}|${v}") colors)}
        EOF
        if [ -n "$miss" ]; then
          echo "paletteKvantum: KvantumAlt has no such key(s):$miss" >&2
          echo "  Those colours would silently stay upstream's. Re-read its kvconfig." >&2
          exit 1
        fi

        # --- the art --------------------------------------------------------
        python3 ${./kvantum-recolour.py} \
          "${themeName}/${themeName}.svg" "${p.mantle}" "${p.fg0}"
        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall
        install -dm755 "$out/share/Kvantum"
        cp -r "${themeName}" "$out/share/Kvantum/${themeName}"
        runHook postInstall
      '';

      meta = {
        description = "Kvantum's achromatic KvantumAlt art, tinted to this repo's palette";
        license = prev.lib.licenses.gpl3Only;
        platforms = prev.lib.platforms.linux;
      };
    };

  # ==========================================================================
  # paletteGtk — the GTK theme, recoloured from the palette
  # ==========================================================================
  # docs/adr/0041, phase 3. Colloid keeps every colour it uses in ONE file per
  # scheme — `_color-palette-gruvbox.scss`, `_color-palette-nord.scss` and three
  # more, all with identical variable names — so this is a FILE ADDITION and not
  # a patch of upstream internals. The only coupling is to those 43 names, and
  # `colloid-palette.py` fails rather than writing a short file.
  #
  # `_color-palette-default.scss` is overwritten rather than a sixth scheme
  # added. Adding one means patching install.sh in three places (the `--tweaks`
  # dispatch, `SCHEME_VARIANTS`, `color_schemes()`); overwriting the default
  # means patching nothing, because `$colorscheme` stays `default` and is only
  # ever special-cased for `dracula` (checked, in _colors-public.scss and the
  # two _common-*.scss).
  #
  # This retired `gruvbox-gtk-theme`, an overlay derivation that existed only
  # because the nixpkgs `gruvbox-dark-gtk` ships no GTK4. That stops being a
  # per-scheme problem once the theme is built here.
  paletteGtk =
    let
      p = themeData;
      themeName = "${import ../modules/home/scheme.nix}-gtk";
      scss = prev.runCommand "colloid-palette.scss" { } ''
        ${prev.python3}/bin/python3 ${./colloid-palette.py} ${paletteJson} "$out"
      '';
    in
    (prev.colloid-gtk-theme.override {
      themeVariants = [ "default" ];
      colorVariants = [ "dark" ];
      sizeVariants = [ "standard" ];
    }).overrideAttrs
      (old: {
        pname = "palette-gtk";

        postPatch = (old.postPatch or "") + ''
          target=src/sass/_color-palette-default.scss
          if [ ! -f "$target" ]; then
            echo "paletteGtk: Colloid has no $target — it reorganised its sass tree." >&2
            echo "  Overwriting the default scheme is how this hooks in; re-read install.sh." >&2
            exit 1
          fi
          cp ${scss} "$target"
        '';

        # Renamed from Colloid's own `Colloid-Dark*` to `<scheme>-gtk*`, so all
        # three generated artefacts read the same way in a theme file and a
        # name that has stopped matching its scheme is visible. Only
        # `index.theme` holds the name internally, and GTK resolves a theme by
        # DIRECTORY anyway — but a metatheme naming a theme that is not there
        # is the kind of thing that gets believed later.
        #
        # The compiled CSS must actually carry the palette, and this guards a
        # narrower gap than it looks. A variable RENAMED upstream is already
        # loud: sassc stops with `Undefined variable: "$grey-700"` (verified
        # 2026-08-20, not assumed). What is silent is the file being written
        # and never IMPORTED — Colloid changing which palette `_tweaks.scss`
        # pulls in — because then sassc succeeds, the theme installs, it
        # resolves by name, it ships its gtk-4.0/gtk.css, and it is Colloid's
        # own blue. Every other check here passes it.
        postInstall =
          (old.postInstall or "")
          + ''
            themes="$out/share/themes"
            for d in "$themes"/Colloid-Dark*; do
              [ -d "$d" ] || continue
              new="$themes/${themeName}''${d##*/Colloid-Dark}"
              mv "$d" "$new"
              if [ -f "$new/index.theme" ]; then
                sed -i "s/^\(Name\|GtkTheme\|MetacityTheme\)=Colloid-Dark.*/\1=$(basename "$new")/" "$new/index.theme"
              fi
            done
            if [ ! -d "$themes/${themeName}" ]; then
              echo "paletteGtk: nothing named Colloid-Dark to rename — install.sh names its output differently now." >&2
              exit 1
            fi

            # nixpkgs' installPhase runs `jdupes --link-soft` over share/, which
            # replaces every duplicate file across the three size variants with a
            # SYMLINK into Colloid-Dark. Renaming the directories leaves those
            # dangling, and nixpkgs' own noBrokenSymlinks check then fails the
            # build — loudly, which is why this was found immediately and is
            # worth keeping that way. Re-point rather than un-dedupe: the
            # deduplication is most of why the closure is 3.2 MB and not more.
            find "$themes" -type l | while IFS= read -r link; do
              t=$(readlink "$link")
              case "$t" in
                *Colloid-Dark*) ln -sfn "''${t//Colloid-Dark/${themeName}}" "$link" ;;
              esac
            done
          ''
          + ''
            css=$(find "$out/share/themes" -name 'gtk.css' -path '*gtk-3.0*' | head -1)
            if [ -z "$css" ]; then
              echo "paletteGtk: no gtk-3.0/gtk.css in the built theme." >&2
              exit 1
            fi
            for role in ${p.bg0} ${p.fg0} ${p.accent}; do
              if ! grep -qi "$role" "$css"; then
                echo "paletteGtk: #$role is nowhere in $css." >&2
                echo "  The palette did not reach the compiled CSS — check the variable names in" >&2
                echo "  src/sass/_color-palette-default.scss against pkgs/colloid-palette.py." >&2
                exit 1
              fi
            done
          '';

        meta = old.meta // {
          description = "Colloid, compiled against this repo's palette";
        };
      });

  # ==========================================================================
  # Brother MFC-L3740CDW printer driver
  # ==========================================================================
  # Unused — driverless IPP Everywhere works (printing.nix). Kept as fallback.
  brother-mfc-l3740cdw = prev.stdenv.mkDerivation rec {
    pname = "brother-mfc-l3740cdw";
    version = "3.5.1-1";

    src = prev.fetchurl {
      url = "https://download.brother.com/welcome/dlf105760/mfcl3740cdwpdrv-${version}.i386.deb";
      hash = "sha256-3weoQ4jJJ9h2fIm0LCyW9yY8dvuGESI26/isdmhzBZY=";
    };

    nativeBuildInputs = with prev; [
      dpkg
      autoPatchelfHook
      makeWrapper
    ];
    buildInputs = with prev; [
      cups
      ghostscript
      perl
      bash
    ];

    unpackPhase = "dpkg-deb -x $src .";

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r opt $out/ 2>/dev/null || true
      cp -r usr/share $out/share 2>/dev/null || true
      mkdir -p $out/share/cups/model
      find $out/opt -name '*.ppd' -exec cp {} $out/share/cups/model/ \; 2>/dev/null || true
      runHook postInstall
    '';

    meta.description = "Brother MFC-L3740CDW CUPS driver";
    meta.platforms = [ "x86_64-linux" ];
  };

  # ==========================================================================
  # CurseForge (AppImage)
  # ==========================================================================
  curseforge = prev.appimageTools.wrapType2 rec {
    pname = "curseforge";
    version = "1.310.1-35445";
    src = prev.fetchurl {
      url = "https://curseforge.overwolf.com/electron/linux/CurseForge-${version}.AppImage";
      hash = "sha256-9GOk9GNPEYvw8adKny2NYd77KN82i7nVtfYCgWxltkU=";
    };
    extraPkgs = pkgs: with pkgs; [ libsecret ];
    meta.description = "CurseForge mod manager";
  };

  # ==========================================================================
  # lock-backgrounds — the swaylock background pool
  # ==========================================================================
  # A pool rather than one image: the member is chosen per lock (docs/adr/0018).
  # Seeds are fixed, so which images exist is reproducible even though which one
  # gets used is not.
  #
  # 1920x1200 is the panel's native mode, and is load-bearing — see blocks.py.
  # The ramp is centred on the palette's `bg0` rather than on a literal, so the
  # lock screen cannot end up the one surface still wearing the old scheme. Only
  # the centre comes from the palette; ±6 is the spread of the ramp, which is a
  # property of the gradient and not a colour.
  #
  # The ramp varies LIGHTNESS ONLY: all three channels move by the same ±6, so
  # every tone keeps bg0's exact channel offsets and therefore its hue. The
  # check below asserts the offsets are preserved rather than that they are
  # zero — a neutral base satisfies both, a tinted one only the first.
  # docs/adr/0029.
  lock-backgrounds =
    let
      palette = import ../modules/home/palette.nix;
      chan = i: prev.lib.fromHexString (builtins.substring i 2 palette.bg0);
      mid = [
        (chan 0)
        (chan 2)
        (chan 4)
      ];
      # Zero-padded: toHexString 5 is "5", which would build "#555" — a valid
      # colour, a different one, and nothing downstream would object.
      byte =
        v:
        let
          h = prev.lib.toLower (prev.lib.toHexString v);
        in
        if builtins.stringLength h == 1 then "0${h}" else h;
      tone = d: "#" + prev.lib.concatMapStrings (c: byte (c + d)) mid;
      stops = "${tone (-6)},${tone 0},${tone 6}";
      # The per-channel bounds the checkPhase asserts, as shell-safe literals.
      chanName = [
        "r"
        "g"
        "b"
      ];
    in
    prev.stdenv.mkDerivation {
      pname = "lock-backgrounds";
      version = "1";

      dontUnpack = true;
      nativeBuildInputs = [
        prev.python3
        prev.imagemagick
      ];

      buildPhase = ''
        runHook preBuild
        mkdir -p pool
        for i in $(seq 1 24); do
          python3 ${./lock-backgrounds/blocks.py} \
            --grid 12x8 --steps 9 --seed "$i" \
            --stops '${stops}' \
            --out block.ppm
          # `-type TrueColor` so the PNG is RGB whatever the palette is. Without
          # it ImageMagick picks the colorspace from CONTENT, and a neutral bg0
          # (gruvbox's #282828 is r=g=b) writes a Gray PNG whose green and blue
          # channels then read as 0 — see the checkPhase below, which that broke.
          magick block.ppm -filter Point -resize '1920x1200!' -type TrueColor \
            "pool/$(printf 'lock-%02d' "$i").png"
        done
        runHook postBuild
      '';

      # The floor. A pool that generated wrong is invisible at lock time — the
      # screen just looks slightly off — and every wrong version so far looked
      # plausible.
      #
      # Bounds come from the same `mid` the ramp is drawn from, so the check
      # cannot go stale against a palette change. Exact per channel for hue,
      # ±1 for the mean because 96 blocks sampled from 9 tones vary that much
      # on their own: docs/adr/0029 argues both.
      #
      # `-colorspace sRGB` on every measurement, belt to `-type TrueColor` above
      # — ImageMagick reports mean.g and mean.b as 0 for an image it calls Gray,
      # so a NEUTRAL palette failed this claiming green was 0.
      # docs/gotchas.md → Theming.
      doCheck = true;
      checkPhase = ''
        runHook preCheck
        n=$(find pool -name '*.png' | wc -l)
        [ "$n" -eq 24 ] || { echo "pool has $n members, expected 24" >&2; exit 1; }
        for f in pool/*.png; do
          ${prev.lib.concatStrings (
            prev.lib.zipListsWith (name: want: ''
              mean=$(magick "$f" -colorspace sRGB -format '%[fx:int(mean.${name}*255)]' info:)
              [ "$mean" -ge ${toString (want - 1)} ] && [ "$mean" -le ${toString (want + 1)} ] ||
                { echo "$f: ${name} mean $mean, expected ${toString want}±1 (${tone 0})" >&2; exit 1; }
            '') chanName mid
          )}
          drifted=$(magick "$f" -colorspace sRGB -unique-colors txt: |
            grep -oE '#[0-9A-F]{6}' |
            awk 'function v(s, i) { return strtonum("0x" substr(s, i, 2)) }
                 { if (v($0,2) - v($0,4) != ${toString (builtins.elemAt mid 0 - builtins.elemAt mid 1)} ||
                       v($0,4) - v($0,6) != ${
                         toString (builtins.elemAt mid 1 - builtins.elemAt mid 2)
                       }) n++ }
                 END { print n+0 }')
          [ "$drifted" -eq 0 ] ||
            { echo "$f: $drifted tones off ${tone 0}'s hue — the ramp shifts colour, not just lightness" >&2; exit 1; }
        done
        runHook postCheck
      '';

      installPhase = ''
        runHook preInstall
        mkdir -p "$out/share/lock-backgrounds"
        cp pool/*.png "$out/share/lock-backgrounds/"
        runHook postInstall
      '';

      meta.description = "Blocky background pool for swaylock, on the palette's base tone";
    };

  # ==========================================================================
  # power-profiles-tlp — the PPD bus name, answered from TLP
  # ==========================================================================
  # TLP and power-profiles-daemon cannot both run (docs/adr/0017), so every
  # client that speaks PPD (`powerprofilesctl`, GNOME's power page) finds
  # nothing and renders nothing. This owns the name and translates.
  # docs/adr/0026; the unit and its `--power-mode` are in modules/system/power.nix.
  #
  # `--replace-fail` on the shebang, so a rewrite of the script that drops it
  # is a build error rather than a daemon that runs under the wrong python.
  power-profiles-tlp =
    let
      python = prev.python3.withPackages (ps: [
        ps.dbus-python
        ps.pygobject3
      ]);
    in
    prev.stdenv.mkDerivation {
      pname = "power-profiles-tlp";
      version = "1";

      dontUnpack = true;
      nativeBuildInputs = [ prev.makeWrapper ];

      installPhase = ''
        runHook preInstall
        install -Dm755 ${./power-profiles-tlp/daemon.py} $out/bin/power-profiles-tlp
        substituteInPlace $out/bin/power-profiles-tlp \
          --replace-fail '#!/usr/bin/env python3' '#!${python}/bin/python3'

        install -Dm644 ${./power-profiles-tlp/dbus-policy.conf} \
          $out/share/dbus-1/system.d/org.freedesktop.UPower.PowerProfiles.conf

        # Activation, and it is NOT redundant with the always-on unit. quickshell
        # bus-ACTIVATES this name at startup and gives up permanently when that
        # fails — observed: "Could not launch service …: The name is not
        # activatable", then "The PowerProfiles service will not work", after
        # which every client's profile call returns early in silence. A unit
        # that merely happens to be running is not the same as a name dbus can
        # start. `SystemdService` is what dbus-broker uses; `Exec` is the
        # non-systemd fallback. docs/adr/0026.
        install -Dm644 ${./power-profiles-tlp/dbus-service.in} \
          $out/share/dbus-1/system-services/org.freedesktop.UPower.PowerProfiles.service
        substituteInPlace \
          $out/share/dbus-1/system-services/org.freedesktop.UPower.PowerProfiles.service \
          --replace-fail '@out@' "$out"

        # `gi.repository.Gio` and `.GLib` resolve through typelibs, not through
        # PYTHONPATH. Without this the imports raise at startup — which under a
        # systemd unit is a failure nothing in the session ever surfaces.
        wrapProgram $out/bin/power-profiles-tlp \
          --prefix GI_TYPELIB_PATH : "${prev.glib.out}/lib/girepository-1.0"
        runHook postInstall
      '';

      # The floor. `--help` imports dbus and gi and exits, so a missing python
      # dependency or an unwrapped typelib path fails the BUILD rather than
      # arriving as an inert widget three reboots later.
      doInstallCheck = true;
      installCheckPhase = ''
        runHook preInstallCheck
        $out/bin/power-profiles-tlp --help >/dev/null
        runHook postInstallCheck
      '';

      meta.description = "Serve the power-profiles-daemon D-Bus API from TLP";
    };

  # ==========================================================================
  # lockscreen — swaylock over a background picked from the pool
  # ==========================================================================
  # Deliberately NOT named `swaylock`. A wrapper of that name would land earlier
  # in PATH and shadow swaylock-effects, which is the exact trap that makes
  # `programs.swaylock.package = null` load-bearing. docs/gotchas.md → swaylock.
  #
  # Every lock path goes through this one name — swayidle's before-sleep, lock
  # and 5-minute timeout, wlogout, power-menu.sh. docs/adr/0018.
  lockscreen = prev.writeShellApplication {
    name = "lockscreen";
    # Absolute paths: swayidle runs this from `sh -c` with a PATH that carries
    # bash and little else.
    runtimeInputs = [
      prev.swaylock-effects
      prev.coreutils
    ];
    text = ''
      # nullglob so an empty pool yields an empty array rather than the literal
      # glob — otherwise the fallback below never fires and swaylock is handed a
      # path with a `*` in it.
      shopt -s nullglob
      pool=(${final.lock-backgrounds}/share/lock-backgrounds/*.png)

      # A lock that will not start is worse than a plain one, so an empty pool
      # falls back to the solid `color` still set in the swaylock config.
      if [ ''${#pool[@]} -eq 0 ]; then
        exec swaylock "$@"
      fi

      exec swaylock -i "''${pool[RANDOM % ''${#pool[@]}]}" "$@"
    '';
  };

  # ==========================================================================
  # Still unpackaged — absent from nixpkgs as of 2026-07-27
  # ==========================================================================
  #   piavpn-bin, freedownloadmanager, betterbird, torbrowser-launcher,
  #   quickmedia, pipemixer, r-quick-share, haroopad, mdview, pdf-compress,
  #   qrookie-vrp, phosphor-icons, nerd-fonts-sf-mono
  #
  # `tor-browser` and `thunderbird` ARE in nixpkgs — prefer those over the
  # launcher/Betterbird if you ever package these.
}
