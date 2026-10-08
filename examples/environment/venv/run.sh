#!/bin/bash
#SBATCH --job-name=env
#SBATCH --time=00:30:00
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G
#
# Portable r3 job runner (works under SLURM and on a laptop). See examples/compute-job/run.sh
# for the annotated version — this is the same template.
set -euo pipefail

[ -f output/done ] && exit 0

R3_JOB_ID="${R3_JOB_ID:-$(basename "$(pwd)")}"

JOB_DIR="${SCRATCH:-$(mktemp -d)}/job"
rm -rf "$JOB_DIR"
r3 checkout "$R3_JOB_ID" "$JOB_DIR"
cd "$JOB_DIR"

if [[ -z "${SLURM_JOB_ID:-}" ]]; then
    STEP_CMD="bash"
elif [[ -z "${SLURM_STEP_ID:-}" ]]; then
    STEP_CMD="srun bash"
else
    STEP_CMD="bash"
fi
$STEP_CMD run_inner.sh

echo "completed" > output/done
