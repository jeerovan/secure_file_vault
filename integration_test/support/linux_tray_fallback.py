#!/usr/bin/env python3
"""Run under dbus-run-session on GNOME; never alter the owner's tray host."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import threading
import time

import gi
gi.require_version('Atspi', '2.0')
from gi.repository import Atspi, Gio, GLib

parser = argparse.ArgumentParser()
parser.add_argument('binary', type=Path)
parser.add_argument('runtime', type=Path)
args = parser.parse_args()
binary, runtime = args.binary.resolve(), args.runtime.resolve()
assert (runtime / 'synthetic-fixture.marker').is_file()
assert os.environ.get('XDG_RUNTIME_DIR') == str(runtime / 'run'), \
    'Private runtime directory required before starting dbus-run-session'
assert (runtime / 'run').stat().st_mode & 0o777 == 0o700
assert b'com.jeerovan.fife.TrayVerification\0' in (
    binary.parent / 'lib/libflutter_secure_storage_linux_plugin.so').read_bytes()
assert os.environ['DBUS_SESSION_BUS_ADDRESS'] != f'unix:path=/run/user/{os.getuid()}/bus'
bus = Gio.bus_get_sync(Gio.BusType.SESSION)
owner_bus = Gio.DBusConnection.new_for_address_sync(
    f'unix:path=/run/user/{os.getuid()}/bus',
    Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT |
    Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION, None, None)
def bus_id(connection):
    return connection.call_sync('org.freedesktop.DBus', '/org/freedesktop/DBus',
        'org.freedesktop.DBus', 'GetId', None, None,
        Gio.DBusCallFlags.NONE, 3000, None).unpack()[0]
assert bus_id(bus) != bus_id(owner_bus), 'Refuse owner session bus'
owner_bus.close_sync(None)

loop = GLib.MainLoop()
threading.Thread(target=loop.run, daemon=True).start()
# GTK/Flutter probes appearance through the desktop portal during startup.
# A full portal on a private bus would try to start an entire second GNOME
# service stack. Supply only empty appearance settings; no file/auth portal.
portal_xml = '''<node><interface name="org.freedesktop.portal.Settings">
<method name="ReadAll"><arg type="as" direction="in"/>
<arg type="a{sa{sv}}" direction="out"/></method>
<method name="Read"><arg type="s" direction="in"/><arg type="s" direction="in"/>
<arg type="v" direction="out"/></method>
<property name="version" type="u" access="read"/>
<signal name="SettingChanged"><arg type="s"/><arg type="s"/><arg type="v"/></signal>
</interface></node>'''
def portal_method(connection, sender, obj, interface, name, parameters, invocation):
    if name == 'ReadAll':
        invocation.return_value(GLib.Variant('(a{sa{sv}})', ({},)))
    else:
        invocation.return_dbus_error('org.freedesktop.portal.Error.NotFound',
                                     'No custom appearance in tray fixture')
bus.register_object('/org/freedesktop/portal/desktop',
    Gio.DBusNodeInfo.new_for_xml(portal_xml).interfaces[0], portal_method,
    lambda *unused: GLib.Variant('u', 1), None)
portal_id = Gio.bus_own_name_on_connection(bus, 'org.freedesktop.portal.Desktop',
    Gio.BusNameOwnerFlags.NONE, None, None)
processes = []
registered = []
watcher_id = None

def until(check, seconds=15):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        result = check()
        if result:
            return result
        time.sleep(.1)
    raise AssertionError('Expected native state did not arrive')

def children(node):
    return [node.get_child_at_index(i) for i in range(node.get_child_count())]

def app_for(process):
    return next((app for app in children(Atspi.get_desktop(0))
                 if app and app.get_process_id() == process.pid), None)

def showing_frame(process):
    app = app_for(process)
    return app and any(window and window.get_role_name() == 'frame' and
                      window.get_state_set().contains(Atspi.StateType.SHOWING)
                      for window in children(app))

def close(process):
    assert process.poll() is None
    assert Path(f'/proc/{process.pid}/exe').resolve() == binary
    def walk(node):
        yield node
        for child in children(node):
            if child:
                yield from walk(child)
    app = until(lambda: app_for(process))
    buttons = [node for node in walk(app) if node.get_name() == 'Close' and
               node.get_state_set().contains(Atspi.StateType.SHOWING)]
    assert len(buttons) == 1, 'Expected real GTK header-bar Close button'
    action = buttons[0].get_action_iface()
    index = next(i for i in range(action.get_n_actions())
                 if action.get_action_name(i) == 'click')
    assert action.do_action(index)

def launch():
    env = dict(os.environ, GDK_BACKEND='wayland',
               WAYLAND_DISPLAY=f'/run/user/{os.getuid()}/wayland-0',
               XDG_RUNTIME_DIR=str(runtime / 'run'),
               XDG_DATA_HOME=str(runtime / 'xdg'), GTK_A11Y='atspi',
               GTK_USE_PORTAL='0', GTK_THEME='Adwaita', GSETTINGS_BACKEND='memory',
               GIO_USE_VFS='local',
               FIFE_LINUX_TRAY_TEST_ROOT=str(runtime))
    log = (runtime / 'native.log').open('a')
    process = subprocess.Popen([str(binary)], env=env, stdout=log, stderr=log)
    log.close()
    processes.append(process)
    until(lambda: (runtime / f'ready-{process.pid}').exists())
    until(lambda: showing_frame(process))
    return process

xml = '''<node><interface name="org.kde.StatusNotifierWatcher">
<method name="RegisterStatusNotifierItem"><arg type="s" direction="in"/></method>
<method name="RegisterStatusNotifierHost"><arg type="s" direction="in"/></method>
<property name="RegisteredStatusNotifierItems" type="as" access="read"/>
<property name="IsStatusNotifierHostRegistered" type="b" access="read"/>
<property name="ProtocolVersion" type="i" access="read"/>
<signal name="StatusNotifierItemRegistered"><arg type="s"/></signal>
<signal name="StatusNotifierItemUnregistered"><arg type="s"/></signal>
<signal name="StatusNotifierHostRegistered"/>
<signal name="StatusNotifierHostUnregistered"/>
</interface></node>'''

def method(connection, sender, obj, interface, name, parameters, invocation):
    if name == 'RegisterStatusNotifierItem':
        service = parameters.unpack()[0]
        item = sender + service if service.startswith('/') else service
        registered.append(item)
        connection.emit_signal(None, obj, interface, 'StatusNotifierItemRegistered',
                               GLib.Variant('(s)', (item,)))
    invocation.return_value(GLib.Variant('()', ()))

def prop(connection, sender, obj, interface, name):
    return {'RegisteredStatusNotifierItems': GLib.Variant('as', registered),
            'IsStatusNotifierHostRegistered': GLib.Variant('b', True),
            'ProtocolVersion': GLib.Variant('i', 0)}[name]

try:
    absent = launch()
    close(absent)
    assert absent.wait(timeout=10) == 0, 'Close without host must exit'

    bus.register_object('/StatusNotifierWatcher',
        Gio.DBusNodeInfo.new_for_xml(xml).interfaces[0], method, prop, None)
    watcher_id = Gio.bus_own_name_on_connection(bus, 'org.kde.StatusNotifierWatcher',
        Gio.BusNameOwnerFlags.NONE, None, None)
    hosted = launch()
    until(lambda: registered)
    close(hosted)
    until(lambda: not showing_frame(hosted))
    assert hosted.poll() is None, 'Host present: Close must retain process'
    Gio.bus_unown_name(watcher_id)
    watcher_id = None
    until(lambda: showing_frame(hosted))
    assert hosted.poll() is None, 'Host loss must restore existing process'
    close(hosted)
    assert hosted.wait(timeout=10) == 0
    proof = {'noHostCloseExited': True, 'hostedCloseKeptHiddenProcess': True,
             'hostLossRestoredSameWindow': True, 'subsequentNoHostCloseExited': True,
             'actualNativeRunner': True, 'privateSessionBus': True,
             'vaultAndNetworkNotConstructed': True,
             'binarySha256': hashlib.sha256(binary.read_bytes()).hexdigest()}
    (runtime / 'fallback-proof.json').write_text(json.dumps(proof, indent=2))
    print(json.dumps(proof))
finally:
    if watcher_id is not None:
        Gio.bus_unown_name(watcher_id)
    for process in processes:
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=10)
    Gio.bus_unown_name(portal_id)
    loop.quit()
