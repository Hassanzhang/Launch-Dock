#!/usr/bin/env python3
"""Prepare an optional disposable uvicorn integration sample under .build/."""
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parent.parent / '.build' / 'check-project'
root.mkdir(parents=True, exist_ok=True)
subprocess.run([sys.executable, '-m', 'venv', str(root / '.venv')], check=True)
python = root / '.venv/bin/python'
subprocess.run([str(python), '-m', 'pip', 'install', '--disable-pip-version-check', 'uvicorn==0.39.0'], check=True)
(root / 'web.py').write_text(
    "async def app(scope, receive, send):\n"
    " await send({'type':'http.response.start','status':200,'headers':[]})\n"
    " await send({'type':'http.response.body','body':b'LaunchDock OK'})\n",
    encoding='utf-8',
)
print(f'Prepared integration project: {root}')
