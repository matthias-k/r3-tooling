# environment/container — a Singularity image as an r3 dependency

Builds a Singularity image into `output/container.sif` from `container.def`; consumers depend on it
and run with `singularity exec`. This is the cluster-side flavor of the environment-provider
archetype (the laptop-side flavor is [`../venv/`](../venv/)). Prefer a container when you need
system-level isolation — CUDA / apt libraries or non-Python tools a venv can't capture.

## Files
- `container.def` — the image recipe (CUDA base → apt libs → Quarto → pip `requirements.txt`).
- `requirements.txt` — the Python packages installed into the image.
- `run.sh` — `singularity build --fakeroot output/container.sif container.def`, idempotent.
- `metadata.yaml` / `r3.yaml` — labels and (empty) dependencies.

## How a consumer uses it
```yaml
# consumer's r3.yaml
dependencies:
  - find_latest: { tags: { $glob: PROJECT/containers/default/* }, projects: PROJECT }
    source: output/container.sif
    destination: container.sif
```
```bash
# consumer's run_inner.sh — a run_in_container helper keeps the exec line in one place
singularity exec --nv --bind "$R3_REPOSITORY" --env PYTHONPATH=<your repos> \
    container.sif python run.py
```

## Keep it lean
Resist baking dev tooling (ssh/vim/htop) or licensed installers (e.g. MATLAB) into the compute
image every job depends on — those belong in a separate dev image. A fat base image is slow to
build, rebuild, and check out.
