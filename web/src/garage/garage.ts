import type { CarSpec } from '../gen/schema';
import type { Tuning } from '../gen/tuning';
import { garageConfig, GarageRules, type GarageAction, type GarageState, type Levels, type Look, type LookPart } from './rules';

/** Cash of the cars state (specs/garage.md "Hotovost", as in specs/shops.md). */
export interface GarageCash {
  get(): number;
  set(cash: number): void;
}

/**
 * The garage of one session (specs/garage.md): the P0 `garage` state, purchases that take cash
 * from the cars state, and the levels and looks the drive and the drawing read. No UI.
 */
export class GarageWorld {
  readonly rules = new GarageRules();
  state: GarageState;

  constructor(readonly tuning: Tuning, specs: Iterable<CarSpec>, readonly cash: GarageCash) {
    this.state = this.rules.init(garageConfig(tuning.garage, specs), 0);
  }

  /** `load` from the save; a broken save (illegal load) leaves everything stock. */
  load(upgrades: unknown, looks: unknown): void {
    try {
      this.state = this.rules.apply(this.state, { by: 'player', op: 'load', upgrades, looks });
    } catch {
      this.state = this.rules.apply(this.state, { by: 'player', op: 'load', upgrades: {}, looks: {} });
    }
  }

  /** Slots of a car in catalog order (empty for `micro`). */
  slots(car: string): string[] {
    return this.rules.config.cars[car] ?? [];
  }

  levels(car: string): Levels {
    return { ...(this.state.upgrades[car] ?? {}) } as Levels;
  }

  look(car: string): Look {
    return { ...(this.state.looks[car] ?? {}) } as Look;
  }

  level(car: string, slot: string): number {
    return this.rules.level(this.state, car, slot);
  }

  /** Number of choices of a part. */
  choices(part: LookPart): number {
    return this.rules.config.parts[part] ?? 1;
  }

  /** Price of the next level, null when maxed or not a slot of the car. */
  upgradePrice(car: string, slot: string): number | null {
    return this.rules.upgradePrice(this.state, car, slot);
  }

  canUpgrade(car: string, slot: string): boolean {
    const p = this.upgradePrice(car, slot);
    return p !== null && this.cash.get() >= p;
  }

  lookPrice(part: LookPart, value: number): number {
    return this.rules.lookPrice(part, value);
  }

  canLook(car: string, part: LookPart, value: number): boolean {
    return value !== this.rules.look(this.state, car, part) && this.cash.get() >= this.lookPrice(part, value);
  }

  /** Buys the next level; returns the amount paid or null when not allowed. */
  upgrade(car: string, slot: string): number | null {
    return this.run({ by: 'player', op: 'upgrade', car, slot, cash: this.cash.get() });
  }

  /** Buys (or resets to stock for free) a look choice; returns the amount paid or null. */
  setLook(car: string, part: LookPart, value: number): number | null {
    return this.run({ by: 'player', op: 'look', car, part, value, cash: this.cash.get() });
  }

  private run(a: GarageAction): number | null {
    let next: GarageState;
    try {
      next = this.rules.apply(this.state, a);
    } catch {
      return null;
    }
    this.state = next;
    this.cash.set(this.cash.get() - next.last.amount);
    return next.last.amount;
  }
}
