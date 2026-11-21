# Sdílená vrstva a `metro` (DUALSTACK D0)

Obsah, pravidla, čísla, texty, barvy a testy existují jednou; dva klienti (F = `app/` + `packages/`,
W = `web/`) je čtou nebo proti nim skládají zkoušku. Plán: `Prompts/01-METROPOLE_DUALSTACK_PLAN.md`.

## Složky

| Cesta | Obsah |
|---|---|
| `content/` | `tuning.yaml` (všechna herní čísla), `cars/`, `cities/`, `minigames/catalog.yaml`, `npc/` (postavy a skity) |
| `i18n/<locale>.json` | jediný zdroj textů (šablona `en.json` s ARB metadaty) |
| `design/tokens.json` | barvy, světla, písmo, rozestupy, poloměry |
| `schema/` | JSON Schema: auto, kontrakt miniher, uložení, vektory, scénáře, parita |
| `specs/` | specifikace modulů (osnova v `specs/README.md`), každá s `version` |
| `vectors/` | zlaté vektory P0 (`<modul>.json`) |
| `scenarios/` | scénáře P1 |
| `assets/` | sprity, portréty, zvuky |
| `parity.yaml` | matice parity; `metro parity report` z ní dělá `PARITY.md` (gitignorovaný) |
| `metro.yaml` | vlastnictví cest, bootstrap větve, města přibalená do aplikace |
| `packs.lock` | verze balíčků měst v GitHub Releases (píše `citypack publish`) |

## Příkazy

```sh
(cd tools/metro && go build -o ../../run/bin/metro ./cmd/metro)
run/bin/metro gen            # shared_gen (Dart), web/src/gen (TS), ARB, protobuf (Dart, TS, Go)
run/bin/metro gen --check    # CI: generovaný kód odpovídá sdíleným souborům
run/bin/metro sync           # app/assets/shared + web/public/shared (před každým buildem)
run/bin/metro validate       # obsah proti schema/
run/bin/metro vectors check  # formát vektorů, shoda se specVersion
run/bin/metro vectors record --client flutter|web --module prng
run/bin/metro parity report [--release]
run/bin/metro guard --base origin/main
run/bin/citypack publish nyc # balíček z build/packs/nyc do GitHub Release + packs.lock
run/bin/citypack pull all    # podle packs.lock do build/packs/
```

`metro gen` potřebuje na PATH `protoc`, `protoc-gen-dart` a `protoc-gen-go`; `protoc-gen-es` bere
z `web/node_modules` (`npm ci` ve `web/`). Verze jsou připnuté v `.github/actions/setup-shared`:
protoc 36.2, protoc_plugin 25.1.0, protoc-gen-go 1.36.12, @bufbuild/protoc-gen-es 2.17.0.

## Generovaný kód

| Zdroj | Dart (`packages/shared_gen`) | TS (`web/src/gen`) |
|---|---|---|
| `content/tuning.yaml` | `Tuning` (přísný parser, `flatten()`, posluchači) | `tuning.ts` (`Tuning.fromJson`) |
| `design/tokens.json` | `Tokens` (barvy jako `0xAARRGGBB`) | `tokens.ts`, `tokens.css` |
| `i18n/*.json` | `l10n/app_<locale>.arb` → `flutter gen-l10n`; `i18n.g.dart` (`tr()`, `MessageKey`) pro čisté balíčky | `i18n.ts` (`t()`, typ `MessageKey`) |
| cities, cars, catalog | `CityId`, `CarId`, `EngineId`, `MinigameId` | `ids.ts` |
| `schema/{car,minigame,save}` | `CarSpec`, `Minigame*`, `Save` | `schema.ts` |
| `schema/npc.schema.json` | `Npc*` (v `schema.g.dart`) | `Npc*` (v `schema.ts`) |
| `tools/citypack/proto` | `citypack_pb.dart` | `pb/citypack_pb.ts` (+ Go do citypacku) |

Typy v `Tuning` se odvozují z literálů: `25` = int, `25.0` = double. Generované soubory se commitují
a needitují; `metro gen --check` v CI spadne, když nesedí.

## Postup jedné feature (DUALSTACK 8)

Větve `shared/…`, `flutter/…`, `web/…`; každá smí měnit jen své cesty (`metro guard`, `metro.yaml`).
Generované složky `packages/shared_gen/` a `web/src/gen/` patří SHARED. Výjimka je bootstrap větev
`shared/d0`, která oba klienty napojila.

## Ověřeno (OVĚŘ z plánu)

- **CORS u Releases:** `github.com/…/releases/download/…` odpovídá 302 bez `Access-Control-Allow-Origin`,
  prohlížeč přílohy stáhnout nemůže → web si balíčky kopíruje do buildu (`metro sync` → `public/shared/packs`).
- **Babylon.js 9.35:** `Engine`, `WebGPUEngine.IsSupportedAsync` + `initAsync`, `CreateGround`, `FreeCamera`
  (`FOVMODE_HORIZONTAL_FIXED`) z `@babylonjs/core/...`. Výchozí WebGL2, WebGPU jen `?gpu=webgpu`.
- **Protobuf v TS:** `@bufbuild/protobuf` + `protoc-gen-es` 2.17 (jeden runtime).
- **Iterace solveru:** Box2D v3 (forge2d) nemá rychlostní/poziční iterace, jen sub-stepy
  (`drive.substeps`); planck.js (Box2D v2) iterace má – nastaví se v D1 a rozdíl ověří scénáře P1.

## Dialogy NPC (`content/npc/`)

Skity mají přes tisíc replik ve dvou jazycích, proto nejsou v `i18n/` (ARB by se rozrostl a klíče
`skit_<id>_<n>` by se nedaly revidovat po scénách). Vlastní formát drží text u scény:

- `content/npc/characters.yaml` – postavy (`NpcCharacters`), `content/npc/skits/<id>.yaml` – skity
  (`NpcSkit`); každý text je objekt `{en, cs}` se všemi jazyky z `i18n/`.
- `metro validate` je kontroluje proti `schema/npc.schema.json` (`$defs/NpcCharacters`, `$defs/NpcSkit`)
  a navíc hlídá `id` = jméno souboru, známou postavu a index portrétu v `color.npc.portraits`.
- `metro gen` z téhož schématu generuje typy `NpcPack`, `NpcCharacter`, `NpcSkit`, … pro oba klienty.
- `metro sync` vše sloučí do `content/npc.json` (`NpcPack`, skity seřazené podle `id`) v
  `app/assets/shared/` i `web/public/shared/`; klienti ho načtou za běhu.
- Nový jazyk = přidat ho do `i18n/` i do `NpcText` ve schématu; validace pak ukáže chybějící texty.

Pravidla výběru, vibe a kontaktů: `specs/dialogue.md`.
