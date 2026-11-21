import { minigameCatalog } from '../../gen/ids';
import type { Minigame, MinigameEnv } from '../api';
import { h, svg } from '../dom';
import { mountShell } from '../shell';
import { KoulenaRules, koulenaConfig, type KoulenaConfig, type KoulenaState } from './rules';

/** Lane layout in board millimetres (y up, rings centred at 0, 0); the SVG flips y. */
export interface LaneLayout {
  /** Half the lane width. */
  halfW: number;
  /** Top edge of the lane (above the pockets). */
  top: number;
  /** Where the ball rests before a throw. */
  ballY: number;
  /** Bottom edge of the lane. */
  bottom: number;
  /** Ball radius for drawing. */
  ballR: number;
  /** A straight-up swipe starts aiming here (the board's lower edge). */
  aimOriginY: number;
}

/** Derives the lane from the board config, so new rings or pockets just fit. */
export function laneLayout(c: KoulenaConfig): LaneLayout {
  const outer = c.ringR.at(-1) ?? 0;
  let halfW = outer, top = outer;
  for (let i = 0; i + 1 < c.pockets.length; i += 2) {
    halfW = Math.max(halfW, Math.abs(c.pockets[i]!) + c.pocketR);
    top = Math.max(top, c.pockets[i + 1]! + c.pocketR);
  }
  const ballR = Math.max(c.pocketR * 0.7, 1);
  const ballY = -outer * 3.5;
  return { halfW: halfW * 1.1, top: top * 1.12, ballY, bottom: ballY - ballR * 3, ballR, aimOriginY: -outer };
}

/** Swipe in CSS px (dx right, dy down) → integer aim point in mm on the board. */
export function flickAim(lay: LaneLayout, dx: number, dy: number, mmPerPx: number): { x: number; y: number } {
  return { x: Math.round(dx * mmPerPx), y: Math.round(lay.aimOriginY - dy * mmPerPx) };
}

const TWEEN_MS = 450;
const SHOW_MS = 700;
const MIN_SWIPE_PX = 12;

/** Koulená (boardwalk roll), specs/minigames/koulena.md: flick the ball up the lane into the rings. */
export function koulena(env: MinigameEnv): Minigame {
  const { t, tuning } = env;
  const tm = tuning.minigames.koulena;
  return {
    meta: minigameCatalog.koulena,
    mount: (host, ctx, onFinish) =>
      mountShell(host, ctx, env, {
        id: 'koulena',
        rules: ['koulenaRules1', 'koulenaRules2', 'koulenaRules3'],
        timeCapS: tm.timeCapS,
        start(api) {
          const cfg = koulenaConfig(tm);
          const rules = new KoulenaRules();
          let s: KoulenaState = rules.init(cfg, ctx.seed);
          const lay = laneLayout(cfg);
          let rolling = false;
          let raf = 0;
          let toast = 0;
          let drag: { id: number; x: number; y: number } | null = null;

          // y is flipped: SVG y = -mm y.
          const vb = [-lay.halfW, -lay.top, 2 * lay.halfW, lay.top - lay.bottom];
          const lane = svg('svg', { class: 'koulena-lane', viewBox: vb.join(' '), preserveAspectRatio: 'xMidYMid meet' });
          lane.append(svg('rect', { x: vb[0]!, y: vb[1]!, width: vb[2]!, height: vb[3]!, class: 'koulena-wood', rx: lay.ballR }));
          for (let i = cfg.ringR.length - 1; i >= 0; i--) {
            const r = cfg.ringR[i]!;
            lane.append(svg('circle', { cx: 0, cy: 0, r, class: `koulena-ring ${i % 2 ? 'odd' : 'even'}` }));
            const inner = cfg.ringR[i - 1] ?? 0;
            const label = svg('text', { x: 0, y: -(inner + r) / 2, class: 'koulena-label', 'font-size': (r - inner) * 0.5 });
            label.textContent = String(cfg.ringPoints[i] ?? 0);
            lane.append(label);
          }
          for (let i = 0; i + 1 < cfg.pockets.length; i += 2) {
            const px = cfg.pockets[i]!, py = -cfg.pockets[i + 1]!;
            lane.append(svg('circle', { cx: px, cy: py, r: cfg.pocketR, class: 'koulena-pocket' }));
            const label = svg('text', { x: px, y: py, class: 'koulena-label pocket', 'font-size': cfg.pocketR * 0.7 });
            label.textContent = String(cfg.pocketPoints);
            lane.append(label);
          }
          const guide = svg('line', { class: 'koulena-guide', x1: 0, y1: -lay.ballY, x2: 0, y2: -lay.ballY, visibility: 'hidden' });
          const mark = svg('circle', { class: 'koulena-mark', r: lay.ballR * 0.45, visibility: 'hidden' });
          const ball = svg('circle', { class: 'koulena-ball', cx: 0, cy: -lay.ballY, r: lay.ballR });
          lane.append(guide, mark, ball);

          const info = h('div.koulena-info');
          const note = h('div.koulena-note');
          api.body.append(h('div.koulena', {}, info, lane, note));

          function draw(): void {
            const series = Math.min(s.series, cfg.series);
            const shown = s.over ? cfg.balls : s.ball + 1;
            info.textContent = t('koulenaSeries', { series, ball: shown });
            api.status(t('scoreValue', { score: s.score }));
          }

          function place(x: number, y: number, r: number): void {
            ball.setAttribute('cx', String(x));
            ball.setAttribute('cy', String(-y));
            ball.setAttribute('r', String(r));
          }

          function swipe(e: PointerEvent): { dx: number; dy: number } {
            return { dx: e.clientX - drag!.x, dy: e.clientY - drag!.y };
          }

          lane.addEventListener('pointerdown', (e) => {
            if (api.paused || s.over || rolling || drag) return;
            drag = { id: e.pointerId, x: e.clientX, y: e.clientY };
            lane.setPointerCapture?.(e.pointerId);
          });
          lane.addEventListener('pointermove', (e) => {
            if (!drag || e.pointerId !== drag.id) return;
            const { dx, dy } = swipe(e);
            const aim = flickAim(lay, dx, dy, tm.flickMmPerPx);
            const ok = dy < -MIN_SWIPE_PX;
            guide.setAttribute('visibility', ok ? 'visible' : 'hidden');
            guide.setAttribute('x2', String(aim.x));
            guide.setAttribute('y2', String(-aim.y));
          });
          const end = (e: PointerEvent): void => {
            if (!drag || e.pointerId !== drag.id) return;
            const { dx, dy } = swipe(e);
            drag = null;
            guide.setAttribute('visibility', 'hidden');
            if (e.type !== 'pointerup' || dy > -MIN_SWIPE_PX || api.paused || s.over || rolling) return;
            const aim = flickAim(lay, dx, dy, tm.flickMmPerPx);
            throwBall(aim.x, aim.y);
          };
          lane.addEventListener('pointerup', end);
          lane.addEventListener('pointercancel', end);

          function throwBall(x: number, y: number): void {
            s = rules.apply(s, { by: 'player', x, y, level: ctx.difficulty });
            const hit = s.lastHit;
            rolling = true;
            mark.setAttribute('visibility', 'hidden');
            const t0 = performance.now();
            const step = (now: number): void => {
              const k = Math.min(1, (now - t0) / TWEEN_MS);
              const e = 1 - (1 - k) * (1 - k);
              place(hit.x * e, lay.ballY + (hit.y - lay.ballY) * e, lay.ballR * (1 - 0.3 * e));
              if (k < 1) {
                raf = requestAnimationFrame(step);
                return;
              }
              landed();
            };
            raf = requestAnimationFrame(step);
          }

          function landed(): void {
            const hit = s.lastHit;
            mark.setAttribute('cx', String(hit.x));
            mark.setAttribute('cy', String(-hit.y));
            mark.setAttribute('visibility', 'visible');
            note.textContent = String(hit.points);
            note.classList.toggle('flash', hit.points > 0);
            draw();
            window.clearTimeout(toast);
            toast = window.setTimeout(function next() {
              if (api.paused) {
                toast = window.setTimeout(next, 200);
                return;
              }
              const r = rules.result(s);
              if (r) {
                api.finish(r);
                return;
              }
              note.classList.remove('flash');
              place(0, lay.ballY, lay.ballR);
              rolling = false;
            }, SHOW_MS);
          }

          draw();
          return {
            stop: () => {
              cancelAnimationFrame(raf);
              window.clearTimeout(toast);
            },
            timeout: () => {
              if (s.over) return;
              cancelAnimationFrame(raf);
              window.clearTimeout(toast);
              s = rules.apply(s, { by: 'timeout' });
              draw();
              api.finish(rules.result(s)!);
            },
          };
        },
      }, onFinish),
  };
}
