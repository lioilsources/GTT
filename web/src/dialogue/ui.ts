import './dialogue.css';

import type { Locale, MessageKey } from '../gen/i18n';
import type { NpcCharacter } from '../gen/schema';
import type { MinigameOpponent } from '../minigames/api';
import { art, artImage, expressionFor, usable } from '../art';
import { h } from '../minigames/dom';
import { overlays } from '../pause';
import { text, tones, type Tone } from './rules';
import { initials, type DialogueSession } from './session';

export interface DialogueEnv {
  locale: Locale;
  t: (k: MessageKey, a?: Record<string, string | number>) => string;
}

const toneKey: Record<Tone, MessageKey> = { flirt: 'npcToneFlirt', joke: 'npcToneJoke', dry: 'npcToneDry' };

/**
 * NPC portrait: the generated image (`artPath`, an index path from specs/art.md) cropped to a
 * circle over the placeholder (initials on a token-coloured circle), which shows without a file.
 */
export function portrait(name: string, index: number, size = 56, artPath: string | null = null): HTMLElement {
  const el = h('div.npc-portrait', {
    style: {
      width: `${size}px`,
      height: `${size}px`,
      fontSize: `${Math.round(size * 0.4)}px`,
      background: `var(--color-npc-portraits-${index}, var(--color-npc-portraits-0))`,
    },
  }, initials(name));
  setPortraitArt(el, artPath);
  return el;
}

/** Swaps the image of a portrait (null = back to initials); no-op when the path is unchanged. */
export function setPortraitArt(el: HTMLElement, artPath: string | null): void {
  const path = usable(artPath);
  if ((el.dataset.art ?? null) === path) return;
  el.querySelector('img.art-fill')?.remove();
  if (path) {
    el.dataset.art = path;
    el.append(artImage(path, 'art-fill', () => delete el.dataset.art));
  } else delete el.dataset.art;
}

/** The opponent's short line on a minigame result screen (rival portrait `npc/<id>.png`). */
export function opponentBubble(o: MinigameOpponent, winner: 'player' | 'ai' | 'draw'): HTMLElement {
  return h('div.npc-opponent', {},
    portrait(o.name, o.portrait, 40, art().avatar(o.id)),
    h('div.npc-bubble', {}, h('b', {}, o.name), ' ', o.line(winner)));
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
  // Expression by vibe (specs/art.md): happy / neutral / annoyed, then `<id>.png`, then initials.
  const artPath = (): string | null => art().portrait(charId, expressionFor(session.vibe(charId), session.tuning));
  const face = portrait(ch.name, ch.portrait, 56, artPath());

  const root = h('div.npc', {},
    h('div.npc-head', {},
      face,
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

  // The game stands while the dialogue is open (specs/pause.md).
  const release = overlays.open('dialogue');
  const close = (): void => {
    if (closed) return;
    closed = true;
    release();
    session.leave();
    onClose();
  };

  function render(): void {
    const v = session.vibe(charId);
    setPortraitArt(face, artPath());
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
    release();
    root.remove();
  };
}
