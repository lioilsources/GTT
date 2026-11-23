import { minigameCatalog } from '../../gen/ids';
import { tokens } from '../../gen/tokens';
import type { Minigame, MinigameEnv } from '../api';
import { bindDrag, begin, disc, dragPower, playback, toast } from '../canvas';
import { h } from '../dom';
import { mountShell } from '../shell';
import { BowlingRules, bowlingConfig, pinSpot, simulateRoll, type BowlingConfig, type BowlingState } from './rules';

/** Lane view: x at one scale; y split into a magnified pin deck (top) and a squeezed approach (bottom). */
interface LaneView {
  k: number;
  ox: number;
  /** Screen y of the deck band top, the deck/approach seam and the foul line. */
  top: number;
  seam: number;
  foul: number;
  deckFrom: number;
  deckTo: number;
}

const GUTTER = 14000;

function laneView(canvas: HTMLCanvasElement, c: BowlingConfig): LaneView {
  const w = canvas.clientWidth, hh = canvas.clientHeight;
  const k = Math.min((w - 16) / (c.laneW + 2 * GUTTER), (hh * 0.4) / (c.deckY1 - c.deckY0));
  const ox = (w - c.laneW * k) / 2;
  const top = 12;
  const deckFrom = c.deckY0 - 30000, deckTo = c.deckY1;
  const seam = top + (deckTo - deckFrom) * k * 0.75;
  return { k, ox, top, seam, foul: hh - c.ballR * k * 3, deckFrom, deckTo };
}

const vx = (v: LaneView, x: number): number => v.ox + x * v.k;
function vy(v: LaneView, y: number): number {
  if (y >= v.deckFrom) return v.seam - ((y - v.deckFrom) / (v.deckTo - v.deckFrom)) * (v.seam - v.top);
  return v.foul - (y / v.deckFrom) * (v.foul - v.seam);
}

interface Shown {
  ball: { x: number; y: number; on: boolean };
  pins: Array<{ x: number; y: number; on: boolean }>;
}

/** Bowling, specs/minigames/bowling.md: slide the ball along the line, then swipe towards the pins. */
export function bowling(env: MinigameEnv): Minigame {
  const { t, tuning } = env;
  const tm = tuning.minigames.bowling;
  return {
    meta: minigameCatalog.bowling,
    mount: (host, ctx, onFinish) =>
      mountShell(host, ctx, env, {
        id: 'bowling',
        rules: ['bowlingRules1', 'bowlingRules2', 'bowlingRules3'],
        timeCapS: tm.timeCapS,
        start(api) {
          const cfg = bowlingConfig(tm, ctx.difficulty);
          const rules = new BowlingRules();
          let s: BowlingState = rules.init(cfg, ctx.seed);
          let x = Math.floor(cfg.laneW / 2);
          let busy = false;
          let mode: '' | 'slide' | 'throw' = '';
          let slideFrom = x;
          let aim: { aim: number; power: number } | null = null;
          let cancel = (): void => {};
          let raf = 0;
          const rest = (): Shown => ({
            ball: { x, y: 0, on: true },
            pins: s.standing.map((on, i) => ({ ...pinSpot(cfg, i), on })),
          });
          let shown = rest();

          const canvas = h('canvas.mgc-canvas');
          const info = h('div.mgc-info');
          const sheet = h('div.mgc-frames');
          api.body.append(h('div.mgc', {}, sheet, info, h('div.mgc-wrap', {}, canvas)));

          function hud(): void {
            api.status(t('scoreValue', { score: s.score }));
            info.textContent = s.over ? '' : t('bowlingFrame', { frame: s.frame });
            const cells: string[] = [];
            let i = 0;
            for (let f = 1; f <= 10 && i < s.rolls.length; f++) {
              const a = s.rolls[i]!, b = s.rolls[i + 1];
              if (f < 10) {
                cells.push(a === 10 ? 'X' : b === undefined ? `${a}` : a + b === 10 ? `${a} /` : `${a} ${b}`);
                i += a === 10 ? 1 : 2;
              } else {
                cells.push(s.rolls.slice(i).map((r) => (r === 10 ? 'X' : `${r}`)).join(' '));
                i = s.rolls.length;
              }
            }
            const text = cells.join(' · ');
            if (sheet.textContent !== text) sheet.textContent = text;
          }

          function draw(): void {
            const g = begin(canvas);
            if (!g) return;
            const v = laneView(canvas, cfg);
            const k = v.k;
            g.fillStyle = tokens.colorWorldDayAsphalt;
            g.fillRect(vx(v, -GUTTER), v.top, (cfg.laneW + 2 * GUTTER) * k, v.foul - v.top + cfg.ballR * k * 2);
            g.fillStyle = tokens.colorWorldDayFacades[5]!;
            g.fillRect(vx(v, 0), v.top, cfg.laneW * k, v.foul - v.top + cfg.ballR * k * 2);
            g.fillStyle = tokens.colorWorldDayFacades[0]!;
            g.fillRect(vx(v, 0), v.top, cfg.laneW * k, vy(v, cfg.deckY0) - v.top);
            g.strokeStyle = tokens.colorUiControlHalf;
            g.lineWidth = 1;
            g.beginPath();
            g.moveTo(vx(v, 0), v.foul);
            g.lineTo(vx(v, cfg.laneW), v.foul);
            g.stroke();
            // Arrows on the approach as aiming marks.
            g.fillStyle = tokens.colorShopsBar;
            for (let j = 1; j < 7; j++) {
              const ax = vx(v, (cfg.laneW * j) / 7), ay = (v.seam + v.foul) / 2 + Math.abs(j - 3.5) * 6;
              g.beginPath();
              g.moveTo(ax, ay - 8);
              g.lineTo(ax - 4, ay + 4);
              g.lineTo(ax + 4, ay + 4);
              g.fill();
            }
            if (aim && !busy) {
              g.setLineDash([6, 6]);
              g.strokeStyle = tokens.colorUiControlWheel;
              g.lineWidth = 2;
              g.beginPath();
              g.moveTo(vx(v, x), vy(v, 0));
              g.lineTo(vx(v, aim.aim), vy(v, cfg.headY));
              g.stroke();
              g.setLineDash([]);
            }
            shown.pins.forEach((p) => {
              if (!p.on) return;
              disc(g, vx(v, p.x), vy(v, p.y), cfg.pinR * k * 1.15, tokens.colorWorldDayMarking, tokens.colorUiLabelShadow, 1);
              disc(g, vx(v, p.x), vy(v, p.y), cfg.pinR * k * 0.4, tokens.colorBoothBody);
            });
            const b = shown.ball;
            if (b.on) {
              const r = Math.max(5, cfg.ballR * k * (b.y >= v.deckFrom ? 1 : 0.9));
              disc(g, vx(v, b.x), vy(v, b.y), r, tokens.colorPoliceBody, tokens.colorUiLabelShadow, 1);
            }
            if (aim && !busy) {
              const bw = Math.min(canvas.clientWidth * 0.5, 180);
              g.fillStyle = tokens.colorUiControlHalf;
              g.fillRect((canvas.clientWidth - bw) / 2, canvas.clientHeight - 6, bw, 6);
              g.fillStyle = tokens.colorBrandAccent;
              g.fillRect((canvas.clientWidth - bw) / 2, canvas.clientHeight - 6, (bw * aim.power) / 100, 6);
            }
          }

          function frame(): void {
            raf = requestAnimationFrame(frame);
            hud();
            draw();
          }

          function roll(a: { by: 'player'; op: 'roll'; x: number; aim: number; power: number }): void {
            if (!rules.legal(s, a)) return;
            busy = true;
            aim = null;
            const vel = rules.velocity(s, a);
            const frames: Shown[] = [];
            let n = 0;
            simulateRoll(cfg, s.standing, a.x, vel, (bodies) => {
              if (++n % tm.stepsPerFrame !== 0) return;
              const [ball, ...pins] = bodies.map((q) => ({ x: q.x, y: q.y, on: q.on }));
              frames.push({ ball: ball!, pins });
            });
            cancel = playback(api, frames, (f) => (shown = f), () => {
              const before = s;
              s = rules.apply(s, a);
              const k = s.lastKnocked;
              const pinsUp = before.standing.filter(Boolean).length;
              if (k === 10 && pinsUp === 10) toast(api.body, t('bowlingStrike'));
              else if (k > 0 && k === pinsUp) toast(api.body, t('bowlingSpare'));
              const r = rules.result(s);
              if (r) {
                api.finish(r);
                return;
              }
              window.setTimeout(() => {
                busy = false;
                shown = rest();
              }, 500);
            });
          }

          bindDrag(canvas, {
            canStart: () => !api.paused && !busy && !s.over,
            move(dx, dy) {
              const v = laneView(canvas, cfg);
              if (mode === '') {
                if (Math.hypot(dx, dy) < 12) return;
                mode = Math.abs(dx) > Math.abs(dy) ? 'slide' : 'throw';
                slideFrom = x;
              }
              if (mode === 'slide') {
                x = Math.max(cfg.ballR, Math.min(cfg.laneW - cfg.ballR, Math.round(slideFrom + dx / v.k)));
                shown = rest();
                aim = null;
              } else {
                const p = dy < -12 ? dragPower(0, dy, canvas.clientHeight * 0.55) : 0;
                aim = p > 0 ? { aim: Math.round(x + dx / v.k), power: p } : null;
              }
            },
            release(_dx, _dy, ok) {
              const a = aim;
              const m = mode;
              mode = '';
              aim = null;
              if (!ok || m !== 'throw' || !a || busy) return;
              roll({ by: 'player', op: 'roll', x, aim: a.aim, power: a.power });
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
