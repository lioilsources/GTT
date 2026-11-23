import { minigameCatalog } from '../../gen/ids';
import type { Minigame, MinigameEnv } from '../api';
import { h } from '../dom';
import { card } from '../oko/game';
import { aiPrng } from '../rules';
import { mountShell } from '../shell';
import { turnDriver } from '../turns';
import { SrdceRules, srdceConfig, type SrdceAction, type SrdceState } from './rules';

/** Grid areas of the four seats around the table: you, left, across, right. */
const AREAS = ['s', 'w', 'n', 'e'] as const;

/**
 * Srdce (hearts), specs/minigames/srdce.md: your hand as a fan at the bottom (illegal cards dimmed),
 * three opponents around the table; the last trick stays on the table until the next card is led.
 */
export function srdce(env: MinigameEnv): Minigame {
  const { t, tuning } = env;
  const tm = tuning.minigames.srdce;
  return {
    meta: minigameCatalog.srdce,
    mount: (host, ctx, onFinish) =>
      mountShell(host, ctx, env, {
        id: 'srdce',
        rules: ['srdceRules1', 'srdceRules2', 'srdceRules3'],
        timeCapS: tm.timeCapS,
        start(api) {
          const rules = new SrdceRules();
          const ai = aiPrng(ctx.seed);
          let s: SrdceState = rules.init(srdceConfig(tm), ctx.seed);

          const info = h('div.oko-info');
          const seats = [0, 1, 2, 3].map((i) => h(`div.srdce-seat.${AREAS[i]}`));
          const trick = h('div.srdce-trick');
          const hand = h('div.srdce-hand');
          api.body.append(h('div.srdce', {}, info, h('div.srdce-table', {}, ...seats.slice(1), trick), seats[0]!, hand));

          const driver = turnDriver({
            api, thinkS: tm.aiThinkS,
            aiTurn: () => !s.over && s.turn !== 0,
            aiMove: () => play(rules.aiAction(s, ctx.difficulty, ai)),
            result: () => rules.result(s),
          });

          const mine = (): boolean => !s.over && s.turn === 0;
          const names = [t('srdceYou'), t('srdceWest'), t('srdceNorth'), t('srdceEast')];

          function draw(): void {
            info.textContent = t('srdceDeal', { n: s.deal, total: tm.maxDeals });
            seats.forEach((el, i) => {
              el.classList.toggle('turn', !s.over && s.turn === i);
              el.textContent = `${names[i]}  ${t('srdcePoints', { n: s.scores[i]! + (s.over ? 0 : s.taken[i]!) })}`;
            });
            const live = s.trick.length > 0;
            const cards = live ? s.trick : s.lastTrick.cards;
            const leader = live ? s.leader : s.lastTrick.leader;
            trick.replaceChildren(
              ...cards.map((c, k) => {
                const seat = (leader + k) % 4;
                const el = card(c);
                el.classList.add('srdce-played', AREAS[seat]!);
                if (!live && seat === s.lastTrick.winner) el.classList.add('won');
                return el;
              }),
            );
            const legal = new Set(mine() ? rules.legalCards(s) : []);
            hand.replaceChildren(
              ...s.hands[0]!.map((c) => {
                const el = card(c);
                if (legal.has(c)) {
                  el.classList.add('tap');
                  el.addEventListener('click', () => tap(c));
                } else if (mine()) el.classList.add('dim');
                return el;
              }),
            );
            api.status(s.over ? '' : mine() ? t('yourTurn') : t('opponentTurn'));
          }

          function tap(c: number): void {
            if (api.paused || !mine()) return;
            play({ by: 'player', card: c });
          }

          function play(a: SrdceAction): void {
            if (s.over) return;
            s = rules.apply(s, a);
            draw();
            driver.after();
          }

          draw();
          driver.after();
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
