import './loop.css';

import type { CarFleet } from '../cars/fleet';
import { DialogueSession, setDialogueSession } from '../dialogue/session';
import type { DriveWorld } from '../drive/driveWorld';
import type { Locale, MessageKey } from '../gen/i18n';
import { carIdValues, minigameCatalog, type MinigameId } from '../gen/ids';
import type { MinigameResult, NpcPack, Save } from '../gen/schema';
import type { Tuning } from '../gen/tuning';
import type { WorldMinigame } from '../minigames/api';
import { h } from '../minigames/dom';
import { minigames } from '../minigames/registry';
import type { PassportHud } from '../passport/hud';
import type { PhoneApi } from '../phone';
import type { City } from '../world/model';
import { loopDifficulty, LoopBook, opponentIndex, spotInReach, type LoopOutcome, type LoopSpot } from './logic';
import { composeSave, freshSave, normalizeSave, saveConfig } from './save';
import { BrowserSaveStore, type SaveStore } from './store';
import { mountLoopResult } from './ui';

export interface LoopEnv {
  city: City;
  tuning: Tuning;
  locale: Locale;
  t: (k: MessageKey, a?: Record<string, string | number>) => string;
  drive: DriveWorld;
  fleet: CarFleet;
  passport: PassportHud;
  phone: PhoneApi;
  /** NPC content for opponents (null = no opponents). */
  npcPack: NpcPack | null;
  /** HUD root (cash pill, play button) and the round-button row (debug reset). */
  hud: HTMLElement;
  buttons: HTMLElement;
  /** Control scheme and night, owned by main.ts. */
  settings: { get(): Save['settings']; set(s: Save['settings']): void };
  /** Called after the saved car replaced the driven one. */
  onCarChanged(): void;
  params: URLSearchParams;
  store?: SaveStore;
}

export interface LoopApi {
  /** True while a minigame or the result card is up: the world neither steps nor renders. */
  readonly busy: boolean;
  /** HUD tick (~10×/s): cash pill and the "Play" context button. */
  update(dt: number): void;
  /** Starts the minigame of a spot (arrival or the context button). */
  start(spotId: string): void;
  /** Police fine hook (specs/economy.md). */
  fine(amount: number): void;
  /** Tow fee hook for a wrecked car (specs/economy.md). */
  tow(): void;
  save(): Promise<void>;
  snapshot(): Save;
  resetSave(): Promise<void>;
  /** Save storage (one save per city); Travel reads other cities' saves from it. */
  store: SaveStore;
  book: LoopBook;
  onOutcome: Array<(o: LoopOutcome) => void>;
  /** World minigames by id (engine `drive`, e.g. Taxi); without one the spot shows "coming soon". */
  worldGames: Partial<Record<MinigameId, WorldMinigame>>;
}

/** Loop glue of client W (specs/loop.md): loads the save, wires arrival → minigame → result → save. */
export async function installLoop(env: LoopEnv): Promise<LoopApi> {
  const { city, tuning, t, fleet, passport, phone } = env;
  const store = env.store ?? new BrowserSaveStore();
  const cfg = saveConfig(tuning, city.id, carIdValues);
  const tracker = passport.tracker;
  const book = new LoopBook(tuning, {
    getCash: () => fleet.state.cash,
    setCash: (c) => fleet.setCash(c),
    stamp: (id, stars) => tracker.minigame(id, stars),
  });
  const spots = city.spots.items;
  const spotById = new Map(spots.map((s) => [s.id, s]));
  const loopSpots: LoopSpot[] = spots.map((s) => ({ id: s.id, minigame: s.minigame, x: s.parkX / 10, y: s.parkY / 10 }));

  // NPC opponents need the dialogue session in the world too (specs/dialogue.md).
  const npc = env.npcPack ? new DialogueSession(env.npcPack, tuning.npc, city.id, (Math.random() * 0x100000000) >>> 0) : null;
  setDialogueSession(npc);
  let savedNpc: Save['npc'] = { vibe: {}, contacts: [], recent: [] };

  // ---------- save
  const snapshot = (): Save => {
    const cs = fleet.state;
    return composeSave(cfg, {
      cash: cs.cash,
      cars: [...cs.owned],
      car: cs.stolen ? (cs.owned[0] ?? cs.driving) : cs.driving,
      stamps: tracker.stamps,
      best: book.best,
      plays: book.plays,
      feed: phone.feedSave(),
      npc: npc ? { vibe: { ...npc.state.vibe }, contacts: [...npc.state.contacts], recent: [...npc.state.recent] } : savedNpc,
      settings: env.settings.get(),
    });
  };
  const restore = (s: Save): void => {
    fleet.restore({ cash: s.cash, owned: s.cars, driving: s.car });
    env.onCarChanged();
    tracker.restore(s.stamps);
    book.restore(s.best, s.plays);
    phone.feedRestore(s.feed);
    savedNpc = s.npc;
    if (npc) {
      const known = new Set(npc.pack.characters.map((c) => c.id));
      const skits = new Set(npc.pack.skits.map((k) => k.id));
      const vibe = { ...npc.state.vibe };
      for (const [k, v] of Object.entries(s.npc.vibe)) if (known.has(k)) vibe[k] = Math.min(tuning.npc.vibeMax, Math.max(0, v));
      npc.state = {
        ...npc.state,
        vibe,
        contacts: s.npc.contacts.filter((c) => known.has(c)),
        recent: s.npc.recent.filter((k) => skits.has(k)).slice(-tuning.npc.recentK),
      };
    }
    if (!env.params.has('scheme')) env.settings.set(s.settings);
  };
  let saving: Promise<void> = Promise.resolve();
  let resetting = false;
  const save = (): Promise<void> => {
    if (resetting) return saving;
    return (saving = saving.then(() => store.write(city.id, snapshot())).catch((e) => console.warn('save failed', e)));
  };
  restore(normalizeSave(cfg, await store.read(city.id).catch(() => null)));

  fleet.on('carChanged', () => void save());
  fleet.on('bought', () => void save());
  const onHide = (): void => {
    if (document.visibilityState === 'hidden') void save();
  };
  document.addEventListener('visibilitychange', onHide);
  window.addEventListener('pagehide', () => void save());

  // ---------- HUD: cash pill, play button, toast
  const cashPill = h('div.pill', { id: 'loop-cash' });
  const playBtn = h('button.round', { id: 'loop-play', type: 'button', hidden: true });
  const toast = h('div.pill.loop-toast', { hidden: true });
  env.hud.append(cashPill, playBtn);
  document.body.append(toast);
  let toastS = 0;
  const showToast = (text: string): void => {
    toast.textContent = text;
    toast.hidden = false;
    toastS = tuning.nav.toastS;
  };
  let playSpot: LoopSpot | null = null;
  let holdS = 0;
  playBtn.addEventListener('click', () => {
    if (playSpot) start(playSpot.id);
  });

  // ---------- minigame
  let busy = false;
  const mgName = (id: string): string => t(`mg_${id}` as MessageKey);
  const inWorldGame = (): boolean => Object.values(api.worldGames).some((g) => g?.active);

  /** Loop result after a minigame (full-screen or in the world). */
  function finish(spotId: string, id: MinigameId, card: { distDm: number } | null, r: MinigameResult): void {
    const o = book.finish({ spot: spotId, minigame: id, engine: minigameCatalog[id].engine, result: r, driveDm: card?.distDm ?? 0 }, (m) => tracker.has('minigame', m));
    for (const f of api.onOutcome) f(o);
    void save();
    busy = true;
    mountLoopResult(document.body, t, o, {
      drive: () => (busy = false),
      feed: () => {
        busy = false;
        phone.phone.open('feed');
      },
    });
  }

  function start(spotId: string): void {
    const spot = spotById.get(spotId);
    if (busy || !spot || !spot.minigame || inWorldGame()) return;
    const id = spot.minigame as MinigameId;
    const meta = minigameCatalog[id];
    const make = minigames[id];
    if (!meta) return;
    const world = meta.engine === 'drive' ? api.worldGames[id] : undefined;
    if (!world && (meta.engine === 'drive' || !make)) {
      showToast(t('loopSoon', { name: mgName(id) }));
      return;
    }
    const card = phone.accepted && phone.accepted.spot === spotId ? phone.accepted : null;
    phone.accepted = null;
    phone.phone.close();
    if (world) {
      // World minigame (specs/minigames/taxi.md): the world keeps running, no full-screen host.
      phone.nav.cancel();
      playBtn.hidden = true;
      playSpot = null;
      const ctx = {
        cityId: city.id,
        difficulty: loopDifficulty(card?.difficulty ?? null, book.plays[spotId] ?? 0, tuning.feed),
        seed: (Math.random() * 0x100000000) >>> 0,
        locale: env.locale,
      };
      world.start(spotId, ctx, (r) => finish(spotId, id, card, r));
      return;
    }
    if (!make) return;
    const seed = (Math.random() * 0x100000000) >>> 0;
    const chars = npc?.pack.characters ?? [];
    const oi = opponentIndex(spotId, chars.length);
    const opponentId = oi >= 0 ? chars[oi]!.id : undefined;
    const ctx = {
      cityId: city.id,
      difficulty: loopDifficulty(card?.difficulty ?? null, book.plays[spotId] ?? 0, tuning.feed),
      seed,
      locale: env.locale,
      ...(opponentId ? { opponentId } : {}),
    };
    const game = make({ tuning, locale: env.locale, t, opponent: npc?.opponent(opponentId, seed, env.locale) });
    busy = true;
    playBtn.hidden = true;
    const host = h('div', { id: 'minigames', className: 'loop-host' });
    document.body.append(host);
    const unmount = game.mount(host, ctx, (r: MinigameResult) => {
      unmount();
      host.remove();
      finish(spotId, id, card, r);
    });
  }

  phone.onArrived.push((id) => {
    const s = spotById.get(id);
    if (s?.minigame && !inWorldGame()) start(id);
  });

  const api: LoopApi = {
    get busy() {
      return busy;
    },
    update(dt) {
      cashPill.textContent = t('cashHud', { cash: fleet.state.cash });
      if (toastS > 0 && (toastS -= dt) <= 0) toast.hidden = true;
      const c = env.drive.car;
      let s: LoopSpot | null = null;
      if (!busy && !phone.phone.isOpen && !phone.nav.active && !inWorldGame()) {
        const now = spotInReach(loopSpots, c.x, c.y, c.speed, c.layer, tuning.loop);
        if (now) {
          s = now;
          holdS = tuning.loop.actionHoldS;
        } else if (playSpot && holdS > 0) {
          holdS -= dt;
          const d2 = (playSpot.x - c.x) ** 2 + (playSpot.y - c.y) ** 2;
          if (holdS > 0 && d2 <= tuning.loop.spotRadiusM ** 2) s = playSpot;
        }
      }
      if (s !== playSpot) {
        playSpot = s;
        playBtn.hidden = s === null;
        if (s) playBtn.textContent = t('loopPlay', { name: mgName(s.minigame) });
      }
    },
    start,
    fine: (amount) => {
      book.fine(amount);
      void save();
    },
    tow: () => {
      book.tow();
      void save();
    },
    save,
    snapshot,
    async resetSave() {
      resetting = true;
      await saving;
      await store.write(city.id, freshSave(cfg));
      location.reload();
    },
    store,
    book,
    onOutcome: [],
    worldGames: {},
  };

  // ?play=<spotId> starts that spot's minigame right away (DUALSTACK 6.6 debug parameter).
  const play = env.params.get('play');
  if (play) setTimeout(() => start(play), 0); // after main.ts registered the world minigames
  if (env.params.has('debug')) {
    env.buttons.append(h('button.round', { type: 'button', title: t('saveReset'), onclick: () => void api.resetSave() }, '⌫'));
  }
  return api;
}
