import { minigameCatalog } from '../../gen/ids';
import type { Minigame, MinigameEnv } from '../api';
import { dieFace } from '../dice';
import { h, svg } from '../dom';
import { aiPrng } from '../rules';
import { mountShell } from '../shell';
import { turnDriver } from '../turns';
import { PraseRules, praseConfig, type PraseAction, type PraseState } from './rules';

/** Prase (pig), specs/minigames/prase.md: one big die, Roll on or Bank the turn. */
export function prase(env: MinigameEnv): Minigame {
  const { t, tuning } = env;
  const tm = tuning.minigames.prase;
  return {
    meta: minigameCatalog.prase,
    mount: (host, ctx, onFinish) =>
      mountShell(host, ctx, env, {
        id: 'prase',
        rules: ['praseRules1', 'praseRules2', 'praseRules3'],
        ruleArgs: { target: tm.target },
        timeCapS: tm.timeCapS,
        start(api) {
          const rules = new PraseRules();
          const ai = aiPrng(ctx.seed);
          let s: PraseState = rules.init(praseConfig(tm), ctx.seed);
          let toast = 0;

          const round = h('div.deset-info');
          const scores = h('div.deset-info');
          const board = svg('svg', { class: 'deset-board', viewBox: '0 0 100 70', preserveAspectRatio: 'xMidYMid meet' });
          const note = h('div.deset-note');
          const roll = h('button.mg-btn', { type: 'button', onclick: () => tap('roll') }, t('praseRoll'));
          const hold = h('button.mg-btn', { type: 'button', onclick: () => tap('hold') }, t('praseHold'));
          api.body.append(h('div.deset', {}, round, scores, board, note, h('div.deset-buttons', {}, roll, hold)));

          const driver = turnDriver({
            api, thinkS: tm.aiThinkS,
            aiTurn: () => !s.over && s.turn === 'ai',
            aiMove: () => play(rules.aiAction(s, ctx.difficulty, ai)),
            result: () => rules.result(s),
          });

          function draw(): void {
            round.textContent = t('desetRound', { round: Math.min(s.round, tm.maxRounds), max: tm.maxRounds });
            scores.textContent = t('desetScores', { player: s.player, ai: s.ai });
            board.replaceChildren(dieFace(30, 5, 40, s.die, s.bust ? ['bust'] : []));
            if (!note.classList.contains('flash')) note.textContent = t('praseTurn', { n: s.turnScore });
            const mine = !s.over && s.turn === 'player';
            roll.disabled = !mine;
            hold.disabled = !mine || s.turnScore === 0;
            api.status(s.over ? '' : mine ? t('yourTurn') : t('opponentTurn'));
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

          function tap(op: 'roll' | 'hold'): void {
            if (api.paused || s.over || s.turn !== 'player') return;
            play({ by: 'player', op });
          }

          function play(a: PraseAction): void {
            if (s.over) return;
            s = rules.apply(s, a);
            if (a.by !== 'timeout' && a.op === 'roll' && s.bust) flash(t('praseBust'));
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
