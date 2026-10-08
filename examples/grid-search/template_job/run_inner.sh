#!/bin/bash
# One grid cell's logic. Runs against the environment's interpreter (swap in a container's
# `run_in_container python ...` if you use the container flavor instead).
set -euo pipefail
PY="env/$(cat env/interpreter_path.txt)"

if [ -n "${SLURM_ARRAY_TASK_ID:-}" ]; then
    [ -z "${TOTAL_BATCH_COUNT:-}" ] && { echo "TOTAL_BATCH_COUNT required in array mode" >&2; exit 1; }
    BATCH_ARGS="--batch-index $SLURM_ARRAY_TASK_ID --batch-count $TOTAL_BATCH_COUNT"
    echo "array batch $SLURM_ARRAY_TASK_ID of $TOTAL_BATCH_COUNT"
else
    BATCH_ARGS=""
fi

PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1 "$PY" run.py --config config.yaml $BATCH_ARGS

# Per-batch marker, so auto_submit.py can resume an array without re-running finished batches.
if [ -n "${SLURM_ARRAY_TASK_ID:-}" ]; then
    mkdir -p output
    touch "output/done_batch_${SLURM_ARRAY_TASK_ID}"
fi
