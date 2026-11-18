import assert from 'node:assert/strict';
import fs from 'node:fs';
import ts from 'typescript';
const base = new URL('../src/lib/demo/', import.meta.url);
function load(name) {
  const source = fs.readFileSync(new URL(`${name}.ts`, base), 'utf8');
  const compiled = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS } });
  const exports = {};
  new Function('require', 'exports', compiled.outputText)(dependency => load(dependency.replace('./', '')), exports);
  return exports;
}
const { createSimulation, advance, summarize, scenarios } = load('overview-simulation');
const initial = summarize(createSimulation(), 'production', 5);
assert.deepEqual([initial.count, initial.errors, initial.p95, initial.availability], [200, 0, 394, 100]);
for (const scenario of Object.keys(scenarios)) {
  let simulation = { ...createSimulation(), scenario };
  for (let tick = 0; tick < 30; tick++) {
    simulation = advance(simulation);
    assert.ok(simulation.events.length <= 1000 && simulation.probes.length <= 1000);
    for (const minutes of [5, 15, 60, 1440]) {
      const data = summarize(simulation, 'production', minutes);
      assert.equal(data.buckets.reduce((n, b) => n + b.count, 0), data.count);
      assert.equal(data.endpoints.reduce((n, e) => n + e.count, 0), data.count);
      assert.equal(data.buckets.reduce((n, b) => n + b.errors, 0), data.errors);
      assert.ok(data.errors <= data.count);
      assert.ok(data.availability === null || data.availability >= 0 && data.availability <= 100);
      assert.ok(data.p95 === null || data.p50 <= data.p95 && data.p95 <= data.p99);
    }
  }
}
const empty = summarize(createSimulation(), 'staging', 5);
assert.deepEqual([empty.count, empty.p95, empty.availability], [0, null, null]);
console.log('PASS: seed, all scenarios/ranges, retention, aggregation, quantiles, and missing data.');
