# -*- mode: python ; coding: utf-8 -*-
"""PyInstaller specification file for Madrid Public Libraries Book Finder.

Bundles backend modules, static frontend assets, and dependencies into a single executable.
"""

import sys
from pathlib import Path
from PyInstaller.utils.hooks import collect_all, collect_submodules

block_cipher = None

BASE_DIR = Path.cwd()

# Collect hidden imports and data files for dynamic libraries
fastapi_datas, fastapi_binaries, fastapi_hiddenimports = collect_all('fastapi')
uvicorn_datas, uvicorn_binaries, uvicorn_hiddenimports = collect_all('uvicorn')
starlette_datas, starlette_binaries, starlette_hiddenimports = collect_all('starlette')
httpx_datas, httpx_binaries, httpx_hiddenimports = collect_all('httpx')
bs4_datas, bs4_binaries, bs4_hiddenimports = collect_all('bs4')

datas = [
    (str(BASE_DIR / 'frontend'), 'frontend'),
    (str(BASE_DIR / 'backend'), 'backend'),
] + fastapi_datas + uvicorn_datas + starlette_datas + httpx_datas + bs4_datas

hiddenimports = list(set([
    'uvicorn',
    'uvicorn.logging',
    'uvicorn.loops',
    'uvicorn.loops.auto',
    'uvicorn.protocols',
    'uvicorn.protocols.http',
    'uvicorn.protocols.http.auto',
    'uvicorn.protocols.websockets',
    'uvicorn.protocols.websockets.auto',
    'uvicorn.lifespans',
    'uvicorn.lifespans.on',
    'uvicorn.lifespans.off',
    'fastapi',
    'fastapi.staticfiles',
    'fastapi.responses',
    'starlette',
    'starlette.staticfiles',
    'starlette.responses',
    'pydantic',
    'httpx',
    'bs4',
    'backend.main',
    'backend.scraper',
    'backend.models',
    'backend.madrid_libraries_geo',
    'backend.goodreads_service',
] + fastapi_hiddenimports + uvicorn_hiddenimports + starlette_hiddenimports + httpx_hiddenimports + bs4_hiddenimports))

a = Analysis(
    ['run_app.py'],
    pathex=[str(BASE_DIR)],
    binaries=fastapi_binaries + uvicorn_binaries + starlette_binaries + httpx_binaries + bs4_binaries,
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=['tkinter', 'matplotlib', 'numpy', 'scipy', 'pandas', 'IPython'],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.zipfiles,
    a.datas,
    [],
    name='MadridBookFinder',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=True,  # Shows terminal logs; set to False if completely silent GUI is desired
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
