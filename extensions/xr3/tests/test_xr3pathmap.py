import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import pytest
import xr3pathmap


def test_resolve_job_path_basic(tmp_path):
    root = tmp_path / "proj"
    (root / "exp" / "v1").mkdir(parents=True)
    cfg = {"pathmap": {"roots": [{"path": str(root)}]}}
    assert xr3pathmap.resolve_job_path(root / "exp" / "v1", cfg) == "exp/v1"


def test_resolve_job_path_prefix(tmp_path):
    root = tmp_path / "tasks"
    (root / "job").mkdir(parents=True)
    cfg = {"pathmap": {"roots": [{"path": str(root), "prefix": "combined"}]}}
    assert xr3pathmap.resolve_job_path(root / "job", cfg) == "combined/job"


def test_resolve_job_path_longest_root_wins(tmp_path):
    outer = tmp_path / "o"
    inner = outer / "i"
    (inner / "job").mkdir(parents=True)
    cfg = {"pathmap": {"roots": [{"path": str(outer)}, {"path": str(inner)}]}}
    assert xr3pathmap.resolve_job_path(inner / "job", cfg) == "job"


def test_resolve_job_path_no_match_raises(tmp_path):
    (tmp_path / "elsewhere" / "job").mkdir(parents=True)
    cfg = {"pathmap": {"roots": [{"path": str(tmp_path / "other")}]}}
    with pytest.raises(xr3pathmap.PathmapError) as excinfo:
        xr3pathmap.resolve_job_path(tmp_path / "elsewhere" / "job", cfg)
    assert "pathmap" in str(excinfo.value).lower()


def test_resolve_job_path_no_roots_raises(tmp_path):
    with pytest.raises(xr3pathmap.PathmapError):
        xr3pathmap.resolve_job_path(tmp_path / "job", {"pathmap": {"roots": []}})


def test_resolve_job_path_error_names_config_source(tmp_path):
    with pytest.raises(xr3pathmap.PathmapError) as excinfo:
        xr3pathmap.resolve_job_path(
            tmp_path / "job", {"pathmap": {"roots": []}}, config_source="/my/cfg.yaml"
        )
    assert "/my/cfg.yaml" in str(excinfo.value)


def test_base_root_no_prefix_has_no_leading_slash(tmp_path):
    # A prefix-less "base root": subpath maps directly, first dir is first segment.
    root = tmp_path / "projects"
    (root / "research" / "exp" / "v1").mkdir(parents=True)
    cfg = {"pathmap": {"roots": [{"path": str(root)}]}}
    result = xr3pathmap.resolve_job_path(root / "research" / "exp" / "v1", cfg)
    assert result == "research/exp/v1"
    assert not result.startswith("/")


def test_multiple_base_roots_longest_match_wins(tmp_path):
    outer = tmp_path / "projects"
    inner = outer / "research"
    (inner / "exp" / "v1").mkdir(parents=True)
    cfg = {"pathmap": {"roots": [{"path": str(outer)}, {"path": str(inner)}]}}
    # inner is the longer match -> strips inner, not outer
    assert xr3pathmap.resolve_job_path(inner / "exp" / "v1", cfg) == "exp/v1"


def test_tilde_expansion_in_root(tmp_path, monkeypatch):
    monkeypatch.setenv("HOME", str(tmp_path))
    (tmp_path / "projects" / "research" / "v1").mkdir(parents=True)
    cfg = {"pathmap": {"roots": [{"path": "~/projects"}]}}
    assert xr3pathmap.resolve_job_path(
        tmp_path / "projects" / "research" / "v1", cfg
    ) == "research/v1"


def test_envvar_expansion_in_root(tmp_path, monkeypatch):
    monkeypatch.setenv("MYBASE", str(tmp_path / "projects"))
    (tmp_path / "projects" / "research" / "v1").mkdir(parents=True)
    cfg = {"pathmap": {"roots": [{"path": "$MYBASE"}]}}
    assert xr3pathmap.resolve_job_path(
        tmp_path / "projects" / "research" / "v1", cfg
    ) == "research/v1"


def test_job_dir_equals_root_raises(tmp_path):
    root = tmp_path / "projects"
    root.mkdir()
    cfg = {"pathmap": {"roots": [{"path": str(root)}]}}
    with pytest.raises(xr3pathmap.PathmapError) as excinfo:
        xr3pathmap.resolve_job_path(root, cfg)
    assert "pathmap root" in str(excinfo.value).lower()
