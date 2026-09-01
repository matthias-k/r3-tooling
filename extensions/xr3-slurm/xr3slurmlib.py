"""Pure SLURM string/parse helpers for xr3-slurm.

Stdlib only (no r3/executor) so it is unit-testable in base Python.
The xr3-slurm CLI does all I/O; this module does all parsing/formatting.
"""
from __future__ import annotations
