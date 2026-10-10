# Python monitor vs. Lean oracle – discrepancies

## D1 – duplicate session ids (input precondition, not a monitor bug)
Found by `python/tests/test_differential.py` (minimal case: two identical `sessions` entries, empty trace).
Lean `Exec.init` creates one agent per `cfg.sessions` entry, so duplicate `sid`s yield duplicate agent entries in
`final.agents`; the Python monitor keeps a dict. Session ids are unique by construction (the trusted session layer
issues them), so this is a precondition: Python raises `ValueError` on duplicates, the generator emits unique ids.
No `[FABLE]` task needed (no semantic difference for valid configurations).
