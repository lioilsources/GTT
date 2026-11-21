import { minigameCatalog } from '../../gen/ids';
import type { Minigame, MinigameEnv } from '../api';
import { h, svg } from '../dom';
import { aiPrng } from '../rules';
import { mountShell } from '../shell';
import { DamaRules, colOf, countPieces, damaConfig, mustCapture, rowOf, type DamaAction, type DamaState } from './rules';

const CELL = 12.5;

/**
 * Dama, specs/minigames/dama.md: tap a piece, then its destination; a multi-jump is tapped square by
 * square, only along prefixes of legal paths. The opponent answers after `ai_think_s`.
 */
export function dama(env: MinigameEnv): Minigame {
  const { t, tuning } = env;
  const tm = tuning.minigames.dama;
  return {
    meta: minigameCatalog.dama,
    mount: (host, ctx, onFinish) =>
      mountShell(host, ctx, env, {
        id: 'dama',
        rules: ['damaRules1', 'damaRules2', 'damaRules3'],
        timeCapS: tm.timeCapS,
        start(api) {
          const rules = new DamaRules();
          const ai = aiPrng(ctx.seed);
          let s: DamaState = rules.init(damaConfig(tm), ctx.seed);
          let legal: number[][] = [];
          let sel: number[] = [];
          let aiTimer = 0;

          const board = svg('svg', { class: 'dama-board', viewBox: '0 0 100 100', preserveAspectRatio: 'xMidYMid meet' });
          const info = h('div.dama-info');
          const note = h('div.dama-note');
          api.body.append(h('div.dama', {}, info, board, note));

          const refresh = (): void => {
            legal = s.turn === 'player' ? rules.legalActions(s).map((a) => ('path' in a ? a.path : [])) : [];
          };
          const extends_ = (p: number[]): boolean => sel.every((x, i) => p[i] === x);

          function draw(): void {
            board.replaceChildren();
            const must = s.turn === 'player' && mustCapture(s);
            const starts = new Set(legal.map((p) => p[0]!));
            const next = new Set(sel.length ? legal.filter((p) => p.length > sel.length && extends_(p)).map((p) => p[sel.length]!) : []);
            for (let r = 0; r < 8; r++) {
              for (let c = 0; c < 8; c++) {
                board.append(svg('rect', { x: c * CELL, y: r * CELL, width: CELL, height: CELL, class: (r + c) & 1 ? 'sq dark' : 'sq light' }));
              }
            }
            for (let i = 0; i < 32; i++) {
              const x = colOf(i) * CELL + CELL / 2, y = rowOf(i) * CELL + CELL / 2;
              const ch = s.board[i]!;
              const g = svg('g', { class: 'dama-cell' });
              g.append(svg('rect', { x: x - CELL / 2, y: y - CELL / 2, width: CELL, height: CELL, class: 'hit' }));
              if (sel.includes(i)) g.append(svg('rect', { x: x - CELL / 2, y: y - CELL / 2, width: CELL, height: CELL, class: 'trail' }));
              if (ch !== '.') {
                const mine = ch === 'w' || ch === 'W';
                let cls = mine ? 'piece player' : 'piece ai';
                if (sel[0] === i) cls += ' selected';
                else if (must && starts.has(i)) cls += ' must';
                g.append(svg('circle', { cx: x, cy: y, r: CELL * 0.38, class: cls }));
                if (ch === 'W' || ch === 'B') g.append(svg('circle', { cx: x, cy: y, r: CELL * 0.18, class: 'crown' }));
              }
              if (next.has(i)) g.append(svg('circle', { cx: x, cy: y, r: CELL * 0.14, class: 'target' }));
              g.addEventListener('click', () => tap(i));
              board.append(g);
            }
            info.textContent = t('damaPieces', { player: countPieces(s.board, 'player'), ai: countPieces(s.board, 'ai') });
            api.status(s.over ? '' : s.turn === 'player' ? t('yourTurn') : t('opponentTurn'));
            note.textContent = !s.over && must ? t('damaMustCapture') : '';
          }

          function tap(i: number): void {
            if (api.paused || s.over || s.turn !== 'player') return;
            const step = [...sel, i];
            const matches = sel.length ? legal.filter((p) => p.length >= step.length && step.every((x, k) => p[k] === x)) : [];
            if (matches.length) {
              const full = matches.find((p) => p.length === step.length);
              if (full) {
                sel = [];
                play({ by: 'player', path: full });
                return;
              }
              sel = step;
            } else {
              sel = legal.some((p) => p[0] === i) ? [i] : [];
            }
            draw();
          }

          function play(a: DamaAction): void {
            if (api.paused || s.over) return;
            s = rules.apply(s, a);
            refresh();
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

          refresh();
          draw();
          return {
            stop: () => window.clearTimeout(aiTimer),
            timeout: () => {
              if (s.over) return;
              window.clearTimeout(aiTimer);
              s = rules.apply(s, { by: 'timeout' });
              sel = [];
              legal = [];
              draw();
              api.finish(rules.result(s)!);
            },
          };
        },
      }, onFinish),
  };
}
