# -*- mode: python ; coding: utf-8 -*-
# PyInstaller spec for monitor_hub
# Build: pyinstaller monitor_hub.spec

block_cipher = None

a = Analysis(
    ['run.py'],
    pathex=['.'],
    binaries=[],
    datas=[
        ('monitor_hub/templates', 'monitor_hub/templates'),
        ('monitor_hub/static',    'monitor_hub/static'),
    ],
    hiddenimports=[
        'flask',
        'flask.templating',
        'jinja2',
        'jinja2.ext',
        'werkzeug',
        'werkzeug.serving',
        'werkzeug.debug',
        'monitor_hub.server.app',
        'monitor_hub.server.sources',
        'monitor_hub.server.switch',
        'monitor_hub.server.identify',
        'monitor_hub.server.settings',
        'monitor_hub.server.execute_switch',
        'monitor_hub.agent.ddc',
        'monitor_hub.tray',
        'monitor_hub.net',
        'monitor_hub.runtime_paths',
        'monitor_hub.logging_setup',
        'monitorcontrol',
        'pystray',
        'PIL',
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
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
    name='monitor_hub',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=False,         # windowed: launched via --tray from startup, no console flash on login
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
