# raw-data — a "job you don't run" (received / hand-placed data)

Not every job computes something. Some of the most important jobs just **hold data you received
from the outside world**, with a committed README as the provenance record — a benchmark a
colleague sent you, a model's weights from a site that now 404s. You can't reproduce those by
re-running code, but you still want them frozen, findable, and dependable like any other job.

The pattern: a job whose only tracked files are this `README.md` and `metadata.yaml`. You commit
it, then place the data **by hand** into the committed job's `output/`. From then on it's an
ordinary entry node — downstream jobs depend on it by `path` exactly as they depend on a computed
one, and r3 records that they used this frozen copy.

**There is deliberately no `run.sh`.**

---

## <DATASET NAME> — raw data

Received from <who / where> on <DATE>, manually copied to `output/`.

- `<file-a>` — <what it is, and anything a future reader needs to trust or interpret it>.
- `<file-b>` — <...>.

Source / original location: <URL or description — even if it's now dead, say so>.
License / terms: <if any>.
