"""One grid cell. Reads config.yaml; optionally processes only its slice of the work
(--batch-index / --batch-count) so a heavy cell can run as a SLURM array over batches."""
import argparse
import json
import pathlib

import yaml

p = argparse.ArgumentParser()
p.add_argument("--config", default="config.yaml")
p.add_argument("--batch-index", type=int, default=None)
p.add_argument("--batch-count", type=int, default=None)
args = p.parse_args()

cfg = yaml.safe_load(open(args.config))
items = list(range(cfg["n_items"]))
if args.batch_index is not None:
    items = items[args.batch_index :: args.batch_count]   # this batch's stride-slice

# --- your per-cell computation here -------------------------------------------
result = {"model": cfg["model"], "dataset": cfg["dataset"], "sum": sum(items)}

out = pathlib.Path("output")
out.mkdir(exist_ok=True)
suffix = "" if args.batch_index is None else f"_batch{args.batch_index}"
json.dump(result, open(out / f"results{suffix}.json", "w"), indent=2)
print("wrote", f"results{suffix}.json", result)
