import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { parse } from 'yaml';
import { describe, expect, it } from 'vitest';

import { canonical, replayers, type VectorFile } from '../src/rules/vectors';

const root = join(__dirname, '..', '..');
const parity = parse(readFileSync(join(root, 'parity.yaml'), 'utf8')) as Array<{ vectors?: string; web: string }>;

// Vectors are replayed only for rows where the web client is done (DUALSTACK 5.6).
const done = parity.filter((r) => r.vectors && r.web === 'done').map((r) => r.vectors as string);

describe('P0 vectors', () => {
  for (const file of readdirSync(join(root, 'vectors')).filter((f) => f.endsWith('.json'))) {
    const v = JSON.parse(readFileSync(join(root, 'vectors', file), 'utf8')) as VectorFile;
    const replay = replayers[v.module];
    const pending = !done.includes(`vectors/${file}`) || !replay;
    describe.skipIf(pending)(v.module, () => {
      for (const c of v.cases) {
        it(c.name, () => {
          const states = replay!(c);
          c.steps.forEach((s, i) => expect(canonical(states[i]), `step ${i}`).toBe(canonical(s.state)));
        });
      }
    });
  }
});
