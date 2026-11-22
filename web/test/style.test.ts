import { readFileSync } from 'node:fs';
import { join } from 'node:path';

import { describe, expect, it } from 'vitest';
import { parse } from 'yaml';

import { tokens } from '../src/gen/tokens';
import { Tuning } from '../src/gen/tuning';
import { cityInks, cityPalette, cityTokenPrefix, dayPalette, nightPalette, rgba } from '../src/render/palette';
import { RISOGRAPH_FRAGMENT, RISOGRAPH_UNIFORMS, risographOn, risographUniforms } from '../src/render/risograph';

const tuning = Tuning.fromJson(parse(readFileSync(join(__dirname, '..', '..', 'content', 'tuning.yaml'), 'utf8')));

describe('city skins (specs/style.md)', () => {
  it('token prefix of a city id', () => {
    expect(cityTokenPrefix('nyc')).toBe('colorCityNyc');
    expect(cityTokenPrefix('prague')).toBe('colorCityPrague');
    expect(cityTokenPrefix('new-york')).toBe('colorCityNewYork');
  });

  it('nyc day palette maps color.city.nyc with the shared day lights', () => {
    const p = cityPalette('nyc');
    expect(p.land).toEqual(rgba(tokens.colorCityNycLand));
    expect(p.water).toEqual(rgba(tokens.colorCityNycWater));
    expect(p.asphalt).toEqual(rgba(tokens.colorCityNycAsphalt));
    expect(p.centerLine).toEqual(rgba(tokens.colorCityNycCenterLine));
    expect(p.bridgeEdge).toEqual(rgba(tokens.colorCityNycBridgeEdge));
    expect(p.landmark).toEqual(rgba(tokens.colorCityNycLandmark));
    expect(p.facades).toEqual(tokens.colorCityNycFacades.map((c) => rgba(c)));
    expect(p.shadow).toEqual(rgba(tokens.colorCityNycShadow));
    expect(p.shadow[3]).toBeCloseTo(0x59 / 255, 6);
    expect(p.roofLight).toBe(tokens.lightDayRoofLight);
    expect(p.sunX).toBe(tokens.lightDaySunX);
    expect(p.sunY).toBe(tokens.lightDaySunY);
    expect(p.ambient).toBe(tokens.lightDayAmbient);
    expect(p.night).toBe(false);
  });

  it('prague day palette maps color.city.prague, inks too', () => {
    const p = cityPalette('prague');
    expect(p.land).toEqual(rgba(tokens.colorCityPragueLand));
    expect(p.park).toEqual(rgba(tokens.colorCityPraguePark));
    expect(p.plaza).toEqual(rgba(tokens.colorCityPraguePlaza));
    expect(p.pedestrian).toEqual(rgba(tokens.colorCityPraguePedestrian));
    expect(p.rail).toEqual(rgba(tokens.colorCityPragueRail));
    expect(p.sidewalk).toEqual(rgba(tokens.colorCityPragueSidewalk));
    expect(p.alley).toEqual(rgba(tokens.colorCityPragueAlley));
    expect(p.marking).toEqual(rgba(tokens.colorCityPragueMarking));
    expect(p.bridgeDeck).toEqual(rgba(tokens.colorCityPragueBridgeDeck));
    expect(p.tunnel).toEqual(rgba(tokens.colorCityPragueTunnel));
    expect(p.facades).toEqual(tokens.colorCityPragueFacades.map((c) => rgba(c)));
    expect(p.shadow).toEqual(rgba(tokens.colorCityPragueShadow));
    expect(cityInks('prague')).toEqual(tokens.colorCityPragueInks.map((c) => rgba(c)));
    expect(cityInks('nyc')).toEqual([]);
  });

  it('an unknown city falls back to color.world.day; night stays shared', () => {
    expect(cityPalette('atlantis')).toBe(dayPalette);
    expect(cityPalette('')).toBe(dayPalette);
    expect(dayPalette.shadow).toEqual(rgba(tokens.colorCarShadow));
    expect(nightPalette.shadow).toEqual(rgba(tokens.colorCarShadow));
    expect(nightPalette.night).toBe(true);
  });
});

describe('risograph (specs/style.md "Risograf")', () => {
  it('only by day in a city with style.risograph.<id>', () => {
    expect(risographOn(tuning.style, 'prague', false)).toBe(tuning.style.risograph.prague);
    expect(risographOn(tuning.style, 'prague', true)).toBe(false);
    expect(risographOn(tuning.style, 'nyc', false)).toBe(tuning.style.risograph.nyc);
    expect(risographOn(tuning.style, 'nyc', true)).toBe(false);
    for (const id of ['atlantis', 'toJson', 'constructor', '']) expect(risographOn(tuning.style, id, false)).toBe(false);
  });

  it('follows the tuning flag', () => {
    const t = Tuning.fromJson(tuning.toJson());
    t.style.risograph.nyc = true;
    t.style.risograph.prague = false;
    expect(risographOn(t.style, 'nyc', false)).toBe(true);
    expect(risographOn(t.style, 'prague', false)).toBe(false);
  });

  it('pixel sizes scale with the device pixel ratio', () => {
    const ink = rgba(tokens.colorCityPragueInks[0]);
    const u1 = risographUniforms(tuning.style, ink, 1);
    const u3 = risographUniforms(tuning.style, ink, 3);
    expect(u1.ink).toEqual([ink[0], ink[1], ink[2]]);
    expect(u1.offsetPx).toBeCloseTo(tuning.style.misregistrationPx);
    expect(u3.offsetPx).toBeCloseTo(tuning.style.misregistrationPx * 3);
    expect(u3.cellPx).toBeCloseTo(tuning.style.halftoneCellPx * 3);
    expect(u3.grainPx).toBeCloseTo(tuning.style.grainSizePx * 3);
    expect(u3.fringe).toBe(tuning.style.fringe);
    expect(u3.halftoneLow).toBe(tuning.style.halftoneLow);
    expect(u3.halftoneHigh).toBe(tuning.style.halftoneHigh);
    expect(u3.grainStrength).toBe(tuning.style.grainStrength);
  });

  it('the shader declares every uniform it is given', () => {
    for (const u of [...RISOGRAPH_UNIFORMS, 'texelSize']) expect(RISOGRAPH_FRAGMENT).toMatch(new RegExp(`uniform \\w+ ${u};`));
    expect(RISOGRAPH_FRAGMENT).toContain('0.299, 0.587, 0.114');
  });
});
