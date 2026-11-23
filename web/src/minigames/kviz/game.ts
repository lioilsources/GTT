import { ASSET_BASE_URL } from '../../config';
import { minigameCatalog } from '../../gen/ids';
import type { Minigame, MinigameEnv } from '../api';
import { h } from '../dom';
import { mountShell } from '../shell';
import { KvizRules, kvizConfig, type KvizState, type QuizBank } from './rules';

const banks = new Map<string, Promise<QuizBank>>();

/** The city bank written by `metro sync` (content/quiz/<city>.json), fetched once per city. */
function loadBank(city: string): Promise<QuizBank> {
  let p = banks.get(city);
  if (!p) {
    p = fetch(`${ASSET_BASE_URL}content/quiz/${city}.json`, { cache: 'no-cache' }).then((r) => {
      if (!r.ok) throw new Error(`quiz ${city}: HTTP ${r.status}`);
      return r.json() as Promise<QuizBank>;
    });
    p.catch(() => banks.delete(city));
    banks.set(city, p);
  }
  return p;
}

/**
 * Městský kvíz, specs/minigames/kviz.md: the question on top, four big buttons below, a bar
 * counting down `question_s` (then the answer is -1). After an answer it flashes right / wrong.
 */
export function kviz(env: MinigameEnv): Minigame {
  const { t, tuning, locale } = env;
  const tm = tuning.minigames.kviz;
  return {
    meta: minigameCatalog.kviz,
    mount: (host, ctx, onFinish) =>
      mountShell(host, ctx, env, {
        id: 'kviz',
        rules: ['kvizRules1', 'kvizRules2', 'kvizRules3'],
        timeCapS: tm.timeCapS,
        start(api) {
          const rules = new KvizRules();
          let s: KvizState | null = null;
          let bank: QuizBank | null = null;
          let qTimer = 0, nextTimer = 0, left = 0;
          let locked = false;
          let stopped = false;

          const head = h('div.board-info');
          const question = h('div.quiz-q');
          const bar = h('div.quiz-bar', {}, h('div.quiz-fill'));
          const buttons = h('div.quiz-options');
          const note = h('div.board-note');
          api.body.append(h('div.quiz', {}, head, bar, question, buttons, note));

          const lang = locale === 'cs' ? 'cs' : 'en';

          function draw(picked = -2): void {
            if (!s || !bank) return;
            if (s.over) return;
            const q = bank.questions[s.order[s.cur]!]!;
            head.textContent = t('kvizQuestion', { n: s.cur + 1, total: s.order.length });
            question.textContent = q.q[lang];
            const perm = s.perms[s.cur]!;
            buttons.replaceChildren(
              ...perm.map((orig, d) => {
                let cls = 'mg-btn quiz-opt';
                if (picked !== -2) {
                  if (rules.isRight(s!, d)) cls += ' right';
                  else if (d === picked) cls += ' wrong';
                }
                return h('button', { type: 'button', className: cls, disabled: picked !== -2, onclick: () => answer(d) }, q.options[lang][orig]!);
              }),
            );
          }

          function setBar(): void {
            const fill = bar.firstElementChild as HTMLElement;
            fill.style.width = `${Math.max(0, (100 * left) / (tm.questionS * 1000))}%`;
          }

          function startQuestion(): void {
            locked = false;
            note.textContent = '';
            note.className = 'board-note';
            left = tm.questionS * 1000;
            draw();
            setBar();
            window.clearInterval(qTimer);
            qTimer = window.setInterval(() => {
              if (api.paused || locked) return;
              left -= 100;
              setBar();
              if (left <= 0) answer(-1);
            }, 100);
          }

          function answer(d: number): void {
            if (!s || s.over || locked || api.paused) return;
            locked = true;
            window.clearInterval(qTimer);
            const right = rules.isRight(s, d);
            draw(d);
            note.textContent = right ? t('kvizRight') : t('kvizWrong');
            note.className = right ? 'board-note right' : 'board-note wrong';
            s = rules.apply(s, { by: 'player', answer: d });
            nextTimer = window.setTimeout(function next() {
              if (api.paused) {
                nextTimer = window.setTimeout(next, 200);
                return;
              }
              const r = rules.result(s!);
              if (r) api.finish(r);
              else startQuestion();
            }, 1100);
          }

          loadBank(ctx.cityId)
            .then((b) => {
              if (stopped) return;
              bank = b;
              s = rules.init(kvizConfig(tm, b.questions.map((q) => q.answer)), ctx.seed);
              const r = rules.result(s);
              if (r) api.finish(r);
              else startQuestion();
            })
            .catch(() => {
              if (!stopped) question.textContent = t('notYet');
            });
          api.status('');

          return {
            stop: () => {
              stopped = true;
              window.clearInterval(qTimer);
              window.clearTimeout(nextTimer);
            },
            timeout: () => {
              if (!s || s.over) return;
              window.clearInterval(qTimer);
              window.clearTimeout(nextTimer);
              s = rules.apply(s, { by: 'timeout' });
              api.finish(rules.result(s)!);
            },
          };
        },
      }, onFinish),
  };
}
