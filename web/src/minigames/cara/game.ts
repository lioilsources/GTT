import { minigameCatalog } from '../../gen/ids';
import type { Minigame, MinigameEnv } from '../api';
import { h, svg } from '../dom';
import { roundNote } from '../kulicky/game';
import { mountShell } from '../shell';
import { bindSwipe, pausableTimer, tween } from '../swipe';
import { CaraRules, caraConfig, type CaraConfig, type CaraState } from './rules';

/** Pavement layout in mm (y up, the line at y = 0, the wall just behind it); the SVG flips y. */
export interface PavementLayout {
  halfW: number;
  /** The wall's face. */
  wallY: number;
  top: number;
  /** Where coins rest before a toss. */
  startY: number;
  bottom: number;
  coinR: number;
  /** Coins are drawn left (player) and right (rival) of the middle. */
  laneX: number;
  /** A straight-up swipe starts aiming here. */
  aimOriginY: number;
}

export function pavementLayout(c: CaraConfig): PavementLayout {
  const spread = Math.max(...c.scatter, ...c.aiScatter, ...c.aiAim);
  const halfW = spread * 2.5;
  const coinR = spread * 0.18;
  const wallY = spread * 1.2;
  const startY = -spread * 5.5;
  return { halfW, wallY, top: wallY + spread * 0.6, startY, bottom: startY - coinR * 3, coinR, laneX: halfW / 3, aimOriginY: -spread * 4 };
}

/** Swipe length in CSS px (dy down) → integer aimed distance from the line in mm. */
export function tossAim(lay: PavementLayout, dy: number, mmPerPx: number): number {
  return Math.round(lay.aimOriginY - dy * mmPerPx);
}

const TWEEN_MS = 450;
const SHOW_MS = 800;
const AI_MS = 700;

/** Čára (coin to the wall), specs/minigames/cara.md: toss closest to the line without burning it. */
export function cara(env: MinigameEnv): Minigame {
  const { t, tuning } = env;
  const tm = tuning.minigames.cara;
  return {
    meta: minigameCatalog.cara,
    mount: (host, ctx, onFinish) =>
      mountShell(host, ctx, env, {
        id: 'cara',
        rules: ['caraRules1', 'caraRules2', 'caraRules3'],
        timeCapS: tm.timeCapS,
        start(api) {
          const cfg = caraConfig(tm);
          const rules = new CaraRules();
          let s: CaraState = rules.init(cfg, ctx.seed);
          const lay = pavementLayout(cfg);
          const timer = pausableTimer(() => api.paused);
          let busy = false;
          let cancelTween = (): void => {};

          const vb = [-lay.halfW, -lay.top, 2 * lay.halfW, lay.top - lay.bottom];
          const pave = svg('svg', { class: 'koulena-lane', viewBox: vb.join(' '), preserveAspectRatio: 'xMidYMid meet' });
          pave.append(svg('rect', { x: vb[0]!, y: vb[1]!, width: vb[2]!, height: vb[3]!, class: 'kulicky-ground', rx: lay.coinR }));
          pave.append(svg('rect', { x: vb[0]!, y: vb[1]!, width: vb[2]!, height: lay.top - lay.wallY, class: 'cara-wall' }));
          pave.append(svg('line', { x1: -lay.halfW, y1: 0, x2: lay.halfW, y2: 0, class: 'cara-line' }));
          const guide = svg('line', { class: 'koulena-guide', x1: -lay.laneX, y1: -lay.startY, x2: -lay.laneX, y2: -lay.startY, visibility: 'hidden' });
          const mine = svg('circle', { class: 'koulena-ball', cx: -lay.laneX, cy: -lay.startY, r: lay.coinR });
          const rival = svg('circle', { class: 'kulicky-rival', cx: lay.laneX, cy: -lay.startY, r: lay.coinR });
          pave.append(guide, mine, rival);

          const info = h('div.koulena-info');
          const note = h('div.koulena-note');
          api.body.append(h('div.koulena', {}, info, pave, note));

          function draw(): void {
            const round = Math.min(s.round, cfg.rounds);
            api.status(t('localScore', { round, rounds: cfg.rounds, player: s.playerPts, ai: s.aiPts }));
            info.textContent = s.over ? '' : s.turn === 'player' ? t('yourTurn') : t('opponentTurn');
          }

          function place(el: SVGCircleElement, y: number, burnt: boolean): void {
            el.setAttribute('cy', String(-y));
            el.classList.toggle('burnt', burnt);
          }

          function toss(el: SVGCircleElement, y: number, burnt: boolean, done: () => void): void {
            cancelTween = tween(TWEEN_MS, (k) => place(el, lay.startY + (y - lay.startY) * k, false), () => {
              place(el, y, burnt);
              done();
            });
          }

          bindSwipe(pave, {
            canStart: () => !api.paused && !s.over && !busy && s.turn === 'player',
            move(_dx, dy) {
              guide.setAttribute('visibility', dy < 0 ? 'visible' : 'hidden');
              guide.setAttribute('y2', String(-tossAim(lay, dy, tm.flickMmPerPx)));
            },
            release(_dx, dy, ok) {
              guide.setAttribute('visibility', 'hidden');
              if (!ok) return;
              s = rules.apply(s, { by: 'player', y: tossAim(lay, dy, tm.flickMmPerPx), level: ctx.difficulty });
              busy = true;
              note.textContent = '';
              draw();
              toss(mine, s.playerCoin.y, s.playerCoin.burnt, () => timer.later(AI_MS, rivalToss));
            },
          });

          function rivalToss(): void {
            const before = s;
            s = rules.apply(s, rules.aiAction(s, ctx.difficulty));
            toss(rival, s.aiCoin.y, s.aiCoin.burnt, () => {
              note.textContent = t(roundNote(before, s));
              note.classList.toggle('flash', s.playerPts > before.playerPts);
              draw();
              timer.later(SHOW_MS, () => {
                const r = rules.result(s);
                if (r) {
                  api.finish(r);
                  return;
                }
                note.classList.remove('flash');
                place(mine, lay.startY, false);
                place(rival, lay.startY, false);
                busy = false;
                draw();
              });
            });
          }

          draw();
          return {
            stop: () => {
              cancelTween();
              timer.cancel();
            },
            timeout: () => {
              if (s.over) return;
              cancelTween();
              timer.cancel();
              s = rules.apply(s, { by: 'timeout' });
              draw();
              api.finish(rules.result(s)!);
            },
          };
        },
      }, onFinish),
  };
}
