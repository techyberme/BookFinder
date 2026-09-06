#!/usr/bin/env python3
"""
Zahorí - macOS Desktop App Generator

Generates a native double-clickable 'Zahorí.app' bundle and shortcut 
directly on the user's macOS Desktop.
"""

import os
import sys
import stat
import shutil
import subprocess

PROJECT_DIR = os.path.dirname(os.path.abspath(__file__))
DESKTOP_DIR = os.path.expanduser("~/Desktop")
APP_NAME = "Zahorí.app"
APP_PATH = os.path.join(DESKTOP_DIR, APP_NAME)


def generate_icns():
    """Generates native macOS .icns file from icon-512.png."""
    iconset_dir = "/tmp/Zahori.iconset"
    if os.path.exists(iconset_dir):
        shutil.rmtree(iconset_dir)
    os.makedirs(iconset_dir, exist_ok=True)

    png_path = os.path.join(PROJECT_DIR, "frontend", "icon-512.png")
    if not os.path.exists(png_path):
        print(f"Warning: {png_path} not found.")
        return None

    try:
        from PIL import Image
        img = Image.open(png_path)
        sizes = [
            (16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"),
            (128, "128x128"), (256, "128x128@2x"), (256, "256x256"),
            (512, "256x256@2x"), (512, "512x512")
        ]

        for sz, name in sizes:
            resized = img.resize((sz, sz), Image.Resampling.LANCZOS)
            resized.save(os.path.join(iconset_dir, f"icon_{name}.png"))

        icns_path = os.path.join(PROJECT_DIR, "frontend", "Zahori.icns")
        subprocess.run(["iconutil", "-c", "icns", iconset_dir, "-o", icns_path], check=False)
        return icns_path
    except Exception as e:
        print(f"ICNS generation note: {e}")
        return None


def create_mac_app():
    """Creates the macOS .app bundle on ~/Desktop."""
    icns_path = generate_icns()

    if os.path.exists(APP_PATH):
        try:
            shutil.rmtree(APP_PATH)
        except Exception:
            pass

    contents_dir = os.path.join(APP_PATH, "Contents")
    macos_dir = os.path.join(contents_dir, "MacOS")
    res_dir = os.path.join(contents_dir, "Resources")

    os.makedirs(macos_dir, exist_ok=True)
    os.makedirs(res_dir, exist_ok=True)

    if icns_path and os.path.exists(icns_path):
        shutil.copy(icns_path, os.path.join(res_dir, "Zahori.icns"))

    info_plist = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>es</string>
    <key>CFBundleExecutable</key>
    <string>ZahoriLauncher</string>
    <key>CFBundleIconFile</key>
    <string>Zahori.icns</string>
    <key>CFBundleIdentifier</key>
    <string>es.madrid.zahori</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Zahorí</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.4.0</string>
    <key>CFBundleVersion</key>
    <string>1.4.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
"""
    with open(os.path.join(contents_dir, "Info.plist"), "w", encoding="utf-8") as f:
        f.write(info_plist)

    with open(os.path.join(contents_dir, "PkgInfo"), "w", encoding="utf-8") as f:
        f.write("APPL????")

    current_python = sys.executable

    launcher_path = os.path.join(macos_dir, "ZahoriLauncher")
    launcher_script = f"""#!/bin/bash
PROJECT_DIR="{PROJECT_DIR}"
cd "$PROJECT_DIR" || exit 1

PYTHON_BIN="{current_python}"
if [ ! -f "$PYTHON_BIN" ]; then
  PYTHON_BIN="$(which python3)"
fi

exec "$PYTHON_BIN" "$PROJECT_DIR/run_app.py"
"""
    with open(launcher_path, "w", encoding="utf-8") as f:
        f.write(launcher_script)

    os.chmod(launcher_path, os.stat(launcher_path).st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)

    # Command shortcut fallback
    cmd_path = os.path.join(DESKTOP_DIR, "Zahorí.command")
    cmd_script = f"""#!/bin/bash
PROJECT_DIR="{PROJECT_DIR}"
cd "$PROJECT_DIR" || exit 1

PYTHON_BIN="{current_python}"
if [ ! -f "$PYTHON_BIN" ]; then
  PYTHON_BIN="$(which python3)"
fi

"$PYTHON_BIN" "$PROJECT_DIR/run_app.py"
"""
    with open(cmd_path, "w", encoding="utf-8") as f:
        f.write(cmd_script)

    os.chmod(cmd_path, os.stat(cmd_path).st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)

    print(f"✨ Zahorí desktop app created successfully at: {APP_PATH}")


if __name__ == "__main__":
    create_mac_app()
