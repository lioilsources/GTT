import { minigameCatalog } from '../../gen/ids';
import type { Minigame, MinigameEnv } from '../api';
import { h, svg } from '../dom';
import { aiPrng } from '../rules';
import { mountShell } from '../shell';
import { bindSwipe, pausableTimer, tween } from '../swipe';
import { NohejbalRules, nohejbalConfig, type NohejbalConfig, type NohejbalState } from './rules';

/**
 * Top-down court in SVG units (mm, y down): the rival's half is y ∈ [−depth, 0] at the top, the
 * player's half y ∈ [0, depth] below, the net at y = 0. Rules coordinates are per half (y back from
 * the net), so a shot into the rival's half is drawn at (x, −y) and one into the player's at (x, y).
 */
export interface CourtLayout {
  halfW: number;
  depth: number;
  /** Space around the lines so out balls stay visible. */
  pad: number;
  ballR: number;
  manR: number;
}

export function courtLayout(c: NohejbalConfig): CourtLayout {
  const pad = Math.max(...c.scatter, ...c.aiScatter);
  return { halfW: c.halfWidth, depth: c.depth, pad, ballR: c.halfWidth * 0.05, manR: c.halfWidth * 0.09 };
}

/** Swipe in CSS px (dx right, dy down) → integer aim point in the rival's half (y back from the net). */
export function courtAim(dx: number, dy: number, mmPerPx: number): { x: number; y: number } {
  return { x: Math.round(dx * mmPerPx), y: Math.round(-dy * mmPerPx) };
}

const TWEEN_MS = 500;
const SHOW_MS = 800;
const AI_MS = 650;

/** Nohejbal (footnet), specs/minigames/nohejbal.md: the first `sport` engine game. */
export function nohejbal(env: MinigameEnv): Minigame {
  const { t, tuning } = env;
  const tm = tuning.minigames.nohejbal;
  return {
    meta: minigameCatalog.nohejbal,
    mount: (host, ctx, onFinish) =>
      mountShell(host, ctx, env, {
        id: 'nohejbal',
        rules: ['nohejbalRules1', 'nohejbalRules2', 'nohejbalRules3'],
        timeCapS: tm.timeCapS,
        start(api) {
          const cfg = nohejbalConfig(tm);
          const rules = new NohejbalRules();
          const ai = aiPrng(ctx.seed);
          let s: NohejbalState = rules.init(cfg, ctx.seed);
          const lay = courtLayout(cfg);
          const timer = pausableTimer(() => api.paused);
          let busy = false;
          let cancelTween = (): void => {};
          const homeY = Math.trunc(cfg.depth / 2);
          const reach = cfg.aiReach[ctx.difficulty - 1] ?? 0;

          const w = lay.halfW + lay.pad, d = lay.depth + lay.pad;
          const court = svg('svg', { class: 'koulena-lane', viewBox: [-w, -d, 2 * w, 2 * d].join(' '), preserveAspectRatio: 'xMidYMid meet' });
          court.append(svg('rect', { x: -w, y: -d, width: 2 * w, height: 2 * d, class: 'kulicky-ground', rx: lay.ballR }));
          court.append(svg('rect', { x: -lay.halfW, y: -lay.depth, width: 2 * lay.halfW, height: lay.depth, class: 'nohejbal-half' }));
          court.append(svg('rect', { x: -lay.halfW, y: 0, width: 2 * lay.halfW, height: lay.depth, class: 'nohejbal-half' }));
          court.append(svg('line', { x1: -w, y1: 0, x2: w, y2: 0, class: 'nohejbal-net' }));
          court.append(svg('circle', { cx: 0, cy: -homeY, r: reach, class: 'nohejbal-reach' }));
          const guide = svg('line', { class: 'koulena-guide', x1: 0, y1: homeY, x2: 0, y2: homeY, visibility: 'hidden' });
          const mark = svg('circle', { class: 'koulena-mark', r: lay.ballR * 0.6, visibility: 'hidden' });
          const me = svg('circle', { class: 'koulena-ball', cx: 0, cy: homeY, r: lay.manR });
          const rival = svg('circle', { class: 'kulicky-rival', cx: 0, cy: -homeY, r: lay.manR });
          const ball = svg('circle', { class: 'nohejbal-ball', cx: 0, cy: homeY, r: lay.ballR });
          court.append(guide, mark, me, rival, ball);

          const info = h('div.koulena-info');
          const note = h('div.koulena-note');
          api.body.append(h('div.koulena', {}, info, court, note));

          function draw(): void {
            api.status(t('nohejbalScore', { player: s.playerPts, ai: s.aiPts }));
            info.textContent = s.over ? '' : s.turn === 'player' ? t('yourTurn') : t('opponentTurn');
          }

          function at(el: SVGCircleElement, x: number, y: number): void {
            el.setAttribute('cx', String(x));
            el.setAttribute('cy', String(y));
          }

          function home(): void {
            at(me, 0, homeY);
            at(rival, 0, -homeY);
            at(ball, 0, s.turn === 'player' ? homeY : -homeY);
          }

          /** Applies one shot and animates the ball (and the receiver, when it gets there). */
          function play(a: Parameters<NohejbalRules['apply']>[1]): void {
            const before = s;
            s = rules.apply(s, a);
            const shot = s.lastShot;
            const toRival = shot.by === 'player';
            const fromX = Number(ball.getAttribute('cx')), fromY = Number(ball.getAttribute('cy'));
            const tx = shot.x, ty = toRival ? -shot.y : shot.y;
            const runner = toRival ? rival : me;
            const rx0 = Number(runner.getAttribute('cx')), ry0 = Number(runner.getAttribute('cy'));
            busy = true;
            mark.setAttribute('visibility', 'hidden');
            note.textContent = '';
            draw();
            cancelTween = tween(TWEEN_MS, (k) => {
              at(ball, fromX + (tx - fromX) * k, fromY + (ty - fromY) * k);
              if (shot.reached) at(runner, rx0 + (tx - rx0) * k, ry0 + (ty - ry0) * k);
            }, () => {
              mark.setAttribute('cx', String(tx));
              mark.setAttribute('cy', String(ty));
              mark.setAttribute('visibility', 'visible');
              if (shot.reached) {
                // Rally goes on: the receiver plays the ball back from where it caught it.
                if (s.turn === 'ai') timer.later(AI_MS, rivalShot);
                else busy = false;
                return;
              }
              const won = s.playerPts > before.playerPts;
              note.textContent = t(won ? 'roundWon' : 'roundLost');
              note.classList.toggle('flash', won);
              timer.later(SHOW_MS, () => {
                const r = rules.result(s);
                if (r) {
                  api.finish(r);
                  return;
                }
                note.classList.remove('flash');
                mark.setAttribute('visibility', 'hidden');
                home();
                draw();
                if (s.turn === 'ai') timer.later(AI_MS, rivalShot);
                else busy = false;
              });
            });
          }

          function rivalShot(): void {
            if (s.over) return;
            play(rules.aiAction(s, ctx.difficulty, ai));
          }

          bindSwipe(court, {
            canStart: () => !api.paused && !s.over && !busy && s.turn === 'player',
            move(dx, dy) {
              const aim = courtAim(dx, dy, tm.flickMmPerPx);
              guide.setAttribute('visibility', dy < 0 ? 'visible' : 'hidden');
              guide.setAttribute('x1', me.getAttribute('cx') ?? '0');
              guide.setAttribute('y1', me.getAttribute('cy') ?? String(homeY));
              guide.setAttribute('x2', String(aim.x));
              guide.setAttribute('y2', String(-aim.y));
            },
            release(dx, dy, ok) {
              guide.setAttribute('visibility', 'hidden');
              if (!ok) return;
              const aim = courtAim(dx, dy, tm.flickMmPerPx);
              play({ by: 'player', x: aim.x, y: aim.y, level: ctx.difficulty });
            },
          });

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
