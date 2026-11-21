# Klient W (web)

TypeScript + Vite + Babylon.js 9 + planck.js podle `Prompts/01-METROPOLE_DUALSTACK_PLAN.md` (kap. 6).
Hračka M0 ze stejného citypacku a `content/tuning.yaml` jako Flutter klient.

```
run/bin/metro sync          # tuning.json, auta a balíčky do web/public/shared/
cd web && npm ci
npm run dev                 # http://localhost:5173/?debug
npm run typecheck && npm test && npm run build
```

## Struktura
- `src/world/` – citypack (gzip protobuf přes `DecompressionStream`), graf, chunky, streaming, kamera. Čistá logika.
- `src/drive/` – auto (model pneumatik ze `specs/drive.md`), vrstvy, zábradlí, mobiliář, ovládání A/B/C.
  Čistá logika bez Babylonu; testy ve `test/drive.test.ts` jezdí po skutečném balíčku NYC.
- `src/render/` – geometrie (čistá, testovaná) a scéna Babylonu.
- `src/minigames/` – kontrakt miniher (`api.ts`, `rules.ts`), společné UI (`shell.ts`: návod, pauza,
  strop, výsledek), Galerie a hry (`<id>/rules.ts` čistá pravidla, `<id>/game.ts` UI).
- `src/gen/` – generuje `metro gen`, needitovat.

## Obraz shodný s F (DUALSTACK 6.2)
Kamera stojí kolmo nad autem ve výšce `H = 1 / extrusion.k`. Budovy se staví do výšky
`z = H · (1 − 1/s(h))`, takže perspektiva dá stejné zvětšení střech jako 2,5D vytažení ve F.
Auto drží na `car_anchor` posunutá projekce (lens shift), ne posun kamery. Mosty jsou ve výšce
`layers.deck_lift_m`.

## Parametry adresy
- `?debug` – `window.metro` (engine, scéna, jízda, `firstFrameMs`, `frameTimes`).
- `?gallery` – Galerie miniher; `?mg=<id>&seed=<n>&level=<1-5>` – rovnou minihra.
- `?scheme=a|b|c` – schéma ovládání; `?spot=<id>` – start na spotu; `?gpu=webgpu` – volitelně WebGPU.
- Klávesnice: šipky/WASD, mezerník = ruční brzda.

## Odchylky od F (P2, prezentace)
- Mobiliář rozmisťuje sdílený PRNG (`specs/prng.md`); F zatím `dart:math` Random, takže pozice se liší.
- Auto v planck.js má zkosené rohy místo zaobleného boxu Box2D v3; hmotnost je stejná jako ve F.
- Spadlá lampa je kreslená jako kotouč, ne ležící sloup.

## Odchylka od plánu (6.1)
UI miniher je čisté DOM/SVG s malým pomocníkem `h()` (`src/minigames/dom.ts`), ne Svelte: typová
kontrola `.svelte` souborů (svelte-check) nad TypeScriptem 7 není ověřená a diskrétní hry UI
framework nepotřebují. Až přijde telefon s feedem (M1-S7), rozhodne se znovu.
