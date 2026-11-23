import { minigameCatalog } from '../../gen/ids';
import type { Minigame, MinigameEnv } from '../api';
import { h, svg } from '../dom';
import { aiPrng } from '../rules';
import { mountShell } from '../shell';
import { turnDriver } from '../turns';
import { MILLS, MlynRules, mlynConfig, type MlynAction, type MlynState } from './rules';

/** Point positions on a 7×7 grid (specs/minigames/mlyn.md "Deska"). */
const XY: ReadonlyArray<readonly [number, number]> = [
  [0, 0], [3, 0], [6, 0], [1, 1], [3, 1], [5, 1], [2, 2], [3, 2], [4, 2],
  [0, 3], [1, 3], [2, 3], [4, 3], [5, 3], [6, 3],
  [2, 4], [3, 4], [4, 4], [1, 5], [3, 5], [5, 5], [0, 6], [3, 6], [6, 6],
];
const px = (p: number): [number, number] => [8 + XY[p]![0] * 14, 8 + XY[p]![1] * 14];

type Move = { by: 'player' | 'ai'; from: number; to: number; remove: number };

/**
 * Mlýn, specs/minigames/mlyn.md: placing by tapping a point, moving by tapping a stone and then
 * its target; after a mill the board recolours and the player taps the rival stone to take.
 */
export function mlyn(env: MinigameEnv): Minigame {
  const { t, tuning } = env;
  const tm = tuning.minigames.mlyn;
  return {
    meta: minigameCatalog.mlyn,
    mount: (host, ctx, onFinish) =>
      mountShell(host, ctx, env, {
        id: 'mlyn',
        rules: ['mlynRules1', 'mlynRules2', 'mlynRules3'],
        timeCapS: tm.timeCapS,
        start(api) {
          const rules = new MlynRules();
          const ai = aiPrng(ctx.seed);
          let s: MlynState = rules.init(mlynConfig(tm), ctx.seed);
          let legal: Move[] = [];
          let from = -1;
          /** Moves waiting for the removal choice (same from and to). */
          let taking: Move[] = [];
          let lastAi: Move | null = null;

          const board = svg('svg', { class: 'mill-board', viewBox: '0 0 100 100', preserveAspectRatio: 'xMidYMid meet' });
          const info = h('div.board-info');
          const note = h('div.board-note');
          api.body.append(h('div.board-game', {}, info, board, note));

          const driver = turnDriver({
            api, thinkS: tm.aiThinkS,
            aiTurn: () => !s.over && s.turn === 'ai',
            aiMove: () => play(rules.aiAction(s, ctx.difficulty, ai) as Move),
            result: () => rules.result(s),
          });

          const refresh = (): void => {
            legal = s.turn === 'player' && !s.over ? (rules.legalActions(s) as Move[]) : [];
          };

          function draw(): void {
            board.replaceChildren();
            for (const [a, , c] of MILLS) {
              const [x1, y1] = px(a), [x2, y2] = px(c);
              board.append(svg('line', { x1, y1, x2, y2, class: 'mill-line' }));
            }
            const placing = s.hand.player > 0;
            const targets = new Set(taking.length ? [] : legal.filter((m) => (placing ? m.from === -1 : m.from === from)).map((m) => m.to));
            const movable = new Set(placing ? [] : legal.map((m) => m.from));
            const removable = new Set(taking.map((m) => m.remove));
            for (let p = 0; p < 24; p++) {
              const [x, y] = px(p);
              const g = svg('g', { class: 'mill-point' });
              g.append(svg('circle', { cx: x, cy: y, r: 6.5, class: 'hit' }));
              const ch = s.board[p];
              if (ch === '.') {
                g.append(svg('circle', { cx: x, cy: y, r: targets.has(p) && (placing || from >= 0) ? 2.2 : 1.4, class: targets.has(p) && (placing || from >= 0) ? 'dot target' : 'dot' }));
              } else {
                let cls = ch === 'w' ? 'stone player' : 'stone ai';
                if (p === from) cls += ' selected';
                else if (removable.has(p)) cls += ' take';
                else if (!taking.length && movable.has(p)) cls += ' movable';
                if (lastAi?.to === p) cls += ' last';
                g.append(svg('circle', { cx: x, cy: y, r: 4.6, class: cls }));
              }
              g.addEventListener('click', () => tap(p));
              board.append(g);
            }
            info.textContent = t('mlynHand', { player: s.hand.player, ai: s.hand.ai });
            api.status(s.over ? '' : s.turn === 'player' ? t('yourTurn') : t('opponentTurn'));
            note.textContent = taking.length ? t('mlynTake') : '';
          }

          function tap(p: number): void {
            if (api.paused || s.over || s.turn !== 'player') return;
            if (taking.length) {
              const m = taking.find((x) => x.remove === p);
              if (m) {
                taking = [];
                from = -1;
                play(m);
              }
              return;
            }
            const placing = s.hand.player > 0;
            if (!placing && s.board[p] === 'w') {
              from = legal.some((m) => m.from === p) ? p : -1;
              draw();
              return;
            }
            const f = placing ? -1 : from;
            if (!placing && f < 0) return;
            const ms = legal.filter((m) => m.from === f && m.to === p);
            if (!ms.length) return;
            if (ms.length === 1 && ms[0]!.remove === -1) {
              from = -1;
              play(ms[0]!);
              return;
            }
            // A mill: the player taps the rival stone to take (even when only one is allowed).
            taking = ms;
            draw();
          }

          function play(a: Move): void {
            if (s.over) return;
            s = rules.apply(s, a);
            lastAi = a.by === 'ai' ? a : lastAi;
            refresh();
            draw();
            driver.after();
          }

          refresh();
          draw();
          return {
            stop: () => driver.stop(),
            timeout: () => {
              if (s.over) return;
              driver.stop();
              s = rules.apply(s, { by: 'timeout' } as MlynAction);
              taking = [];
              legal = [];
              draw();
              api.finish(rules.result(s)!);
            },
          };
        },
      }, onFinish),
  };
}
