import { minigameCatalog } from '../../gen/ids';
import type { Minigame, MinigameEnv } from '../api';
import { h, svg } from '../dom';
import { mountShell } from '../shell';
import { PosuvneRules, posuvneConfig, type PosuvneState } from './rules';

/**
 * Posuvné puzzle, specs/minigames/posuvne.md: a tap on a tile in the gap's row or column slides the
 * whole run; the UI sends the single moves from the gap outwards.
 */
export function posuvne(env: MinigameEnv): Minigame {
  const { t, tuning } = env;
  const tm = tuning.minigames.posuvne;
  return {
    meta: minigameCatalog.posuvne,
    mount: (host, ctx, onFinish) =>
      mountShell(host, ctx, env, {
        id: 'posuvne',
        rules: ['posuvneRules1', 'posuvneRules2', 'posuvneRules3'],
        timeCapS: tm.timeCapS,
        start(api) {
          const rules = new PosuvneRules();
          let s: PosuvneState = rules.init(posuvneConfig(tm, ctx.difficulty), ctx.seed);
          let finishTimer = 0;

          const board = svg('svg', { class: 'grid-board slide-board', viewBox: '0 0 100 100', preserveAspectRatio: 'xMidYMid meet' });
          const info = h('div.board-info');
          api.body.append(h('div.board-game', {}, info, board, h('div.board-note')));

          function draw(): void {
            board.replaceChildren();
            for (let p = 0; p < 16; p++) {
              const n = s.tiles[p]!;
              if (n === 0) continue;
              const x = (p & 3) * 25, y = (p >> 2) * 25;
              const g = svg('g', { class: 'grid-cell' });
              g.append(svg('rect', { x: x + 1, y: y + 1, width: 23, height: 23, rx: 3, class: n === p + 1 ? 'tile home' : 'tile' }));
              const label = svg('text', { x: x + 12.5, y: y + 13, class: 'tile-num' });
              label.textContent = String(n);
              g.append(label);
              g.addEventListener('click', () => tap(p));
              board.append(g);
            }
            info.textContent = t('posuvneMoves', { moves: s.moves, par: s.par });
            api.status('');
          }

          function tap(p: number): void {
            if (api.paused || s.over) return;
            const gap = s.tiles.indexOf(0);
            const sameRow = p >> 2 === gap >> 2, sameCol = (p & 3) === (gap & 3);
            if (p === gap || (!sameRow && !sameCol)) return;
            const step = sameRow ? (p > gap ? 1 : -1) : p > gap ? 4 : -4;
            // From the gap outwards: each tile next to the gap slides in turn.
            for (let q = gap + step; !s.over; q += step) {
              s = rules.apply(s, { by: 'player', tile: s.tiles[q]! });
              if (q === p) break;
            }
            draw();
            const r = rules.result(s);
            if (r) finishTimer = window.setTimeout(() => api.finish(r), 700);
          }

          draw();
          return {
            stop: () => window.clearTimeout(finishTimer),
            timeout: () => {
              if (s.over) return;
              s = rules.apply(s, { by: 'timeout' });
              draw();
              api.finish(rules.result(s)!);
            },
          };
        },
      }, onFinish),
  };
}
