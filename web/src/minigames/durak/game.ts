import { minigameCatalog } from '../../gen/ids';
import type { Minigame, MinigameEnv } from '../api';
import { h } from '../dom';
import { card } from '../oko/game';
import { aiPrng } from '../rules';
import { mountShell } from '../shell';
import { turnDriver } from '../turns';
import { DurakRules, durakConfig, face, type DurakAction, type DurakState } from './rules';

const SUITS = ['♠', '♥', '♦', '♣'];

/**
 * Durak, specs/minigames/durak.md: NPCs with card counts on top, the table of attack/beat pairs with
 * the stock and the trump, your hand at the bottom (legal cards tappable), Take / Done buttons.
 */
export function durak(env: MinigameEnv): Minigame {
  const { t, tuning } = env;
  const tm = tuning.minigames.durak;
  return {
    meta: minigameCatalog.durak,
    mount: (host, ctx, onFinish) =>
      mountShell(host, ctx, env, {
        id: 'durak',
        rules: ['durakRules1', 'durakRules2', 'durakRules3'],
        timeCapS: tm.timeCapS,
        start(api) {
          const rules = new DurakRules();
          const ai = aiPrng(ctx.seed);
          let s: DurakState = rules.init(durakConfig(tm, ctx.difficulty), ctx.seed);

          const seats = h('div.durak-seats');
          const info = h('div.oko-info');
          const table = h('div.oko-hand.durak-table');
          const note = h('div.oko-info');
          const hand = h('div.oko-hand.durak-hand');
          const buttons = h('div.oko-buttons');
          api.body.append(h('div.oko', {}, seats, info, table, note, hand, buttons));

          const driver = turnDriver({
            api, thinkS: tm.aiThinkS,
            aiTurn: () => !s.over && rules.turn(s) !== 0,
            aiMove: () => play(rules.aiAction(s, ctx.difficulty, ai)),
            result: () => rules.result(s),
          });

          const mine = (): boolean => !s.over && rules.turn(s) === 0;

          function draw(): void {
            const turn = rules.turn(s);
            seats.replaceChildren(
              ...Array.from({ length: s.n - 1 }, (_, k) => {
                const i = k + 1;
                const out = s.finished.includes(i);
                const el = h('div.durak-seat', {}, `${t('durakOpp', { n: i })} · ${out ? t('durakOut') : t('durakCards', { n: s.hands[i]!.length })}`);
                if (!s.over && turn === i) el.classList.add('turn');
                return el;
              }),
            );
            info.textContent = t('durakTrump', { suit: SUITS[s.trump]!, n: s.stock.length });
            const trump = card(face(s.trumpCard));
            trump.classList.add('small', 'durak-trump');
            table.replaceChildren(
              ...(s.stock.length ? [trump] : []),
              ...s.table.map((p) => {
                const a = card(face(p.a));
                a.classList.add('small');
                const pair = h('div.durak-pair', {}, a);
                if (p.d >= 0) {
                  const d = card(face(p.d));
                  d.classList.add('small', 'durak-beat');
                  pair.append(d);
                }
                return pair;
              }),
            );
            const legal = mine() ? rules.legalActions(s) : [];
            const cards = new Map<number, DurakAction>();
            for (const l of legal) if ('card' in l) cards.set(l.card, l);
            const small = s.hands[0]!.length > 8;
            hand.replaceChildren(
              ...s.hands[0]!.map((c) => {
                const el = card(face(c));
                if (small) el.classList.add('small');
                const a = cards.get(c);
                if (a) {
                  el.classList.add('tap');
                  el.addEventListener('click', () => tap(a));
                } else if (mine()) el.classList.add('dim');
                return el;
              }),
            );
            const extra = legal.find((l) => 'op' in l && (l.op === 'take' || l.op === 'pass'));
            buttons.replaceChildren(
              ...(extra && 'op' in extra
                ? [h('button.mg-btn', { type: 'button', onclick: () => tap(extra) }, t(extra.op === 'take' ? 'durakTake' : 'durakPass'))]
                : []),
            );
            note.textContent = !mine() ? '' : turn === s.defender ? t('durakDefend') : s.table.length ? t('durakThrow') : t('durakAttack');
            api.status(s.over ? '' : mine() ? t('yourTurn') : t('opponentTurn'));
          }

          function tap(a: DurakAction): void {
            if (api.paused || !mine()) return;
            play(a);
          }

          function play(a: DurakAction): void {
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
