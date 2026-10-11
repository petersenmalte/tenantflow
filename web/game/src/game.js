// UI of "Leak the Vault". Plain DOM, no dependencies; all text is set via textContent.
(function () {
  "use strict";
  const { LEVELS, ALL_ACTIONS, withTrace } = TF;
  const M = TF, R = TF;
  const MODE_LABEL = { none: "Off", "cedar-only": "Cedar", fides: "FIDES", tenantflow: "TenantFlow" };
  const MODE_NOTE = {
    none: "No checks at all.",
    "cedar-only": "Per-call Cedar check only.",
    fides: "Cedar + a re-implementation of the FIDES label logic (agent-framework-core 1.5.0); it trusts labels inside data.",
    tenantflow: "Cedar + the information-flow monitor with tenant labels.",
  };

  const S = { level: 0, mode: "none", mon: null, log: [], last: null, done: null, why: null, policy: null, fuzz: null };

  const h = (tag, props, ...kids) => {
    const e = document.createElement(tag);
    for (const [k, v] of Object.entries(props || {})) {
      if (k === "class") e.className = v; else if (k.startsWith("on")) e.addEventListener(k.slice(2), v);
      else if (v === true) e.setAttribute(k, ""); else if (v !== false && v != null) e.setAttribute(k, v);
    }
    for (const k of kids.flat()) if (k != null) e.append(k.nodeType ? k : document.createTextNode(String(k)));
    return e;
  };
  const $ = (id) => document.getElementById(id);
  const lv = () => LEVELS[S.level];
  const show = (v) => (typeof v === "string" ? v : JSON.stringify(v));

  // ---- chips ----
  function chips(label) {
    const out = [];
    for (const o of [...label.owners].sort()) out.push(h("span", { class: "chip " + o }, o));
    if (!label.owners.size) out.push(h("span", { class: "chip empty" }, "no owner"));
    if (label.integ === TF.UNTRUSTED) out.push(h("span", { class: "chip untrusted" }, "untrusted"));
    return out;
  }
  const tenantOf = (a) => S.mon.sessions[a.session][0];
  const agentName = (a) => `${tenantOf(a)} agent ${TF.agentKey(a).replace(/\/$/, "")}`;

  // ---- setup ----
  function scenarioNow() {
    const sc = withTrace(lv(), []);
    if (lv().sandbox) sc.cedar = { allow: [...S.policy].map((k) => { const [role, action] = k.split("|"); return { role, action }; }) };
    return sc;
  }
  function reset() {
    if (lv().sandbox && !S.policy) S.policy = new Set(ALL_ACTIONS.map((a) => "analyst|" + a));
    S.mon = TF.monitorFromScenario(scenarioNow(), S.mode);
    S.log = []; S.last = null; S.done = null; S.why = null; S.fuzz = null;
    render();
  }

  // ---- stepping ----
  function doStep(agent, action) {
    const wasWon = R.won(lv().goal, S.mon, S.log);
    const response = S.mon.step(agent, action);
    const entry = { agent, action, response };
    S.log.push(entry);
    const st = S.mon.agents.get(TF.agentKey(agent));
    entry.ctx = st ? st.ctx : null;
    if (!TF.isDenied(response)) {
      if (response.kind === "payload") S.last = response.value;
      else if (response.kind === "payloads" && response.values.length) S.last = response.values[0];
    }
    const nowWon = R.won(lv().goal, S.mon, S.log);
    entry.why = R.explain(S.mode, action, response, { leak: nowWon && !wasWon });
    if (nowWon && !S.done) S.done = "win";
    S.why = entry;
    return entry;
  }
  function describe(a) {
    const x = a.action;
    switch (x.op) {
      case "call": return `call ${x.tool}(${show(x.args)})`;
      case "query": return `query "${x.q}"`;
      case "write": return `write ${show(x.payload)}`;
      case "delegate": return `delegate to role ${x.role}`;
      case "report": return `report ${show(x.payload)}`;
      default: return `receive from child ${x.child}`;
    }
  }
  function playSolution() {
    reset();
    for (const s of lv().solution) doStep(s.agent, s.action);
    if (!S.done) S.done = "safe";
    render();
  }

  // ---- render ----
  function renderLevels() {
    const nav = $("levels"); nav.replaceChildren();
    LEVELS.forEach((l, i) => nav.append(h("button", { "aria-current": i === S.level, onclick: () => { S.level = i; reset(); } }, `Level ${l.id}`)));
    const f = $("modes"); f.replaceChildren(h("legend", null, "Protection"));
    for (const m of TF.MODES)
      f.append(h("label", { title: MODE_NOTE[m] }, h("input", { type: "radio", name: "mode", value: m, checked: S.mode === m, onchange: () => { S.mode = m; reset(); } }), " " + MODE_LABEL[m]));
  }
  function renderBrief() {
    const l = lv();
    $("brief").replaceChildren(h("h2", null, `Level ${l.id}: ${l.title}`), h("p", null, l.story),
      h("p", { class: "muted" }, "Hint: " + l.hint), h("p", { class: "muted" }, `Protection: ${MODE_LABEL[S.mode]}. ${MODE_NOTE[S.mode]}`));
  }
  function renderBoard() {
    const grid = h("div", { class: "grid" });
    for (const st of S.mon.agents.values()) {
      const t = tenantOf(st.id);
      grid.append(h("div", { class: "box " + t }, h("h3", null, agentName(st.id)), h("div", { class: "muted" }, `role ${st.role}`),
        h("div", null, "context: ", chips(st.ctx))));
    }
    const idx = h("div", { class: "box" }, h("h3", null, "Shared RAG index"));
    if (!S.mon.index.length) idx.append(h("div", { class: "muted" }, "empty"));
    for (const d of S.mon.index) idx.append(h("div", { class: "doc" }, chips(d.label), h("span", { class: "mono" }, show(d.payload))));
    grid.append(idx);
    const ev = h("div", { class: "box" }, h("h3", null, "Tool calls seen by the world"));
    if (!S.mon.events.length) ev.append(h("div", { class: "muted" }, "none yet"));
    for (const e of S.mon.events) {
      const info = S.mon.toolInfo(e.tenant, e.tool);
      ev.append(h("div", { class: "doc" }, h("span", { class: "mono" }, `${e.tool}(${show(e.args)})`), " ", chips(e.label),
        info && info.observers.length ? h("span", { class: "muted" }, ` → seen by ${info.observers.join(", ")}`) : null));
    }
    grid.append(ev);
    $("board").replaceChildren(h("h2", null, "State"), grid);
  }
  function renderControls() {
    const box = $("controls");
    const agents = [...S.mon.agents.values()].map((s) => s.id);
    const agentSel = h("select", { id: "agent", "aria-label": "Acting agent" }, agents.map((a, i) => h("option", { value: i }, agentName(a))));
    const kinds = [...Object.keys(S.mon.tools).concat([TF.DELIVER]).map((t) => "call:" + t), "query", "write", "delegate", "report", "receive"];
    const kindSel = h("select", { id: "kind", "aria-label": "Action" }, kinds.map((k) => h("option", { value: k }, k.replace("call:", "call "))));
    const text = h("input", { type: "text", id: "text", "aria-label": "Argument or query", placeholder: "argument / query / payload" });
    const role = h("select", { id: "role", "aria-label": "Role of the child" }, ["analyst", "ops"].map((r) => h("option", { value: r }, r)));
    const child = h("input", { type: "text", id: "child", value: "0", size: 2, "aria-label": "Child index", style: "min-width:3rem;flex:0" });
    const sync = () => {
      const k = kindSel.value;
      role.hidden = k !== "delegate"; child.hidden = k !== "receive";
      text.hidden = k === "delegate" || k === "receive";
    };
    kindSel.addEventListener("change", sync);
    const useLast = h("button", { type: "button", title: "Put the last response into the field", onclick: () => { if (S.last != null) text.value = show(S.last); } }, "↩ last response");
    const run = h("button", { class: "primary", type: "button", onclick: () => {
      if (S.done === "win" && lv().goal !== "violation") return;
      const agent = agents[+agentSel.value], k = kindSel.value;
      let v = text.value; try { if (/^[\[{]/.test(v)) v = JSON.parse(v); } catch (_) { /* keep the string */ }
      const action = k.startsWith("call:") ? { op: "call", tool: k.slice(5), args: v }
        : k === "query" ? { op: "query", q: text.value } : k === "write" ? { op: "write", payload: v }
        : k === "delegate" ? { op: "delegate", role: role.value, task: "task" } : k === "report" ? { op: "report", payload: v }
        : { op: "receive", child: Math.max(0, parseInt(child.value, 10) || 0) };
      doStep(agent, action); render();
    } }, "Run step");
    box.replaceChildren(h("h2", null, "Your move"),
      h("div", { class: "row" }, h("label", null, "Agent ", agentSel), h("label", null, "Action ", kindSel)),
      h("div", { class: "row" }, text, role, child, useLast, run),
      h("div", { class: "row" }, h("button", { type: "button", onclick: reset }, "Reset level"),
        lv().solution.length ? h("button", { type: "button", onclick: playSolution }, "Show a winning attack") : null));
    sync();
    if (lv().sandbox) box.append(sandboxPanel());
  }
  function sandboxPanel() {
    const roles = ["analyst", "ops"];
    const table = h("table", null, h("tr", null, h("th", null, "action"), roles.map((r) => h("th", null, r))),
      ALL_ACTIONS.map((a) => h("tr", null, h("td", { class: "mono" }, a), roles.map((r) => {
        const key = r + "|" + a;
        return h("td", null, h("input", { type: "checkbox", "aria-label": `${r} may ${a}`, checked: S.policy.has(key),
          onchange: (ev) => { if (ev.target.checked) S.policy.add(key); else S.policy.delete(key); reset(); } }));
      }))));
    const seed = h("input", { type: "text", id: "seed", value: "1", size: 4, style: "min-width:4rem;flex:0", "aria-label": "Fuzzer seed" });
    const out = h("div", { id: "fuzzout", "aria-live": "polite" });
    if (S.fuzz) out.append(...fuzzResult(S.fuzz));
    return h("div", null, h("h2", null, "Cedar policy (allow-list)"), table,
      h("p", { class: "muted" }, "Cedar permits only what is checked. Delegation to role `ops` is how a child gets other rights."),
      h("div", { class: "row" }, h("label", null, "Seed ", seed),
        h("button", { class: "primary", type: "button", onclick: () => {
          const n = Math.max(1, parseInt(seed.value, 10) || 1);
          const res = R.fuzz(scenarioNow(), S.mode, "violation", { seed: n, episodes: 1000, length: 8 });
          S.fuzz = { res, seed: n }; render();
        } }, "Run fuzzer (1000 random episodes)")), out);
  }
  function fuzzResult(f) {
    if (!f.res) return [h("div", { class: "banner safe" }, `No violation found in 1000 random episodes of 8 steps (seed ${f.seed}). This is a bounded search, not a proof. For TenantFlow the proof is theorem Model.isolation, under the spec's assumptions.`)];
    const steps = f.res.steps;
    return [h("div", { class: "banner win" }, h("strong", null, `Leak found in episode ${f.res.episode}, shrunk to ${steps.length} step(s):`),
      h("ol", null, steps.map((s) => h("li", { class: "mono" }, `${agentName(s.agent)}: ${describe(s)}`))),
      h("button", { type: "button", onclick: () => { reset(); for (const s of steps) doStep(s.agent, s.action); S.fuzz = f; render(); } }, "Replay on the board"))];
  }
  function renderLog() {
    const box = $("log");
    const ol = h("ol", { id: "steps" });
    S.log.forEach((e, i) => {
      const d = TF.isDenied(e.response);
      ol.append(h("li", null, h("span", { class: "mono" }, `${agentName(e.agent)}: ${describe(e)}`), " ",
        d ? h("span", { class: "badge no" }, "✘ denied") : h("span", { class: "badge ok" }, "✔ allowed"),
        !d && e.response.kind !== "ok" && e.response.kind !== "child" ? h("div", { class: "mono muted" }, "→ " + show(e.response.value ?? e.response.values)) : null,
        e.ctx ? h("div", null, "context after: ", chips(e.ctx)) : null,
        " ", h("button", { type: "button", onclick: () => { S.why = e; renderWhy(); } }, "Why?")));
    });
    box.replaceChildren(h("h2", null, "Steps"), S.log.length ? ol : h("p", { class: "muted" }, "No steps yet."));
    if (S.done === "win" && lv().goal !== "violation")
      box.append(h("div", { class: "banner win" }, h("strong", null, "You got through. "), lv().lesson));
    else if (S.done === "safe" || (S.log.length && S.mode === "tenantflow" && lv().solution.length && S.log.length >= lv().solution.length && !S.done))
      box.append(h("div", { class: "banner safe" }, h("strong", null, "Blocked. "), lv().lesson));
  }
  function renderWhy() {
    const box = $("why");
    if (!S.why || !S.why.why) { box.hidden = true; return; }
    const w = S.why.why;
    box.hidden = false;
    box.replaceChildren(h("h2", null, "Why?"), h("p", null, w.text),
      h("p", { class: "muted" },
        w.theorem ? ["Lean theorem: ", h("a", { href: w.theorem.url }, w.theorem.name), ". "] : "No theorem is claimed about Cedar itself. ",
        w.slide ? ["Deck: ", h("a", { href: w.slide.href }, w.slide.label), "."] : ""));
  }
  function render() { renderLevels(); renderBrief(); renderBoard(); renderControls(); renderLog(); renderWhy(); }

  reset();
})();
