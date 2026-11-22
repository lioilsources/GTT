import { minigameCatalog } from '../../gen/ids';
import type { MessageKey } from '../../gen/i18n';
import type { Minigame, MinigameEnv } from '../api';
import { h, svg } from '../dom';
import { mountShell } from '../shell';
import { bindSwipe, pausableTimer, tween } from '../swipe';
import { KulickyRules, kulickyConfig, type KulickyConfig, type KulickyState } from './rules';

/** Yard layout in mm (y up, hole at 0, 0); the SVG flips y. */
export interface YardLayout {
  halfW: number;
  top: number;
  /** Where marbles rest before a flick. */
  startY: number;
  bottom: number;
  marbleR: number;
  /** A straight-up swipe starts aiming here (the yard's lower edge). */
  aimOriginY: number;
}

/** Derives the yard from the widest scatter so every landing point fits. */
export function yardLayout(c: KulickyConfig): YardLayout {
  const spread = Math.max(c.holeR * 4, ...c.scatter, ...c.aiScatter);
  const halfW = spread * 2.5;
  const marbleR = Math.max(c.holeR * 0.45, 1);
  const startY = -halfW * 1.6;
  return { halfW, top: halfW, startY, bottom: startY - marbleR * 4, marbleR, aimOriginY: -halfW };
}

/** Swipe in CSS px (dx right, dy down) → integer aim point in mm. */
export function yardAim(lay: YardLayout, dx: number, dy: number, mmPerPx: number): { x: number; y: number } {
  return { x: Math.round(dx * mmPerPx), y: Math.round(lay.aimOriginY - dy * mmPerPx) };
}

/** Which round line to show after the rival's shot settled a round. */
export function roundNote(before: { playerPts: number; aiPts: number }, after: { playerPts: number; aiPts: number }): MessageKey {
  const dp = after.playerPts - before.playerPts, da = after.aiPts - before.aiPts;
  return dp > da ? 'roundWon' : da > dp ? 'roundLost' : 'draw';
}

const TWEEN_MS = 450;
const SHOW_MS = 800;
const AI_MS = 700;

/** Kuličky (marbles), specs/minigames/kulicky.md: flick your marble to the hole, then the rival flicks. */
export function kulicky(env: MinigameEnv): Minigame {
  const { t, tuning } = env;
  const tm = tuning.minigames.kulicky;
  return {
    meta: minigameCatalog.kulicky,
    mount: (host, ctx, onFinish) =>
      mountShell(host, ctx, env, {
        id: 'kulicky',
        rules: ['kulickyRules1', 'kulickyRules2', 'kulickyRules3'],
        timeCapS: tm.timeCapS,
        start(api) {
          const cfg = kulickyConfig(tm);
          const rules = new KulickyRules();
          let s: KulickyState = rules.init(cfg, ctx.seed);
          const lay = yardLayout(cfg);
          const timer = pausableTimer(() => api.paused);
          let busy = false;
          let cancelTween = (): void => {};

          const vb = [-lay.halfW, -lay.top, 2 * lay.halfW, lay.top - lay.bottom];
          const yard = svg('svg', { class: 'koulena-lane', viewBox: vb.join(' '), preserveAspectRatio: 'xMidYMid meet' });
          yard.append(svg('rect', { x: vb[0]!, y: vb[1]!, width: vb[2]!, height: vb[3]!, class: 'kulicky-ground', rx: lay.marbleR }));
          yard.append(svg('line', { x1: -lay.halfW, y1: -lay.aimOriginY, x2: lay.halfW, y2: -lay.aimOriginY, class: 'kulicky-line' }));
          yard.append(svg('circle', { cx: 0, cy: 0, r: cfg.holeR, class: 'koulena-pocket' }));
          const guide = svg('line', { class: 'koulena-guide', x1: 0, y1: -lay.startY, x2: 0, y2: -lay.startY, visibility: 'hidden' });
          const startX = lay.marbleR * 3;
          const mine = svg('circle', { class: 'koulena-ball', cx: -startX, cy: -lay.startY, r: lay.marbleR });
          const rival = svg('circle', { class: 'kulicky-rival', cx: startX, cy: -lay.startY, r: lay.marbleR });
          yard.append(guide, mine, rival);

          const info = h('div.koulena-info');
          const note = h('div.koulena-note');
          api.body.append(h('div.koulena', {}, info, yard, note));

          function draw(): void {
            const round = Math.min(s.round, cfg.rounds);
            api.status(t('localScore', { round, rounds: cfg.rounds, player: s.playerPts, ai: s.aiPts }));
            info.textContent = s.over ? '' : s.turn === 'player' ? t('yourTurn') : t('opponentTurn');
          }

          function place(el: SVGCircleElement, x: number, y: number): void {
            el.setAttribute('cx', String(x));
            el.setAttribute('cy', String(-y));
          }

          function roll(el: SVGCircleElement, x0: number, x: number, y: number, done: () => void): void {
            cancelTween = tween(TWEEN_MS, (k) => place(el, x0 + (x - x0) * k, lay.startY + (y - lay.startY) * k), done);
          }

          bindSwipe(yard, {
            canStart: () => !api.paused && !s.over && !busy && s.turn === 'player',
            move(dx, dy) {
              const aim = yardAim(lay, dx, dy, tm.flickMmPerPx);
              guide.setAttribute('visibility', dy < 0 ? 'visible' : 'hidden');
              guide.setAttribute('x1', String(-startX));
              guide.setAttribute('x2', String(aim.x));
              guide.setAttribute('y2', String(-aim.y));
            },
            release(dx, dy, ok) {
              guide.setAttribute('visibility', 'hidden');
              if (!ok) return;
              const aim = yardAim(lay, dx, dy, tm.flickMmPerPx);
              s = rules.apply(s, { by: 'player', x: aim.x, y: aim.y, level: ctx.difficulty });
              busy = true;
              note.textContent = '';
              draw();
              roll(mine, -startX, s.playerShot.x, s.playerShot.y, () => timer.later(AI_MS, rivalShot));
            },
          });

          function rivalShot(): void {
            const before = s;
            s = rules.apply(s, rules.aiAction(s, ctx.difficulty));
            roll(rival, startX, s.aiShot.x, s.aiShot.y, () => {
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
                place(mine, -startX, lay.startY);
                place(rival, startX, lay.startY);
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
