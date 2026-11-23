import { minigameCatalog } from '../../gen/ids';
import type { MessageKey } from '../../gen/i18n';
import { tokens } from '../../gen/tokens';
import type { Minigame, MinigameEnv } from '../api';
import { begin, disc, toast } from '../canvas';
import { GameClock } from '../clock';
import { h } from '../dom';
import { aiPrng } from '../rules';
import { mountShell } from '../shell';
import { StickballRules, stickballConfig, type StickballAction, type StickballState } from './rules';

/** Pause between the end of one pitch and the next wind-up (UI only). */
const NEXT_MS = 1100;
/** Bands occupy this fraction of the canvas height above the batter (high, mid, low from the top). */
const BANDS_TOP = 0.52, BANDS_H = 0.33;

/** Lane of a tap at canvas y: 2 high (top band), 1 mid, 0 low; outside the bands the nearest one. */
export function laneAt(y: number, height: number): number {
  const top = height * BANDS_TOP, band = (height * BANDS_H) / 3;
  const i = Math.floor((y - top) / band);
  return 2 - Math.max(0, Math.min(2, i));
}

/** Stickball, specs/minigames/stickball.md: tap the band the pitch comes into, on time. */
export function stickball(env: MinigameEnv): Minigame {
  const { t, tuning } = env;
  const tm = tuning.minigames.stickball;
  return {
    meta: minigameCatalog.stickball,
    mount: (host, ctx, onFinish) =>
      mountShell(host, ctx, env, {
        id: 'stickball',
        rules: ['stickballRules1', 'stickballRules2', 'stickballRules3'],
        timeCapS: tm.timeCapS,
        start(api) {
          const cfg = stickballConfig(tm, ctx.difficulty);
          const rules = new StickballRules();
          const ai = aiPrng(ctx.seed);
          const clock = GameClock.of(api);
          let s: StickballState = rules.init(cfg, ctx.seed);
          let finished = false;
          let nextAt = NEXT_MS;
          let pitchAt = 0;
          let pitches = 0;
          /** Swing animation: lane and when (game ms). */
          let swing: { lane: number; at: number } | null = null;

          const canvas = h('canvas.mgc-canvas');
          const info = h('div.mgc-info');
          const wrap = h('div.mgc-wrap', {}, canvas);
          api.body.append(h('div.mgc', {}, info, wrap));

          function play(a: StickballAction): void {
            if (finished) return;
            s = rules.apply(s, a);
            if (a.by === 'player') {
              if (s.last) toast(wrap, t(`stickballLast_${s.last}` as MessageKey), 900);
              nextAt = clock.now + NEXT_MS;
            }
            const r = rules.result(s);
            if (r) {
              finished = true;
              api.finish(r);
            }
          }

          const arrival = (): number => pitchAt + s.pitch.flightMs;

          function step(now: number): void {
            const ms = clock.frame(now);
            if (finished || api.paused) return;
            if (s.phase === 'pitch' && ms >= nextAt) {
              play(rules.aiAction(s, cfg.level, ai));
              pitchAt = ms;
              pitches++;
              swing = null;
            } else if (s.phase === 'bat' && ms > arrival() + cfg.foulMs) {
              play({ by: 'player', op: 'take' });
            }
          }

          function draw(): void {
            api.status(t('stickballRuns', { n: s.runs }));
            info.textContent = t('stickballCount', { balls: s.balls, strikes: s.strikes, outs: s.outs });
            const g = begin(canvas);
            if (!g) return;
            const W = canvas.clientWidth, H = canvas.clientHeight;
            // Street in perspective: narrow at the pitcher, wide at the batter.
            g.fillStyle = tokens.colorStickballCurb;
            g.fillRect(0, 0, W, H);
            g.fillStyle = tokens.colorStickballStreet;
            g.beginPath();
            g.moveTo(W * 0.38, 0);
            g.lineTo(W * 0.62, 0);
            g.lineTo(W * 1.05, H);
            g.lineTo(-W * 0.05, H);
            g.closePath();
            g.fill();
            // Bands at the batter.
            const band = (H * BANDS_H) / 3;
            [tokens.colorStickballZoneHigh, tokens.colorStickballZoneMid, tokens.colorStickballZoneLow].forEach((c, i) => {
              g.fillStyle = c;
              g.fillRect(W * 0.08, H * BANDS_TOP + i * band, W * 0.84, band - 2);
            });
            // Bases as manhole covers: first right, second up, third left of home.
            const bx = W * 0.5, by = H * 0.93, d = Math.min(W, H) * 0.06;
            disc(g, bx, by, d * 0.45, tokens.colorStickballManhole);
            [[bx + d * 1.6, by - d * 0.7], [bx, by - d * 1.4], [bx - d * 1.6, by - d * 0.7]].forEach(([x, y], i) => {
              disc(g, x!, y!, d * 0.5, (s.bases >> i) & 1 ? tokens.colorStickballRunner : tokens.colorStickballManhole);
            });
            // Pitcher.
            const px = W * 0.5, py = H * 0.12;
            disc(g, px, py, Math.min(W, H) * 0.035, tokens.colorStickballRunner);
            // Batter and stick.
            const ms = clock.now;
            const lane = swing && ms - swing.at < 250 ? swing.lane : 1;
            const ly = H * BANDS_TOP + (2 - lane + 0.5) * band;
            disc(g, W * 0.3, H * 0.86, Math.min(W, H) * 0.045, tokens.colorStickballRunner);
            g.strokeStyle = tokens.colorStickballCurb;
            g.lineWidth = 6;
            g.lineCap = 'round';
            g.beginPath();
            g.moveTo(W * 0.3, H * 0.84);
            const k = swing && ms - swing.at < 250 ? 1 : 0;
            g.lineTo(W * (0.3 + 0.32 * k + 0.05), ly - (1 - k) * band);
            g.stroke();
            // Ball in flight.
            if (s.phase === 'bat') {
              const f = Math.min(1.25, Math.max(0, (ms - pitchAt) / s.pitch.flightMs));
              const tx = s.pitch.zone ? W * 0.5 : W * (pitches % 2 ? 0.92 : 0.08);
              const ty = H * BANDS_TOP + (2 - s.pitch.lane + 0.5) * band;
              const x = px + (tx - px) * f, y = py + (ty - py) * f;
              disc(g, x, y, Math.min(W, H) * (0.012 + 0.02 * Math.min(1, f)), tokens.colorStickballBall);
            }
          }

          canvas.addEventListener('pointerdown', (e) => {
            if (api.paused || finished || s.phase !== 'bat') return;
            e.preventDefault();
            const at = clock.at(performance.now());
            if (at < arrival() - 2 * cfg.foulMs) return;
            const r = canvas.getBoundingClientRect();
            const lane = laneAt(e.clientY - r.top, canvas.clientHeight);
            swing = { lane, at };
            play({ by: 'player', op: 'swing', lane, errMs: Math.floor(at - arrival()) });
          });

          let raf = 0;
          const frame = (now: number): void => {
            raf = requestAnimationFrame(frame);
            step(now);
            draw();
          };
          raf = requestAnimationFrame(frame);
          return { stop: () => cancelAnimationFrame(raf), timeout: () => play({ by: 'timeout' }) };
        },
      }, onFinish),
  };
}
