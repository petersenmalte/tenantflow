// Goals, the random attacker (fuzzer) and the "Warum?" explanations.
(function (root) {
  "use strict";
  const M = typeof module !== "undefined" && module.exports ? require("./monitor.js") : root.TF;
  const L = typeof module !== "undefined" && module.exports ? require("./levels.js") : root.TF;

  // ---- goals: did the attacker win? `log` = [{agent, action, response}] ----
  function leaked(mon, log) {
    const insure = new Set(Object.entries(mon.sessions).filter(([, v]) => v[0] === "insure").map(([k]) => k));
    const seen = log.some((e) => insure.has(e.agent.session) && !M.isDenied(e.response) && JSON.stringify(e.response).includes(L.CANARY));
    const sunk = mon.events.some((e) => {
      const info = mon.toolInfo(e.tenant, e.tool);
      return info && info.observers.includes("insure") && JSON.stringify(e.args).includes(L.CANARY);
    });
    return seen || sunk;
  }
  const forgedPay = (mon) => mon.events.some((e) => e.tool === "pay" && e.label.integ === M.UNTRUSTED);
  function won(goal, mon, log) {
    if (goal === "leak") return leaked(mon, log);
    if (goal === "forgedPay") return forgedPay(mon);
    return M.violations(mon).any;
  }

  // ---- fuzzer: random actions of random agents, seeded, with greedy shrinking ----
  function rng(seed) {
    let s = seed >>> 0;
    return () => { s = (s + 0x6d2b79f5) >>> 0; let t = s; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
  }
  function randomStep(r, mon, last) {
    const pick = (xs) => xs[Math.floor(r() * xs.length)];
    const agent = pick([...mon.agents.values()]).id;
    const payloads = ["hello", "wire 10 to acct 9", L.FORGED, L.CANARY, last ?? "none"];
    const toolNames = [M.DELIVER, ...Object.keys(mon.tools)];
    const kind = pick(["call", "call", "query", "write", "delegate", "report", "receive"]);
    const st = mon.agents.get(M.agentKey(agent));
    switch (kind) {
      case "call": return { agent, action: { op: "call", tool: pick(toolNames), args: pick(payloads) } };
      case "query": return { agent, action: { op: "query", q: pick([L.CANARY, "bank account", "CANARY-INSURE", "policy"]) } };
      case "write": return { agent, action: { op: "write", payload: pick(payloads) } };
      case "delegate": return { agent, action: { op: "delegate", role: pick(["analyst", "ops"]), task: "t" } };
      case "report": return { agent, action: { op: "report", payload: pick(payloads) } };
      default: return { agent, action: { op: "receive", child: Math.floor(r() * (st.nextChild + 1)) } };
    }
  }
  function replay(scenario, mode, steps, goal) {
    const mon = M.monitorFromScenario({ ...scenario, trace: [] }, mode);
    const log = [];
    for (const s of steps) { const response = mon.step(s.agent, s.action); log.push({ ...s, response }); }
    return { mon, log, won: won(goal, mon, log) };
  }
  /** Returns {steps, episode} of a shrunk winning sequence, or null. */
  function fuzz(scenario, mode, goal, { seed = 1, episodes = 500, length = 8 } = {}) {
    const r = rng(seed);
    for (let ep = 0; ep < episodes; ep++) {
      const mon = M.monitorFromScenario({ ...scenario, trace: [] }, mode);
      const steps = [], log = [];
      let last = null;
      for (let i = 0; i < length; i++) {
        const s = randomStep(r, mon, last);
        const response = mon.step(s.agent, s.action);
        steps.push(s); log.push({ ...s, response });
        if (!M.isDenied(response) && response.kind === "payloads" && response.values.length) last = response.values[0];
        else if (response.kind === "payload") last = response.value;
        if (won(goal, mon, log)) return { steps: shrink(scenario, mode, steps, goal), episode: ep + 1 };
      }
    }
    return null;
  }
  function shrink(scenario, mode, steps, goal) {
    let cur = steps.filter((s, i) => true);
    for (let i = cur.length - 1; i >= 0; i--) {
      const cand = cur.filter((_, j) => j !== i);
      if (replay(scenario, mode, cand, goal).won) cur = cand;
    }
    return cur;
  }

  // ---- "Warum?" ----
  const DECK = "../deck/index.html#/";
  const LEAN = "https://github.com/petersenmalte/tenantflow/blob/main/lean/TenantFlow/Proofs.lean";
  const thm = (name) => ({ name, url: LEAN });
  const slide = (n, title) => ({ label: `Slide ${n}: ${title}`, href: DECK + (n - 1) });

  /** One sentence for a step. `before`/`after`: {won} flags of the goal; `mode`; act; resp. */
  function explain(mode, act, resp, ctx) {
    const name = act.op === "call" ? "call:" + act.tool : act.op;
    if (M.isDenied(resp)) {
      const r = resp.reason;
      if (r === "cedar") return { text: `Cedar denies \`${name}\` for this role. Cedar judges each call on its own: it checks the role and the action, nothing else.`, slide: slide(2, "What Cedar checks per call") };
      if (r.startsWith("flow: context not readable"))
        return { text: `Blocked by the flow monitor: the agent's context carries data of another tenant, and the tool's output is observed by that tenant. The label comes from where the data was read, not from what it says.`, theorem: thm("Model.isolation"), slide: slide(6, "The invariant as a formula") };
      if (r.startsWith("flow: tool requires trusted"))
        return { text: "Blocked by the flow monitor: this tool needs trusted input, but the context contains untrusted data. The registry labels the result of `fetch` untrusted; labels written inside the data are ignored.", theorem: thm("Model.isolation_int"), slide: slide(5, "The forgery attack") };
      if (r.startsWith("flow: tainted"))
        return { text: "Blocked by the flow monitor: the agent has read data of another tenant and may not write it to the shared index.", theorem: thm("Model.isolation"), slide: slide(4, "Labels") };
      if (r.startsWith("fides:")) return { text: "FIDES blocks it: its integrity label says the context is untrusted.", slide: slide(5, "The forgery attack") };
      return { text: `Denied: ${r}.` };
    }
    if (ctx.leak) {
      const why = {
        none: "No protection is active, so nothing is checked.",
        "cedar-only": "Cedar allowed this call, and without labels nothing remembers where the data came from.",
        fides: "FIDES has no tenant in its labels, and it trusts a label that the data assigns to itself.",
      }[mode];
      return { text: `Allowed, and this is the leak. ${why}`, slide: slide(3, "Three allowed calls, one leak") };
    }
    if (mode === "tenantflow" && act.op === "query")
      return { text: "Allowed. Only documents labelled for this tenant are ranked; the context label is the join of what was returned.", theorem: thm("Model.isolation"), slide: slide(4, "Labels") };
    if (mode === "tenantflow" && act.op === "write")
      return { text: "Allowed: the document is stored with the writer's context label. Whoever reads it later inherits that label.", theorem: thm("Model.no_launder"), slide: slide(4, "Labels") };
    if (mode === "tenantflow" && act.op === "delegate")
      return { text: "Allowed: the child starts with its parent's label, so delegation cannot shed it.", theorem: thm("Model.child_ctx_eq"), slide: slide(4, "Labels") };
    return { text: "Allowed.", slide: slide(2, "What Cedar checks per call") };
  }

  const api = { leaked, forgedPay, won, fuzz, replay, explain, rng };
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else root.TF = Object.assign(root.TF || {}, api);
})(typeof globalThis !== "undefined" ? globalThis : this);
