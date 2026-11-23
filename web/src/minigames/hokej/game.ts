import { minigameCatalog } from '../../gen/ids';
import { tokens } from '../../gen/tokens';
import type { Minigame, MinigameEnv } from '../api';
import { begin, capture, disc, fit, sx, sy, tickLoop, toWorld } from '../canvas';
import { h } from '../dom';
import { mountShell } from '../shell';
import { HokejRules, hokejConfig, type HokejAction, type HokejState } from './rules';

/** Rink border drawn around the table (u). */
const BOARD = 160;

/** Vzdušný hokej (air hockey), specs/minigames/hokej.md: the mallet follows the finger in the lower half. */
export function hokej(env: MinigameEnv): Minigame {
  const { t, tuning } = env;
  const tm = tuning.minigames.hokej;
  return {
    meta: minigameCatalog.hokej,
    mount: (host, ctx, onFinish) =>
      mountShell(host, ctx, env, {
        id: 'hokej',
        rules: ['hokejRules1', 'hokejRules2', 'hokejRules3'],
        timeCapS: tm.timeCapS,
        start(api) {
          const cfg = hokejConfig(tm, ctx.difficulty);
          const rules = new HokejRules();
          let s: HokejState = rules.init(cfg);
          let finished = false;

          const canvas = h('canvas.mgc-canvas');
          const info = h('div.mgc-info');
          api.body.append(h('div.mgc', {}, info, h('div.mgc-wrap', {}, canvas)));
          const view = () => fit(canvas, -BOARD, -BOARD, cfg.w + BOARD, cfg.h + BOARD, 4);

          function play(a: HokejAction): void {
            if (finished || s.over) return;
            s = rules.apply(s, a);
            const r = rules.result(s);
            if (r) {
              finished = true;
              api.finish(r);
            }
          }

          function draw(): void {
            api.status(t('hokejScore', { player: s.playerGoals, ai: s.aiGoals }));
            info.textContent = s.pause > 0 && s.tick > 0 ? t('hokejGoal') : '';
            const g = begin(canvas);
            if (!g) return;
            const v = view();
            const k = v.k;
            const mid = Math.floor(cfg.w / 2);
            g.fillStyle = tokens.colorPoliceBody;
            g.fillRect(sx(v, -BOARD), sy(v, cfg.h + BOARD), (cfg.w + 2 * BOARD) * k, (cfg.h + 2 * BOARD) * k);
            g.fillStyle = tokens.colorWeatherIcon;
            g.fillRect(sx(v, 0), sy(v, cfg.h), cfg.w * k, cfg.h * k);
            g.fillStyle = tokens.colorCarDetailLimoPillar;
            g.fillRect(sx(v, mid - cfg.goalHalf), sy(v, cfg.h + BOARD), 2 * cfg.goalHalf * k, BOARD * k);
            g.fillRect(sx(v, mid - cfg.goalHalf), sy(v, 0), 2 * cfg.goalHalf * k, BOARD * k);
            g.strokeStyle = tokens.colorPoliceLightRed;
            g.lineWidth = 2;
            g.beginPath();
            g.moveTo(sx(v, 0), sy(v, cfg.h / 2));
            g.lineTo(sx(v, cfg.w), sy(v, cfg.h / 2));
            g.stroke();
            g.beginPath();
            g.arc(sx(v, mid), sy(v, cfg.h / 2), cfg.goalHalf * 0.8 * k, 0, Math.PI * 2);
            g.stroke();
            g.save();
            g.beginPath();
            g.rect(sx(v, 0), sy(v, cfg.h), cfg.w * k, cfg.h * k);
            g.clip();
            g.strokeStyle = tokens.colorPoliceLightBlue;
            for (const y of [0, cfg.h]) {
              g.beginPath();
              g.arc(sx(v, mid), sy(v, y), cfg.goalHalf * k, 0, Math.PI * 2);
              g.stroke();
            }
            g.restore();
            const mallet = (x: number, y: number, col: string): void => {
              disc(g, sx(v, x), sy(v, y), cfg.malletR * k, col, tokens.colorUiLabelShadow, 2);
              disc(g, sx(v, x), sy(v, y), cfg.malletR * 0.45 * k, tokens.colorWorldDayMarking);
            };
            mallet(s.ai.x, s.ai.y, tokens.colorTrafficLightRed);
            mallet(s.me.x, s.me.y, tokens.colorPoliceLightBlue);
            disc(g, sx(v, s.puck.x), sy(v, s.puck.y), cfg.puckR * k, tokens.colorCarDetailTaxiChecker);
          }

          const follow = (e: PointerEvent): void => {
            if (api.paused || finished) return;
            e.preventDefault();
            const p = toWorld(canvas, view(), e);
            play({ by: 'player', op: 'move', x: Math.round(p.x), y: Math.round(p.y) });
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
