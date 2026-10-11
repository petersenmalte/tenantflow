"""The deck numbers come from bench/results via web/deck/scripts/gen_variables.py."""

import re
import subprocess
import sys
from pathlib import Path

DECK = Path(__file__).resolve().parents[2] / "web" / "deck"


def test_variables_up_to_date():
    r = subprocess.run(
        [sys.executable, str(DECK / "scripts/gen_variables.py"), "--check"],
        capture_output=True,
        text=True,
    )
    assert r.returncode == 0, "run: python3 web/deck/scripts/gen_variables.py"


def test_every_var_used_by_the_slides_exists():
    text = (DECK / "index.qmd").read_text()
    have = {}
    path: list[tuple[int, str]] = []
    for line in (DECK / "_variables.yml").read_text().splitlines():
        if line.startswith("#") or not line.strip():
            continue
        ind = (len(line) - len(line.lstrip())) // 2
        key, _, val = line.strip().partition(":")
        path = [p for p in path if p[0] < ind]
        path.append((ind, key))
        if val.strip():
            have[".".join(k for _, k in path)] = val.strip()
    used = set(re.findall(r"\{\{< var ([\w.]+) >\}\}", text))
    assert used and used <= set(have), sorted(used - set(have))


def test_lean_statement_up_to_date():
    """_isolation.lean is committed (Quarto resolves includes before the pre-render script runs)."""
    sys.path.insert(0, str(DECK / "scripts"))
    import prepare

    assert (DECK / "_isolation.lean").read_text() == prepare.lean_statement("isolation"), (
        "run: python3 web/deck/scripts/prepare.py"
    )
