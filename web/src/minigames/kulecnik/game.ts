import { minigameCatalog } from '../../gen/ids';
import { tokens } from '../../gen/tokens';
import type { Minigame, MinigameEnv } from '../api';
import { bindDrag, begin, disc, dragPower, fit, playback, sx, sy, toast, type View } from '../canvas';
import { h } from '../dom';
import { aiPrng } from '../rules';
import { mountShell } from '../shell';
import { pausableTimer } from '../swipe';
import {
  KulecnikRules,
  kulecnikConfig,
  pocket,
  simulateShot,
  type Ball,
  type KulecnikShot,
  type KulecnikState,
} from './rules';

const P = tokens.colorGaragePaints;
/** Ball colours by number (1–7 solids, 8 black; 9–15 reuse 1–7 with a white band). */
const BALL = [P[0]!, P[4]!, P[2]!, tokens.colorPedestriansShirts[0]!, P[6]!, P[5]!, P[3]!, P[9]!, P[1]!];
/** Cushion margin around the playing surface (u). */
const RAIL = 7000;

/** Kulečník 8-ball, specs/minigames/kulecnik.md: drag from the cue ball to aim and set power. */
export function kulecnik(env: MinigameEnv): Minigame {
  const { t, tuning } = env;
  const tm = tuning.minigames.kulecnik;
  return {
    meta: minigameCatalog.kulecnik,
    mount: (host, ctx, onFinish) =>
      mountShell(host, ctx, env, {
        id: 'kulecnik',
        rules: ['kulecnikRules1', 'kulecnikRules2', 'kulecnikRules3'],
        timeCapS: tm.timeCapS,
        start(api) {
          const cfg = kulecnikConfig(tm);
          const rules = new KulecnikRules();
          let s: KulecnikState = rules.init(cfg, ctx.seed);
          const ai = aiPrng(ctx.seed);
          const timer = pausableTimer(() => api.paused);
          let shown: Ball[] = s.balls;
          let busy = false;
          let aim: { x: number; y: number; power: number } | null = null;
          let cancel = (): void => {};
          let raf = 0;

          const canvas = h('canvas.mgc-canvas');
          const info = h('div.mgc-info');
          const fill = h('div.mgc-power-fill');
          const power = h('div.mgc-power', {}, fill);
          api.body.append(h('div.mgc', {}, info, h('div.mgc-wrap', {}, canvas), power));

          const view = (): View => fit(canvas, -RAIL, -RAIL, cfg.tableW + RAIL, cfg.tableH + RAIL, 8);

          function hud(): void {
            const g = s.playerGroup;
            const grp = g === 'solid' ? t('kulecnikSolids') : g === 'stripe' ? t('kulecnikStripes') : t('kulecnikOpen');
            api.status(grp);
            info.textContent = s.over ? '' : s.turn === 'player' ? t('yourTurn') : t('opponentTurn');
            fill.style.width = `${aim ? aim.power : 0}%`;
          }

          /** First ball the cue would touch along the aim (straight, no cushions), as a ghost-ball centre. */
          function guideEnd(dx: number, dy: number): { x: number; y: number } {
            const c = shown[0]!;
            const L = Math.hypot(dx, dy) || 1;
            const ux = dx / L, uy = dy / L;
            let best = Infinity;
            const R = 2 * cfg.ballR;
            shown.forEach((b, i) => {
              if (i === 0 || !b.on) return;
              const ox = b.x - c.x, oy = b.y - c.y;
              const along = ox * ux + oy * uy;
              const perp2 = ox * ox + oy * oy - along * along;
              if (along <= 0 || perp2 > R * R) return;
              best = Math.min(best, along - Math.sqrt(R * R - perp2));
            });
            const r = cfg.ballR;
            const wall = Math.min(
              ux > 0 ? (cfg.tableW - r - c.x) / ux : ux < 0 ? (r - c.x) / ux : Infinity,
              uy > 0 ? (cfg.tableH - r - c.y) / uy : uy < 0 ? (r - c.y) / uy : Infinity,
            );
            const d = Math.max(0, Math.min(best, wall));
            return { x: c.x + ux * d, y: c.y + uy * d };
          }

          function draw(): void {
            const g = begin(canvas);
            if (!g) return;
            const v = view();
            const k = v.k;
            g.fillStyle = tokens.colorShopsBar;
            g.beginPath();
            g.roundRect(sx(v, -RAIL), sy(v, cfg.tableH + RAIL), (cfg.tableW + 2 * RAIL) * k, (cfg.tableH + 2 * RAIL) * k, RAIL * k * 0.6);
            g.fill();
            g.fillStyle = tokens.colorCarDetailCanopy;
            g.fillRect(sx(v, 0), sy(v, cfg.tableH), cfg.tableW * k, cfg.tableH * k);
            g.strokeStyle = tokens.colorUiControlHalf;
            g.lineWidth = 1;
            g.beginPath();
            g.moveTo(sx(v, 0), sy(v, cfg.tableH / 4));
            g.lineTo(sx(v, cfg.tableW), sy(v, cfg.tableH / 4));
            g.stroke();
            for (let p = 0; p < 6; p++) {
              const pk = pocket(cfg, p);
              disc(g, sx(v, pk.x), sy(v, pk.y), pk.r * k, tokens.colorCarDetailLimoPillar);
            }
            if (aim && !busy) {
              const c = shown[0]!;
              const dx = aim.x - c.x, dy = aim.y - c.y;
              const e = guideEnd(dx, dy);
              g.setLineDash([6, 6]);
              g.strokeStyle = tokens.colorUiControlWheel;
              g.lineWidth = 2;
              g.beginPath();
              g.moveTo(sx(v, c.x), sy(v, c.y));
              g.lineTo(sx(v, e.x), sy(v, e.y));
              g.stroke();
              g.setLineDash([]);
              g.beginPath();
              g.arc(sx(v, e.x), sy(v, e.y), cfg.ballR * k, 0, Math.PI * 2);
              g.stroke();
            }
            shown.forEach((b, i) => {
              if (!b.on) return;
              const x = sx(v, b.x), y = sy(v, b.y), r = cfg.ballR * k;
              disc(g, x, y, r, BALL[i <= 8 ? i : i - 8]!, tokens.colorUiLabelShadow, 1);
              if (i >= 9) {
                g.save();
                g.beginPath();
                g.arc(x, y, r, 0, Math.PI * 2);
                g.clip();
                g.fillStyle = BALL[0]!;
                g.fillRect(x - r, y - r, 2 * r, r * 0.55);
                g.fillRect(x - r, y + r * 0.45, 2 * r, r * 0.55);
                g.restore();
              }
            });
            if (aim && !busy) {
              // The cue stick behind the ball, pulled back with the power.
              const c = shown[0]!;
              const dx = aim.x - c.x, dy = aim.y - c.y;
              const L = Math.hypot(dx, dy) || 1;
              const ux = dx / L, uy = -dy / L;
              const back = (cfg.ballR * 1.6 + aim.power * 120) * k;
              const len = cfg.tableW * 0.9 * k;
              const x0 = sx(v, c.x) - ux * back, y0 = sy(v, c.y) - uy * back;
              g.strokeStyle = tokens.colorCarDetailAwningA;
              g.lineCap = 'round';
              g.lineWidth = Math.max(3, cfg.ballR * 0.5 * k);
              g.beginPath();
              g.moveTo(x0, y0);
              g.lineTo(x0 - ux * len, y0 - uy * len);
              g.stroke();
              g.lineCap = 'butt';
            }
          }

          function frame(): void {
            raf = requestAnimationFrame(frame);
            hud();
            draw();
          }

          /** Animates a shot from the recorded steps, then applies it through the rules. */
          function play(a: KulecnikShot): void {
            busy = true;
            aim = null;
            const frames: Ball[][] = [];
            let n = 0;
            simulateShot(cfg, s.balls, a.x, a.y, a.power, (bodies) => {
              if (++n % tm.stepsPerFrame === 0) frames.push(bodies.map((b) => ({ x: b.x, y: b.y, on: b.on })));
            });
            cancel = playback(api, frames, (f) => (shown = f), () => {
              s = rules.apply(s, a);
              shown = s.balls;
              if (s.last.foul && s.last.by === 'player') toast(api.body, t('kulecnikFoul'));
              const r = rules.result(s);
              if (r) {
                api.finish(r);
                return;
              }
              if (s.turn === 'ai') timer.later(tm.aiThinkS * 1000, () => play(rules.aiAction(s, ctx.difficulty, ai) as KulecnikShot));
              else busy = false;
            });
          }

          bindDrag(canvas, {
            canStart: () => !api.paused && !busy && !s.over && s.turn === 'player',
            move(dx, dy) {
              const v = view();
              const c = s.balls[0]!;
              const p = dragPower(dx, dy, Math.min(canvas.clientWidth, canvas.clientHeight) * 0.45);
              const ax = c.x + Math.round(dx / v.k), ay = c.y + Math.round(-dy / v.k);
              aim = p > 0 && (ax !== c.x || ay !== c.y) ? { x: ax, y: ay, power: p } : null;
            },
            release(_dx, _dy, ok) {
              const a = aim;
              aim = null;
              if (!ok || !a || busy || s.turn !== 'player') return;
              play({ by: 'player', op: 'shot', x: a.x, y: a.y, power: a.power });
            },
          });

          raf = requestAnimationFrame(frame);
          return {
            stop: () => {
              cancelAnimationFrame(raf);
              cancel();
              timer.cancel();
            },
            timeout: () => {
              if (s.over) return;
              cancel();
              timer.cancel();
              s = rules.apply(s, { by: 'timeout' });
              api.finish(rules.result(s)!);
            },
          };
        },
      }, onFinish),
  };
}
