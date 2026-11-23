import { minigameCatalog } from '../../gen/ids';
import { tokens } from '../../gen/tokens';
import type { Minigame, MinigameEnv } from '../api';
import { begin, disc, tickLoop } from '../canvas';
import { h } from '../dom';
import { mountShell } from '../shell';
import { KrtekRules, krtekConfig, type KrtekAction, type KrtekState } from './rules';

/** How far (in ticks) a mole slides out and back in at the start and end of its time up. */
const SLIDE_TICKS = 8;

interface Cell {
  cx: number;
  cy: number;
  r: number;
}

/** Bouchni krtka (whack-a-mole), specs/minigames/krtek.md: tap moles as they pop up. */
export function krtek(env: MinigameEnv): Minigame {
  const { t, tuning } = env;
  const tm = tuning.minigames.krtek;
  return {
    meta: minigameCatalog.krtek,
    mount: (host, ctx, onFinish) =>
      mountShell(host, ctx, env, {
        id: 'krtek',
        rules: ['krtekRules1', 'krtekRules2', 'krtekRules3'],
        timeCapS: tm.timeCapS,
        start(api) {
          const cfg = krtekConfig(tm, ctx.difficulty);
          const rules = new KrtekRules();
          let s: KrtekState = rules.init(cfg, ctx.seed);
          let finished = false;
          const up = cfg.upTicks[cfg.level - 1]!;
          const whacks: Array<{ hole: number; at: number }> = [];

          const canvas = h('canvas.mgc-canvas');
          const info = h('div.mgc-info');
          api.body.append(h('div.mgc', {}, info, h('div.mgc-wrap', {}, canvas)));

          function cells(): Cell[] {
            const cols = 3, rows = Math.ceil(cfg.holes / cols);
            const w = canvas.clientWidth, hh = canvas.clientHeight;
            const size = Math.min(w / cols, hh / rows);
            const ox = (w - size * cols) / 2, oy = (hh - size * rows) / 2;
            return Array.from({ length: cfg.holes }, (_, i) => ({
              cx: ox + size * ((i % cols) + 0.5),
              cy: oy + size * (Math.floor(i / cols) + 0.5),
              r: size * 0.36,
            }));
          }

          function play(a: KrtekAction): void {
            if (finished || s.over) return;
            s = rules.apply(s, a);
            const r = rules.result(s);
            if (r) {
              finished = true;
              api.finish(r);
            }
          }

          function draw(now: number): void {
            api.status(t('scoreValue', { score: s.score }));
            info.textContent = t('krtekTime', { seconds: Math.max(0, Math.ceil((cfg.gameTicks - s.tick) / tm.tickHz)) });
            const g = begin(canvas);
            if (!g) return;
            g.fillStyle = tokens.colorWorldDayPark;
            g.fillRect(0, 0, canvas.clientWidth, canvas.clientHeight);
            cells().forEach((c, i) => {
              const hole = s.holes[i]!;
              g.fillStyle = tokens.colorCarDetailBed;
              g.beginPath();
              g.ellipse(c.cx, c.cy + c.r * 0.45, c.r, c.r * 0.42, 0, 0, Math.PI * 2);
              g.fill();
              if (hole.kind !== '') {
                const shown = Math.min(1, Math.min(up - hole.left + 1, hole.left) / SLIDE_TICKS);
                const y = c.cy + c.r * 0.45 - c.r * 0.9 * shown;
                g.save();
                g.beginPath();
                g.rect(c.cx - c.r, c.cy - c.r * 2, 2 * c.r, c.r * 2.45);
                g.clip();
                if (hole.kind === 'bomb') {
                  disc(g, c.cx, y, c.r * 0.6, tokens.colorCarDetailTaxiChecker);
                  g.strokeStyle = tokens.colorTrafficLightAmber;
                  g.lineWidth = 3;
                  g.beginPath();
                  g.moveTo(c.cx + c.r * 0.3, y - c.r * 0.5);
                  g.lineTo(c.cx + c.r * 0.5, y - c.r * 0.8);
                  g.stroke();
                } else {
                  const fur = hole.kind === 'gold' ? tokens.colorBrandAccent : tokens.colorGaragePaints[9]!;
                  disc(g, c.cx, y, c.r * 0.62, fur);
                  disc(g, c.cx - c.r * 0.22, y - c.r * 0.15, c.r * 0.08, tokens.colorCarDetailTaxiChecker);
                  disc(g, c.cx + c.r * 0.22, y - c.r * 0.15, c.r * 0.08, tokens.colorCarDetailTaxiChecker);
                  disc(g, c.cx, y + c.r * 0.08, c.r * 0.12, tokens.colorGaragePaints[7]!);
                }
                g.restore();
              }
              g.fillStyle = tokens.colorWorldDayPark;
              g.beginPath();
              g.ellipse(c.cx, c.cy + c.r * 0.6, c.r * 1.05, c.r * 0.3, 0, 0, Math.PI);
              g.fill();
            });
            for (let j = whacks.length - 1; j >= 0; j--) {
              const w = whacks[j]!;
              const age = (now - w.at) / 250;
              if (age >= 1) {
                whacks.splice(j, 1);
                continue;
              }
              const c = cells()[w.hole]!;
              g.globalAlpha = 1 - age;
              g.strokeStyle = tokens.colorWorldDayMarking;
              g.lineWidth = 4;
              g.beginPath();
              g.arc(c.cx, c.cy, c.r * (0.6 + age * 0.5), 0, Math.PI * 2);
              g.stroke();
              g.globalAlpha = 1;
            }
          }

          canvas.addEventListener('pointerdown', (e) => {
            if (api.paused || finished) return;
            e.preventDefault();
            const rect = canvas.getBoundingClientRect();
            const x = e.clientX - rect.left, y = e.clientY - rect.top;
            const i = cells().findIndex((c) => (x - c.cx) ** 2 + (y - c.cy) ** 2 <= (c.r * 1.15) ** 2);
            if (i < 0) return;
            whacks.push({ hole: i, at: performance.now() });
            play({ by: 'player', op: 'hit', hole: i });
          });

          const stop = tickLoop(api, tm.tickHz, () => !finished, (n) => play({ by: 'player', op: 'tick', n }), draw);
          return { stop, timeout: () => play({ by: 'timeout' }) };
        },
      }, onFinish),
  };
}
