#!/usr/bin/env python3
"""Bare reference dev-checkout loop for r3 — public r3 API only (`r3.Repository`, `r3.Job`).

Materializes an uncommitted job's dependencies in place so you can run it before
committing; `cleanup` reverses it. Environments often have richer wrappers — prefer one
if available.

    python r3dev.py checkout <job_dir>   # materialize the job's dependencies in place
    python r3dev.py cleanup  <job_dir>   # remove them again

`checkout` leaves alone whatever is already there, so re-running it is safe;
`cleanup` is how you drop stale dependencies and pick up newer ones.
"""
import os
import shutil
import sys
from pathlib import Path

import r3

command, job_dir = sys.argv[1], Path(sys.argv[2])
repository = r3.Repository(os.environ["R3_REPOSITORY"])

for dependency in r3.Job(job_dir).dependencies:
    destination = job_dir / dependency.destination

    if command == "checkout":
        if destination.exists() or destination.is_symlink():
            print(f"{dependency.destination}: already there")
        else:
            repository.checkout(dependency, job_dir)   # resolve it, then fetch it in
            print(f"{dependency.destination}: checked out")

    elif command == "cleanup":
        if destination.is_symlink():
            destination.unlink()                       # a job dependency: symlinked in
        elif destination.is_dir():
            shutil.rmtree(destination)                 # a git dependency: a real directory
        else:
            continue
        print(f"{dependency.destination}: removed")
