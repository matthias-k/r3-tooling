# SPEC — <one-line question this experiment answers>

**Status:** draft. **Date:** YYYY-MM-DD.

## Question
What are you trying to find out, and why? State it before you know the answer.

## Approach
How you'll answer it — inputs, method, and the metric that decides it.

## Data
Which dataset job(s) this reads (by `path`), and any split / preprocessing.

## Outputs
What lands in `output/` (e.g. `results.json`) and what each field means.

## Job structure
- `compute/` (this job): deps = environment + dataset → results.
- `report/` (sibling): deps = environment + this compute job → `report.html`.
