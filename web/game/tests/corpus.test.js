// S16: randomised differential test. tests/fixtures/corpus.json.gz holds scenarios drawn from the Hypothesis
// strategies of python/tests/test_differential.py with the Lean oracle's output (TenantFlow) and the Python
// baselines' outputs (none, cedar-only, fides); regenerate with scripts/gen_corpus.py.
const test = require("node:test");
const assert = require("node:assert");
const fs = require("fs"), path = require("path"), zlib = require("zlib");
const M = require("../src/monitor.js");

const corpus = JSON.parse(zlib.gunzipSync(fs.readFileSync(path.join(__dirname, "fixtures/corpus.json.gz"))));
const norm = (out) => JSON.parse(JSON.stringify({ decisions: out.decisions, final: out.final }));

for (const mode of M.MODES)
  test(`corpus: JS ${mode} agrees with the reference on ${corpus.length} random scenarios`, () => {
    let steps = 0;
    for (const [i, { scenario, expected }] of corpus.entries()) {
      const got = norm(M.runScenario(scenario, mode));
      steps += scenario.trace.length;
      assert.deepStrictEqual(got, expected[mode], `scenario #${i}: ${JSON.stringify(scenario)}`);
    }
    assert.ok(steps > 10000);
  });

test("corpus exercises every flow denial of the monitor", () => {
  const reasons = new Set(corpus.flatMap((c) => c.expected.tenantflow.decisions.map((d) => d.response.reason)));
  for (const r of ["flow: context not readable by every observer of the tool", "flow: tool requires trusted input",
    "flow: tainted agent may not write", "cedar"]) assert.ok(reasons.has(r), r);
});
