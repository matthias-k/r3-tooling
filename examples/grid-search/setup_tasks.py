#!/usr/bin/env python3
"""Generate one r3 job directory per cell of a grid, from template_job/.

The pattern (see RESEARCH_WORKFLOW.md § template_job + tasks matrix):
  - build the grid from building blocks (here: MODELS × DATASETS);
  - for each cell, copy template_job/, substitute {PLACEHOLDERS} in the text files, MERGE the
    cell's own dependencies into the template r3.yaml, and write config/metadata;
  - give each cell a unique main tag (tags[0]) so re-running SKIPS cells already in r3;
  - `xr3 check` then `xr3 commit` each new cell.

A sweep is just many ordinary jobs — no sweep system, and a single `find_all` over the cells'
shared tag composes it back later.

Usage:
  python setup_tasks.py --dry-run     # list the cells, make nothing
  python setup_tasks.py               # generate cell dirs under tasks/
  python setup_tasks.py --commit      # generate + `xr3 check`/`commit` new cells
"""
import argparse
import subprocess
from pathlib import Path

import yaml

HERE = Path(__file__).resolve().parent
TEMPLATE = HERE / "template_job"
TASKS = HERE / "tasks"

# --- the grid axes (edit these) ----------------------------------------------
MODELS = ["linear", "mlp"]
DATASETS = ["toy_a", "toy_b"]

# Template text files copied with placeholder substitution.
TEXT_FILES = ["run.sh", "run_inner.sh", "run.py", "config.yaml", "metadata.yaml"]


def subst(text: str, repl: dict) -> str:
    for key, value in repl.items():
        text = text.replace("{" + key + "}", str(value))
    return text


def per_cell_dependencies(model: str, dataset: str) -> list:
    """The cell's OWN dependencies, merged into the template's base deps at generate time."""
    return [
        {
            "find_latest": {"path": f"PROJECT/datasets/{dataset}"},
            "source": "output",
            "destination": "data",
        },
    ]


def generate_cell(model: str, dataset: str, do_commit: bool) -> None:
    repl = {"MODEL": model, "DATASET": dataset}

    # The cell's unique main tag (tags[0]) decides whether it already exists in r3.
    meta = yaml.safe_load(subst((TEMPLATE / "metadata.yaml").read_text(), repl))
    main_tag = meta["tags"][0]
    found = subprocess.run(["r3", "find", f"--tag={main_tag}"], capture_output=True, text=True)
    if found.stdout.strip():
        print(f"skip  {model}/{dataset} (already in r3)")
        return

    cell = TASKS / model / dataset
    cell.mkdir(parents=True, exist_ok=True)
    for name in TEXT_FILES:
        (cell / name).write_text(subst((TEMPLATE / name).read_text(), repl))

    # r3.yaml: MERGE base deps (from the template) + this cell's own deps.
    base = yaml.safe_load((TEMPLATE / "r3.yaml").read_text())
    base["dependencies"] = base.get("dependencies", []) + per_cell_dependencies(model, dataset)
    (cell / "r3.yaml").write_text(subst(yaml.safe_dump(base, sort_keys=False), repl))

    print(f"made  {model}/{dataset}")
    if do_commit:
        subprocess.run(["xr3", "check", str(cell)], check=True)
        subprocess.run(["xr3", "commit", str(cell)], check=True)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--commit", action="store_true", help="xr3 check + commit new cells")
    ap.add_argument("--dry-run", action="store_true", help="list cells, make nothing")
    args = ap.parse_args()

    for model in MODELS:
        for dataset in DATASETS:
            if args.dry_run:
                print(f"would make {model}/{dataset}")
            else:
                generate_cell(model, dataset, do_commit=args.commit)


if __name__ == "__main__":
    main()
