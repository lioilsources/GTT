import { minigameCatalog } from '../../gen/ids';
import type { Minigame, MinigameEnv } from '../api';
import { toast } from '../canvas';
import { h, svg } from '../dom';
import { aiPrng } from '../rules';
import { mountShell } from '../shell';
import { turnDriver } from '../turns';
import { SachyRules, material, sachyConfig, type SachyState } from './rules';

const CELL = 20;
/** Solid chess glyphs (no text), coloured per side by CSS. */
const GLYPH: Record<string, string> = { k: '♚', q: '♛', r: '♜', b: '♝', n: '♞', p: '♟' };

/**
 * Bulvárové šachy, specs/minigames/sachy.md: Gardner 5×5. Tap your piece to see its targets, tap a
 * target to move; the last move stays highlighted.
 */
export function sachy(env: MinigameEnv): Minigame {
  const { t, tuning } = env;
  const tm = tuning.minigames.sachy;
  return {
    meta: minigameCatalog.sachy,
    mount: (host, ctx, onFinish) =>
      mountShell(host, ctx, env, {
        id: 'sachy',
        rules: ['sachyRules1', 'sachyRules2', 'sachyRules3'],
        timeCapS: tm.timeCapS,
        start(api) {
          const rules = new SachyRules();
          const ai = aiPrng(ctx.seed);
          let s: SachyState = rules.init(sachyConfig(tm), ctx.seed);
          let sel = -1;
          let last: number[] = [];

          const board = svg('svg', { class: 'dama-board sachy-board', viewBox: '0 0 100 100', preserveAspectRatio: 'xMidYMid meet' });
          const info = h('div.board-info');
          api.body.append(h('div.board-game', {}, info, board));

          const driver = turnDriver({
            api, thinkS: tm.aiThinkS,
            aiTurn: () => !s.over && s.turn === 'ai',
            aiMove: () => play(rules.aiAction(s, ctx.difficulty, ai) as { by: 'ai'; from: number; to: number }),
            result: () => rules.result(s),
          });

          const moves = (): Array<{ from: number; to: number }> =>
            s.turn === 'player' && !s.over ? (rules.legalActions(s) as Array<{ from: number; to: number }>) : [];

          function draw(): void {
            board.replaceChildren();
            const ms = moves();
            const targets = new Set(ms.filter((m) => m.from === sel).map((m) => m.to));
            for (let i = 0; i < 25; i++) {
              const r = Math.floor(i / 5), c = i % 5;
              const x = c * CELL, y = r * CELL;
              const g = svg('g', { class: 'dama-cell' });
              g.append(svg('rect', { x, y, width: CELL, height: CELL, class: (r + c) & 1 ? 'sq dark' : 'sq light' }));
              if (last.includes(i) || i === sel) g.append(svg('rect', { x, y, width: CELL, height: CELL, class: 'trail' }));
              const ch = s.board[i]!;
              if (ch !== '.') {
                const p = svg('text', { x: x + CELL / 2, y: y + CELL * 0.78, class: `sachy-piece ${ch === ch.toUpperCase() ? 'player' : 'ai'}` });
                p.textContent = GLYPH[ch.toLowerCase()]! + '\uFE0E';
                g.append(p);
              }
              if (targets.has(i)) g.append(svg('circle', { cx: x + CELL / 2, cy: y + CELL / 2, r: CELL * 0.14, class: 'target' }));
              g.addEventListener('click', () => tap(i, ms));
              board.append(g);
            }
            info.textContent = t('sachyMaterial', { player: material(s.board, 'player'), ai: material(s.board, 'ai') });
            api.status(s.over ? '' : s.turn === 'player' ? t('yourTurn') : t('opponentTurn'));
          }

          function tap(i: number, ms: Array<{ from: number; to: number }>): void {
            if (api.paused || s.over || s.turn !== 'player') return;
            if (sel >= 0 && ms.some((m) => m.from === sel && m.to === i)) {
              play({ by: 'player', from: sel, to: i });
              return;
            }
            sel = ms.some((m) => m.from === i) ? i : -1;
            draw();
          }

          function play(a: { by: 'player' | 'ai'; from: number; to: number }): void {
            if (s.over) return;
            s = rules.apply(s, a);
            sel = -1;
            last = [a.from, a.to];
            draw();
            if (!s.over && rules.check(s)) toast(api.body, t('sachyCheck'), 900);
            driver.after();
          }

          draw();
          return {
            stop: () => driver.stop(),
            timeout: () => {
              if (s.over) return;
              driver.stop();
              s = rules.apply(s, { by: 'timeout' });
              draw();
              api.finish(rules.result(s)!);
            },
          };
        },
      }, onFinish),
  };
}
