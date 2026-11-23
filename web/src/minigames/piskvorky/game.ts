import { minigameCatalog } from '../../gen/ids';
import type { Minigame, MinigameEnv } from '../api';
import { h, svg } from '../dom';
import { aiPrng } from '../rules';
import { mountShell } from '../shell';
import { turnDriver } from '../turns';
import { PiskvorkyRules, piskvorkyConfig, winningLine, type PiskvorkyState } from './rules';

/**
 * Piškvorky, specs/minigames/piskvorky.md: the first tap selects a square, a second tap on it
 * places the mark (big fingers on a 15×15 board). The last AI mark is ringed, the winning row marked.
 */
export function piskvorky(env: MinigameEnv): Minigame {
  const { t, tuning } = env;
  const tm = tuning.minigames.piskvorky;
  return {
    meta: minigameCatalog.piskvorky,
    mount: (host, ctx, onFinish) =>
      mountShell(host, ctx, env, {
        id: 'piskvorky',
        rules: ['piskvorkyRules1', 'piskvorkyRules2', 'piskvorkyRules3'],
        timeCapS: tm.timeCapS,
        start(api) {
          const rules = new PiskvorkyRules();
          const ai = aiPrng(ctx.seed);
          const cfg = piskvorkyConfig(tm);
          const n = cfg.size;
          let s: PiskvorkyState = rules.init(cfg, ctx.seed);
          let sel = -1, lastAi = -1, lastCell = -1;

          const board = svg('svg', { class: 'grid-board', viewBox: `0 0 ${n * 10} ${n * 10}`, preserveAspectRatio: 'xMidYMid meet' });
          const note = h('div.board-note');
          api.body.append(h('div.board-game', {}, board, note));

          const driver = turnDriver({
            api, thinkS: tm.aiThinkS,
            aiTurn: () => !s.over && s.turn === 'ai',
            aiMove: () => play(rules.aiAction(s, ctx.difficulty, ai) as { by: 'ai'; cell: number }),
            result: () => rules.result(s),
          });

          function draw(): void {
            board.replaceChildren();
            const win = new Set(s.over && lastCell >= 0 ? winningLine(s.board, n, lastCell) : []);
            for (let i = 0; i < n * n; i++) {
              const x = (i % n) * 10, y = Math.floor(i / n) * 10;
              const g = svg('g', { class: 'grid-cell' });
              let cls = 'sq';
              if (i === sel) cls += ' sel';
              if (win.has(i)) cls += ' win';
              g.append(svg('rect', { x, y, width: 10, height: 10, class: cls }));
              const ch = s.board[i];
              if (ch === 'x') {
                g.append(svg('path', { d: `M${x + 2.5} ${y + 2.5}L${x + 7.5} ${y + 7.5}M${x + 7.5} ${y + 2.5}L${x + 2.5} ${y + 7.5}`, class: 'mark player' }));
              } else if (ch === 'o') {
                g.append(svg('circle', { cx: x + 5, cy: y + 5, r: 2.8, class: i === lastAi ? 'mark ai last' : 'mark ai' }));
              } else if (i === sel) {
                g.append(svg('path', { d: `M${x + 3} ${y + 3}L${x + 7} ${y + 7}M${x + 7} ${y + 3}L${x + 3} ${y + 7}`, class: 'mark ghost' }));
              }
              g.addEventListener('click', () => tap(i));
              board.append(g);
            }
            api.status(s.over ? '' : s.turn === 'player' ? t('yourTurn') : t('opponentTurn'));
            note.textContent = sel >= 0 ? t('piskvorkyTapAgain') : '';
          }

          function tap(i: number): void {
            if (api.paused || s.over || s.turn !== 'player' || s.board[i] !== '.') return;
            if (sel !== i) {
              sel = i;
              draw();
              return;
            }
            sel = -1;
            play({ by: 'player', cell: i });
          }

          function play(a: { by: 'player' | 'ai'; cell: number }): void {
            if (s.over) return;
            s = rules.apply(s, a);
            lastCell = a.cell;
            if (a.by === 'ai') lastAi = a.cell;
            draw();
            driver.after();
          }

          draw();
          return {
            stop: () => driver.stop(),
            timeout: () => {
              if (s.over) return;
              driver.stop();
              s = rules.apply(s, { by: 'timeout' });
              sel = -1;
              draw();
              api.finish(rules.result(s)!);
            },
          };
        },
      }, onFinish),
  };
}
