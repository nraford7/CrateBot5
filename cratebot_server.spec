# -*- mode: python ; coding: utf-8 -*-
"""
PyInstaller spec file for CrateBot Python backend.
Creates a standalone executable that runs the FastAPI server.
"""

import sys
from pathlib import Path

# Fix recursion limit for deep import chains
sys.setrecursionlimit(sys.getrecursionlimit() * 5)

# Project paths
project_root = Path(SPECPATH)
backend_path = project_root / 'backend'
python_path = project_root / 'python'

# Analysis
a = Analysis(
    [str(backend_path / 'run_server.py')],
    pathex=[
        str(project_root),
        str(python_path),
        str(python_path / 'src'),
    ],
    binaries=[],
    datas=[
        # Include model files if any default models exist
        (str(Path.home() / '.cratebot' / 'models'), 'models'),
    ] if (Path.home() / '.cratebot' / 'models').exists() else [],
    hiddenimports=[
        # FastAPI and dependencies
        'fastapi',
        'uvicorn',
        'uvicorn.logging',
        'uvicorn.loops',
        'uvicorn.loops.auto',
        'uvicorn.protocols',
        'uvicorn.protocols.http',
        'uvicorn.protocols.http.auto',
        'uvicorn.protocols.websockets',
        'uvicorn.protocols.websockets.auto',
        'uvicorn.lifespan',
        'uvicorn.lifespan.on',
        'pydantic',
        'pydantic_core',
        'starlette',
        'anyio',
        'sniffio',

        # Audio processing
        'librosa',
        'librosa.util',
        'soundfile',
        'audioread',
        'pydub',

        # ML
        'sklearn',
        'sklearn.ensemble',
        'sklearn.tree',
        'sklearn.preprocessing',
        'sklearn.metrics',
        'sklearn.model_selection',
        'numpy',
        'pandas',
        'joblib',
        'lightgbm',
        'scipy',
        'scipy.fft',
        'scipy._lib',
        'scipy._lib.array_api_compat',
        'scipy._lib.array_api_compat.numpy',
        'scipy._lib.array_api_compat.numpy.fft',
        'scipy._cyutility',

        # Audio analysis
        'mutagen',
        'mutagen.id3',
        'mutagen.mp3',

        # Backend modules
        'backend',
        'backend.api_server',
        'backend.task_manager',
        'backend.models',
        'backend.models.schemas',

        # Core modules
        'src',
        'src.core',
        'src.core.auto_tagger',
        'src.core.audio_analyzer',
        'src.core.tag_manager',
        'src.core.vibe_generator',
        'src.core.hook_transcriber',
        'src.core.panns_analyzer',
        'src.core.essentia_analyzer',
        'src.core.refinement_manager',
        'src.core.tag_scanner',
        'src.core.feature_cache',
        'src.core.training_checkpoint',
        'src.core.utils',
        'core.utils',
        'src.models',
        'src.models.tag_predictor',
        'jaraco',
        'jaraco.collections',
        'jaraco.context',
        'jaraco.functools',
        'jaraco.text',
        'pkg_resources',
        'setuptools',

        # Optional dependencies (graceful failure if not installed)
        'anthropic',
        'faster_whisper',
        'essentia',
        'essentia.standard',

    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[
        # Exclude GUI-related packages not needed for server
        'tkinter',
        'pygame',
        'PIL',
        'matplotlib',

        # Exclude test frameworks
        'pytest',
        'pytest_cov',

    ],
    noarchive=False,
    optimize=0,
)

# Package
pyz = PYZ(a.pure)

# Executable
exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name='cratebot-server',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=True,  # Server needs console output
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)

# One-directory build to avoid onefile semaphore issues on macOS
coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name='cratebot-server-dist',
)
