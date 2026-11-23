import { minigameCatalog } from '../../gen/ids';
import { tokens } from '../../gen/tokens';
import type { Minigame, MinigameEnv } from '../api';
import { begin, capture, fit, sx, sy, tickLoop } from '../canvas';
import { h } from '../dom';
import { mountShell } from '../shell';
import { HadRules, hadConfig, type HadAction, type HadState } from './rules';

/** A swipe this long (CSS px) along one axis turns the snake; the origin then moves on, so one drag can turn twice. */
const TURN_PX = 22;
const KEYS: Record<string, number> = { ArrowUp: 0, ArrowRight: 1, ArrowDown: 2, ArrowLeft: 3, w: 0, d: 1, s: 2, a: 3 };

/** Had (snake), specs/minigames/had.md: swipe to turn, eat to grow. */
export function had(env: MinigameEnv): Minigame {
  const { t, tuning } = env;
  const tm = tuning.minigames.had;
  return {
    meta: minigameCatalog.had,
    mount: (host, ctx, onFinish) =>
      mountShell(host, ctx, env, {
        id: 'had',
        rules: ['hadRules1', 'hadRules2', 'hadRules3'],
        timeCapS: tm.timeCapS,
        start(api) {
          const cfg = hadConfig(tm, ctx.difficulty);
          const rules = new HadRules();
          let s: HadState = rules.init(cfg, ctx.seed);
          let finished = false;

          const canvas = h('canvas.mgc-canvas');
          const info = h('div.mgc-info');
          api.body.append(h('div.mgc', {}, info, h('div.mgc-wrap', {}, canvas)));

          function play(a: HadAction): void {
            if (finished || s.over) return;
            s = rules.apply(s, a);
            const r = rules.result(s);
            if (r) {
              finished = true;
              api.finish(r);
            }
          }

          function draw(): void {
            api.status(t('scoreValue', { score: s.score }));
            info.textContent = t('hadLength', { n: s.body.length });
            const g = begin(canvas);
            if (!g) return;
            const v = fit(canvas, 0, 0, cfg.w, cfg.h, 4);
            const c = v.k;
            g.fillStyle = tokens.colorWorldNightPark;
            g.fillRect(sx(v, 0), sy(v, cfg.h), cfg.w * c, cfg.h * c);
            g.fillStyle = tokens.colorCarDetailCanopy;
            for (let y = 0; y < cfg.h; y++) for (let x = (y % 2); x < cfg.w; x += 2) g.fillRect(sx(v, x), sy(v, y + 1), c, c);
            const [fx, fy] = s.food;
            g.fillStyle = tokens.colorTrafficLightRed;
            g.beginPath();
            g.arc(sx(v, fx + 0.5), sy(v, fy + 0.5), c * 0.38, 0, Math.PI * 2);
            g.fill();
            s.body.forEach(([x, y], i) => {
              g.fillStyle = i === 0 ? tokens.colorWorldDayMarking : tokens.colorBrandAccent;
              g.beginPath();
              g.roundRect(sx(v, x) + 1, sy(v, y + 1) + 1, c - 2, c - 2, c * 0.3);
              g.fill();
            });
          }

          let drag: { id: number; x: number; y: number } | null = null;
          canvas.addEventListener('pointerdown', (e) => {
            e.preventDefault();
            drag = { id: e.pointerId, x: e.clientX, y: e.clientY };
            capture(canvas, e.pointerId);
          });
          canvas.addEventListener('pointermove', (e) => {
            if (!drag || drag.id !== e.pointerId || api.paused) return;
            const dx = e.clientX - drag.x, dy = e.clientY - drag.y;
            if (Math.max(Math.abs(dx), Math.abs(dy)) < TURN_PX) return;
            const dir = Math.abs(dx) > Math.abs(dy) ? (dx > 0 ? 1 : 3) : dy > 0 ? 2 : 0;
            drag = { id: e.pointerId, x: e.clientX, y: e.clientY };
            play({ by: 'player', op: 'turn', dir });
          });
          const up = (e: PointerEvent): void => {
            if (drag?.id === e.pointerId) drag = null;
          };
          canvas.addEventListener('pointerup', up);
          canvas.addEventListener('pointercancel', up);
          const onKey = (e: KeyboardEvent): void => {
            const dir = KEYS[e.key];
            if (dir === undefined || api.paused) return;
            e.preventDefault();
            play({ by: 'player', op: 'turn', dir });
          };
          window.addEventListener('keydown', onKey);

          const stop = tickLoop(api, tm.tickHz, () => !finished, (n) => play({ by: 'player', op: 'tick', n }), draw);
          return {
            stop: () => {
              stop();
              window.removeEventListener('keydown', onKey);
            },
            timeout: () => play({ by: 'timeout' }),
          };
        },
      }, onFinish),
  };
}
