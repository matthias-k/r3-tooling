import sys
from pathlib import Path

# Make `import xr3config` work regardless of pytest's rootdir.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import pytest
import xr3config


def test_load_config_missing_returns_defaults(tmp_path):
    cfg = xr3config.load_config(str(tmp_path / "nope.yaml"))
    assert cfg["blockers"]["tags"] == ["bug/"]
    assert cfg["blockers"]["block_on_wip"] is True
    assert cfg["pathmap"]["roots"] == []
    assert cfg["dev_checkout"]["ignored_destinations"] == []
    assert cfg["dev_checkout"]["ignored_repositories"] == []


def test_load_config_merges_over_defaults(tmp_path):
    p = tmp_path / "xr3.yaml"
    p.write_text(
        "blockers:\n"
        "  tags: ['bug/', 'wip/']\n"
        "pathmap:\n"
        "  roots:\n"
        "    - path: /a/b\n"
    )
    cfg = xr3config.load_config(str(p))
    assert cfg["blockers"]["tags"] == ["bug/", "wip/"]
    # deep-merge keeps sibling defaults not present in the file:
    assert cfg["blockers"]["block_on_wip"] is True
    assert cfg["pathmap"]["roots"] == [{"path": "/a/b"}]


def test_load_config_env_override(tmp_path, monkeypatch):
    p = tmp_path / "env.yaml"
    p.write_text("blockers:\n  block_on_wip: false\n")
    monkeypatch.setenv("XR3_CONFIG", str(p))
    cfg = xr3config.load_config()  # no explicit path -> uses $XR3_CONFIG
    assert cfg["blockers"]["block_on_wip"] is False


def test_load_config_non_mapping_raises(tmp_path):
    p = tmp_path / "bad.yaml"
    p.write_text("- just\n- a\n- list\n")
    with pytest.raises(ValueError):
        xr3config.load_config(str(p))


def test_resolve_job_path_basic(tmp_path):
    root = tmp_path / "proj"
    (root / "exp" / "v1").mkdir(parents=True)
    cfg = {"pathmap": {"roots": [{"path": str(root)}]}}
    assert xr3config.resolve_job_path(root / "exp" / "v1", cfg) == "exp/v1"


def test_resolve_job_path_prefix(tmp_path):
    root = tmp_path / "tasks"
    (root / "job").mkdir(parents=True)
    cfg = {"pathmap": {"roots": [{"path": str(root), "prefix": "combined"}]}}
    assert xr3config.resolve_job_path(root / "job", cfg) == "combined/job"


def test_resolve_job_path_longest_root_wins(tmp_path):
    outer = tmp_path / "o"
    inner = outer / "i"
    (inner / "job").mkdir(parents=True)
    cfg = {"pathmap": {"roots": [{"path": str(outer)}, {"path": str(inner)}]}}
    # inner is more specific -> path relative to inner
    assert xr3config.resolve_job_path(inner / "job", cfg) == "job"


def test_resolve_job_path_no_match_raises(tmp_path):
    (tmp_path / "elsewhere" / "job").mkdir(parents=True)
    cfg = {"pathmap": {"roots": [{"path": str(tmp_path / "other")}]}}
    with pytest.raises(xr3config.PathmapError) as excinfo:
        xr3config.resolve_job_path(tmp_path / "elsewhere" / "job", cfg)
    assert "pathmap" in str(excinfo.value).lower()


def test_resolve_job_path_no_roots_raises(tmp_path):
    with pytest.raises(xr3config.PathmapError):
        xr3config.resolve_job_path(tmp_path / "job", {"pathmap": {"roots": []}})
