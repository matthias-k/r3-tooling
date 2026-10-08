# environment/venv — a Python environment as an r3 dependency (no Singularity)

This job **builds a Python environment** into `output/` and hands it to downstream jobs as an
ordinary r3 dependency. It replaces a Singularity container with a self-contained, relocatable
interpreter, so the whole study reproduces on a **laptop without Singularity or SLURM**.

## What it produces (`output/`)
- `py/` — a python-build-standalone CPython interpreter with the study's packages installed
  directly into it (**sealed read-only** at the end of the build).
- `quarto/` — a self-contained Quarto CLI for `.qmd` reports (rendered with Python cells via the
  jupyter engine). **Left writable** — Quarto may write its own cache on first render; only the
  Python env carries the pip-corruption risk the seal guards against.
- `requirements.lock.txt` — exact resolved versions (the reproducibility record).
- `interpreter_path.txt` / `quarto_path.txt` — paths *relative to `output/`*, for consumers.
- `python_version.txt` — the interpreter version string.

## Why "Flavor B" (the interpreter is captured)
A plain venv is an *overlay* that points back at a base interpreter by absolute path — even
`uv venv --relocatable` keeps `.venv/bin/python` as an absolute symlink to the base. So a venv in
`output/` captures your *packages* but **not the interpreter**. A python-build-standalone
interpreter self-locates its own `lib/` relative to its executable, so the **whole environment
lives inside `output/`** and is provenanced like any other r3 artifact. This — not "uv vs.
not-uv" — is the real choice:

- **Flavor A (`uv venv`; simplest; interpreter external):** `uv venv --relocatable` then install.
  Caveat: the base interpreter must exist at the *same absolute path on every node* — so put uv's
  Python on shared storage (`UV_PYTHON_INSTALL_DIR=...`), not under `~/.local`.
- **Flavor B (this example; interpreter captured):** fetch a python-build-standalone interpreter
  into `output/py` and install into it directly (`--break-system-packages` overrides its PEP-668
  marker — we *intend* it as the env). Verified: copy → seal read-only → reach via a single
  symlink → `import numpy` still works and `sys.prefix` self-locates to the checkout path.

## Why it's sealed read-only
r3 deliberately leaves `output/` **writable** in the store, and every consumer symlinks to the
*same* directory — so a stray `pip install` from any consumer would corrupt the shared env. The
build therefore seals it (`chmod -R a-w output/py`) as its last step. This is a convention the
env job enforces itself, not something r3 does.

## How a consumer uses it
```yaml
# consumer's r3.yaml
dependencies:
  - find_latest: { path: PROJECT/environments/default }
    source: output          # symlinks the sealed env into ./env
    destination: env
```
```bash
# consumer's run_inner.sh — run the captured interpreter; never pip/uv into the sealed env
PY="env/$(cat env/interpreter_path.txt)"
PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1 "$PY" run.py
```
`PYTHONNOUSERSITE=1` matters: without it, an attempted install against the sealed env silently
redirects to `~/.local` and shadows it; with it, the failure is loud. For a report, the same env
provides Quarto — set `QUARTO_PYTHON="$PWD/$PY"` and a writable `HOME`, then
`env/$(cat env/quarto_path.txt) render report.qmd --to html`.

## Gotchas (both flavors)
- **Console-script shebangs hardcode the build path.** Call `bin/python -m <tool>` rather than the
  installed console script, or rewrite the shebang at build time (`uv venv --relocatable` does this
  for Flavor A).
- **`uv run` wants to mutate the env** → it fails on a sealed env. Use `bin/python` directly.
- **System libraries are not captured.** Neither flavor captures glibc / the CUDA driver / arbitrary
  apt packages — only the interpreter + Python packages. For those, use [`../container/`](../container/).

## Build / rebuild
`run_job_locally <committed-dir>` (laptop) or `xr3-slurm submit <id>` (SLURM). To cut a new
version, edit `requirements.txt`, bump `metadata.yaml`, and re-commit.
