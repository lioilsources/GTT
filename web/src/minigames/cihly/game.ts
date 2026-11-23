import { minigameCatalog } from '../../gen/ids';
import { tokens } from '../../gen/tokens';
import type { Minigame, MinigameEnv } from '../api';
import { begin, capture, disc, fit, sx, sy, tickLoop, toWorld } from '../canvas';
import { h } from '../dom';
import { mountShell } from '../shell';
import { CihlyRules, brickRect, cihlyConfig, halfWidth, type CihlyAction, type CihlyState } from './rules';

/** Row colours from the top. */
const ROWS = [
  tokens.colorTrafficLightRed,
  tokens.colorGaragePaints[5]!,
  tokens.colorBrandAccent,
  tokens.colorGaragePaints[3]!,
  tokens.colorGaragePaints[2]!,
  tokens.colorGaragePaints[6]!,
];

/** Cihly (breakout), specs/minigames/cihly.md: the paddle follows the finger. */
export function cihly(env: MinigameEnv): Minigame {
  const { t, tuning } = env;
  const tm = tuning.minigames.cihly;
  return {
    meta: minigameCatalog.cihly,
    mount: (host, ctx, onFinish) =>
      mountShell(host, ctx, env, {
        id: 'cihly',
        rules: ['cihlyRules1', 'cihlyRules2', 'cihlyRules3'],
        timeCapS: tm.timeCapS,
        start(api) {
          const cfg = cihlyConfig(tm, ctx.difficulty);
          const rules = new CihlyRules();
          let s: CihlyState = rules.init(cfg, ctx.seed);
          let finished = false;

          const canvas = h('canvas.mgc-canvas');
          const info = h('div.mgc-info');
          api.body.append(h('div.mgc', {}, info, h('div.mgc-wrap', {}, canvas)));
          const view = () => fit(canvas, 0, 0, cfg.w, cfg.h, 4);

          function play(a: CihlyAction): void {
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
            info.textContent = t('cihlyLives', { n: s.lives });
            const g = begin(canvas);
            if (!g) return;
            const v = view();
            const k = v.k;
            g.fillStyle = tokens.colorWorldNightAsphalt;
            g.fillRect(sx(v, 0), sy(v, cfg.h), cfg.w * k, cfg.h * k);
            s.bricks.forEach((on, i) => {
              if (!on) return;
              const b = brickRect(cfg, i);
              g.fillStyle = ROWS[Math.floor(i / cfg.cols) % ROWS.length]!;
              g.beginPath();
              g.roundRect(sx(v, b.x0), sy(v, b.y1), (b.x1 - b.x0) * k, (b.y1 - b.y0) * k, 2);
              g.fill();
            });
            const hw = halfWidth(cfg);
            g.fillStyle = tokens.colorWorldDayMarking;
            g.beginPath();
            g.roundRect(sx(v, s.paddle - hw), sy(v, cfg.paddleY + cfg.paddleH), 2 * hw * k, 2 * cfg.paddleH * k, cfg.paddleH * k);
            g.fill();
            const bx = s.serve > 0 ? s.paddle : s.ball.x;
            disc(g, sx(v, bx), sy(v, s.ball.y), Math.max(3, cfg.ballR * k), tokens.colorBrandAccent);
          }

          const follow = (e: PointerEvent): void => {
            if (api.paused) return;
            e.preventDefault();
            play({ by: 'player', op: 'move', x: Math.round(toWorld(canvas, view(), e).x) });
          };
          canvas.addEventListener('pointerdown', (e) => {
            capture(canvas, e.pointerId);
            follow(e);
          });
          canvas.addEventListener('pointermove', follow);

          const stop = tickLoop(api, tm.tickHz, () => !finished, (n) => play({ by: 'player', op: 'tick', n }), draw);
          return { stop, timeout: () => play({ by: 'timeout' }) };
        },
      }, onFinish),
  };
}
