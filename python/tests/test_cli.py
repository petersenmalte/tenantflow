import json
from pathlib import Path

from tenantflow.cli import main

EXAMPLE = Path(__file__).resolve().parents[2] / "examples" / "shared-rag.json"


def test_cedar_only_leaks_exit_1(capsys):
    assert main(["check", str(EXAMPLE), "--json"]) == 1
    res = json.loads(capsys.readouterr().out)
    assert res["leak"] and res["trace"] and res["violations"]


def test_tenantflow_no_leak_exit_0(capsys):
    assert main(["check", str(EXAMPLE), "--enforce", "tenantflow", "--depth", "3"]) == 0
    assert "no leak in the model" in capsys.readouterr().out


def test_integrity_counterexample(tmp_path, capsys):
    cfg = json.loads(EXAMPLE.read_text())
    cfg["index"] = []
    del cfg["tools"]["notify_insure"]  # only the integrity path remains
    p = tmp_path / "c.json"
    p.write_text(json.dumps(cfg))
    assert main(["check", str(p), "--depth", "2", "--json"]) == 1
    res = json.loads(capsys.readouterr().out)
    assert any("trusted-only" in v for v in res["violations"])
    assert main(["check", str(p), "--enforce", "tenantflow", "--depth", "3"]) == 0


def test_cedar_policy_blocks_the_path(tmp_path):
    cfg = json.loads(EXAMPLE.read_text())
    cfg["cedarPolicies"] = (
        'permit(principal == Role::"analyst", action == Action::"call:deliver", resource);'
    )
    p = tmp_path / "c.json"
    p.write_text(json.dumps(cfg))
    assert main(["check", str(p), "--depth", "3"]) == 0  # nothing allowed that leaks
