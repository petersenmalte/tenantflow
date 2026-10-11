"""Pre-render step of the deck (run by Quarto, see _quarto.yml; stdlib only).

1. _variables.yml from bench/results/results.json (gen_variables.py).
2. _isolation.lean: the statement of `isolation`, extracted from lean/TenantFlow/Proofs.lean (no hand-copying).
3. game/ and img/: a copy of the browser game (web/game) for the live widgets and the "play" links, and the benchmark plot; git-ignored.
"""
# ruff: noqa: E501

from __future__ import annotations

import re
import shutil
import sys
from pathlib import Path

DECK = Path(__file__).resolve().parents[1]
ROOT = DECK.parents[1]
sys.path.insert(0, str(DECK / "scripts"))
import gen_variables  # noqa: E402


def lean_statement(name: str) -> str:
    text = (ROOT / "lean/TenantFlow/Proofs.lean").read_text()
    m = re.search(rf"^theorem {name} .*?:= by", text, re.S | re.M)
    if not m:
        raise SystemExit(f"theorem {name} not found")
    return m.group(0).removesuffix(":= by").rstrip() + " := …\n"


def main() -> int:
    gen_variables.main()
    (DECK / "_isolation.lean").write_text(lean_statement("isolation"))
    dst = DECK / "game"
    shutil.rmtree(dst, ignore_errors=True)
    shutil.copytree(ROOT / "web/game", dst, ignore=shutil.ignore_patterns("node_modules", "tests", "scripts", "*.json", "README.md"))
    for f in (dst / "src/rules.js", dst / "index.html"):  # inside the deck, the deck is one level up
        f.write_text(f.read_text().replace("../deck/index.html", "../index.html"))
    (DECK / "img").mkdir(exist_ok=True)
    shutil.copy(ROOT / "bench/results/plots/summary-light.png", DECK / "img/summary-light.png")
    print("prepared _variables.yml, _isolation.lean, game/")
    return 0


if __name__ == "__main__":
    sys.exit(main())
