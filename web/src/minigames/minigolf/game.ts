import { minigameCatalog } from '../../gen/ids';
import { tokens } from '../../gen/tokens';
import type { Minigame, MinigameEnv } from '../api';
import { bindDrag, begin, disc, dragPower, fit, playback, sx, sy, toast, type View } from '../canvas';
import { h } from '../dom';
import { mountShell } from '../shell';
import { MinigolfRules, minigolfConfig, simulatePutt, type Box, type MinigolfState } from './rules';

/** Border drawn around the course (u). */
const EDGE = 4000;

/** Minigolf, specs/minigames/minigolf.md: drag from the ball to aim, longer = harder. */
export function minigolf(env: MinigameEnv): Minigame {
  const { t, tuning } = env;
  const tm = tuning.minigames.minigolf;
  return {
    meta: minigameCatalog.minigolf,
    mount: (host, ctx, onFinish) =>
      mountShell(host, ctx, env, {
        id: 'minigolf',
        rules: ['minigolfRules1', 'minigolfRules2', 'minigolfRules3'],
        timeCapS: tm.timeCapS,
        start(api) {
          const cfg = minigolfConfig(tm, ctx.difficulty);
          const rules = new MinigolfRules();
          let s: MinigolfState = rules.init(cfg, ctx.seed);
          let ball = { x: s.x, y: s.y };
          let shownHole = s.hole;
          let busy = false;
          let aim: { x: number; y: number; power: number } | null = null;
          let cancel = (): void => {};
          let raf = 0;

          const canvas = h('canvas.mgc-canvas');
          const info = h('div.mgc-info');
          const fill = h('div.mgc-power-fill');
          api.body.append(h('div.mgc', {}, info, h('div.mgc-wrap', {}, canvas), h('div.mgc-power', {}, fill)));

          const view = (): View => {
            const hl = rules.holeAt(shownHole);
            return fit(canvas, -EDGE, -EDGE, hl.w + EDGE, hl.h + EDGE, 8);
          };

          function hud(): void {
            const hole = Math.min(s.hole, 6);
            api.status(t('minigolfStrokes', { n: s.strokes }));
            info.textContent = t('minigolfHole', { hole, par: rules.holeAt(hole).par });
            fill.style.width = `${aim ? aim.power : 0}%`;
          }

          function box(g: CanvasRenderingContext2D, v: View, b: Box, color: string): void {
            g.fillStyle = color;
            g.fillRect(sx(v, b.x0), sy(v, b.y1), (b.x1 - b.x0) * v.k, (b.y1 - b.y0) * v.k);
          }

          function draw(): void {
            const g = begin(canvas);
            if (!g) return;
            const v = view();
            const hl = rules.holeAt(shownHole);
            const k = v.k;
            box(g, v, { x0: -EDGE, y0: -EDGE, x1: hl.w + EDGE, y1: hl.h + EDGE }, tokens.colorCarDetailBed);
            box(g, v, { x0: 0, y0: 0, x1: hl.w, y1: hl.h }, tokens.colorWorldDayPark);
            for (const b of hl.water) box(g, v, b, tokens.colorWorldDayWater);
            for (const b of hl.sand) box(g, v, b, tokens.colorWorldDayFacades[5]!);
            for (const b of hl.walls) box(g, v, b, tokens.colorShopsBar);
            for (const b of hl.bumpers) disc(g, sx(v, b.x), sy(v, b.y), b.r * k, tokens.colorBoothBody, tokens.colorBoothRoof, 2);
            disc(g, sx(v, hl.cx), sy(v, hl.cy), Math.max(5, cfg.ballR * 1.6 * k), tokens.colorCarDetailLimoPillar);
            g.strokeStyle = tokens.colorWorldDayMarking;
            g.lineWidth = 2;
            g.beginPath();
            g.moveTo(sx(v, hl.cx), sy(v, hl.cy));
            g.lineTo(sx(v, hl.cx), sy(v, hl.cy) - 28);
            g.stroke();
            g.fillStyle = tokens.colorTrafficLightRed;
            g.beginPath();
            g.moveTo(sx(v, hl.cx), sy(v, hl.cy) - 28);
            g.lineTo(sx(v, hl.cx) + 14, sy(v, hl.cy) - 22);
            g.lineTo(sx(v, hl.cx), sy(v, hl.cy) - 16);
            g.fill();
            if (aim && !busy) {
              const L = Math.hypot(aim.x - ball.x, aim.y - ball.y) || 1;
              const reach = (aim.power / 100) * hl.h * 0.35;
              g.setLineDash([5, 5]);
              g.strokeStyle = tokens.colorUiControlWheel;
              g.lineWidth = 2;
              g.beginPath();
              g.moveTo(sx(v, ball.x), sy(v, ball.y));
              g.lineTo(sx(v, ball.x + ((aim.x - ball.x) / L) * reach), sy(v, ball.y + ((aim.y - ball.y) / L) * reach));
              g.stroke();
              g.setLineDash([]);
            }
            disc(g, sx(v, ball.x), sy(v, ball.y), Math.max(4, cfg.ballR * k), tokens.colorWorldDayMarking, tokens.colorUiLabelShadow, 1);
          }

          function frame(): void {
            raf = requestAnimationFrame(frame);
            hud();
            draw();
          }

          function putt(a: { by: 'player'; op: 'putt'; x: number; y: number; power: number }): void {
            if (!rules.legal(s, a)) return;
            busy = true;
            aim = null;
            const vel = rules.velocity(s, a);
            const frames: Array<{ x: number; y: number }> = [];
            let n = 0;
            const out = simulatePutt(cfg, rules.holeAt(s.hole), s.x, s.y, vel, (b) => {
              if (++n % tm.stepsPerFrame === 0) frames.push({ x: b.x, y: b.y });
            });
            frames.push({ x: out.x, y: out.y });
            cancel = playback(api, frames, (f) => (ball = f), () => {
              const before = s;
              s = rules.apply(s, a);
              if (out.end === 'water') toast(api.body, t('minigolfWater'));
              if (out.end === 'cup') toast(api.body, t('minigolfHoled'));
              const r = rules.result(s);
              if (r) {
                api.finish(r);
                return;
              }
              window.setTimeout(() => {
                shownHole = s.hole;
                ball = { x: s.x, y: s.y };
                busy = false;
              }, s.hole !== before.hole || out.end === 'water' ? 700 : 0);
            });
          }

          bindDrag(canvas, {
            canStart: () => !api.paused && !busy && !s.over,
            move(dx, dy) {
              const v = view();
              const p = dragPower(dx, dy, Math.min(canvas.clientWidth, canvas.clientHeight) * 0.45);
              const ax = s.x + Math.round(dx / v.k), ay = s.y + Math.round(-dy / v.k);
              aim = p > 0 && (ax !== s.x || ay !== s.y) ? { x: ax, y: ay, power: p } : null;
            },
            release(_dx, _dy, ok) {
              const a = aim;
              aim = null;
              if (!ok || !a || busy) return;
              putt({ by: 'player', op: 'putt', ...a });
            },
          });

          raf = requestAnimationFrame(frame);
          return {
            stop: () => {
              cancelAnimationFrame(raf);
              cancel();
            },
            timeout: () => {
              if (s.over) return;
              cancel();
              s = rules.apply(s, { by: 'timeout' });
              api.finish(rules.result(s)!);
            },
          };
        },
      }, onFinish),
  };
}
