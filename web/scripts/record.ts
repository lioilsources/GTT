// Re-records a vector file with the web client's rules: `metro vectors record --client web --module <id>`.
import { readFileSync, writeFileSync } from 'node:fs';

import { replayers, replayResult, rulesModules, type VectorFile } from '../src/rules/vectors';

const [module, file] = process.argv.slice(2);
if (!module || !file) throw new Error('usage: record <module> <vectors/module.json>');
const replay = replayers[module];
if (!replay) throw new Error(`no web replayer for ${module}`);
const v = JSON.parse(readFileSync(file, 'utf8')) as VectorFile;
for (const c of v.cases) {
  const states = replay(c);
  c.steps.forEach((s, i) => (s.state = states[i] ?? {}));
  if (module in rulesModules) c.result = replayResult(module, c) ?? null;
}
writeFileSync(file, JSON.stringify(v, null, 1) + '\n');
console.log(`recorded ${v.cases.length} cases of ${module} with web`);
