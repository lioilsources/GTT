import { minigameCatalog } from '../../gen/ids';
import { tokens } from '../../gen/tokens';
import type { Minigame, MinigameEnv } from '../api';
import { begin, capture, disc, toast } from '../canvas';
import { GameClock } from '../clock';
import { h } from '../dom';
import { mountShell } from '../shell';
import { beatTimes, DoubledutchRules, doubledutchConfig, type DoubledutchAction, type DoubledutchState } from './rules';

/** Swipe up: at least this many CSS px upwards, faster than SWIPE_MS (specs "UI"). */
export const SWIPE_PX = 40, SWIPE_MS = 300;
/** How long the jumper shows a trip (UI only). */
const TRIP_MS = 450;

/**
 * Which beat an input at `atMs` belongs to: `next` when it comes at most okMs before its time or
 * later; null (ignored) when earlier.
 */
export function inputErr(times: readonly number[], next: number, atMs: number, okMs: number): number | null {
  const tb = times[next];
  if (tb === undefined || atMs < tb - okMs) return null;
  return Math.floor(atMs - tb);
}

/** Double Dutch, specs/minigames/doubledutch.md: tap on the beat, swipe up on a trick beat. */
export function doubledutch(env: MinigameEnv): Minigame {
  const { t, tuning } = env;
  const tm = tuning.minigames.doubledutch;
  return {
    meta: minigameCatalog.doubledutch,
    mount: (host, ctx, onFinish) =>
      mountShell(host, ctx, env, {
        id: 'doubledutch',
        rules: ['doubledutchRules1', 'doubledutchRules2', 'doubledutchRules3'],
        timeCapS: tm.timeCapS,
        start(api) {
          const cfg = doubledutchConfig(tm, ctx.difficulty);
          const rules = new DoubledutchRules();
          const clock = GameClock.of(api);
          let s: DoubledutchState = rules.init(cfg, ctx.seed);
          const times = beatTimes(cfg, tm.leadInMs);
          let finished = false;
          let tripAt = -1e9;

          const canvas = h('canvas.mgc-canvas');
          const info = h('div.mgc-info');
          const wrap = h('div.mgc-wrap', {}, canvas);
          api.body.append(h('div.mgc', {}, info, wrap));

          function play(a: DoubledutchAction): void {
            if (finished) return;
            const before = s;
            s = rules.apply(s, a);
            if (a.by === 'player') {
              const tripped = s.trips > before.trips;
              if (tripped) tripAt = clock.now;
              const word = tripped ? t('ddMiss') : s.perfect > before.perfect ? t('ddPerfect') : s.good > before.good ? t('ddGood') : t('ddOk');
              toast(wrap, s.combo >= 2 && !tripped ? `${word} · ${t('ddCombo', { n: s.combo })}` : word, 600);
            }
            const r = rules.result(s);
            if (r) {
              finished = true;
              api.finish(r);
            }
          }

          function draw(): void {
            const ms = clock.now;
            api.status(t('scoreValue', { score: s.score }));
            info.textContent = t('ddTrips', { n: s.trips, max: cfg.maxTrips });
            const g = begin(canvas);
            if (!g) return;
            const W = canvas.clientWidth, H = canvas.clientHeight;
            g.fillStyle = tokens.colorStickballStreet;
            g.fillRect(0, 0, W, H);
            // Rope phase: 0 at the previous beat, 1 at the next one (one turn per gap).
            const i = Math.min(s.next, times.length - 1);
            const t1 = times[i]!, t0 = i > 0 ? times[i - 1]! : t1 - (times[1]! - times[0]!);
            const ph = Math.max(0, Math.min(1, (ms - t0) / Math.max(1, t1 - t0)));
            const x0 = W * 0.12, x1 = W * 0.88, ground = H * 0.62, top = H * 0.2;
            const rope = (phase: number, color: string): void => {
              // The rope's lowest point is on the ground at the beat; it swings over the top at half way.
              const y = ground - (ground - top) * (0.5 - 0.5 * Math.cos(2 * Math.PI * phase));
              g.strokeStyle = color;
              g.lineWidth = 5;
              g.beginPath();
              g.moveTo(x0, H * 0.42);
              g.quadraticCurveTo(W / 2, 2 * y - H * 0.42, x1, H * 0.42);
              g.stroke();
            };
            rope(ph, tokens.colorDoubledutchRopeA);
            rope(ph + 0.5, tokens.colorDoubledutchRopeB);
            disc(g, x0, H * 0.42, 10, tokens.colorStickballCurb);
            disc(g, x1, H * 0.42, 10, tokens.colorStickballCurb);
            // Jumper: in the air around the beat, red after a trip.
            const near = Math.min(Math.abs(ms - t1), Math.abs(ms - t0));
            const lift = Math.max(0, 1 - near / 180) * H * 0.06;
            const tripped = ms - tripAt < TRIP_MS;
            const jc = tripped ? tokens.colorDoubledutchMiss : tokens.colorDoubledutchJumper;
            disc(g, W / 2, ground - H * 0.12 - lift, Math.min(W, H) * 0.045, jc);
            g.strokeStyle = jc;
            g.lineWidth = 8;
            g.lineCap = 'round';
            g.beginPath();
            g.moveTo(W / 2, ground - H * 0.08 - lift);
            g.lineTo(W / 2, ground - lift);
            g.stroke();
            // Approaching beat: a ring that closes on the target at the beat time.
            const cy = H * 0.84, r0 = Math.min(W, H) * 0.08;
            disc(g, W / 2, cy, r0, 'transparent', tokens.colorDoubledutchRing, 3);
            if (!s.over) {
              const left = times[s.next]! - ms;
              const trick = s.kinds[s.next] === 1;
              const col = trick ? tokens.colorDoubledutchTrick : tokens.colorDoubledutchRing;
              const r = r0 * (1 + Math.max(0, left) / 400);
              if (left < 1200) disc(g, W / 2, cy, r, 'transparent', col, 4);
              if (trick) {
                g.fillStyle = col;
                g.beginPath();
                g.moveTo(W / 2, cy - r0 * 0.6);
                g.lineTo(W / 2 + r0 * 0.45, cy + r0 * 0.3);
                g.lineTo(W / 2 - r0 * 0.45, cy + r0 * 0.3);
                g.closePath();
                g.fill();
              }
            }
          }

          function step(now: number): void {
            const ms = clock.frame(now);
            if (finished || api.paused || s.over) return;
            // A held finger that has not swiped up within SWIPE_MS is a tap (its time is the touch).
            if (down && !down.sent) {
              if (now - down.real >= SWIPE_MS) send(0);
              else if (down.at >= times[s.next]! - cfg.okMs) return;
            }
            if (s.over) return;
            // No input until ok_ms after the beat: a miss.
            if (ms > times[s.next]! + cfg.okMs) play({ by: 'player', op: 'miss' });
          }

          let down: { id: number; x: number; y: number; at: number; real: number; sent: boolean } | null = null;
          const send = (input: number): void => {
            if (!down || down.sent) return;
            down.sent = true;
            const err = inputErr(times, s.next, down.at, cfg.okMs);
            if (err !== null) play({ by: 'player', op: 'hit', input, errMs: err });
          };
          canvas.addEventListener('pointerdown', (e) => {
            if (api.paused || finished || down) return;
            e.preventDefault();
            capture(canvas, e.pointerId);
            const now = performance.now();
            down = { id: e.pointerId, x: e.clientX, y: e.clientY, at: clock.at(now), real: now, sent: false };
          });
          canvas.addEventListener('pointermove', (e) => {
            if (!down || e.pointerId !== down.id) return;
            if (down.y - e.clientY >= SWIPE_PX && performance.now() - down.real < SWIPE_MS) send(1);
          });
          const up = (e: PointerEvent): void => {
            if (!down || e.pointerId !== down.id) return;
            if (e.type === 'pointerup') {
              const swipe = down.y - e.clientY >= SWIPE_PX && performance.now() - down.real < SWIPE_MS;
              send(swipe ? 1 : 0);
            }
            down = null;
          };
          canvas.addEventListener('pointerup', up);
          canvas.addEventListener('pointercancel', up);
          const onKey = (e: KeyboardEvent): void => {
            if (api.paused || finished || e.repeat) return;
            const input = e.code === 'Space' ? 0 : e.code === 'ArrowUp' ? 1 : -1;
            if (input < 0) return;
            e.preventDefault();
            const err = inputErr(times, s.next, clock.at(performance.now()), cfg.okMs);
            if (err !== null) play({ by: 'player', op: 'hit', input, errMs: err });
          };
          window.addEventListener('keydown', onKey);

          let raf = 0;
          const frame = (now: number): void => {
            raf = requestAnimationFrame(frame);
            step(now);
            draw();
          };
          raf = requestAnimationFrame(frame);
          return {
            stop: () => {
              cancelAnimationFrame(raf);
              window.removeEventListener('keydown', onKey);
            },
            timeout: () => play({ by: 'timeout' }),
          };
        },
      }, onFinish),
  };
}
