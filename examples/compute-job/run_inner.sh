#!/bin/bash
# Compute logic: run against the captured environment's interpreter (no Singularity).
set -euo pipefail
PY="env/$(cat env/interpreter_path.txt)"   # interpreter inside the ./env dependency
# PYTHONNOUSERSITE=1: never fall back to ~/.local, so the sealed env stays authoritative.
PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1 "$PY" run.py
