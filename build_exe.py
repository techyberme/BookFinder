#!/usr/bin/env python3
"""Build script for packaging Madrid Public Libraries Book Finder into a standalone executable.

Usage:
    python build_exe.py [--clean] [--noconsole]
"""

import os
import sys
import subprocess
import shutil
from pathlib import Path


def main():
    base_dir = Path(__file__).resolve().parent
    os.chdir(base_dir)

    print("=" * 70)
    print("  Building Madrid Public Libraries Book Finder Executable")
    print(f"  Working Directory: {base_dir}")
    print("=" * 70)

    # Check if PyInstaller is installed
    try:
        import PyInstaller
        print(f"[OK] PyInstaller detected (version {PyInstaller.__version__})")
    except ImportError:
        print("[!] PyInstaller is not installed in the current Python environment.")
        print("    Installing PyInstaller via pip...")
        subprocess.check_call([sys.executable, "-m", "pip", "install", "pyinstaller"])

    # Clean old build artifacts if requested or present
    for folder in ["build", "dist"]:
        folder_path = base_dir / folder
        if folder_path.exists():
            print(f"Cleaning old '{folder}/' directory...")
            shutil.rmtree(folder_path, ignore_errors=True)

    spec_file = base_dir / "bookfinder.spec"
    if not spec_file.exists():
        print(f"[ERROR] Specification file not found at: {spec_file}")
        sys.exit(1)

    cmd = [
        sys.executable,
        "-m",
        "PyInstaller",
        "--clean",
        "--noconfirm",
        str(spec_file),
    ]

    print(f"Executing build command: {' '.join(cmd)}")
    result = subprocess.run(cmd)

    if result.returncode == 0:
        dist_dir = base_dir / "dist"
        print("\n" + "=" * 70)
        print("  BUILD SUCCESSFUL!")
        print(f"  Executable output directory: {dist_dir}")
        print("=" * 70)
        for item in dist_dir.iterdir():
            print(f"  -> {item.name} ({item.stat().st_size / (1024 * 1024):.1f} MB)")
        print("\nTo distribute to Windows users, run this command on Windows:")
        print("    pyinstaller --clean --noconfirm bookfinder.spec")
    else:
        print(f"\n[ERROR] Build failed with exit code: {result.returncode}")
        sys.exit(result.returncode)


if __name__ == "__main__":
    main()
