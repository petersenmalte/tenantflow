// Writes the scripted attack of every level as an oracle scenario: tests/fixtures/scenarios.json
const fs = require("fs"), path = require("path");
const { LEVELS, withTrace } = require("../src/levels.js");
const out = LEVELS.filter((l) => l.solution.length).map((l) => ({ id: "level" + l.id, scenario: withTrace(l, l.solution) }));
fs.writeFileSync(path.join(__dirname, "../tests/fixtures/scenarios.json"), JSON.stringify(out, null, 1) + "\n");
console.log("wrote", out.length, "scenarios");
