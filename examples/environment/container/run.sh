#!/usr/bin/env bash
# Environment job: build the Singularity image into output/. No `r3 checkout` needed — this job
# reads only its own container.def. Idempotent via output/done.
set -e
mkdir -p output
[ -f output/done ] && { echo "already built"; exit 0; }

if singularity build --fakeroot output/container.sif container.def; then
    echo "completed" > output/done
else
    echo "build failed — remove output/done to retry" >&2
    echo "failed" > output/done
    exit 1
fi
