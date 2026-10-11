// The gameplay: drag moves (item onto target) as the board performs them, per level and protection mode.
const test = require("node:test");
const assert = require("node:assert");
const M = require("../src/monitor.js");
const L = require("../src/levels.js");
const R = require("../src/rules.js");
const { Session, compare } = require("../src/play.js");
const { THEOREMS } = require("../src/theorems.js");

const BANK = { session: "1", path: [] }, INS = { session: "2", path: [] }, HELPER = { session: "1", path: [0] };
const chip = (s, a, i = 0) => ({ kind: "chip", agent: a, chip: s.hand(a)[i] });

// Each level's intended drag sequence; returns the session.
const MOVES = {
  1: (s) => [s.drop({ kind: "source", tool: "vault" }, { kind: "agent", agent: INS })],
  2: (s) => [
    s.drop({ kind: "source", tool: "vault" }, { kind: "agent", agent: BANK }),
    s.drop(chip(s, BANK), { kind: "index" }),
    s.drop({ kind: "doc", i: s.mon.index.length - 1 }, { kind: "agent", agent: INS }),
  ],
  3: (s) => [
    s.drop(chip(s, BANK), { kind: "sink", tool: "forward" }),
    s.drop(chip(s, BANK), { kind: "sink", tool: "pay" }),
  ],
  4: (s) => [
    s.drop({ kind: "source", tool: "vault" }, { kind: "agent", agent: BANK }),
    s.drop(chip(s, BANK), { kind: "spawn", role: "ops" }),
    s.drop(chip(s, HELPER), { kind: "sink", tool: "notify_insure" }),
  ],
};
const WINS = { 1: ["none"], 2: ["none", "cedar-only", "fides"], 3: ["none", "cedar-only", "fides"], 4: ["none", "cedar-only", "fides"] };

for (const [id, moves] of Object.entries(MOVES))
  for (const mode of M.MODES)
    test(`level ${id} drag moves / ${mode}: ${WINS[id].includes(mode) ? "leaks" : "blocked"}`, () => {
      const s = new Session(L.LEVELS[id - 1], mode);
      const results = moves(s);
      assert.ok(results.every((r) => r !== null), "every move is a legal drop");
      assert.strictEqual(s.won, WINS[id].includes(mode));
      assert.deepStrictEqual(compare(L.LEVELS[id - 1])[mode], WINS[id].includes(mode), "scripted attack agrees with the drag moves");
      for (const e of s.log) assert.ok(e.why && e.why.short, "every step has an explanation");
    });

test("level 2 under TenantFlow: the write is allowed, the insurer's search filters the entry out", () => {
  const s = new Session(L.LEVELS[1], "tenantflow");
  const [r1, r2, r3] = MOVES[2](s);
  assert.ok(r1.ok && r2.ok);
  assert.strictEqual(r3.filtered, true);
  assert.ok(!JSON.stringify(s.hand(INS)).includes(L.CANARY), "no bank data in the insurer agent");
});

test("level 4 under TenantFlow: the helper carries the bank's label", () => {
  const s = new Session(L.LEVELS[3], "tenantflow");
  MOVES[4](s);
  assert.deepStrictEqual(M.labelJson(s.mon.agents.get("1/0").ctx).owners, ["bank"]);
  assert.strictEqual(s.log[s.log.length - 1].response.reason, "flow: context not readable by every observer of the tool");
});

test("theorem (e) is cited only when its hypothesis holds", () => {
  const s = new Session(L.LEVELS[1], "tenantflow");
  const [r1] = MOVES[2](s);
  assert.strictEqual(r1.entries[0].why.also, "Model.transparency"); // bank agent, fresh context, vault has no observers
  const s3 = new Session(L.LEVELS[2], "tenantflow");
  MOVES[3](s3); // after the untrusted reply the agent is no longer Single
  assert.strictEqual(s3.log[1].why.also, undefined);
  assert.ok(THEOREMS["Model.transparency"] && THEOREMS["Exec.transparency_denied"]);
});

test("illegal drops are rejected without a monitor step", () => {
  const s = new Session(L.LEVELS[1], "none");
  assert.strictEqual(s.drop({ kind: "source", tool: "vault" }, { kind: "index" }), null);
  assert.strictEqual(s.log.length, 0);
});

test("every theorem the game cites exists in lean/ (links in src/theorems.js)", () => {
  const cited = new Set(L.LEVELS.flatMap((l) => l.theorems || []));
  for (const mode of M.MODES) for (const lv of L.LEVELS) {
    const s = new Session(lv, mode);
    for (const st of lv.solution) { const e = s.run(st.agent, st.action); if (e.why.theorem) cited.add(e.why.theorem); }
  }
  cited.add(R.explainFiltered("tenantflow", { label: { owners: new Set(["bank"]) } }, "insure").theorem);
  cited.add("Model.isolation"); cited.add("Model.isolation_int");
  for (const t of cited) assert.ok(THEOREMS[t], `${t} missing: run node scripts/gen_theorems.js`);
});

test("theorem line anchors are current (warning only: lean/ may change in parallel)", (t) => {
  const r = require("child_process").spawnSync(process.execPath, [require("path").join(__dirname, "../scripts/gen_theorems.js"), "--check"]);
  if (r.status !== 0) t.diagnostic("src/theorems.js is stale: run node scripts/gen_theorems.js");
});
