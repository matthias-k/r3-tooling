#!/bin/bash
#SBATCH --job-name=grid-cell
#SBATCH --time=01:00:00
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G
#
# One grid cell. Single-task:  sbatch run.sh
# Array (one cell split into batches):  sbatch --array=0-$((N-1)) run.sh   (N = TOTAL_BATCH_COUNT)
set -euo pipefail

[ -f output/done ] && exit 0

# TOTAL_BATCH_COUNT is set by setup_tasks.py for array cells; empty = single-task cell.
TOTAL_BATCH_COUNT=TOTAL_BATCH_COUNT_PLACEHOLDER

R3_JOB_ID="${R3_JOB_ID:-$(basename "$(pwd)")}"
JOB_DIR="${SCRATCH:-$(mktemp -d)}/job"
rm -rf "$JOB_DIR"
r3 checkout "$R3_JOB_ID" "$JOB_DIR"
cd "$JOB_DIR"
[ -n "$TOTAL_BATCH_COUNT" ] && export TOTAL_BATCH_COUNT

if [[ -z "${SLURM_JOB_ID:-}" ]]; then
    STEP_CMD="bash"
elif [[ -z "${SLURM_STEP_ID:-}" ]]; then
    STEP_CMD="srun bash"
else
    STEP_CMD="bash"
fi
$STEP_CMD run_inner.sh

# A single-task cell is done here; an array cell is done when its last batch writes its marker
# (see run_inner.sh), so only mark done when this is not an array task.
[[ -z "${SLURM_ARRAY_TASK_ID:-}" ]] && echo "completed" > output/done
