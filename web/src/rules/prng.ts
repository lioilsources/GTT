/**
 * Shared PRNG (specs/prng.md, version 1): xorshift32 with rejection sampling.
 * Bit-identical to packages/rules_core/lib/src/prng.dart; checked by vectors/prng.json.
 */
export class Prng {
  private x: number;

  constructor(seed: number) {
    const s = seed >>> 0;
    this.x = s === 0 ? 0x9e3779b9 : s;
  }

  /** Current generator state (uint32). */
  get state(): number {
    return this.x;
  }

  nextU32(): number {
    let x = this.x;
    x = (x ^ (x << 13)) >>> 0;
    x = (x ^ (x >>> 17)) >>> 0;
    x = (x ^ (x << 5)) >>> 0;
    this.x = x;
    return x;
  }

  /** Uniform integer in [0, n). */
  nextInt(n: number): number {
    if (!Number.isInteger(n) || n < 1 || n > 2 ** 32) throw new RangeError(`nextInt(${n})`);
    const limit = Math.floor(2 ** 32 / n) * n;
    for (;;) {
      const r = this.nextU32();
      if (r < limit) return r % n;
    }
  }

  /** Fisher–Yates in place; returns the same array. */
  shuffle<T>(a: T[]): T[] {
    for (let i = a.length - 1; i >= 1; i--) {
      const j = this.nextInt(i + 1);
      const t = a[i] as T;
      a[i] = a[j] as T;
      a[j] = t;
    }
    return a;
  }
}
