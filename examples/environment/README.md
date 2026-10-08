# environment — the compute environment as an r3 dependency

A job's environment is itself provided as *another r3 job* that builds it into `output/`;
consumers depend on that job and run against it. This is the **provider** archetype, in two
flavors — pick one:

- **[`venv/`](venv/)** — a self-contained Python interpreter (python-build-standalone) plus
  packages, sealed read-only. **No Singularity**, so the whole study reproduces on a laptop.
  Prefer it off-cluster, or when a container is more overhead than incoming students should pay.
- **[`container/`](container/)** — a Singularity image built from a `container.def`. Prefer it
  when you need system-level isolation (CUDA / apt libraries, non-Python tools) that a venv
  can't capture.

Both are consumed the same way: `find_latest` the environment job, `source: output`, and run the
captured interpreter directly. A consumer never installs into the environment — it's shared across
all consumers (and, for the venv flavor, sealed).
