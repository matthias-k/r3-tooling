#!/bin/bash
# Environment job (Flavor B): build a self-contained, *relocatable* toolchain into output/ and
# seal the Python env read-only — this replaces a Singularity container. "Flavor B" = a
# python-build-standalone interpreter captured inside output/py (interpreter + packages both
# provenanced), plus a self-contained Quarto CLI for rendering .qmd reports. See README.md.
set -euo pipefail

PY_MINOR=3.12
QUARTO_VERSION=1.10.18
export PYTHONDONTWRITEBYTECODE=1

echo ">> [1/6] Fetch a self-contained interpreter (python-build-standalone) into output/py"
uv python install --install-dir output/py "cpython-${PY_MINOR}"
# The '3.12.*' glob (WITH the dot) matches the concrete patch-version dir, not uv's
# 'cpython-3.12-...' minor-version symlink.
PY=$(ls -d output/py/cpython-${PY_MINOR}.*-*/bin/python${PY_MINOR} | head -1)
echo ">> interpreter: $PY"; "$PY" --version

echo ">> [2/6] Install packages directly into that interpreter (no venv overlay)"
"$PY" -m pip install --break-system-packages --no-cache-dir --upgrade pip
"$PY" -m pip install --break-system-packages --no-cache-dir -r requirements.txt

echo ">> [3/6] Fetch a self-contained Quarto CLI into output/quarto (left writable: Quarto may"
echo ">>       write its own tool cache on first render; only the Python env needs sealing)"
mkdir -p output/quarto
QURL="https://github.com/quarto-dev/quarto-cli/releases/download/v${QUARTO_VERSION}/quarto-${QUARTO_VERSION}-linux-amd64.tar.gz"
curl -sSL "$QURL" | tar -xz --strip-components=1 -C output/quarto
echo "quarto/bin/quarto" > output/quarto_path.txt
QUARTO_PYTHON="$(pwd)/$PY" output/quarto/bin/quarto --version

echo ">> [4/6] Record the pointers consumers read"
"$PY" -m pip freeze > output/requirements.lock.txt     # exact resolved versions (the record)
"$PY" --version > output/python_version.txt
echo "${PY#output/}" > output/interpreter_path.txt      # interpreter path relative to output/

echo ">> [5/6] Smoke-test the stack"
"$PY" -c "import numpy, scipy, matplotlib, yaml, nbclient, nbformat, ipykernel; print('env OK')"

echo ">> [6/6] Pre-compile bytecode, then seal the Python env read-only"
"$PY" -m compileall -q "output/py" || true
chmod -R a-w output/py        # r3 leaves output/ writable; the env job must seal it itself
echo ">> environment build complete"
