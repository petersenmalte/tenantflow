"""Trusted adapter: in-memory RAG index with tenant labels set from the session.

The adapter is part of the trusted computing base (``docs/spec.md`` assumptions): labels are
derived from the *session* (tenant, taint of the writing agent), never from document content, and
queries are filtered server-side before ranking. The embedding is a deterministic toy.
"""

from __future__ import annotations

import hashlib
from dataclasses import dataclass, field
from typing import Any

from .monitor import Doc, Label, score


def embed(text: str, dim: int = 64) -> list[int]:
    """Deterministic toy embedding: hashed bag of whitespace tokens (counts per bucket)."""
    vec = [0] * dim
    for tok in text.split():
        h = int.from_bytes(hashlib.sha256(tok.encode()).digest()[:4], "big")
        vec[h % dim] += 1
    return vec


@dataclass
class RagIndex:
    """Shared index; every document carries the label of the writing session's context."""

    top_k: int = 3
    docs: list[Doc] = field(default_factory=list)

    def write(self, ctx: Label, tenant: str, payload: Any) -> bool:
        """Store ``payload`` labelled with ``ctx``. Refused if ``ctx`` is not readable by ``tenant``
        (a tainted agent must not publish foreign data into the index)."""
        if not ctx.readable_by(tenant):
            return False
        self.docs.append(Doc(ctx, payload))
        return True

    def query(self, tenant: str, q: str) -> list[Doc]:
        """Server-side filtering: only documents readable by ``tenant`` are ranked at all."""
        visible = [d for d in self.docs if d.label.readable_by(tenant)]
        return sorted(visible, key=lambda d: -score(q, d.payload))[: self.top_k]
