#!/usr/bin/env python3
"""Reject bundled Mach-O libraries requiring a newer macOS than the app."""

import re
import subprocess
import sys
from pathlib import Path


MACHO_MAGIC = {
    bytes.fromhex(magic)
    for magic in (
        "feedface", "cefaedfe", "feedfacf", "cffaedfe",
        "cafebabe", "bebafeca", "cafebabf", "bfbafeca",
    )
}


def version(value):
    if not re.fullmatch(r"\d+(?:\.\d+){0,2}", value):
        raise ValueError(f"Invalid macOS version: {value!r}")
    parts = tuple(int(part) for part in value.split("."))
    return parts + (0,) * (3 - len(parts))


def command(*args):
    result = subprocess.run(args, capture_output=True, text=True, check=True)
    return result.stdout


def verify(root, deployment_target):
    minimum = version(deployment_target)
    if not root.is_dir():
        raise ValueError(f"Missing bundled-code directory: {root}")
    binaries = 0
    errors = []
    for path in sorted(root.rglob("*")):
        # Versioned frameworks expose symlinks to the same real binary.
        if path.is_symlink() or not path.is_file():
            continue
        with path.open("rb") as stream:
            if stream.read(4) not in MACHO_MAGIC:
                continue
        binaries += 1
        architectures = command("/usr/bin/lipo", "-archs", str(path)).split()
        if not architectures:
            raise ValueError(f"No architectures found: {path}")
        for architecture in architectures:
            loads = command(
                "/usr/bin/otool", "-arch", architecture, "-l", str(path)
            )
            targets = []
            for block in re.split(r"Load command \d+\n", loads):
                if re.search(r"\bcmd LC_BUILD_VERSION\b", block):
                    if not re.search(r"\bplatform (?:1|MACOS)\s", block):
                        raise ValueError(f"Non-macOS binary: {path} ({architecture})")
                    match = re.search(r"\bminos ([\d.]+)", block)
                elif re.search(r"\bcmd LC_VERSION_MIN_MACOSX\b", block):
                    match = re.search(r"\bversion ([\d.]+)", block)
                else:
                    continue
                if match:
                    targets.append(match.group(1))
            if len(targets) != 1:
                raise ValueError(f"Cannot verify minimum macOS: {path} ({architecture})")
            if version(targets[0]) > minimum:
                errors.append(
                    f"{path.relative_to(root)} ({architecture}) requires macOS "
                    f"{targets[0]}; app declares {deployment_target}"
                )
    if not binaries:
        raise ValueError(f"No Mach-O binaries found: {root}")
    if errors:
        raise ValueError("\n".join(errors))
    print(f"Verified {binaries} bundled binaries against macOS {deployment_target}.")


if __name__ == "__main__":
    try:
        if len(sys.argv) != 3:
            raise ValueError("Usage: verify_deployment_target.py DIRECTORY MACOS_VERSION")
        verify(Path(sys.argv[1]), sys.argv[2])
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
