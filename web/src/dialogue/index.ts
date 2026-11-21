import type { NpcContext } from './rules';
import { dialogueSession } from './session';
import { mountDialogue, type DialogueEnv } from './ui';

export { DialogueSession, dialogueSession, setDialogueSession } from './session';
export { mountDialogue, opponentBubble, portrait, type DialogueEnv } from './ui';
export type { NpcContext, Tone } from './rules';

/**
 * Street chat entry for other features (METROPOLE_PLAN 11): picks a skit for the character and
 * context from the app-wide session and shows the dialogue overlay. False when no skit fits.
 */
export function startSkit(host: HTMLElement, env: DialogueEnv, characterId: string, context: NpcContext, onClose: () => void = () => {}): boolean {
  const s = dialogueSession();
  if (!s || !s.startSkit(characterId, context)) return false;
  const unmount = mountDialogue(host, s, env, () => {
    unmount();
    onClose();
  });
  return true;
}
