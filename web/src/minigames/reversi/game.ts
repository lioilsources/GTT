import { minigameCatalog } from '../../gen/ids';
import type { Minigame, MinigameEnv } from '../api';
import { h, svg } from '../dom';
import { aiPrng } from '../rules';
import { mountShell } from '../shell';
import { turnDriver } from '../turns';
import { ReversiRules, discs, reversiConfig, type ReversiState } from './rules';

/**
 * Reversi, specs/minigames/reversi.md: legal squares carry small dots, a tap plays. Without a legal
 * move the UI passes on its own with a short toast.
 */
export function reversi(env: MinigameEnv): Minigame {
  const { t, tuning } = env;
  const tm = tuning.minigames.reversi;
  return {
    meta: minigameCatalog.reversi,
    mount: (host, ctx, onFinish) =>
      mountShell(host, ctx, env, {
        id: 'reversi',
        rules: ['reversiRules1', 'reversiRules2', 'reversiRules3'],
        timeCapS: tm.timeCapS,
        start(api) {
          const rules = new ReversiRules();
          const ai = aiPrng(ctx.seed);
          let s: ReversiState = rules.init(reversiConfig(tm), ctx.seed);
          let last = -1;
          let passTimer = 0;

          const board = svg('svg', { class: 'grid-board reversi-board', viewBox: '0 0 80 80', preserveAspectRatio: 'xMidYMid meet' });
          const info = h('div.board-info');
          const note = h('div.board-note');
          api.body.append(h('div.board-game', {}, info, board, note));

          const driver = turnDriver({
            api, thinkS: tm.aiThinkS,
            aiTurn: () => !s.over && s.turn === 'ai',
            aiMove: () => play(rules.aiAction(s, ctx.difficulty, ai) as { by: 'ai'; cell: number }),
            result: () => rules.result(s),
          });

          const legalCells = (): number[] =>
            s.turn === 'player' && !s.over ? rules.legalActions(s).map((a) => ('cell' in a ? a.cell : -1)) : [];

          function draw(): void {
            board.replaceChildren();
            const legal = new Set(legalCells());
            for (let i = 0; i < 64; i++) {
              const x = (i & 7) * 10, y = (i >> 3) * 10;
              const g = svg('g', { class: 'grid-cell' });
              g.append(svg('rect', { x, y, width: 10, height: 10, class: 'sq felt' }));
              const ch = s.board[i];
              if (ch !== '.') g.append(svg('circle', { cx: x + 5, cy: y + 5, r: 4, class: (ch === 'x' ? 'disc player' : 'disc ai') + (i === last ? ' last' : '') }));
              else if (legal.has(i)) g.append(svg('circle', { cx: x + 5, cy: y + 5, r: 1.2, class: 'dot target' }));
              g.addEventListener('click', () => tap(i));
              board.append(g);
            }
            info.textContent = t('reversiCount', { player: discs(s.board, 'player'), ai: discs(s.board, 'ai') });
            api.status(s.over ? '' : s.turn === 'player' ? t('yourTurn') : t('opponentTurn'));
          }

          function tap(i: number): void {
            if (api.paused || s.over || s.turn !== 'player' || !legalCells().includes(i)) return;
            play({ by: 'player', cell: i });
          }

          function play(a: { by: 'player' | 'ai'; cell: number }): void {
            if (s.over) return;
            s = rules.apply(s, a);
            if (a.cell >= 0) last = a.cell;
            draw();
            if (driver.after()) return;
            // The player has only the pass: show the toast, then pass on their behalf.
            if (s.turn === 'player' && legalCells()[0] === -1) {
              note.textContent = t('reversiPass');
              window.clearTimeout(passTimer);
              passTimer = window.setTimeout(function tick() {
                if (api.paused) {
                  passTimer = window.setTimeout(tick, 200);
                  return;
                }
                note.textContent = '';
                play({ by: 'player', cell: -1 });
              }, 1200);
            }
          }

          draw();
          return {
            stop: () => {
              driver.stop();
              window.clearTimeout(passTimer);
            },
            timeout: () => {
              if (s.over) return;
              driver.stop();
              window.clearTimeout(passTimer);
              s = rules.apply(s, { by: 'timeout' });
              draw();
              api.finish(rules.result(s)!);
            },
          };
        },
      }, onFinish),
  };
}
