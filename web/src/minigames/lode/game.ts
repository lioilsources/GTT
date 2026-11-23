import { minigameCatalog } from '../../gen/ids';
import type { Minigame, MinigameEnv } from '../api';
import { h, svg } from '../dom';
import { aiPrng } from '../rules';
import { mountShell } from '../shell';
import { turnDriver } from '../turns';
import { LodeRules, lodeConfig, sunk, type LodeAction, type LodeState } from './rules';

/**
 * Lodě, specs/minigames/lode.md: the rival grid on top (a tap fires), the own smaller grid below;
 * "Re-deal" before the first shot. A sunk ship is outlined.
 */
export function lode(env: MinigameEnv): Minigame {
  const { t, tuning } = env;
  const tm = tuning.minigames.lode;
  return {
    meta: minigameCatalog.lode,
    mount: (host, ctx, onFinish) =>
      mountShell(host, ctx, env, {
        id: 'lode',
        rules: ['lodeRules1', 'lodeRules2', 'lodeRules3'],
        timeCapS: tm.timeCapS,
        start(api) {
          const rules = new LodeRules();
          const ai = aiPrng(ctx.seed);
          let s: LodeState = rules.init(lodeConfig(tm), ctx.seed);
          let lastAi = -1;
          let toast = 0;

          const rival = svg('svg', { class: 'grid-board sea', viewBox: '0 0 100 100', preserveAspectRatio: 'xMidYMid meet' });
          const own = svg('svg', { class: 'grid-board sea own', viewBox: '0 0 100 100', preserveAspectRatio: 'xMidYMid meet' });
          const info = h('div.board-info');
          const note = h('div.board-note');
          const shuffle = h('button.mg-btn', { type: 'button', onclick: () => act({ by: 'player', op: 'shuffle' }) });
          api.body.append(h('div.board-game.lode', {}, info, rival, note, own, shuffle));

          const driver = turnDriver({
            api, thinkS: tm.aiThinkS,
            aiTurn: () => !s.over && s.turn === 'ai',
            aiMove: () => act(rules.aiAction(s, ctx.difficulty, ai)),
            result: () => rules.result(s),
          });

          function grid(el: SVGSVGElement, shots: string, ships: number[][], showShips: boolean, onTap?: (i: number) => void): void {
            el.replaceChildren();
            const shipAt = new Set(ships.flat());
            for (let i = 0; i < 100; i++) {
              const x = (i % 10) * 10, y = Math.floor(i / 10) * 10;
              const g = svg('g', { class: 'grid-cell' });
              g.append(svg('rect', { x, y, width: 10, height: 10, class: showShips && shipAt.has(i) ? 'sq ship' : 'sq water' }));
              const ch = shots[i];
              if (ch === 'o') g.append(svg('circle', { cx: x + 5, cy: y + 5, r: 1.4, class: 'miss' }));
              else if (ch === 'x') {
                g.append(svg('path', { d: `M${x + 2} ${y + 2}L${x + 8} ${y + 8}M${x + 8} ${y + 2}L${x + 2} ${y + 8}`, class: 'hitmark' }));
              }
              if (onTap) g.addEventListener('click', () => onTap(i));
              el.append(g);
            }
            for (const sh of ships) {
              if (!sunk(sh, shots)) continue;
              const xs = sh.map((c) => c % 10), ys = sh.map((c) => Math.floor(c / 10));
              const x0 = Math.min(...xs) * 10, y0 = Math.min(...ys) * 10;
              el.append(svg('rect', {
                x: x0 + 0.8, y: y0 + 0.8, width: (Math.max(...xs) + 1) * 10 - x0 - 1.6, height: (Math.max(...ys) + 1) * 10 - y0 - 1.6, class: 'sunk',
              }));
            }
            if (lastAi >= 0 && showShips) {
              el.append(svg('rect', { x: (lastAi % 10) * 10, y: Math.floor(lastAi / 10) * 10, width: 10, height: 10, class: 'last' }));
            }
          }

          function draw(): void {
            grid(rival, s.aShots, s.aShips, false, tap);
            grid(own, s.pShots, s.pShips, true);
            info.textContent = t('lodeShots', { n: s.shots });
            shuffle.textContent = t('lodeShuffle', { n: s.shuffles });
            shuffle.hidden = s.shots > 0 || s.over;
            shuffle.disabled = !rules.canShuffle(s);
            api.status(s.over ? '' : s.turn === 'player' ? t('yourTurn') : t('opponentTurn'));
          }

          function tap(i: number): void {
            if (api.paused || s.over || s.turn !== 'player' || s.aShots[i] !== '.') return;
            act({ by: 'player', op: 'shot', cell: i });
          }

          function act(a: LodeAction): void {
            if (s.over || api.paused) return;
            const before = a.by === 'player' ? s.aShips.filter((sh) => sunk(sh, s.aShots)).length : -1;
            s = rules.apply(s, a);
            if (a.by === 'ai' && 'cell' in a) lastAi = a.cell;
            if (before >= 0 && s.aShips.filter((sh) => sunk(sh, s.aShots)).length > before) {
              note.textContent = t('lodeSunk');
              window.clearTimeout(toast);
              toast = window.setTimeout(() => (note.textContent = ''), 1200);
            }
            draw();
            driver.after();
          }

          draw();
          return {
            stop: () => {
              driver.stop();
              window.clearTimeout(toast);
            },
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
