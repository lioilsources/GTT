import type { MessageKey } from '../gen/i18n';
import { art } from '../art';
import { h } from '../minigames/dom';
import { contexts, text } from './rules';
import type { DialogueSession } from './session';
import { mountDialogue, portrait, type DialogueEnv } from './ui';

/**
 * Debug list of skits (`?skits`, specs/dialogue.md "Ladění"): every character × context; a row
 * starts the skit through the same `startSkit` other features use.
 */
export function runSkits(host: HTMLElement, env: DialogueEnv, session: DialogueSession, direct?: string | null): void {
  const { t, locale } = env;

  function list(): void {
    const rows = session.pack.characters.flatMap((c) => [
      h('h2.npc-skits-char', {}, portrait(c.name, c.portrait, 32, art().avatar(c.id)), ' ',
        t('npcNameAge', { name: c.name, age: c.age }), ' · ',
        t('npcVibe', { vibe: session.vibe(c.id), max: session.tuning.vibeMax }),
        session.state.contacts.includes(c.id) ? ' ✓' : ''),
      h('p.npc-bio', {}, text(c.bio, locale)),
      ...contexts.map((x) => {
        const n = session.rules.candidates(c.id, x).length;
        return h('button.gallery-row', { type: 'button', disabled: n === 0, onclick: () => open(c.id, x) },
          h('span.name', {}, t(`npcCtx_${x}` as MessageKey)),
          h('span.meta', {}, String(n)));
      }),
    ]);
    host.replaceChildren(
      h('div.gallery.npc-skits', {},
        h('h1', {}, t('npcSkits')),
        h('p.npc-bio', {}, t('npcSkitsHint')),
        h('p', {}, t('npcContacts', { n: session.state.contacts.length })),
        ...rows),
    );
  }

  function open(characterId: string, context: (typeof contexts)[number]): void {
    if (!session.startSkit(characterId, context)) return;
    console.info('[metro skit]', session.state.skit);
    const unmount = mountDialogue(host, session, env, () => {
      console.info('[metro skit]', JSON.stringify(session.result()));
      unmount();
      list();
    });
  }

  list();
  // ?skits=<character>:<context> opens one directly (screenshots, links from bug reports).
  const [c, x] = (direct ?? '').split(':');
  if (c && x && (contexts as readonly string[]).includes(x)) open(c, x as (typeof contexts)[number]);
}
