import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import xr3slurmlib as lib


def test_parse_done_state():
    assert lib.parse_done_state("restart\n") == "restart"
    assert lib.parse_done_state("  failed ") == "failed"
    assert lib.parse_done_state("completed\n") == "done"
    assert lib.parse_done_state("") == "done"


def test_is_array_job():
    assert lib.is_array_job("#SBATCH --array=0-9\n#SBATCH --mem=4G\n") is True
    assert lib.is_array_job("#SBATCH --mem=4G\n#!/bin/bash\n") is False
    # leading whitespace before #SBATCH is not a directive (sbatch ignores it)
    assert lib.is_array_job("   #SBATCH --array=0-9\n") is False


def test_build_sbatch_command_scalar():
    cmd = lib.build_sbatch_command(
        script_path="/jobs/ID/run.sh",
        job_dir="/jobs/ID",
        full_id="ID",
        is_array=False,
        exclude_nodes=["cn221", "cn240"],
        partition=None,
        mem=None,
    )
    assert cmd == (
        "sbatch --job-name=ID --comment=/jobs/ID --chdir=/jobs/ID "
        "--output=/jobs/ID/output/slurm_%J.log --error=/jobs/ID/output/slurm_%J.log "
        "--exclude=cn221,cn240 /jobs/ID/run.sh"
    )


def test_build_sbatch_command_array_and_opts():
    cmd = lib.build_sbatch_command(
        script_path="/jobs/ID/run.sh",
        job_dir="/jobs/ID",
        full_id="ID",
        is_array=True,
        exclude_nodes=[],
        partition="a100",
        mem="16G",
    )
    assert "--output=/jobs/ID/output/slurm_%A_%a.log" in cmd
    assert "--exclude" not in cmd          # empty list => omitted
    assert "--partition=a100" in cmd
    assert "--mem=16G" in cmd


def test_parse_sattach_step():
    sacct = "12345         node   ...\n12345.batch   node   ...\n12345.0       node   ...\n"
    assert lib.parse_sattach_step(sacct) == "12345.0"   # first NUMERIC step (skips .batch)
    assert lib.parse_sattach_step("12345  node\n") is None   # no step line
    assert lib.parse_sattach_step("12345\n12345.batch\n") is None  # pseudo-steps only -> no attach


def test_parse_running_step():
    # sacct -j ID -P last row's step id -> integer step number (or None)
    assert lib.parse_running_step("JobID|...\n12345|...\n12345.0|...\n") == 0
    assert lib.parse_running_step("JobID|...\n12345|...\n12345.batch|...\n") is None
    assert lib.parse_running_step("JobID|...\n12345|...\n") is None
