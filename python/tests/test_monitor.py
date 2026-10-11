from tenantflow.adapter import RagIndex, embed
from tenantflow.cedar import CedarAuthorizer
from tenantflow.example_server import demo_monitor, upstream
from tenantflow.gateway import Gateway
from tenantflow.monitor import Action, Label, payload_text, run_scenario, score

A1 = ("1", ())
A2 = ("2", ())


def test_score_and_text():
    assert score("a b", "a x b") == 2
    assert payload_text({"b": 1, "a": [1, "x"]}) == '{"a":[1,"x"],"b":1}'


def test_query_filters_other_tenant():
    mon = demo_monitor()
    r = mon.step(A1, Action("query", q="secret"))
    assert r.value == ["bank secret iban"]
    assert mon.agents[A1].ctx == Label(frozenset({"bank"}))


def test_taint_blocks_write_and_deliver_to_other_tenant():
    mon = demo_monitor()
    mon.index.append(
        __import__("tenantflow.monitor", fromlist=["Doc"]).Doc(
            Label(frozenset({"bank", "shop"})), "mixed"
        )
    )
    # tenants never see mixed docs
    assert "mixed" not in mon.step(A1, Action("query", q="mixed")).value


def test_untrusted_result_taints_and_deliver_ok():
    mon = demo_monitor()
    r = mon.step(A1, Action("call", tool="web_fetch", args={}))
    assert r.kind == "payload"
    assert mon.agents[A1].ctx.integ == "untrusted"
    assert mon.step(A1, Action("call", tool="deliver", args="x")).kind == "ok"


def test_unknown_and_unregistered():
    mon = demo_monitor()
    assert mon.step(("9", ()), Action("query", q="x")).denied
    assert mon.step(A1, Action("call", tool="nope", args=None)).denied


def test_delegate_report_receive():
    mon = demo_monitor()
    n = mon.step(A1, Action("delegate", role="sub", args="t")).value
    assert n == 0
    child = ("1", (0,))
    assert mon.step(A1, Action("report", args="x")).denied  # root has no parent
    assert not mon.step(child, Action("report", args="hi")).denied
    r = mon.step(A1, Action("receive", child=0))
    assert r.value == ["hi"]
    assert mon.step(A1, Action("receive", child=0)).value == []
    assert mon.step(A1, Action("receive", child=5)).denied


def test_cedar_default_deny_and_validate():
    c = CedarAuthorizer.from_allow_list([("analyst", "query")])
    assert c("analyst", "query") and not c("analyst", "write") and not c("x", "query")
    assert c.validate(["query", "write"])
    mon = demo_monitor(c)
    assert not mon.step(A1, Action("query", q="secret")).denied
    assert mon.step(A1, Action("write", args="p")).denied


def test_scenario_runner():
    sc = {
        "sessions": [{"sid": "1", "tenant": "bank", "user": "u1"}],
        "cedar": {"allow": [{"role": "default", "action": "query"}]},
        "index": [{"label": {"owners": ["bank"], "integrity": "trusted"}, "payload": "a b"}],
        "trace": [
            {"agent": {"session": "1"}, "action": {"op": "query", "q": "a"}},
            {"agent": {"session": "1"}, "action": {"op": "write", "payload": 1}},
        ],
    }
    out = run_scenario(sc)
    assert out["decisions"][0]["response"] == {"kind": "payloads", "values": ["a b"]}
    assert out["decisions"][1]["denied"]


def test_adapter():
    idx = RagIndex(top_k=1)
    assert idx.write(Label(frozenset({"a"})), "a", "x y")
    assert not idx.write(Label(frozenset({"a", "b"})), "a", "tainted")
    assert idx.query("b", "x") == []
    assert [d.payload for d in idx.query("a", "x")] == ["x y"]
    assert embed("a b") == embed("a b") and len(embed("a")) == 64


def test_gateway():
    mon = demo_monitor()
    gw = Gateway(mon, upstream)
    meta = {"agent": {"session": "1", "path": []}}

    def call(name, args):
        return gw.handle(
            {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "tools/call",
                "params": {"name": name, "arguments": args, "_meta": meta},
            }
        )["result"]

    assert not call("rag_query", {"q": "secret"})["isError"]
    assert not call("web_fetch", {})["isError"]
    assert not call("deliver", {"to": "x"})["isError"]
    assert call("rag_write", {"payload": "p"})["isError"] is False
    assert gw.handle({"jsonrpc": "2.0", "id": 2, "method": "tools/list"})["result"]["tools"]


def test_gateway_hides_denial_reason(caplog):
    """A8: the agent sees only `denied`; the reason is logged for the operator."""
    import logging

    gw = Gateway(demo_monitor(), upstream)
    req = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "tools/call",
        "params": {
            "name": "nope",
            "arguments": {},
            "_meta": {"agent": {"session": "1", "path": []}},
        },
    }
    with caplog.at_level(logging.INFO, logger="tenantflow.gateway"):
        res = gw.handle(req)["result"]
    assert res["isError"] and res["content"] == [{"type": "text", "text": "denied"}]
    assert "unregistered tool" in caplog.text
    assert "error" in gw.handle({"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {}})
