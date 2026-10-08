"""Minimal compute job: read config, read dependencies, write results to output/.

Replace the body with your real computation. The contract that matters:
  - read inputs from the checked-out dependencies (./env, ./data), nowhere else;
  - write every result under output/ (the one writable place);
  - never hand-copy upstream numbers in — they must flow through declared dependencies
    (the provenance invariant; see RESEARCH_WORKFLOW.md).
"""
import json
import pathlib

import yaml

config = yaml.safe_load(open("config.yaml"))

# --- your computation here; this stub just transforms a config value ----------
result = {"answer": config["n"] * 2}

out = pathlib.Path("output")
out.mkdir(exist_ok=True)
json.dump(result, open(out / "results.json", "w"), indent=2)
print("wrote output/results.json:", result)
