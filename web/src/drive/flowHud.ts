import type { MessageKey } from '../gen/i18n';
import type { Tuning } from '../gen/tuning';
import { h } from '../minigames/dom';
import { overlays } from '../pause';
import type { Phone } from '../phone/phone';
import type { DriveWorld } from './driveWorld';
import { stuckLine, type StuckKind } from './flow';

type T = (k: MessageKey, a?: Record<string, string | number>) => string;

/** localStorage key of the debug stuck log (specs/flow.md "Měření zaseknutí"). */
export const STUCK_LOG_KEY = 'metro.stuck';

export interface FlowHudEnv {
  drive: DriveWorld;
  tuning: Tuning;
  t: T;
  cityId: string;
  hud: HTMLElement;
  buttons: HTMLElement;
  phone: Phone;
  /** The GPS route ahead (interleaved metres) or empty. */
  route: () => number[];
  /** Debug build (dev server or ?debug): writes the stuck log and offers Copy. */
  debug: boolean;
  /** After every rescue move (camera snap). */
  onMoved: (kind: StuckKind) => void;
}

export interface FlowHud {
  /** HUD tick (0.1 s): the "Na silnici" button. */
  update(): void;
  /** Debug overlay line `flowStuck10` and whether it is over flow.stuck_limit_per_10min. */
  stuckLine(): { text: string; over: boolean };
}

/**
 * Client glue of specs/flow.md: the HUD button "Na silnici" (after button_after_s of slow driving),
 * the same action on the phone home screen (the phone is W's pause menu), GPS direction for the road move and the debug stuck log in localStorage with a Copy button.
 */
export function installFlowHud(env: FlowHudEnv): FlowHud {
  const { drive, t } = env;
  const toRoad = (): void => {
    if (drive.flow.animT > 0) return;
    drive.toRoad();
  };
  const button = h('button.round', {
    id: 'flow-road', type: 'button', hidden: true,
    onclick: () => {
      if (!overlays.paused) toRoad();
    },
  }, t('flowToRoad'));
  env.hud.append(button);
  // Pause menu: the phone home screen always has the action (it closes the phone first).
  env.phone.homeActions.push(h('button.phone-action', {
    type: 'button',
    onclick: () => {
      env.phone.close();
      toRoad();
    },
  }, t('flowToRoad')));

  // "Bez otevřené kontextové nabídky": every menu that W opens over the world (garage list, booth,
  // shop and metro cards, …) pauses the game, so the world does not step and nothing more is needed
  // here. A shown context *button* ("Přesednout", "Hrát", …) does not block: standing still without
  // the brake means something holds the car (the auto-throttle would drive on), e.g. bollards next
  // to a parked car that offers "Přesednout".
  drive.routeAhead = () => {
    const r = env.route();
    return r.length >= 4 ? r : null;
  };
  drive.onRescue = (kind) => env.onMoved(kind);

  if (env.debug) {
    drive.flow.onStuck = (e) => {
      try {
        const prev = localStorage.getItem(STUCK_LOG_KEY) ?? '';
        localStorage.setItem(STUCK_LOG_KEY, prev + stuckLine(Date.now() / 1000, env.cityId, e) + '\n');
      } catch {
        // Storage blocked (private window): the log is a debug aid only.
      }
    };
    const copy = h('button.round', {
      id: 'flow-stuck-copy', type: 'button', title: `stuck.log · ${t('copy')}`,
      onclick: () => {
        let text = '';
        try {
          text = localStorage.getItem(STUCK_LOG_KEY) ?? '';
        } catch {
          text = '';
        }
        void navigator.clipboard?.writeText(text).then(() => (copy.title = t('copied')));
      },
    }, '⚑');
    env.buttons.append(copy);
  }

  return {
    update() {
      const show = drive.flow.buttonShown && drive.flow.animT === 0 && !overlays.paused;
      if (button.hidden === show) button.hidden = !show;
    },
    stuckLine() {
      const n = drive.flow.count10(drive.time);
      return { text: t('flowStuck10', { count: n }), over: n > env.tuning.flow.stuckLimitPer10min };
    },
  };
}
