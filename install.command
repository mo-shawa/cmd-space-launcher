#!/usr/bin/python3
"""Install or update Cmd-Space Launcher for the current macOS user."""

import argparse
import fcntl
import hashlib
import os
import platform
import plistlib
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

SOURCE = Path(__file__).resolve().parent
CONFIG = Path.home() / ".hammerspoon"
STORE = CONFIG / ".cmd-space-launcher"
LINK = CONFIG / "CmdSpaceLauncher"
LOADER = b'require("CmdSpaceLauncher.launcher")'
FILES = ("Launcher.swift", "launcher.lua", "window-actions.lua", "SpaceMover.m")
# Only these exact prior standalone launcher configs can be replaced by the loader.
STANDALONE = {
    "c593c5c12831f6a50edfd81bbe608fe1cbb560e480e26fc8823f1bd0f0426e30",
    "f75f1ed4a0f8131ab451cfc066e9cf943478543446b3f02ad7916ffb86f6a29b",
    "a27b85901d36b299a973771dfa10f2f00d2f4f1a7e496ae474d13a135d8f1ddc",
}


def prepare_config():
    init = CONFIG / "init.lua"
    if init.is_symlink():
        print("Your init.lua is a symlink. Add this line in your dotfiles if needed:")
        print('if hs.fs.attributes(hs.configdir .. "/CmdSpaceLauncher/launcher.lua") then')
        print("  " + LOADER.decode())
        print("end")
        return None, None
    original = init.read_bytes() if init.exists() else None
    data = original or b""
    body = data[len(LOADER) + 1:] if data.startswith(LOADER + b"\n") else data
    if hashlib.sha256(body).hexdigest() in STANDALONE:
        return original, LOADER + b"\n"
    if LOADER in (line.strip() for line in data.splitlines()):
        return original, original
    # Prepend so existing Lua files ending in a top-level return still parse.
    prefix = b""
    if data.startswith(b"\xef\xbb\xbf"):
        prefix, data = data[:3], data[3:]
    if data.startswith(b"#!"):
        first, _, data = data.partition(b"\n")
        prefix += first + b"\n"
    return original, prefix + LOADER + b"\n" + data


def write_config(stage, original, updated):
    if updated == original:
        return
    init = CONFIG / "init.lua"
    if original is not None:
        backup_dir = Path(tempfile.mkdtemp(prefix="init-backup-", dir=STORE))
        backup = backup_dir / "init.lua"
        shutil.copy2(init, backup)
        if backup.read_bytes() != original:
            sys.exit("init.lua changed during setup. Run the command again.")
        print("Backed up the previous configuration to", backup)
    new_init = stage / "init.lua"
    new_init.write_bytes(updated)
    if original is not None:
        shutil.copymode(init, new_init)
    if init.is_symlink() or (init.read_bytes() if init.exists() else None) != original:
        sys.exit("init.lua changed during setup. Run the command again.")
    os.replace(new_init, init)


def release_name(source):
    digest = hashlib.sha256(platform.machine().encode())
    for filename in FILES:
        if filename not in FILES[:2] and not (source / filename).exists():
            continue  # v1.0.x only shipped the first two sources.
        digest.update((source / filename).read_bytes())
    return "release-" + digest.hexdigest()[:16]


def check_link():
    if os.path.lexists(LINK) and not (LINK.is_symlink() and LINK.resolve().parent == STORE.resolve()
                                      and LINK.resolve().name.startswith("release-")):
        sys.exit(f"{LINK} already exists and belongs to another installation.")


def install():
    STORE.mkdir(parents=True, exist_ok=True)
    with (STORE / "install.lock").open("a") as lock, tempfile.TemporaryDirectory(dir=STORE) as temp:
        fcntl.flock(lock, fcntl.LOCK_EX)
        stage = Path(temp)
        check_link()
        original, updated = prepare_config()
        release = STORE / release_name(SOURCE)
        if not release.exists():
            build = stage / "release"
            build.mkdir()
            for filename in FILES:
                shutil.copyfile(SOURCE / filename, build / filename)
            subprocess.run(["xcrun", "swiftc", "-O", str(build / "Launcher.swift"),
                            "-o", str(build / "AppSearch")], check=True)
            subprocess.run(["xcrun", "clang", "-O2", "-fobjc-arc", "-framework", "AppKit",
                            str(build / "SpaceMover.m"), "-o", str(build / "SpaceMover")], check=True)
            build.rename(release)
        next_link = stage / "link"
        next_link.symlink_to(release.relative_to(CONFIG))
        os.replace(next_link, LINK)
        write_config(stage, original, updated)


def uninstall():
    if not STORE.is_dir():
        return
    with (STORE / "install.lock").open("a") as lock, tempfile.TemporaryDirectory(dir=STORE) as temp:
        fcntl.flock(lock, fcntl.LOCK_EX)
        check_link()
        init = CONFIG / "init.lua"
        if init.is_symlink():
            print("If you manually added an unconditional launcher require to your dotfiles, remove it.")
        elif init.is_file():
            original = init.read_bytes()
            bom = b"\xef\xbb\xbf" if original.startswith(b"\xef\xbb\xbf") else b""
            lines = original[len(bom):].splitlines(keepends=True)
            updated = bom + b"".join(line for line in lines if line.strip() != LOADER)
            write_config(Path(temp), original, updated)
        if LINK.is_symlink():
            LINK.unlink()
        # Preserve edited releases and extra files alongside our config backups.
        for release in STORE.glob("release-*"):
            if release.is_symlink() or not release.is_dir():
                continue
            files = list(release.iterdir())
            if {p.name for p in files} not in ({"AppSearch", "SpaceMover", *FILES}, {"AppSearch", *FILES[:2]}):
                continue
            if all(p.is_file() and not p.is_symlink() for p in files) and release.name == release_name(release):
                shutil.rmtree(release)
    print("Reload Hammerspoon to release Cmd-Space. Your backups and history are in place.")


def configure_macos():
    domain = "com.apple.symbolichotkeys"
    prefs_path = Path.home() / "Library" / "Preferences" / (domain + ".plist")
    exported = subprocess.run(["defaults", "export", domain, "-"], capture_output=True)
    if exported.returncode and prefs_path.exists():
        sys.exit("Could not read the active Spotlight preferences.")
    prefs = plistlib.loads(exported.stdout) if exported.returncode == 0 else {}
    keys = prefs.get("AppleSymbolicHotKeys", {})
    entry = keys.get("64", {"value": {"type": "standard", "parameters": [32, 49, 1048576]}})
    if entry.get("enabled") is not False:
        if prefs_path.exists():
            original = prefs_path.read_bytes()
            if plistlib.loads(original) != prefs:
                sys.exit("Spotlight's saved and active preferences differ. Run the installer again.")
            backup_dir = Path(tempfile.mkdtemp(prefix="spotlight-backup-", dir=STORE))
            backup = backup_dir / prefs_path.name
            shutil.copy2(prefs_path, backup)
            if backup.read_bytes() != original:
                sys.exit("Could not verify the Spotlight backup.")
            print("Backed up Spotlight preferences to", backup)
        entry = dict(entry, enabled=False)
        subprocess.run(["defaults", "write", domain, "AppleSymbolicHotKeys", "-dict-add",
                        "64", plistlib.dumps(entry).decode()], check=True)
        prefs.setdefault("AppleSymbolicHotKeys", {})["64"] = entry
        if plistlib.loads(subprocess.check_output(["defaults", "export", domain, "-"])) != prefs:
            sys.exit("Spotlight preferences did not match the expected single change.")
    activate = Path("/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings")
    if activate.exists():
        subprocess.run([str(activate), "-u"], check=True)
    else:
        print("Sign out and back in to apply the Spotlight shortcut change.")
    dock = subprocess.run(["defaults", "read", "com.apple.dock", "workspaces-auto-swoosh"], capture_output=True)
    if dock.stdout.strip() != b"1":
        subprocess.run(["defaults", "write", "com.apple.dock", "workspaces-auto-swoosh", "-bool", "YES"], check=True)
        subprocess.run(["killall", "Dock"], check=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--configure-macos", action="store_true",
                      help="disable Spotlight's Cmd-Space shortcut and enable automatic Space switching")
    mode.add_argument("--homebrew", action="store_true",
                      help="use the Hammerspoon cask dependency, configure Cmd-Space and open Hammerspoon")
    mode.add_argument("--uninstall", action="store_true", help="remove the launcher and its loader line")
    args = parser.parse_args()
    if sys.platform != "darwin":
        sys.exit("Cmd-Space Launcher requires macOS.")
    if args.uninstall:
        uninstall()
        return
    if subprocess.run(["xcrun", "--find", "swiftc"], capture_output=True).returncode:
        sys.exit("Install the Xcode Command Line Tools with xcode-select --install, then run this again.")
    if not args.homebrew and not Path("/Applications/Hammerspoon.app").is_dir():
        brew = shutil.which("brew") or next((p for p in ("/opt/homebrew/bin/brew", "/usr/local/bin/brew")
                                              if os.access(p, os.X_OK)), None)
        if not brew:
            sys.exit("Hammerspoon is missing and Homebrew is not installed. Install either, then run this again.")
        subprocess.run([brew, "install", "--cask", "hammerspoon"], check=True)
    install()
    if args.configure_macos or args.homebrew:
        configure_macos()
    if args.homebrew:
        subprocess.run(["open", "-a", "Hammerspoon"], check=True)
    print("Launcher installed. Open Hammerspoon or choose Reload Config in its menu.")
    print("Grant Hammerspoon Accessibility access and clear any Raycast Cmd-Space shortcut.")


if __name__ == "__main__":
    main()
