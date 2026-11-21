import './dialogue.css';

import type { Locale, MessageKey } from '../gen/i18n';
import type { NpcCharacter } from '../gen/schema';
import type { MinigameOpponent } from '../minigames/api';
import { h } from '../minigames/dom';
import { text, tones, type Tone } from './rules';
import { initials, type DialogueSession } from './session';

export interface DialogueEnv {
  locale: Locale;
  t: (k: MessageKey, a?: Record<string, string | number>) => string;
}

const toneKey: Record<Tone, MessageKey> = { flirt: 'npcToneFlirt', joke: 'npcToneJoke', dry: 'npcToneDry' };

/** Placeholder portrait: initials on a token-coloured circle (manga portraits come later via ComfyUI). */
export function portrait(name: string, index: number, size = 56): HTMLElement {
  return h('div.npc-portrait', {
    style: {
      width: `${size}px`,
      height: `${size}px`,
      fontSize: `${Math.round(size * 0.4)}px`,
      background: `var(--color-npc-portraits-${index}, var(--color-npc-portraits-0))`,
    },
  }, initials(name));
}

/** The opponent's short line on a minigame result screen. */
export function opponentBubble(o: MinigameOpponent, winner: 'player' | 'ai' | 'draw'): HTMLElement {
  return h('div.npc-opponent', {}, portrait(o.name, o.portrait, 40), h('div.npc-bubble', {}, h('b', {}, o.name), ' ', o.line(winner)));
}

/**
 * Mounts the dialogue overlay for the skit already started in `session` (`session.startSkit`).
 * Speech bubbles, three reply buttons, walk away; calls `onClose` once. Returns unmount.
 */
export function mountDialogue(host: HTMLElement, session: DialogueSession, env: DialogueEnv, onClose: () => void): () => void {
  const { t, locale } = env;
  const charId = session.state.character;
  const ch = session.character(charId) as NpcCharacter;
  const max = session.tuning.vibeMax;
  const log = h('div.npc-log');
  const vibeFill = h('div.npc-vibe-fill');
  const vibeLabel = h('span.npc-vibe-label');
  const actions = h('div.npc-actions');
  let closed = false;

  const root = h('div.npc', {},
    h('div.npc-head', {},
      portrait(ch.name, ch.portrait),
      h('div.npc-who', {},
        h('div.npc-name', {}, t('npcNameAge', { name: ch.name, age: ch.age })),
        h('div.npc-bio', {}, text(ch.bio, locale)),
        h('div.npc-vibe', {}, h('div.npc-vibe-track', {}, vibeFill), vibeLabel))),
    log,
    actions);

  const say = (who: 'them' | 'me', s: string, tag?: string): void => {
    log.append(h(`div.npc-line.${who}`, {}, tag ? h('span.npc-tag', {}, tag) : null, s));
    log.scrollTop = log.scrollHeight;
  };

  const close = (): void => {
    if (closed) return;
    closed = true;
    session.leave();
    onClose();
  };

  function render(): void {
    const v = session.vibe(charId);
    vibeFill.style.width = `${Math.round((100 * v) / Math.max(1, max))}%`;
    vibeLabel.textContent = t('npcVibe', { vibe: v, max });
    const beat = session.beat;
    if (beat) {
      actions.replaceChildren(
        ...tones.map((tone) =>
          h('button.npc-reply', { type: 'button', onclick: () => pick(tone) },
            h('span.npc-tag', {}, t(toneKey[tone])), text(beat.replies[tone], locale))),
        h('button.mg-btn.ghost', { type: 'button', onclick: close }, t('npcLeave')),
      );
      return;
    }
    const r = session.result();
    const note = r?.newContact
      ? h('div.npc-note.contact', {}, t('npcNewContact', { name: ch.name }))
      : r?.contact
        ? h('div.npc-note', {}, t('npcIsContact', { name: ch.name }))
        : h('div.npc-note', {}, t('npcNoContact'));
    actions.replaceChildren(note, h('button.mg-btn', { type: 'button', onclick: close }, t('npcDone')));
  }

  function pick(tone: Tone): void {
    const beat = session.beat;
    if (!beat) return;
    say('me', text(beat.replies[tone], locale), t(toneKey[tone]));
    session.reply(tone);
    say('them', text(beat.reactions[tone], locale));
    const next = session.beat;
    if (next) say('them', text(next.npc, locale));
    render();
  }

  const first = session.beat;
  if (first) say('them', text(first.npc, locale));
  render();
  host.append(root);
  return () => {
    closed = true;
    root.remove();
  };
}
