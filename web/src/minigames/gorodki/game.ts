import { minigameCatalog } from '../../gen/ids';
import { tokens } from '../../gen/tokens';
import type { MessageKey } from '../../gen/i18n';
import type { Minigame, MinigameEnv } from '../api';
import { bindDrag, begin, disc, dragPower, playback, toast } from '../canvas';
import { h } from '../dom';
import { mountShell } from '../shell';
import { GorodkiRules, gorodkiConfig, simulateThrow, throwLine, type GorodkiConfig, type GorodkiState } from './rules';

/** Court view: the gorod band magnified on top, the run-up squeezed below (as in Bowling). */
interface CourtView {
  k: number;
  ox: number;
  top: number;
  seam: number;
  line: number;
  from: number;
  to: number;
  ly: number;
}

const SIDE = 100000;

function courtView(canvas: HTMLCanvasElement, c: GorodkiConfig, ly: number): CourtView {
  const w = canvas.clientWidth, hh = canvas.clientHeight;
  const from = c.gorodY0 - 120000, to = c.gorodY1 + 60000;
  const k = Math.min((w - 16) / (c.gorodW + 2 * SIDE), (hh * 0.5) / (to - from));
  const ox = (w - c.gorodW * k) / 2;
  const top = 12;
  const seam = top + (to - from) * k;
  return { k, ox, top, seam, line: hh - c.batR * k * 2.5, from, to, ly };
}

const vx = (v: CourtView, x: number): number => v.ox + x * v.k;
function vy(v: CourtView, y: number): number {
  if (y >= v.from) return v.seam - ((y - v.from) / (v.to - v.from)) * (v.seam - v.top);
  return v.line - ((y - v.ly) / (v.from - v.ly)) * (v.line - v.seam);
}

interface Shown {
  bat: { x: number; y: number; on: boolean };
  pieces: Array<{ x: number; y: number; on: boolean }>;
}

/** Gorodki, specs/minigames/gorodki.md: slide along the line, then swing the bat at the figure. */
export function gorodki(env: MinigameEnv): Minigame {
  const { t, tuning } = env;
  const tm = tuning.minigames.gorodki;
  return {
    meta: minigameCatalog.gorodki,
    mount: (host, ctx, onFinish) =>
      mountShell(host, ctx, env, {
        id: 'gorodki',
        rules: ['gorodkiRules1', 'gorodkiRules2', 'gorodkiRules3'],
        timeCapS: tm.timeCapS,
        start(api) {
          const cfg = gorodkiConfig(tm, ctx.difficulty);
          const rules = new GorodkiRules();
          let s: GorodkiState = rules.init(cfg, ctx.seed);
          let x = Math.floor(cfg.gorodW / 2);
          let busy = false;
          let mode: '' | 'slide' | 'throw' = '';
          let slideFrom = x;
          let aim: { aim: number; power: number } | null = null;
          let cancel = (): void => {};
          let raf = 0;
          let spin = 0;
          const rest = (): Shown => ({
            bat: { x, y: throwLine(cfg, s), on: true },
            pieces: s.px.map((px, k) => ({ x: px, y: s.py[k]!, on: s.up[k]! })),
          });
          let shown = rest();

          const canvas = h('canvas.mgc-canvas');
          const info = h('div.mgc-info');
          const sheet = h('div.mgc-frames');
          api.body.append(h('div.mgc', {}, sheet, info, h('div.mgc-wrap', {}, canvas)));

          function hud(): void {
            api.status(t('gorodkiBats', { n: s.bats }));
            const text = s.over ? '' : t('gorodkiFig', { n: s.fig, total: 5, name: t(`gorodkiFig_${s.fig}` as MessageKey) });
            if (sheet.textContent !== text) sheet.textContent = text;
            const note = s.polukon && !s.over ? t('gorodkiPolukon') : '';
            if (info.textContent !== note) info.textContent = note;
          }

          function draw(): void {
            const g = begin(canvas);
            if (!g) return;
            const v = courtView(canvas, cfg, throwLine(cfg, s));
            const k = v.k;
            g.fillStyle = tokens.colorWorldDayPark;
            g.fillRect(vx(v, -SIDE), v.top, (cfg.gorodW + 2 * SIDE) * k, canvas.clientHeight - v.top);
            g.fillStyle = tokens.colorWorldDayFacades[5]!;
            g.fillRect(vx(v, 0), vy(v, cfg.gorodY1), cfg.gorodW * k, vy(v, cfg.gorodY0) - vy(v, cfg.gorodY1));
            g.strokeStyle = tokens.colorWorldDayMarking;
            g.lineWidth = 2;
            g.strokeRect(vx(v, 0), vy(v, cfg.gorodY1), cfg.gorodW * k, vy(v, cfg.gorodY0) - vy(v, cfg.gorodY1));
            g.beginPath();
            g.moveTo(vx(v, -SIDE), v.line);
            g.lineTo(vx(v, cfg.gorodW + SIDE), v.line);
            g.stroke();
            if (aim && !busy) {
              g.setLineDash([6, 6]);
              g.strokeStyle = tokens.colorUiControlWheel;
              g.beginPath();
              g.moveTo(vx(v, x), vy(v, v.ly));
              g.lineTo(vx(v, aim.aim), vy(v, cfg.gorodY0));
              g.stroke();
              g.setLineDash([]);
            }
            shown.pieces.forEach((p) => {
              if (!p.on) return;
              disc(g, vx(v, p.x), vy(v, p.y), Math.max(3, cfg.pieceR * k * 1.1), tokens.colorWorldDayFacades[0]!, tokens.colorUiLabelShadow, 1);
            });
            const b = shown.bat;
            if (b.on) {
              // The bat: a stick spinning about its middle, its sweep is the physics disc.
              const r = Math.max(8, cfg.batR * k * (b.y >= v.from ? 1 : 0.7));
              const cx = vx(v, b.x), cy = vy(v, b.y);
              g.strokeStyle = tokens.colorBoothBody;
              g.lineWidth = Math.max(3, r * 0.22);
              g.lineCap = 'round';
              g.beginPath();
              g.moveTo(cx - Math.cos(spin) * r, cy - Math.sin(spin) * r);
              g.lineTo(cx + Math.cos(spin) * r, cy + Math.sin(spin) * r);
              g.stroke();
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
            if (busy) spin += 0.45;
            hud();
            draw();
          }

          function hurl(a: { by: 'player'; op: 'throw'; x: number; aim: number; power: number }): void {
            if (!rules.legal(s, a)) return;
            busy = true;
            aim = null;
            const vel = rules.velocity(s, a);
            const frames: Shown[] = [];
            let n = 0;
            simulateThrow(cfg, s, a.x, vel, (bodies) => {
              if (++n % tm.stepsPerFrame !== 0) return;
              const [bat, ...pieces] = bodies.map((q) => ({ x: q.x, y: q.y, on: q.on }));
              frames.push({ bat: bat!, pieces });
            });
            cancel = playback(api, frames, (f) => (shown = f), () => {
              const before = s;
              s = rules.apply(s, a);
              if (s.cleared > before.cleared) toast(api.body, t('gorodkiClear'));
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
              const v = courtView(canvas, cfg, throwLine(cfg, s));
              if (mode === '') {
                if (Math.hypot(dx, dy) < 12) return;
                mode = Math.abs(dx) > Math.abs(dy) ? 'slide' : 'throw';
                slideFrom = x;
              }
              if (mode === 'slide') {
                x = Math.max(0, Math.min(cfg.gorodW, Math.round(slideFrom + dx / v.k)));
                shown = rest();
                aim = null;
              } else {
                const p = dy < -12 ? dragPower(0, dy, canvas.clientHeight * 0.55) : 0;
                aim = p > 0 ? { aim: Math.round(x + (dx / v.k) * 2), power: p } : null;
              }
            },
            release(_dx, _dy, ok) {
              const a = aim;
              const m = mode;
              mode = '';
              aim = null;
              if (!ok || m !== 'throw' || !a || busy) return;
              hurl({ by: 'player', op: 'throw', x, aim: a.aim, power: a.power });
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
