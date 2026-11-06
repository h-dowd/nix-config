# Options this config declares for itself.
#
# Kept in its own file because a module that declares `options` must put
# everything else under `config` — mixing `options.foo` with a bare
# `home.username` in one file is a "module has an unsupported attribute"
# evaluation error. A dedicated file avoids wrapping default.nix.
{ config, lib, ... }:

{
  options.local.checkout = lib.mkOption {
    type = lib.types.str;
    default = "${config.home.homeDirectory}/src/nix-config";
    example = "/home/henry/dev/nix-config";
    description = ''
      Absolute path to this repo's checkout on the live filesystem.

      This CANNOT be derived, which is worth understanding before trying to
      remove it. A flake always evaluates from a *copy of itself* in
      /nix/store, so `./.` and `self` both yield a store path. That is exactly
      right for `source = ../../dotfiles/kitty`, and useless for an out-of-store
      symlink, which by definition must point at a mutable path outside the
      store. `builtins.getEnv "PWD"` is not an escape hatch either: it returns
      "" under pure evaluation. Nix genuinely cannot discover where you cloned
      the repo, so somebody has to tell it — once.

      Declared here so that is the only place it is written down.
      `dotfiles.nix` uses it for the remaining `link` entries and `shell.nix`
      for the rebuild aliases. Clone the repo elsewhere and this default is the
      single line to change.

      This option becomes dead the moment the last out-of-store entry is
      converted to a store path, because at that point nothing in the flake
      cares where the checkout lives.
    '';
  };

  # A point, which `time.timeZone` is not — open-meteo takes `timezone=auto`,
  # so the zone is not duplicated here. Declared rather than looked up: two
  # floats reach nobody.
  # `float` so a transposed sign is an eval error. docs/adr/0038.
  options.local.location = {
    latitude = lib.mkOption {
      type = lib.types.float;
      default = 53.3498;
      example = 51.5072;
      description = "Latitude, decimal degrees, north positive.";
    };
    longitude = lib.mkOption {
      type = lib.types.float;
      default = -6.2603;
      example = -0.1276;
      description = "Longitude, decimal degrees, east positive.";
    };
    # Where `weather.sh open` goes. weather.com, which resolves `/l/<lat>,<lon>`
    # to its own city page — so this is a SECOND host learning where this
    # machine is, on top of the open-meteo request docs/adr/0038 counts as the
    # feature's cost. That is a trade, which is why it is an option and not a
    # constant in the script: `https://open-meteo.com/en/docs?latitude=…` tells
    # nobody new, and is the value to set if that matters more than the page.
    #
    # The coordinates are interpolated rather than templated, so an override is
    # a whole URL and there is no placeholder language to get wrong.
    forecastUrl = lib.mkOption {
      type = lib.types.str;
      default =
        "https://weather.com/weather/today/l/"
        + "${toString config.local.location.latitude}"
        + ",${toString config.local.location.longitude}";
      example = "https://www.windy.com/?53.350,-6.260,10";
      description = "The page a right-click on the weather module opens.";
    };

    name = lib.mkOption {
      type = lib.types.str;
      default = "Dublin";
      example = "London";
      description = ''
        What to call the place in a tooltip. Cosmetic, and deliberately not
        derived from the coordinates — deriving it is the geocode lookup this
        option exists to avoid.
      '';
    };
  };
}
