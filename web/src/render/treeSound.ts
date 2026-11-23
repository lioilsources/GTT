/**
 * Tree hit sound (specs/flow.md "zvuk", P2): a short rustle of filtered noise, with a low thump
 * for a medium or large trunk. Synthesised, no asset; silent until the page had a user gesture.
 */
let ctx: AudioContext | null = null;
let noise: AudioBuffer | null = null;

export function treeHitSound(size: number): void {
  try {
    ctx ??= new AudioContext();
    if (ctx.state === 'suspended') void ctx.resume();
    if (ctx.state !== 'running') return;
    const now = ctx.currentTime;
    if (!noise) {
      noise = ctx.createBuffer(1, Math.floor(ctx.sampleRate * 0.4), ctx.sampleRate);
      const d = noise.getChannelData(0);
      // Deterministic pseudo-noise (no Math.random in the game code paths).
      let s = 0x2545f491;
      for (let i = 0; i < d.length; i++) {
        s ^= s << 13;
        s ^= s >>> 17;
        s ^= s << 5;
        d[i] = ((s >>> 0) / 0xffffffff) * 2 - 1;
      }
    }
    const src = ctx.createBufferSource();
    src.buffer = noise;
    const band = ctx.createBiquadFilter();
    band.type = 'bandpass';
    band.frequency.value = 2600;
    band.Q.value = 0.8;
    const g = ctx.createGain();
    g.gain.setValueAtTime(0.0001, now);
    g.gain.exponentialRampToValueAtTime(0.22, now + 0.02);
    g.gain.exponentialRampToValueAtTime(0.0001, now + 0.38);
    src.connect(band).connect(g).connect(ctx.destination);
    src.start(now);
    src.stop(now + 0.4);
    if (size > 0) {
      const o = ctx.createOscillator();
      o.frequency.setValueAtTime(110, now);
      o.frequency.exponentialRampToValueAtTime(45, now + 0.18);
      const og = ctx.createGain();
      og.gain.setValueAtTime(0.35, now);
      og.gain.exponentialRampToValueAtTime(0.0001, now + 0.2);
      o.connect(og).connect(ctx.destination);
      o.start(now);
      o.stop(now + 0.22);
    }
  } catch {
    // No audio (headless, policy): the hit stays silent.
  }
}
