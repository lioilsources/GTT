import type { MessageKey } from '../gen/i18n';
import type { MinigameContext, MinigameResult } from '../gen/schema';
import type { MinigameEnv } from './api';
import { h } from './dom';
import type { RulesResult } from './rules';

/** What a game body gets from the shell. */
export interface ShellApi {
  /** Element the game draws into (between the top bar and the bottom edge). */
  body: HTMLElement;
  /** Sets the status line in the top bar. */
  status(text: string): void;
  /** Ends the game with the rules result (stars, score). */
  finish(r: RulesResult): void;
  /** True while the pause sheet is open; games must not advance then. */
  readonly paused: boolean;
}

export interface ShellSpec {
  id: string;
  /** Up to three rule cards shown before the first game (9.2). */
  rules: MessageKey[];
  timeCapS: number;
  /** Starts the game body; returns a cleanup and the timeout handler. */
  start(api: ShellApi): { stop(): void; timeout(): void };
}

/**
 * Common minigame chrome for every web minigame (specs/minigames/README.md "UI"): rule cards,
 * pause sheet with resume / give up, time cap, result screen with stars, again and back.
 */
export function mountShell(
  host: HTMLElement,
  ctx: MinigameContext,
  env: MinigameEnv,
  spec: ShellSpec,
  onFinish: (r: MinigameResult) => void,
): () => void {
  const { t } = env;
  const root = h('div.mg');
  host.append(root);
  let started = 0;
  let pausedAt = 0;
  let pausedMs = 0;
  let paused = false;
  let game: { stop(): void; timeout(): void } | null = null;
  let timer = 0;
  let done = false;

  const status = h('div.mg-status');
  const title = h('div.mg-title', {}, t(`mg_${spec.id}` as MessageKey));
  const pauseBtn = h('button.round', { type: 'button', title: t('pause'), onclick: () => setPaused(true) }, 'Ⅱ');
  const bar = h('div.mg-bar', {}, pauseBtn, title, status);
  const body = h('div.mg-body');
  const sheet = h('div.mg-sheet', { hidden: true });

  const playedMs = (): number => Math.max(0, performance.now() - started - pausedMs);

  function setPaused(p: boolean): void {
    if (done || paused === p) return;
    paused = p;
    if (p) {
      pausedAt = performance.now();
      sheet.replaceChildren(
        h('div.mg-card', {},
          h('h2', {}, t('pause')),
          h('button.mg-btn', { type: 'button', onclick: () => setPaused(false) }, t('resume')),
          h('button.mg-btn.ghost', { type: 'button', onclick: giveUp }, t('giveUp'))),
      );
      sheet.hidden = false;
    } else {
      pausedMs += performance.now() - pausedAt;
      sheet.hidden = true;
    }
  }

  function giveUp(): void {
    if (done) return;
    done = true;
    stopGame();
    onFinish({ stars: 0, score: 0, playedMs: Math.round(playedMs()), aborted: true });
  }

  function stopGame(): void {
    window.clearInterval(timer);
    game?.stop();
    game = null;
  }

  function showResult(r: RulesResult): void {
    const ms = Math.round(playedMs());
    done = true;
    stopGame();
    const stars = h('div.mg-stars', {}, ...[0, 1, 2].map((i) => h('span', { className: i < r.stars ? 'on' : 'off' }, '★')));
    const head = r.winner === 'player' ? t('youWin') : r.winner === 'draw' ? t('draw') : t('youLose');
    const result: MinigameResult = { stars: r.stars, score: r.score, playedMs: ms, aborted: false };
    sheet.replaceChildren(
      h('div.mg-card', {},
        h('h2', {}, head),
        stars,
        h('p', {}, t('scoreValue', { score: r.score })),
        h('button.mg-btn', { type: 'button', onclick: () => { sheet.hidden = true; begin(); } }, t('playAgain')),
        h('button.mg-btn.ghost', { type: 'button', onclick: () => onFinish(result) }, t('back'))),
    );
    sheet.hidden = false;
  }

  const api: ShellApi = {
    body,
    status: (s) => (status.textContent = s),
    finish: (r) => { if (!done) showResult(r); },
    get paused() { return paused; },
  };

  function begin(): void {
    done = false;
    paused = false;
    pausedMs = 0;
    body.replaceChildren();
    status.textContent = '';
    started = performance.now();
    game = spec.start(api);
    const cap = Math.min(spec.timeCapS, env.tuning.minigames.timeCapS) * 1000;
    timer = window.setInterval(() => {
      if (!paused && !done && playedMs() >= cap) game?.timeout();
    }, 250);
  }

  function intro(i: number): void {
    if (i >= spec.rules.length) {
      sheet.hidden = true;
      begin();
      return;
    }
    sheet.replaceChildren(
      h('div.mg-card', {},
        h('h2', {}, t(`mg_${spec.id}` as MessageKey)),
        h('p.mg-rule', {}, t(spec.rules[i]!)),
        h('div.mg-dots', {}, ...spec.rules.map((_, j) => h('span', { className: j === i ? 'on' : '' }))),
        h('button.mg-btn', { type: 'button', onclick: () => intro(i + 1) }, i + 1 < spec.rules.length ? t('next') : t('play'))),
    );
    sheet.hidden = false;
  }

  root.append(bar, body, sheet);
  const onKey = (e: KeyboardEvent): void => { if (e.key === 'Escape') setPaused(!paused); };
  const onHide = (): void => { if (document.hidden) setPaused(true); };
  window.addEventListener('keydown', onKey);
  document.addEventListener('visibilitychange', onHide);
  void ctx;
  intro(0);

  return () => {
    stopGame();
    window.removeEventListener('keydown', onKey);
    document.removeEventListener('visibilitychange', onHide);
    root.remove();
  };
}
