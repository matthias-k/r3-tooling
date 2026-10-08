#!/bin/bash
#SBATCH --job-name=compute
#SBATCH --time=00:30:00
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G
#
# Portable r3 job runner. The SAME script works under SLURM (`sbatch run.sh` /
# `xr3-slurm submit <id>`) and on a laptop (`bash run.sh` / `run_job_locally <dir>`):
# the scratch location and the launcher both fall back off-cluster, so no SLURM or
# Singularity is required to reproduce the job.
set -euo pipefail

[ -f output/done ] && exit 0                    # idempotency: a finished job no-ops on resubmit

R3_JOB_ID="${R3_JOB_ID:-$(basename "$(pwd)")}"  # committed dir is named by the r3 uuid

JOB_DIR="${SCRATCH:-$(mktemp -d)}/job"          # node-local scratch under SLURM, else a temp dir
rm -rf "$JOB_DIR"
r3 checkout "$R3_JOB_ID" "$JOB_DIR"
cd "$JOB_DIR"

if [[ -z "${SLURM_JOB_ID:-}" ]]; then
    STEP_CMD="bash"          # off-cluster: no SLURM
elif [[ -z "${SLURM_STEP_ID:-}" ]]; then
    STEP_CMD="srun bash"     # inside sbatch, not yet a step
else
    STEP_CMD="bash"          # already inside a step
fi
$STEP_CMD run_inner.sh

echo "completed" > output/done
