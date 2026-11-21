import { minigameCatalog } from '../../gen/ids';
import type { Minigame, MinigameEnv } from '../api';
import { h, svg } from '../dom';
import { aiPrng } from '../rules';
import { mountShell } from '../shell';
import { RING, SECTORS, SipkyRules, sipkyConfig, type SipkyAction, type SipkyState } from './rules';

/** Board drawing extent (0.1 mm): the double ring plus room for the numbers. */
const VIEW = 2000;
const LABEL_R = 1850;

/** SVG annular sector between radii r0..r1 and angles a0..a1 (radians clockwise from +y; SVG y down). */
function wedge(r0: number, r1: number, a0: number, a1: number): string {
  const p = (r: number, a: number): string => `${(r * Math.sin(a)).toFixed(1)} ${(-r * Math.cos(a)).toFixed(1)}`;
  return `M ${p(r0, a0)} L ${p(r1, a0)} A ${r1} ${r1} 0 0 1 ${p(r1, a1)} L ${p(r0, a1)} A ${r0} ${r0} 0 0 0 ${p(r0, a0)} Z`;
}

/** The dartboard; trigonometry is UI only, the rules use the integer tables. */
function board(): SVGGElement {
  const g = svg('g', { class: 'sipky-board' });
  g.append(svg('circle', { cx: 0, cy: 0, r: VIEW - 20, class: 'surround' }));
  const deg = Math.PI / 180;
  const rings: Array<[number, number, string]> = [
    [RING.outerBull, RING.tripleIn, 'single'],
    [RING.tripleIn, RING.tripleOut, 'ring'],
    [RING.tripleOut, RING.doubleIn, 'single'],
    [RING.doubleIn, RING.doubleOut, 'ring'],
  ];
  for (let k = 0; k < 20; k++) {
    const a0 = (18 * k - 9) * deg, a1 = (18 * k + 9) * deg;
    for (const [r0, r1, kind] of rings) {
      g.append(svg('path', { d: wedge(r0, r1, a0, a1), class: `${kind} ${k % 2 === 0 ? 'a' : 'b'}` }));
    }
    const label = svg('text', {
      x: (LABEL_R * Math.sin(18 * k * deg)).toFixed(1),
      y: (-LABEL_R * Math.cos(18 * k * deg)).toFixed(1),
      class: 'num',
    });
    label.textContent = String(SECTORS[k]);
    g.append(label);
  }
  g.append(svg('circle', { cx: 0, cy: 0, r: RING.outerBull, class: 'outer-bull' }));
  g.append(svg('circle', { cx: 0, cy: 0, r: RING.bull, class: 'bull' }));
  return g;
}

/** Sipky 301, specs/minigames/sipky.md: drag to aim (the sight sways), release to throw. */
export function sipky(env: MinigameEnv): Minigame {
  const { t, tuning } = env;
  const tm = tuning.minigames.sipky;
  return {
    meta: minigameCatalog.sipky,
    mount: (host, ctx, onFinish) =>
      mountShell(host, ctx, env, {
        id: 'sipky',
        rules: ['sipkyRules1', 'sipkyRules2', 'sipkyRules3'],
        timeCapS: tm.timeCapS,
        start(api) {
          const rules = new SipkyRules();
          const ai = aiPrng(ctx.seed);
          let s: SipkyState = rules.init(sipkyConfig(tm), ctx.seed);
          let thrown = false;
          let aiTimer = 0;
          let toast = 0;
          let raf = 0;
          let aiming: { x: number; y: number; t0: number } | null = null;
          let sight = { x: 0, y: 0 };

          const pad = svg('svg', {
            class: 'sipky-pad',
            viewBox: `${-VIEW} ${-VIEW} ${2 * VIEW} ${2 * VIEW}`,
            preserveAspectRatio: 'xMidYMid meet',
          });
          const dot = svg('circle', { r: 28, class: 'sipky-dot', visibility: 'hidden' });
          const cross = svg('g', { class: 'sipky-sight', visibility: 'hidden' });
          cross.append(
            svg('circle', { cx: 0, cy: 0, r: 90 }),
            svg('line', { x1: -150, y1: 0, x2: 150, y2: 0 }),
            svg('line', { x1: 0, y1: -150, x2: 0, y2: 150 }),
          );
          pad.append(board(), dot, cross);
          const info = h('div.sipky-info');
          const note = h('div.sipky-note');
          api.body.append(h('div.sipky', {}, info, pad, note));

          function draw(): void {
            info.textContent = t('sipkyRemaining', { player: s.player, ai: s.ai });
            api.status(s.over ? '' : s.turn === 'player' ? t('yourTurn') : t('opponentTurn'));
            if (!note.classList.contains('flash')) note.textContent = t('sipkyDart', { n: s.dart + 1 });
            if (thrown) {
              dot.setAttribute('cx', String(s.lastHit.x));
              dot.setAttribute('cy', String(-s.lastHit.y));
              dot.setAttribute('visibility', 'visible');
            }
          }

          function flash(text: string, bust: boolean): void {
            window.clearTimeout(toast);
            note.textContent = text;
            note.classList.add('flash');
            note.classList.toggle('bust', bust);
            toast = window.setTimeout(() => {
              note.classList.remove('flash', 'bust');
              draw();
            }, 900);
          }

          function play(a: SipkyAction): void {
            if (api.paused || s.over) return;
            const before = s;
            s = rules.apply(s, a);
            thrown = true;
            const side = before.turn;
            const bust = before[side] - s.lastHit.points < 0;
            flash(bust ? t('sipkyBust') : t('sipkyHit', { points: s.lastHit.points }), bust);
            draw();
            const r = rules.result(s);
            if (r) {
              window.setTimeout(() => api.finish(r), 900);
              return;
            }
            scheduleAi();
          }

          function scheduleAi(): void {
            if (s.turn !== 'ai' || s.over) return;
            window.clearTimeout(aiTimer);
            aiTimer = window.setTimeout(function tick() {
              if (api.paused) {
                aiTimer = window.setTimeout(tick, 200);
                return;
              }
              play(rules.aiAction(s, ctx.difficulty, ai));
            }, tm.aiThinkS * 1000);
          }

          /** Client point to board units (0.1 mm, y up). */
          function toBoard(e: PointerEvent): { x: number; y: number } {
            const m = pad.getScreenCTM();
            if (!m) return { x: 0, y: 0 };
            const p = new DOMPoint(e.clientX, e.clientY).matrixTransform(m.inverse());
            return { x: p.x, y: -p.y };
          }

          /** Lissajous-like sway around the finger (UI only, not part of the rules). */
          function frame(now: number): void {
            if (!aiming) return;
            const w = (now - aiming.t0) / 1000 * 2 * Math.PI * tm.wobbleHz;
            const amp = tm.playerWobble;
            sight = { x: aiming.x + amp * Math.sin(w), y: aiming.y + amp * Math.sin(1.7 * w + 0.6) };
            cross.setAttribute('transform', `translate(${sight.x.toFixed(1)} ${(-sight.y).toFixed(1)})`);
            raf = requestAnimationFrame(frame);
          }

          const canAim = (): boolean => !api.paused && !s.over && s.turn === 'player';

          pad.addEventListener('pointerdown', (e) => {
            if (!canAim()) return;
            pad.setPointerCapture?.(e.pointerId);
            aiming = { ...toBoard(e), t0: performance.now() };
            sight = { x: aiming.x, y: aiming.y };
            cross.setAttribute('visibility', 'visible');
            cancelAnimationFrame(raf);
            raf = requestAnimationFrame(frame);
            e.preventDefault();
          });
          pad.addEventListener('pointermove', (e) => {
            if (!aiming) return;
            Object.assign(aiming, toBoard(e));
          });
          const release = (throwIt: boolean) => () => {
            if (!aiming) return;
            aiming = null;
            cancelAnimationFrame(raf);
            cross.setAttribute('visibility', 'hidden');
            if (throwIt && canAim()) play({ by: 'player', x: Math.round(sight.x), y: Math.round(sight.y) });
          };
          pad.addEventListener('pointerup', release(true));
          pad.addEventListener('pointercancel', release(false));

          draw();
          return {
            stop: () => {
              window.clearTimeout(aiTimer);
              window.clearTimeout(toast);
              cancelAnimationFrame(raf);
            },
            timeout: () => {
              if (s.over) return;
              window.clearTimeout(aiTimer);
              aiming = null;
              s = rules.apply(s, { by: 'timeout' });
              draw();
              api.finish(rules.result(s)!);
            },
          };
        },
      }, onFinish),
  };
}
