import { describe, expect, it } from 'vitest';
import { photoParts, photoTrialVariant } from '../src/world/photoTrial';

describe('photo texture trial (local experiment)', () => {
  it('is off without the query parameter', () => {
    expect(photoTrialVariant('')).toBeNull();
    expect(photoTrialVariant('?photo=0')).toBeNull();
    expect(photoTrialVariant('?photo=1')).toBe('2048');
    expect(photoTrialVariant('?photo=1024')).toBe('1024');
    expect(photoTrialVariant('?photo=../x')).toBe('2048');
  });

  it('splits uv.bin per part in photo.json order', () => {
    const raw = new Uint16Array(18).map((_, i) => i * 1000);
    const parts = photoParts({ model: 'm', atlas: 'a.jpg', credit: '', parts: [{ part: 3, tris: 1 }, { part: 0, tris: 2 }] }, raw);
    expect([...parts.keys()]).toEqual([3, 0]);
    expect(parts.get(3)!.length).toBe(6);
    expect(parts.get(0)![0]).toBeCloseTo(6000 / 65535);
  });
});
