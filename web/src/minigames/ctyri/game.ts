import { minigameCatalog } from '../../gen/ids';
import type { Minigame, MinigameEnv } from '../api';
import { h, svg } from '../dom';
import { aiPrng } from '../rules';
import { mountShell } from '../shell';
import { turnDriver } from '../turns';
import { COLS, CtyriRules, ROWS, ctyriConfig, winningLine, type CtyriState } from './rules';

/** Čtyři v řadě, specs/minigames/ctyri.md: a tap anywhere in a column drops a disc there. */
export function ctyri(env: MinigameEnv): Minigame {
  const { t, tuning } = env;
  const tm = tuning.minigames.ctyri;
  return {
    meta: minigameCatalog.ctyri,
    mount: (host, ctx, onFinish) =>
      mountShell(host, ctx, env, {
        id: 'ctyri',
        rules: ['ctyriRules1', 'ctyriRules2', 'ctyriRules3'],
        timeCapS: tm.timeCapS,
        start(api) {
          const rules = new CtyriRules();
          const ai = aiPrng(ctx.seed);
          let s: CtyriState = rules.init(ctyriConfig(tm), ctx.seed);
          let last = -1;

          const board = svg('svg', { class: 'grid-board', viewBox: `0 0 ${COLS * 10} ${ROWS * 10}`, preserveAspectRatio: 'xMidYMid meet' });
          api.body.append(h('div.board-game', {}, board, h('div.board-note')));

          const driver = turnDriver({
            api, thinkS: tm.aiThinkS,
            aiTurn: () => !s.over && s.turn === 'ai',
            aiMove: () => play(rules.aiAction(s, ctx.difficulty, ai) as { by: 'ai'; col: number }),
            result: () => rules.result(s),
          });

          function draw(): void {
            board.replaceChildren();
            const win = new Set(s.over && last >= 0 ? winningLine(s.board, last) : []);
            board.append(svg('rect', { x: 0, y: 0, width: COLS * 10, height: ROWS * 10, class: 'c4-frame' }));
            for (let i = 0; i < COLS * ROWS; i++) {
              const ch = s.board[i];
              const cls = ch === 'x' ? 'disc player' : ch === 'o' ? 'disc ai' : 'hole';
              const c = svg('circle', { cx: (i % COLS) * 10 + 5, cy: Math.floor(i / COLS) * 10 + 5, r: 4, class: cls + (win.has(i) ? ' win' : '') });
              if (i === last && !s.over) {
                c.classList.add('drop');
                c.style.setProperty('--drop', `${-(Math.floor(i / COLS) + 1) * 10}px`);
              }
              board.append(c);
            }
            for (let col = 0; col < COLS; col++) {
              const hit = svg('rect', { x: col * 10, y: 0, width: 10, height: ROWS * 10, class: 'col-hit' });
              hit.addEventListener('click', () => tap(col));
              board.append(hit);
            }
            api.status(s.over ? '' : s.turn === 'player' ? t('yourTurn') : t('opponentTurn'));
          }

          function tap(col: number): void {
            if (api.paused || s.over || s.turn !== 'player' || s.board[col] !== '.') return;
            play({ by: 'player', col });
          }

          function play(a: { by: 'player' | 'ai'; col: number }): void {
            if (s.over) return;
            last = rules.landingCell(s, a.col);
            s = rules.apply(s, a);
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
              draw();
              api.finish(rules.result(s)!);
            },
          };
        },
      }, onFinish),
  };
}
