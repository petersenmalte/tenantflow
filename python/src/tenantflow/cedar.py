"""Per-call authorization with Cedar (``cedarpy``, Python bindings of the Rust ``cedar-policy``).

Request mapping: principal ``Role::"<role>"``, action ``Action::"<name>"`` with
``<name>`` in ``call:<tool> | query | write | delegate | report | receive`` (same names as the
oracle's ``cedar`` allow-list), resource ``Resource::"tenantflow"``.

Not used: the schema generator of ``cedar-policy/cedar-for-agents`` (needs MCP tool descriptors and
a Rust toolchain; the monitor only needs the flat action names). The schema below is hand-written
and checked with ``cedarpy.validate_policies``.
"""

from __future__ import annotations

import json
from collections.abc import Iterable

import cedarpy

RESOURCE = 'Resource::"tenantflow"'

SCHEMA_JSON = json.dumps(
    {
        "": {
            "entityTypes": {"Role": {}, "Resource": {}},
            "actions": {},
        }
    }
)


def _action_decl(name: str) -> dict:
    return {"appliesTo": {"principalTypes": ["Role"], "resourceTypes": ["Resource"]}}


def schema_for(actions: Iterable[str]) -> str:
    schema = json.loads(SCHEMA_JSON)
    schema[""]["actions"] = {a: _action_decl(a) for a in actions}
    return json.dumps(schema)


def _q(s: str) -> str:
    return json.dumps(s)  # Cedar string literals follow JSON escaping for our inputs


def policies_from_allow_list(allow: Iterable[tuple[str, str]]) -> str:
    return "\n".join(
        f"permit(principal == Role::{_q(role)}, action == Action::{_q(action)}, resource);"
        for role, action in allow
    )


class CedarAuthorizer:
    """Callable ``(role, action name) -> bool``; default deny."""

    def __init__(self, policies: str, entities: list | None = None) -> None:
        self.policies = policies
        self.entities = entities or []

    @classmethod
    def from_allow_list(cls, allow: Iterable[tuple[str, str]]) -> CedarAuthorizer:
        return cls(policies_from_allow_list(allow))

    def validate(self, actions: Iterable[str]) -> bool:
        return cedarpy.validate_policies(self.policies, schema_for(actions)).validation_passed

    def __call__(self, role: str, action: str) -> bool:
        request = {
            "principal": f"Role::{_q(role)}",
            "action": f"Action::{_q(action)}",
            "resource": RESOURCE,
            "context": {},
        }
        return cedarpy.is_authorized(request, self.policies, self.entities).allowed
