# L – Vystřelení (pod-plán)

Zadání Ol1na 2026-11-23: `Prompts/05-METROPOLE_LAUNCH_PLAN.md`. Cíl: repo a webový klient snesou
veřejný odkaz („Forkni to“ = repo, „Zahraj si“ = GitHub Pages), otevřený z telefonu.

## Výchozí volby
| # | Otázka | Volba |
|---|---|---|
| L1 | Licence | kód a herní data (`content/` mimo `content/npc/`) MIT; `assets/` a `content/npc/` CC BY-NC 4.0; balíčky měst ODbL; držitel „Ol1n“ (rozhodl Ol1n 2026-11-23) |
| L2 | Výšky Prahy | AWS Terrain Tiles; DMR 5G po vystřelení |
| L3 | F-070–F-073 ve F | po vystřelení, F v `parity.yaml` zůstává `todo` |
| L4 | M4 Tokio | po L |
| L5 | Nástroje | žádný shell: Go v `tools/metro`, Node v `web/scripts` |

## Položky (`plans/progress.yaml`, milník L)
| Blok | Položky | Kdo |
|---|---|---|
| A Praha s kopci | L-S1 | session MacBook (navazuje na M5 T2/T3) |
| B Repo | L-S2 README a status blok, L-S3 počítadla, L-S4 tracker, L-S5 licence a NOTICE | session M2 |
| C Telefon | L-S6 kouřový test, L-S7 první spuštění, L-S8 og metadata, L-S9 demo záběr | session M2 |
| D Dogfooding | L-S10 tramvaje, L-S11 mosty a voda | session MacBook |
| D Dogfooding | L-S12 policie, L-S13 regresní testy | session M2 |
| E Ověření | L-S14 `docs/verify.md`, L-S15 `metro stats` | session M2 |

Dvě sessions pracují v jednom repu souběžně: každá upravuje v `progress.yaml` jen své položky
a před pushem rebasuje na `main`.

Akceptace: `docs/launch.md` (co zbývá jen Ol1novi: tři pražské trasy na telefonu, M5-A5,
licence, schválení demo záběru, post), `metro progress --check` a kouřový test zelené na `main`,
Pages nasazené.

## Stav
- 2026-11-23: plán uložen, položky založeny.
