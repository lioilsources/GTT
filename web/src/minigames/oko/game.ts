import { minigameCatalog } from '../../gen/ids';
import type { Minigame, MinigameEnv } from '../api';
import { h } from '../dom';
import { mountShell } from '../shell';
import { handTotal, isNatural, OkoRules, okoConfig, rankOf, suitOf, type OkoAction, type OkoLast, type OkoState } from './rules';

/** Rank and suit glyphs (symbols, not texts): rank = c mod 13, suit = c div 13 (♠ ♥ ♦ ♣). */
const RANKS = ['2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A'];
const SUITS = ['♠', '♥', '♦', '♣'];
const FLASH_MS = 900;

/** What the table shows: the live hands, or a finished round being revealed from `last`. */
interface View {
  player: number[];
  dealer: number[];
  hole: boolean;
}

function card(c: number | null): HTMLElement {
  if (c === null) return h('div.oko-card.back');
  const s = suitOf(c);
  return h(`div.oko-card${s === 1 || s === 2 ? '.red' : ''}`, {}, h('span.rank', {}, RANKS[rankOf(c)]!), h('span.suit', {}, SUITS[s]!));
}

/** Oko bere (twenty-one), specs/minigames/oko.md: Hit or Stand, the banker draws to dealer_stand. */
export function oko(env: MinigameEnv): Minigame {
  const { t, tuning } = env;
  const tm = tuning.minigames.oko;
  return {
    meta: minigameCatalog.oko,
    mount: (host, ctx, onFinish) =>
      mountShell(host, ctx, env, {
        id: 'oko',
        rules: ['okoRules1', 'okoRules2', 'okoRules3'],
        timeCapS: tm.timeCapS,
        start(api) {
          const rules = new OkoRules();
          let s: OkoState = rules.init(okoConfig(tm), ctx.seed);
          let view: View = live();
          let busy = false;
          let timer = 0;

          const dealerLabel = h('div.oko-label');
          const dealerHand = h('div.oko-hand');
          const note = h('div.oko-note');
          const playerHand = h('div.oko-hand');
          const playerLabel = h('div.oko-label');
          const info = h('div.oko-info');
          const hit = h('button.mg-btn', { type: 'button', onclick: () => play({ by: 'player', op: 'hit' }) }, t('okoHit'));
          const stand = h('button.mg-btn', { type: 'button', onclick: () => play({ by: 'player', op: 'stand' }) }, t('okoStand'));
          api.body.append(
            h('div.oko', {},
              h('div.oko-side', {}, dealerLabel, dealerHand),
              note,
              h('div.oko-side', {}, playerHand, playerLabel),
              info,
              h('div.oko-buttons', {}, hit, stand)),
          );

          function live(): View {
            return { player: s.player, dealer: s.dealer, hole: s.phase === 'play' };
          }

          function draw(): void {
            const shownDealer = view.hole ? view.dealer.slice(0, 1) : view.dealer;
            dealerHand.replaceChildren(...view.dealer.map((c, i) => card(view.hole && i > 0 ? null : c)));
            playerHand.replaceChildren(...view.player.map(card));
            dealerLabel.textContent = `${t('okoBanker')}  ${t('okoTotal', { total: handTotal(shownDealer) })}`;
            playerLabel.textContent = `${t('okoYou')}  ${t('okoTotal', { total: handTotal(view.player) })}`;
            info.textContent = t('roundScore', { player: s.playerWins, ai: s.dealerWins });
            const canPlay = !busy && s.phase === 'play' && !s.over;
            hit.disabled = stand.disabled = !canPlay;
            api.status(canPlay ? t('yourTurn') : '');
          }

          function outcomeText(l: OkoLast): string {
            if (l.outcome === 'push') return t('okoPush');
            if (l.outcome === 'win') return isNatural(l.player) ? t('okoNatural') : t('roundWon');
            return handTotal(l.player) > 21 ? t('okoBust') : t('roundLost');
          }

          /** Wait while paused, then run f after ms. */
          function later(ms: number, f: () => void): void {
            timer = window.setTimeout(function tick() {
              if (api.paused) {
                timer = window.setTimeout(tick, 200);
                return;
              }
              f();
            }, ms);
          }

          /** Reveals the finished round from `last`: hole card, the banker's draws, then the outcome. */
          function reveal(): void {
            busy = true;
            const l = s.last;
            let k = Math.min(2, l.dealer.length);
            const step = (): void => {
              view = { player: l.player, dealer: l.dealer.slice(0, k), hole: false };
              draw();
              if (k < l.dealer.length) {
                k++;
                later(tm.dealerDrawS * 1000, step);
                return;
              }
              note.textContent = outcomeText(l);
              note.classList.add('flash');
              later(FLASH_MS, () => {
                note.classList.remove('flash');
                note.textContent = '';
                const r = rules.result(s);
                if (r) {
                  api.finish(r);
                  return;
                }
                busy = false;
                view = live();
                draw();
              });
            };
            step();
          }

          function play(a: OkoAction): void {
            if (api.paused || busy || s.over) return;
            const before = s;
            s = rules.apply(s, a);
            if (s.round !== before.round || s.over) reveal();
            else {
              view = live();
              draw();
            }
          }

          draw();
          // A natural right at the first deal resolves inside init; show it like any other round.
          if (s.last.outcome !== '') reveal();
          return {
            stop: () => window.clearTimeout(timer),
            timeout: () => {
              if (s.over) return;
              window.clearTimeout(timer);
              s = rules.apply(s, { by: 'timeout' });
              busy = true;
              draw();
              api.finish(rules.result(s)!);
            },
          };
        },
      }, onFinish),
  };
}
