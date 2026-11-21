import { minigameCatalog } from '../../gen/ids';
import { tokens } from '../../gen/tokens';
import type { Minigame, MinigameEnv } from '../api';
import { h } from '../dom';
import { mountShell } from '../shell';
import {
  StrelniceRules,
  kindPoints,
  kindRadius,
  onField,
  strelniceConfig,
  targetPos,
  type StrelniceAction,
  type StrelniceState,
} from './rules';

/** How long a hit pop (+points) floats over the target. */
const POP_MS = 600;
/** Longest real-time step fed to the simulation per frame (tab switches, hiccups). */
const MAX_FRAME_MS = 250;

const KIND_COLORS = [tokens.colorWorldRoadblockA, tokens.colorBrandAccent, tokens.colorWorldDayFacades[2]!];

interface Pop {
  x: number;
  y: number;
  points: number;
  at: number;
}

/** Strelnice (shooting gallery), specs/minigames/strelnice.md: tap moving targets, three timed rounds. */
export function strelnice(env: MinigameEnv): Minigame {
  const { t, tuning } = env;
  const tm = tuning.minigames.strelnice;
  return {
    meta: minigameCatalog.strelnice,
    mount: (host, ctx, onFinish) =>
      mountShell(host, ctx, env, {
        id: 'strelnice',
        rules: ['strelniceRules1', 'strelniceRules2', 'strelniceRules3'],
        timeCapS: tm.timeCapS,
        start(api) {
          const rules = new StrelniceRules();
          const cfg = strelniceConfig(tm);
          let s: StrelniceState = rules.init(cfg, ctx.seed);
          // The lanes sit inside a square field (width × width field units).
          const fieldH = cfg.width;
          let raf = 0;
          let last = -1;
          let acc = 0;
          let finished = false;
          const pops: Pop[] = [];

          const info = h('div.strelnice-info');
          const canvas = h('canvas.strelnice-field');
          const wrap = h('div.strelnice-wrap', {}, canvas);
          const pips = h('div.strelnice-pips');
          const note = h('div.strelnice-note');
          api.body.append(h('div.strelnice', {}, info, wrap, h('div.strelnice-ammo', {}, pips, note)));

          /** Field square placement inside the canvas (CSS pixels): top-aligned, centred horizontally. */
          function layout(): { ox: number; oy: number; k: number } {
            const w = canvas.clientWidth, hh = canvas.clientHeight;
            const k = Math.min(w / cfg.width, hh / fieldH);
            return { ox: (w - cfg.width * k) / 2, oy: 0, k };
          }

          function play(a: StrelniceAction): void {
            if (finished || s.over) return;
            const before = s;
            s = rules.apply(s, a);
            if (s.hits > before.hits && s.round === before.round) {
              const i = s.targets.findIndex((u, j) => u.hit && !before.targets[j]!.hit);
              const tg = before.targets[i]!;
              const p = targetPos(tg, before.tick, cfg);
              pops.push({ x: p.x, y: p.y, points: kindPoints(cfg, tg.kind), at: performance.now() });
            }
            const r = rules.result(s);
            if (r) {
              finished = true;
              hud();
              api.finish(r);
            }
          }

          function hud(): void {
            const left = Math.max(0, Math.ceil((cfg.roundTicks - s.tick) / tm.tickHz));
            info.textContent = t('strelniceRound', { round: s.round, seconds: left });
            api.status(t('scoreValue', { score: s.score }));
            if (pips.childElementCount !== cfg.magazine) {
              pips.replaceChildren(...Array.from({ length: cfg.magazine }, () => h('span')));
            }
            Array.from(pips.children).forEach((p, i) => (p.className = i < s.ammo && s.reload === 0 ? 'on' : ''));
            note.textContent = s.reload > 0 ? t('strelniceReload') : '';
          }

          function draw(now: number): void {
            const dpr = window.devicePixelRatio || 1;
            const cw = Math.round(canvas.clientWidth * dpr), ch = Math.round(canvas.clientHeight * dpr);
            if (canvas.width !== cw || canvas.height !== ch) {
              canvas.width = cw;
              canvas.height = ch;
            }
            const g = canvas.getContext('2d');
            if (!g) return;
            g.setTransform(dpr, 0, 0, dpr, 0, 0);
            g.clearRect(0, 0, canvas.clientWidth, canvas.clientHeight);
            const { ox, oy, k } = layout();
            g.save();
            g.translate(ox, oy);
            g.scale(k, k);
            g.beginPath();
            g.rect(0, 0, cfg.width, fieldH);
            g.clip();
            g.fillStyle = tokens.colorWorldNightPlaza;
            g.fillRect(0, 0, cfg.width, fieldH);
            const maxR = Math.max(...[0, 1, 2].map((i) => kindRadius(cfg, i)));
            g.fillStyle = tokens.colorWorldDayRail;
            for (const y of cfg.lanes) g.fillRect(0, y + maxR + 4, cfg.width, 6);
            for (const tg of s.targets) {
              if (!onField(tg, s.tick, cfg)) continue;
              const p = targetPos(tg, s.tick, cfg);
              const r = kindRadius(cfg, tg.kind);
              const col = KIND_COLORS[tg.kind]!;
              g.strokeStyle = tokens.colorWorldDayRail;
              g.lineWidth = 4;
              g.beginPath();
              g.moveTo(p.x, p.y + r);
              g.lineTo(p.x, cfg.lanes[tg.lane]! + maxR + 4);
              g.stroke();
              disc(g, p.x, p.y, r, col);
              disc(g, p.x, p.y, r * 0.66, tokens.colorWorldRoadblockB);
              disc(g, p.x, p.y, r * 0.33, col);
            }
            g.textAlign = 'center';
            g.textBaseline = 'middle';
            g.font = '700 48px system-ui, sans-serif';
            for (let i = pops.length - 1; i >= 0; i--) {
              const p = pops[i]!;
              const age = (now - p.at) / POP_MS;
              if (age >= 1) {
                pops.splice(i, 1);
                continue;
              }
              g.globalAlpha = 1 - age;
              g.fillStyle = tokens.colorBrandAccent;
              g.fillText(`+${p.points}`, p.x, p.y - 40 * age);
            }
            g.globalAlpha = 1;
            g.restore();
          }

          function frame(now: number): void {
            raf = requestAnimationFrame(frame);
            if (api.paused || finished) {
              last = -1;
            } else {
              if (last >= 0) acc += Math.min(now - last, MAX_FRAME_MS);
              last = now;
              const n = Math.floor((acc * tm.tickHz) / 1000);
              if (n > 0) {
                acc -= (n * 1000) / tm.tickHz;
                play({ by: 'player', op: 'tick', n });
              }
            }
            hud();
            draw(now);
          }

          canvas.addEventListener('pointerdown', (e) => {
            if (api.paused || finished) return;
            e.preventDefault();
            const rect = canvas.getBoundingClientRect();
            const { ox, oy, k } = layout();
            const x = Math.round((e.clientX - rect.left - ox) / k);
            const y = Math.round((e.clientY - rect.top - oy) / k);
            if (x < 0 || x > cfg.width || y < 0 || y > fieldH) return;
            play({ by: 'player', op: 'shoot', x, y });
          });

          hud();
          raf = requestAnimationFrame(frame);
          return {
            stop: () => cancelAnimationFrame(raf),
            timeout: () => {
              if (finished || s.over) return;
              play({ by: 'timeout' });
            },
          };
        },
      }, onFinish),
  };
}

function disc(g: CanvasRenderingContext2D, x: number, y: number, r: number, color: string): void {
  g.fillStyle = color;
  g.beginPath();
  g.arc(x, y, r, 0, Math.PI * 2);
  g.fill();
}
