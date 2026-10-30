#!/usr/bin/env python3
"""Check the real Linux runner after normal startup or tray Open.

Run on the graphical user's session with the sign-in screen visible:
  python3 integration_test/support/linux_startup_focus_check.py PID --binary PATH

Requires GTK's AT-SPI service and gdb with same-user attach permission. It reads
native focus without activating/focusing the window or editing auth state.
Unlike EditableText.set_text_contents, this detects a Flutter field that is
editable in semantics but whose native view cannot receive keyboard events.
The caller launches the normal app; this test does not initialize its lifecycle.
"""

import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

import gi

gi.require_version("Atspi", "2.0")
from gi.repository import Atspi  # noqa: E402

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("pid", type=int)
parser.add_argument("--binary", type=Path, required=True)
args = parser.parse_args()
binary = args.binary.resolve(strict=True)
assert Path(f"/proc/{args.pid}/exe").resolve(strict=True) == binary
assert Path(f"/proc/{args.pid}").stat().st_uid == os.getuid()


def walk(node):
    yield node
    for index in range(node.get_child_count()):
        child = node.get_child_at_index(index)
        if child is not None:
            yield from walk(child)


deadline = time.monotonic() + 15
while True:
    desktop = Atspi.get_desktop(0)
    apps = [desktop.get_child_at_index(i)
            for i in range(desktop.get_child_count())]
    apps = [app for app in apps if app and app.get_process_id() == args.pid]
    nodes = list(walk(apps[0])) if len(apps) == 1 else []
    fields = [node for node in nodes if node.get_role_name() == "text"
              and node.get_name() == "Email Address"
              and node.get_state_set().contains(Atspi.StateType.SHOWING)]
    if (len(fields) == 1 and
            fields[0].get_state_set().contains(Atspi.StateType.EDITABLE)):
        break
    assert time.monotonic() < deadline, "Normal sign-in screen did not settle"
    time.sleep(0.1)

# Read GTK focus only. No focus call, field mutation, initializer or auth request
# is supplied by the harness. The normal privacy lifecycle must restore input.
commands = """set pagination off
set confirm off
set $app = (MyApplication*) g_application_get_default()
set $view = (GtkWidget*) $app->privacy->view_
set $window = (GtkWindow*) $app->window
printf "ACTIVE=%d\\n", (int) gtk_window_is_active($window)
printf "SENSITIVE=%d\\n", (int) gtk_widget_get_sensitive($view)
printf "COVER_HIDDEN=%d\\n", !(int) gtk_widget_get_visible($app->privacy->cover_)
printf "FOCUS_MATCHES_VIEW=%d\\n", ((GtkWidget*) gtk_window_get_focus($window)) == $view
printf "HAS_FOCUS=%d\\n", (int) gtk_widget_has_focus($view)
detach
quit
"""
with tempfile.NamedTemporaryFile(mode="w", suffix=".gdb") as script:
    script.write(commands)
    script.flush()
    result = subprocess.run(
        ["gdb", "--batch", "--quiet", "-p", str(args.pid), "-x", script.name],
        capture_output=True, text=True, timeout=20,
    )
assert result.returncode == 0, "Native focus inspection failed"
keys = {"ACTIVE", "SENSITIVE", "COVER_HIDDEN", "FOCUS_MATCHES_VIEW", "HAS_FOCUS"}
observed = {}
for line in result.stdout.splitlines():
    key, separator, value = line.partition("=")
    if separator and key in keys:
        observed[key] = value == "1"
print(json.dumps({"pid": args.pid, "nativeFocus": observed}))
assert observed.keys() == keys, "Incomplete native observations"
assert all(observed.values()), "Revealed sign-in view must receive keyboard focus"
