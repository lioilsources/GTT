import { minigameCatalog } from '../../gen/ids';
import type { Minigame, MinigameEnv } from '../api';
import { h, svg } from '../dom';
import { aiPrng } from '../rules';
import { mountShell } from '../shell';
import { SirkyRules, sirkyConfig, type SirkyAction, type SirkyState } from './rules';

const PER_ROW = 5;

/** Sirky (duel), specs/minigames/sirky.md: tap Take 1–3, the opponent answers after a short pause. */
export function sirky(env: MinigameEnv): Minigame {
  const { t, tuning } = env;
  const tm = tuning.minigames.sirky;
  return {
    meta: minigameCatalog.sirky,
    mount: (host, ctx, onFinish) =>
      mountShell(host, ctx, env, {
        id: 'sirky',
        rules: ['sirkyRules1', 'sirkyRules2', 'sirkyRules3'],
        timeCapS: tm.timeCapS,
        start(api) {
          const rules = new SirkyRules();
          const ai = aiPrng(ctx.seed);
          let s: SirkyState = rules.init(sirkyConfig(tm), ctx.seed);
          let aiTimer = 0;
          let toast = 0;

          const pile = svg('svg', { class: 'sirky-pile', viewBox: '0 0 100 100', preserveAspectRatio: 'xMidYMid meet' });
          const info = h('div.sirky-info');
          const note = h('div.sirky-note');
          const buttons = h('div.sirky-buttons');
          api.body.append(h('div.sirky', {}, info, pile, note, buttons));

          function draw(): void {
            const rows = Math.ceil(Math.max(s.left, 1) / PER_ROW);
            const cellH = Math.min(30, 96 / Math.max(rows, 1));
            pile.replaceChildren();
            for (let i = 0; i < s.left; i++) {
              const r = Math.floor(i / PER_ROW), c = i % PER_ROW;
              const n = Math.min(PER_ROW, s.left - r * PER_ROW);
              const x = 50 + (c - (n - 1) / 2) * 16;
              const y = 50 + (r - (rows - 1) / 2) * cellH;
              const len = cellH * 0.78;
              const g = svg('g', { class: 'sirky-match' });
              g.append(svg('line', { x1: x, y1: y - len / 2 + 3, x2: x, y2: y + len / 2, class: 'stick' }));
              g.append(svg('ellipse', { cx: x, cy: y - len / 2 + 2.5, rx: 2.4, ry: 3.2, class: 'head' }));
              pile.append(g);
            }
            info.textContent = `${t('sirkyRound', { round: s.round })}  ·  ${t('roundScore', { player: s.player, ai: s.ai })}`;
            api.status(s.over ? '' : s.turn === 'player' ? t('yourTurn') : t('opponentTurn'));
            note.textContent = t('sirkyLeft', { count: s.left });
            buttons.replaceChildren(
              ...[1, 2, 3].slice(0, tm.maxTake).map((k) =>
                h('button.mg-btn', {
                  type: 'button',
                  disabled: s.over || s.turn !== 'player' || k > s.left,
                  onclick: () => play({ by: 'player', take: k }),
                }, t('sirkyTake', { count: k }))),
            );
          }

          function play(a: SirkyAction): void {
            if (api.paused || s.over) return;
            const before = s;
            s = rules.apply(s, a);
            if (s.round !== before.round || s.over) {
              const won = s.player > before.player;
              window.clearTimeout(toast);
              note.classList.add('flash');
              draw();
              note.textContent = won ? t('roundWon') : t('roundLost');
              toast = window.setTimeout(() => note.classList.remove('flash'), 900);
            } else draw();
            const r = rules.result(s);
            if (r) {
              window.setTimeout(() => api.finish(r), 900);
              return;
            }
            scheduleAi();
          }

          function scheduleAi(): void {
            if (s.turn !== 'ai' || s.over) return;
            window.clearTimeout(aiTimer);
            aiTimer = window.setTimeout(function tick() {
              if (api.paused) {
                aiTimer = window.setTimeout(tick, 200);
                return;
              }
              play(rules.aiAction(s, ctx.difficulty, ai));
            }, tm.aiThinkS * 1000);
          }

          draw();
          return {
            stop: () => {
              window.clearTimeout(aiTimer);
              window.clearTimeout(toast);
            },
            timeout: () => {
              if (s.over) return;
              window.clearTimeout(aiTimer);
              s = rules.apply(s, { by: 'timeout' });
              draw();
              api.finish(rules.result(s)!);
            },
          };
        },
      }, onFinish),
  };
}
