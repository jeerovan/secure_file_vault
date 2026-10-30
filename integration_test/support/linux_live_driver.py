#!/usr/bin/env python3
"""Bounded AT-SPI driver for the isolated Linux authorized live-cloud test only."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys

parser = argparse.ArgumentParser()
parser.add_argument('runtime', type=Path)
parser.add_argument('mode', choices=['launch', 'inspect', 'act', 'close', 'tray', 'tray-act'])
parser.add_argument('--name')
parser.add_argument('--action', default='click')
parser.add_argument('--index', type=int)
args = parser.parse_args()
runtime = args.runtime.resolve()
if (not re.fullmatch(r'runtime-[a-f0-9]{16}', runtime.name)
        or not (runtime / 'synthetic-fixture.marker').is_file()):
    raise SystemExit('Explicit synthetic fixture required')
binary = runtime.parent / 'build/linux/x64/debug/bundle/secure_file_vault'
plugin = binary.parent / 'lib/libflutter_secure_storage_linux_plugin.so'
if b'com.jeerovan.fife.LiveCloudTest\0' not in plugin.read_bytes():
    raise SystemExit('Isolated native keyring identity required')
os.environ['DBUS_SESSION_BUS_ADDRESS'] = 'unix:path=/run/user/1000/bus'
if args.mode == 'launch':
    command = [str(binary)]
    if os.environ.get('FIFE_TEST_GRAPHICAL_CHILD') != '1':
        subprocess.run(['gnome-terminal', '--title=FiFe Linux live-cloud test', '--',
                        'env', 'FIFE_TEST_GRAPHICAL_CHILD=1', sys.executable,
                        str(Path(__file__).resolve()), str(runtime), 'launch'], check=True)
        sys.exit(0)
    env = dict(os.environ, FIFE_LINUX_TEST_ROOT=str(runtime),
               XDG_DATA_HOME=str(runtime / 'xdg'))
    with (runtime / 'app.log').open('a') as log:
        child = subprocess.Popen(command, env=env, stdout=log, stderr=log)
        (runtime / 'launch.json').write_text(json.dumps({
            'pid': child.pid, 'binary': str(binary), 'isolated': True}))
        sys.exit(child.wait())

launch = json.loads((runtime / 'launch.json').read_text())
pid = launch['pid']
if (not launch['isolated'] or Path(f'/proc/{pid}/exe').resolve() != binary
        or f'FIFE_LINUX_TEST_ROOT={runtime}'.encode() not in
        Path(f'/proc/{pid}/environ').read_bytes().split(b'\0')):
    raise SystemExit('Wrong process or runtime')
import gi
gi.require_version('Atspi', '2.0')
from gi.repository import Atspi, Gio, GLib

if args.mode in ('tray', 'tray-act'):
    bus = Gio.bus_get_sync(Gio.BusType.SESSION)
    def call(dest, obj, interface, method, signature, values):
        return bus.call_sync(dest, obj, interface, method,
                             GLib.Variant(signature, values), None,
                             Gio.DBusCallFlags.NONE, 3000, None).unpack()
    items = call('org.kde.StatusNotifierWatcher', '/StatusNotifierWatcher',
                 'org.freedesktop.DBus.Properties', 'Get', '(ss)',
                 ('org.kde.StatusNotifierWatcher', 'RegisteredStatusNotifierItems'))[0]
    candidates = []
    for item in items:
        dest, obj = item.split('@', 1)
        owner = call('org.freedesktop.DBus', '/org/freedesktop/DBus',
                     'org.freedesktop.DBus', 'GetConnectionUnixProcessID', '(s)', (dest,))[0]
        if owner != pid:
            continue
        props = call(dest, obj, 'org.freedesktop.DBus.Properties', 'GetAll',
                     '(s)', ('org.kde.StatusNotifierItem',))[0]
        candidates.append((dest, props))
    if len(candidates) != 1 or candidates[0][1]['Title'] != 'FiFe Linux Live Cloud':
        raise SystemExit('Expected isolated native status item')
    dest, props = candidates[0]
    menu = props['Menu']
    layout = call(dest, menu, 'com.canonical.dbusmenu', 'GetLayout',
                  '(iias)', (0, -1, []))[1]
    entries = []
    def read_menu(node):
        ident, properties, nested = node
        if 'label' in properties:
            entries.append(dict(id=ident, **properties))
        for child in nested:
            read_menu(child)
    read_menu(layout)
    if args.mode == 'tray-act':
        matches = [entry for entry in entries if entry['label'] == args.name]
        if len(matches) != 1 or not matches[0].get('enabled', True):
            raise SystemExit('Observed menu action unavailable')
        call(dest, menu, 'com.canonical.dbusmenu', 'Event', '(isvu)',
             (matches[0]['id'], 'clicked', GLib.Variant('i', 0), 0))
    print(json.dumps({'pid': pid, 'menu': entries, 'action': args.name}))
    sys.exit(0)

def children(node):
    for index in range(node.get_child_count()):
        child = node.get_child_at_index(index)
        if child is not None:
            yield child

desktop = Atspi.get_desktop(0)
apps = [app for app in children(desktop) if app.get_process_id() == pid]
if len(apps) != 1:
    raise SystemExit('Isolated accessible application not available')

def walk(node, depth=0):
    if depth > 35:
        return
    yield node, depth
    for child in children(node):
        yield from walk(child, depth + 1)

nodes = list(walk(apps[0]))
def safe_name(node):
    name = node.get_name() or ''
    if len(name.split()) >= 24 or node.get_role_name() == 'password text':
        return '[private text omitted]'
    return name

if args.mode == 'inspect':
    result = []
    for index, (node, depth) in enumerate(nodes):
        action = node.get_action_iface()
        actions = ([action.get_action_name(i) for i in range(action.get_n_actions())]
                   if action else [])
        if safe_name(node) or actions:
            result.append({'index': index, 'name': safe_name(node), 'role': node.get_role_name(),
                           'actions': actions, 'depth': depth,
                           'showing': node.get_state_set().contains(Atspi.StateType.SHOWING)})
    print(json.dumps({'pid': pid, 'controls': result}))
else:
    name = 'Close' if args.mode == 'close' else args.name
    matches = [node for index, (node, _) in enumerate(nodes)
               if (index == args.index if args.index is not None else node.get_name() == name)
               and node.get_state_set().contains(Atspi.StateType.SHOWING)]
    if len(matches) != 1:
        raise SystemExit(f'Expected one observed control; found {len(matches)}')
    action = matches[0].get_action_iface()
    available = [action.get_action_name(i) for i in range(action.get_n_actions())]
    if args.action not in available:
        raise SystemExit(f'Requested action unavailable: {available}')
    if not action.do_action(available.index(args.action)):
        raise SystemExit('Native accessibility action rejected')
    print(json.dumps({'pid': pid, 'name': name, 'action': args.action, 'accepted': True}))
