import { minigameCatalog } from '../../gen/ids';
import type { MessageKey } from '../../gen/i18n';
import type { Minigame, MinigameEnv } from '../api';
import { h, svg } from '../dom';
import { aiPrng } from '../rules';
import { mountShell } from '../shell';
import { turnDriver } from '../turns';
import { PrsiRules, prsiConfig, QUEEN, rankOf, suitOf, type PrsiAction, type PrsiState } from './rules';

/** Simple suit symbols (srdce, list, kule, žalud) in a 0..10 box. */
function suitIcon(su: number): SVGSVGElement {
  const el = svg('svg', { class: `prsi-suit s${su}`, viewBox: '0 0 10 10' });
  if (su === 0) el.append(svg('path', { d: 'M5 9 L1.2 4.8 A2.1 2.1 0 0 1 5 2.6 A2.1 2.1 0 0 1 8.8 4.8 Z' }));
  else if (su === 1) {
    el.append(svg('path', { d: 'M5 1 C8.5 3 8.5 7 5 9 C1.5 7 1.5 3 5 1 Z' }));
    el.append(svg('path', { d: 'M5 2 L5 9.5', class: 'vein' }));
  } else if (su === 2) el.append(svg('circle', { cx: 5, cy: 5, r: 3.6 }));
  else {
    el.append(svg('ellipse', { cx: 5, cy: 6, rx: 2.6, ry: 3.2 }));
    el.append(svg('rect', { x: 1.8, y: 1.6, width: 6.4, height: 2.4, rx: 1, class: 'cap' }));
  }
  return el;
}

/** Prší, specs/minigames/prsi.md: tap a card to play it; a svršek asks for the suit. */
export function prsi(env: MinigameEnv): Minigame {
  const { t, tuning } = env;
  const tm = tuning.minigames.prsi;
  const rankText = (r: number): string =>
    r <= 3 ? String(r + 7) : t((['prsiJack', 'prsiQueen', 'prsiKing', 'prsiAce'] as const)[r - 4]!);
  const card = (c: number | null, cls = '', onTap?: () => void): HTMLElement => {
    if (c === null) return h(`div.oko-card.back${cls}`);
    return h(`div.oko-card.prsi-card${cls}`, onTap ? { onclick: onTap } : {}, h('span.rank', {}, rankText(rankOf(c))), suitIcon(suitOf(c)));
  };
  return {
    meta: minigameCatalog.prsi,
    mount: (host, ctx, onFinish) =>
      mountShell(host, ctx, env, {
        id: 'prsi',
        rules: ['prsiRules1', 'prsiRules2', 'prsiRules3'],
        timeCapS: tm.timeCapS,
        start(api) {
          const rules = new PrsiRules();
          const ai = aiPrng(ctx.seed);
          let s: PrsiState = rules.init(prsiConfig(tm), ctx.seed);
          let picking = -1;
          let toast = 0;

          const info = h('div.oko-info');
          const aiSide = h('div.oko-hand');
          const aiLabel = h('div.oko-info');
          const table = h('div.oko-hand.prsi-table');
          const note = h('div.oko-note');
          const hand = h('div.oko-hand');
          const buttons = h('div.oko-buttons');
          api.body.append(h('div.oko', {}, info, h('div.oko-side', {}, aiSide, aiLabel), table, note, hand, buttons));

          const driver = turnDriver({
            api, thinkS: tm.aiThinkS,
            aiTurn: () => !s.over && s.turn === 'ai',
            aiMove: () => play(rules.aiAction(s, ctx.difficulty, ai)),
            result: () => rules.result(s),
          });

          const mine = (): boolean => !s.over && s.turn === 'player';

          function draw(): void {
            info.textContent = t('prsiRounds', { player: s.playerWins, ai: s.aiWins });
            aiSide.replaceChildren(card(null, '.small'));
            aiLabel.textContent = t('prsiCards', { n: s.ai.length });
            const top = s.pile[s.pile.length - 1]!;
            table.replaceChildren(
              h('div.prsi-stack', {}, card(null), h('span', {}, String(s.deck.length))),
              card(top, s.sevens > 0 || s.ace ? '.hot' : ''),
              h('div.prsi-stack', {}, suitIcon(s.suit), h('span', {}, t(`prsiSuit${s.suit}` as MessageKey))),
            );
            const legal = mine() ? rules.legalActions(s) : [];
            const playable = new Set(legal.flatMap((a) => (a.by !== 'timeout' && a.op === 'play' ? [a.card] : [])));
            hand.replaceChildren(
              ...s.player.map((c) => (playable.has(c) ? card(c, '.tap', () => tapCard(c)) : card(c, mine() ? '.dim' : ''))),
            );
            if (picking >= 0) {
              buttons.replaceChildren(
                ...[0, 1, 2, 3].map((su) =>
                  h('button.mg-btn', { type: 'button', title: t(`prsiSuit${su}` as MessageKey), onclick: () => pick(su) }, suitIcon(su))),
              );
              note.textContent = t('prsiPickSuit');
            } else {
              const label = s.ace ? t('prsiStand') : s.sevens > 0 ? t('prsiDrawN', { n: 2 * s.sevens }) : t('prsiDraw');
              buttons.replaceChildren(h('button.mg-btn', { type: 'button', disabled: !mine(), onclick: () => tapPass() }, label));
              if (!note.classList.contains('flash')) note.textContent = '';
            }
            api.status(s.over ? '' : mine() ? t('yourTurn') : t('opponentTurn'));
          }

          function flash(text: string): void {
            window.clearTimeout(toast);
            note.classList.add('flash');
            note.textContent = text;
            toast = window.setTimeout(() => {
              note.classList.remove('flash');
              draw();
            }, 1200);
          }

          function tapCard(c: number): void {
            if (api.paused || !mine()) return;
            if (rankOf(c) === QUEEN && !s.ace && s.sevens === 0) {
              picking = c;
              draw();
              return;
            }
            play({ by: 'player', op: 'play', card: c, suit: -1 });
          }

          function pick(su: number): void {
            if (api.paused || !mine() || picking < 0) return;
            const c = picking;
            picking = -1;
            play({ by: 'player', op: 'play', card: c, suit: su });
          }

          function tapPass(): void {
            if (api.paused || !mine()) return;
            picking = -1;
            play({ by: 'player', op: s.ace ? 'stand' : 'draw' });
          }

          function play(a: PrsiAction): void {
            if (s.over) return;
            const before = s;
            s = rules.apply(s, a);
            if (s.round !== before.round || (s.over && a.by !== 'timeout')) flash(s.last === 'player' ? t('roundWon') : t('roundLost'));
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
