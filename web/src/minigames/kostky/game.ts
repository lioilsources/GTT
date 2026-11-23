import { minigameCatalog } from '../../gen/ids';
import type { MessageKey } from '../../gen/i18n';
import type { Minigame, MinigameEnv } from '../api';
import { dieFace } from '../dice';
import { h, svg } from '../dom';
import { aiPrng } from '../rules';
import { mountShell } from '../shell';
import { turnDriver } from '../turns';
import { CATS, catValue, KostkyRules, kostkyConfig, total, upperSum, type KostkyAction, type KostkyState } from './rules';

/**
 * Kostkový poker, specs/minigames/kostky.md: tap dice to hold them, roll up to three times, then
 * tap a free row of your column (it shows what the roll would write).
 */
export function kostky(env: MinigameEnv): Minigame {
  const { t, tuning } = env;
  const tm = tuning.minigames.kostky;
  const cfg = kostkyConfig(tm);
  return {
    meta: minigameCatalog.kostky,
    mount: (host, ctx, onFinish) =>
      mountShell(host, ctx, env, {
        id: 'kostky',
        rules: ['kostkyRules1', 'kostkyRules2', 'kostkyRules3'],
        timeCapS: tm.timeCapS,
        start(api) {
          const rules = new KostkyRules();
          const ai = aiPrng(ctx.seed);
          let s: KostkyState = rules.init(cfg, ctx.seed);
          let held = new Set<number>();
          /** Dice of the turn just written, shown until the next roll. */
          let shown: number[] = [];

          const info = h('div.deset-info');
          const board = svg('svg', { class: 'kostky-dice', viewBox: '0 0 100 22', preserveAspectRatio: 'xMidYMid meet' });
          const roll = h('button.mg-btn', { type: 'button', onclick: () => tapRoll() });
          const table = h('table.kostky-table');
          api.body.append(h('div.kostky', {}, info, board, h('div.deset-buttons', {}, roll), table));

          const driver = turnDriver({
            api, thinkS: tm.aiThinkS,
            aiTurn: () => !s.over && s.turn === 'ai',
            aiMove: () => play(rules.aiAction(s, ctx.difficulty, ai)),
            result: () => rules.result(s),
          });

          const mine = (): boolean => !s.over && s.turn === 'player';

          function drawDice(): void {
            const values = s.dice.length ? s.dice : shown;
            board.replaceChildren();
            for (let i = 0; i < 5; i++) {
              const g = dieFace(3 + i * 19.5, 2, 18, values[i] ?? 0, held.has(i) ? ['sel'] : []);
              if (mine() && s.rolls > 0 && s.rolls < 3) {
                g.classList.add('tap');
                g.addEventListener('click', () => toggle(i));
              }
              board.append(g);
            }
          }

          function row(label: string, p: string, a: string, onTap?: () => void, cls = ''): HTMLTableRowElement {
            const cell = h(`td.p${cls}`, onTap ? { onclick: onTap } : {}, p);
            return h('tr', {}, h('th', {}, label), cell, h('td', {}, a));
          }

          function drawTable(): void {
            const head = h('tr', {}, h('th'), h('th', {}, t('srdceYou')), h('th', {}, env.opponent?.name ?? ''));
            const rows: HTMLTableRowElement[] = [head];
            const cell = (v: number): string => (v < 0 ? '' : String(v));
            for (let i = 0; i < CATS; i++) {
              const label = t(`kostkyCat${i}` as MessageKey);
              const free = s.player[i] === -1;
              if (free && mine() && s.rolls > 0) {
                rows.push(row(label, String(catValue(i, s.dice)), cell(s.ai[i]!), () => tapScore(i), '.preview'));
              } else rows.push(row(label, cell(s.player[i]!), cell(s.ai[i]!)));
              if (i === 5) {
                const bonus = (tb: number[]): string => (upperSum(tb) >= tm.bonusAt ? String(tm.bonus) : `${upperSum(tb)}/${tm.bonusAt}`);
                rows.push(row(t('kostkyBonus'), bonus(s.player), bonus(s.ai), undefined, '.sum'));
              }
            }
            rows.push(row(t('kostkyTotal'), String(total(s.player, cfg)), String(total(s.ai, cfg)), undefined, '.sum'));
            table.replaceChildren(...rows);
          }

          function draw(): void {
            info.textContent = t('desetRound', { round: Math.min(s.round, CATS), max: CATS });
            drawDice();
            drawTable();
            roll.textContent = t('kostkyRoll', { n: 3 - s.rolls });
            roll.disabled = !mine() || s.rolls >= 3 || held.size === 5;
            api.status(s.over ? '' : mine() ? t('yourTurn') : t('opponentTurn'));
          }

          function toggle(i: number): void {
            if (api.paused || !mine()) return;
            if (held.has(i)) held.delete(i);
            else held.add(i);
            draw();
          }

          function tapRoll(): void {
            if (api.paused || !mine() || s.rolls >= 3 || held.size === 5) return;
            play({ by: 'player', op: 'roll', keep: s.rolls === 0 ? [] : [...held].sort((a, b) => a - b) });
          }

          function tapScore(cat: number): void {
            if (api.paused || !mine() || s.rolls === 0) return;
            play({ by: 'player', op: 'score', cat });
          }

          function play(a: KostkyAction): void {
            if (s.over) return;
            const before = s;
            s = rules.apply(s, a);
            if (a.by !== 'timeout' && a.op === 'score') {
              shown = before.dice;
              held = new Set();
            } else if (a.by === 'ai' && a.op === 'roll') held = new Set(a.keep);
            else if (a.by === 'player' && a.op === 'roll' && before.rolls === 0) held = new Set();
            if (s.turn === 'player' && before.turn === 'ai') held = new Set();
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
