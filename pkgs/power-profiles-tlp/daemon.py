#!/usr/bin/env python3
"""Serve the power-profiles-daemon D-Bus API from TLP.

TLP and power-profiles-daemon cannot both run (docs/adr/0017), so every client
that speaks PPD -- GNOME's power settings, `powerprofilesctl` -- finds no service and shows nothing, in silence. This
daemon owns the PPD bus name and answers it from TLP's own state, so those
clients read and set the same three profiles the bar and SUPER+SHIFT+P do.

It is a translator, not a tuner: every write goes through `power-mode` and
every read comes from /run/tlp/last_pwr. docs/adr/0026.
"""

import argparse
import os
import signal
import subprocess
import sys

import dbus
import dbus.mainloop.glib
import dbus.service
# GLibUnix, not GLib.unix_signal_add: pygobject 3.56 deprecates the latter and
# prints a PyGIDeprecationWarning on every start, straight into the journal
# where a real fault would appear.
from gi.repository import Gio, GLib, GLibUnix

BUS_NAME = "org.freedesktop.UPower.PowerProfiles"
OBJECT_PATH = "/org/freedesktop/UPower/PowerProfiles"
IFACE = "org.freedesktop.UPower.PowerProfiles"
PROPS_IFACE = "org.freedesktop.DBus.Properties"

# The API level implemented, not this daemon's version -- clients branch on it.
# Provenance goes in each profile's `Driver` field instead, where
# `powerprofilesctl` prints it.
API_VERSION = "0.30"

PWRFILE = "/run/tlp/last_pwr"

# Least to most performant: PPD publishes them in this order and clients render
# it as a slider, so reversing it silently reverses the control.
PROFILES = ("power-saver", "balanced", "performance")

# First field of last_pwr, from tlp-func-base: PP_PRF=0 PP_BAL=1 PP_SAV=2.
# The names on the right are `power-mode`'s arguments AND PPD's profile names --
# they coincide exactly, so only the read side needs a mapping.
CODE_TO_PROFILE = {"0": "performance", "1": "balanced", "2": "power-saver"}

# The file monitor below is the fast path; this is the floor under it. A missed
# inotify event would otherwise leave a stale profile on the bus for as long as
# the session lasts, which reads as "the widget is broken".
RECONCILE_SECONDS = 30


def log(message):
    print(f"power-profiles-tlp: {message}", file=sys.stderr, flush=True)


def die(message):
    log(message)
    sys.exit(1)


def read_profile(path):
    """The profile TLP reports, or None if it does not report one."""
    try:
        with open(path, encoding="ascii") as handle:
            fields = handle.read().split()
    except OSError as exc:
        log(f"cannot read {path}: {exc}")
        return None
    if not fields:
        log(f"{path} is empty")
        return None
    profile = CODE_TO_PROFILE.get(fields[0])
    if profile is None:
        log(f"{path} reports profile code {fields[0]}, which is not one of "
            f"{sorted(CODE_TO_PROFILE)}")
    return profile


class PowerProfiles(dbus.service.Object):
    """org.freedesktop.UPower.PowerProfiles, backed by TLP."""

    def __init__(self, bus_name, power_mode, pwrfile, active):
        super().__init__(bus_name, OBJECT_PATH)
        self._power_mode = power_mode
        self._pwrfile = pwrfile
        self._active = active

    # --- properties -------------------------------------------------------

    def _properties(self):
        return {
            "ActiveProfile": dbus.String(self._active),
            "Profiles": dbus.Array(
                [
                    dbus.Dictionary(
                        {
                            "Profile": dbus.String(name),
                            "Driver": dbus.String("tlp"),
                        },
                        signature="sv",
                    )
                    for name in PROFILES
                ],
                signature="a{sv}",
            ),
            # Holds are declined outright, so this is empty by construction
            # rather than merely empty so far -- see HoldProfile.
            "ActiveProfileHolds": dbus.Array([], signature="a{sv}"),
            "Actions": dbus.Array([], signature="s"),
            # Thermal throttling that PPD would report from its own drivers.
            # TLP exposes no equivalent, and inventing one would be worse than
            # saying nothing.
            "PerformanceDegraded": dbus.String(""),
            "PerformanceInhibited": dbus.String(""),  # deprecated upstream
            "Version": dbus.String(API_VERSION),
        }

    @dbus.service.method(PROPS_IFACE, in_signature="ss", out_signature="v")
    def Get(self, interface, prop):
        properties = self._properties()
        if prop not in properties:
            raise dbus.exceptions.DBusException(
                f"no such property: {prop}",
                name="org.freedesktop.DBus.Error.UnknownProperty",
            )
        return properties[prop]

    @dbus.service.method(PROPS_IFACE, in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface):
        return dbus.Dictionary(self._properties(), signature="sv")

    @dbus.service.method(PROPS_IFACE, in_signature="ssv")
    def Set(self, interface, prop, value):
        if prop != "ActiveProfile":
            raise dbus.exceptions.DBusException(
                f"{prop} is not writable",
                name="org.freedesktop.DBus.Error.PropertyReadOnly",
            )
        self.set_active(str(value))

    @dbus.service.signal(PROPS_IFACE, signature="sa{sv}as")
    def PropertiesChanged(self, interface, changed, invalidated):
        pass

    # --- holds ------------------------------------------------------------

    # PPD lets an application pin a profile for as long as it is running.
    # Honouring that here would mean an app silently overriding a TLP profile
    # whose every value was measured for this chassis (docs/adr/0017), and
    # recording a hold that changes nothing would be this repo's signature bug
    # written on purpose. So it fails, visibly, in the caller's log.

    @dbus.service.method(IFACE, in_signature="sss", out_signature="u")
    def HoldProfile(self, profile, reason, application_id):
        raise dbus.exceptions.DBusException(
            "power-profiles-tlp does not implement profile holds: TLP owns the "
            "profile and nothing may override it behind the user. Set "
            "ActiveProfile instead.",
            name="org.freedesktop.DBus.Error.NotSupported",
        )

    @dbus.service.method(IFACE, in_signature="u")
    def ReleaseProfile(self, cookie):
        raise dbus.exceptions.DBusException(
            f"no such hold: {cookie} (holds are not implemented)",
            name="org.freedesktop.DBus.Error.InvalidArgs",
        )

    # Never emitted, because no hold is ever taken. Declared so that a client
    # connecting to it gets a signal that exists rather than a match rule on
    # nothing.
    @dbus.service.signal(IFACE, signature="u")
    def ProfileReleased(self, cookie):
        pass

    # --- state ------------------------------------------------------------

    def _publish(self, profile):
        if profile == self._active:
            return
        self._active = profile
        self.PropertiesChanged(
            IFACE, {"ActiveProfile": dbus.String(profile)}, []
        )
        log(f"active profile is now {profile}")

    def refresh(self, *_args):
        """Publish a profile TLP changed on its own -- a charger transition."""
        profile = read_profile(self._pwrfile)
        if profile is not None:
            self._publish(profile)
        # Keep the last known value otherwise: the API has no "unknown", and a
        # genuinely absent TLP takes the bus name with it (BindsTo=tlp.service)
        # rather than leaving a lie on the bus.
        return True  # GLib.timeout_add_seconds: stay scheduled

    def set_active(self, profile):
        if profile not in PROFILES:
            raise dbus.exceptions.DBusException(
                f"{profile} is not one of {list(PROFILES)}",
                name="org.freedesktop.DBus.Error.InvalidArgs",
            )
        result = subprocess.run(
            [self._power_mode, profile],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            raise dbus.exceptions.DBusException(
                f"power-mode {profile} exited {result.returncode}: "
                f"{result.stderr.strip() or 'no output'}",
                name="org.freedesktop.DBus.Error.Failed",
            )
        # Read back rather than assume the write landed. power-mode shells out
        # to tlp, and a tlp write that reports success and changes nothing is
        # exactly what docs/adr/0017 was written about; power-profile-cycle.sh
        # does the same read-back for the same reason.
        now = read_profile(self._pwrfile)
        if now != profile:
            raise dbus.exceptions.DBusException(
                f"asked TLP for {profile}, it reports {now or 'nothing'}",
                name="org.freedesktop.DBus.Error.Failed",
            )
        self._publish(now)


def main():
    parser = argparse.ArgumentParser(
        description=__doc__.splitlines()[0],
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--power-mode",
        default="power-mode",
        help="path to the power-mode wrapper that applies a profile "
        "(default: %(default)s)",
    )
    parser.add_argument(
        "--pwrfile",
        default=PWRFILE,
        help="TLP's state file, read for the active profile "
        "(default: %(default)s)",
    )
    parser.add_argument(
        "--bus",
        choices=("system", "session"),
        default="system",
        help="bus to claim the name on; `session` exists so the daemon can be "
        "exercised without root (default: %(default)s)",
    )
    args = parser.parse_args()

    # An unusable power-mode must stop the daemon here rather than at the first
    # click, where the failure would arrive as a widget that does nothing.
    if os.path.sep in args.power_mode:
        usable = os.access(args.power_mode, os.X_OK)
    else:
        usable = any(
            os.access(os.path.join(d, args.power_mode), os.X_OK)
            for d in os.get_exec_path()
        )
    if not usable:
        die(f"{args.power_mode} is not executable -- refusing to start, "
            f"because every profile change goes through it")

    active = read_profile(args.pwrfile)
    if active is None:
        die(f"no profile readable from {args.pwrfile} -- refusing to start "
            f"rather than publish a guess. Is TLP running?")

    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    try:
        bus = dbus.SystemBus() if args.bus == "system" else dbus.SessionBus()
    except dbus.exceptions.DBusException as exc:
        die(f"cannot connect to the {args.bus} bus: {exc}")

    # do_not_queue: a second instance must fail loudly instead of waiting in
    # the queue, serving nothing, looking started.
    try:
        name = dbus.service.BusName(BUS_NAME, bus, do_not_queue=True)
    except dbus.exceptions.NameExistsException:
        die(f"{BUS_NAME} is already owned on the {args.bus} bus -- is "
            f"power-profiles-daemon running?")

    profiles = PowerProfiles(name, args.power_mode, args.pwrfile, active)

    # Bound to a local so the monitor is not collected the moment it goes out
    # of scope, which would drop every change silently.
    monitor = Gio.File.new_for_path(args.pwrfile).monitor_file(
        Gio.FileMonitorFlags.NONE, None
    )
    monitor.connect("changed", profiles.refresh)
    GLib.timeout_add_seconds(RECONCILE_SECONDS, profiles.refresh)

    loop = GLib.MainLoop()
    # Quit the loop rather than dying under the default handler, so the bus
    # name is released on `systemctl stop` instead of being reaped.
    def stop(*_args):
        loop.quit()
        return GLib.SOURCE_REMOVE

    GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, stop)
    GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, signal.SIGINT, stop)

    log(f"serving {BUS_NAME} from {args.pwrfile}, active profile {active}")
    loop.run()
    return 0


if __name__ == "__main__":
    sys.exit(main())
