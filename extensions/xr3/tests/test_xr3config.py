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
