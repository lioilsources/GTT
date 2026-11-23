import { minigameCatalog } from '../../gen/ids';
import type { Minigame, MinigameEnv } from '../api';
import { h, svg } from '../dom';
import { aiPrng } from '../rules';
import { mountShell } from '../shell';
import {
  DesetitisicRules,
  desetitisicConfig,
  rollDice,
  scoreSelection,
  type DesetitisicAction,
  type DesetitisicState,
} from './rules';
import { PIPS } from '../dice';

/** Desetitisic, specs/minigames/desetitisic.md: tap dice to set them aside, then roll on or bank. */
export function desetitisic(env: MinigameEnv): Minigame {
  const { t, tuning } = env;
  const tm = tuning.minigames.desetitisic;
  return {
    meta: minigameCatalog.desetitisic,
    mount: (host, ctx, onFinish) =>
      mountShell(host, ctx, env, {
        id: 'desetitisic',
        rules: ['desetRules1', 'desetRules2', 'desetRules3'],
        timeCapS: tm.timeCapS,
        start(api) {
          const rules = new DesetitisicRules();
          const ai = aiPrng(ctx.seed);
          let s: DesetitisicState = rules.init(desetitisicConfig(tm), ctx.seed);
          let aiTimer = 0;
          let toast = 0;
          let selected = new Set<number>();
          /** Dice shown when the state has none: a busted roll, or the roll the last keep came from. */
          let shown: number[] = [];
          let kept = new Set<number>();
          let busted = false;

          const board = svg('svg', { class: 'deset-board', viewBox: '0 0 100 70', preserveAspectRatio: 'xMidYMid meet' });
          const info = h('div.deset-info');
          const scores = h('div.deset-info');
          const note = h('div.deset-note');
          const buttons = h('div.deset-buttons');
          api.body.append(h('div.deset', {}, info, scores, board, note, buttons));

          const selValue = (): number | null =>
            scoreSelection([...selected].sort((a, b) => a - b).map((i) => s.roll[i]!));
          const myMove = (): boolean => !s.over && s.turn === 'player';

          function drawDice(): void {
            const values = s.phase === 'keep' ? s.roll : shown;
            board.replaceChildren();
            const size = 26, gap = 6;
            values.forEach((v, i) => {
              const col = i % 3, row = Math.floor(i / 3);
              const x = 50 + (col - 1) * (size + gap) - size / 2;
              const y = 35 + (row - 0.5) * (size + gap) - size / 2;
              const cls = ['deset-die'];
              if (selected.has(i)) cls.push('sel');
              if (s.phase !== 'keep' && kept.has(i)) cls.push('kept');
              if (s.phase !== 'keep' && busted) cls.push('bust');
              const g = svg('g', { class: cls.join(' ') });
              g.append(svg('rect', { x, y, width: size, height: size, rx: 5, class: 'face' }));
              for (const [px, py] of PIPS[v] ?? []) {
                g.append(svg('circle', { cx: x + px * size, cy: y + py * size, r: 2.6, class: 'pip' }));
              }
              if (s.phase === 'keep' && myMove()) {
                g.classList.add('tap');
                g.addEventListener('click', () => toggle(i));
              }
              board.append(g);
            });
          }

          function draw(): void {
            info.textContent = t('desetRound', { round: Math.min(s.round, tm.maxRounds), max: tm.maxRounds });
            scores.textContent = t('desetScores', { player: s.player, ai: s.ai });
            api.status(s.over ? '' : s.turn === 'player' ? t('yourTurn') : t('opponentTurn'));
            drawDice();
            if (!note.classList.contains('flash')) note.textContent = t('desetTurn', { points: s.turnScore });
            const mine = myMove();
            const btn = (label: string, enabled: boolean, a: () => DesetitisicAction): HTMLButtonElement =>
              h('button.mg-btn', { type: 'button', disabled: !mine || !enabled, onclick: () => play(a()) }, label);
            if (s.phase === 'keep') {
              const v = selValue();
              buttons.replaceChildren(
                btn(t('desetKeep', { points: v ?? 0 }), v !== null, () => ({
                  by: 'player',
                  op: 'keep',
                  dice: [...selected].sort((a, b) => a - b),
                })),
              );
            } else if (s.phase === 'decide') {
              buttons.replaceChildren(
                btn(t('desetRoll'), true, () => ({ by: 'player', op: 'roll' })),
                btn(t('desetBank', { points: s.turnScore }), true, () => ({ by: 'player', op: 'bank' })),
              );
            } else {
              buttons.replaceChildren(btn(t('desetRoll'), s.phase === 'roll', () => ({ by: 'player', op: 'roll' })));
            }
          }

          function toggle(i: number): void {
            if (api.paused || !myMove() || s.phase !== 'keep') return;
            if (selected.has(i)) selected.delete(i);
            else selected.add(i);
            draw();
          }

          function flash(text: string): void {
            window.clearTimeout(toast);
            note.classList.add('flash');
            note.textContent = text;
            toast = window.setTimeout(() => {
              note.classList.remove('flash');
              draw();
            }, Math.max(900, tm.aiThinkS * 1000));
          }

          function play(a: DesetitisicAction): void {
            if (api.paused || s.over) return;
            const before = s;
            s = rules.apply(s, a);
            selected = new Set();
            if (a.by !== 'timeout' && a.op === 'keep') {
              shown = before.roll;
              kept = new Set(a.dice);
              busted = false;
            } else if (a.by !== 'timeout' && a.op === 'roll' && s.lastBust) {
              shown = rollDice(before.rng, before.dice).values;
              kept = new Set();
              busted = true;
              flash(t('desetBust'));
            } else if (a.by !== 'timeout' && a.op === 'bank') {
              shown = [];
              kept = new Set();
              busted = false;
            }
            draw();
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
