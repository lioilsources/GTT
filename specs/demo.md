# Demo záběr (`?demo=roadster`)

**version: 1** · P2 (jen W, prezentace) · plán: `Prompts/05-METROPOLE_LAUNCH_PLAN.md` L-S9 ·
parita F-077 · čísla `content/tuning.yaml` → `demo`, trasa `content/bench/prague-demo.json`

## Účel

Krátký záběr pro post a náhled odkazu: Vega Roadster jede v Praze do kopce, před ním stojí kolona
za tramvají, auto ji přeskočí s přemetem, dopadne a jede dál. Záběr se dá nahrát dvakrát
se stejným výsledkem.

## Scéna

- Město `prague`, auto `vega_roadster`, trasa `content/bench/prague-demo.json` (Vinohradská od
  Legerovy do kopce k Budečské; formát `specs/bench.md`), autopilot ze `specs/bench.md`.
- Tramvaj: na koleji nejbližší bodu trasy ve vzdálenosti `demo.tram_at_m` od startu (do
  `demo.track_search_m`), čelem ve směru trasy. Stojí po celý záběr (zastávka bez konce).
- Kolona: `demo.queue_cars` aut provozu na hraně trasy v jízdním pruhu za tramvají, mezery
  `demo.queue_gap_m`, stojí (provoz zastavuje za tramvají, `specs/traffic.md`).
- Skok: jakmile je zadní konec posledního auta kolony do `demo.hop_at_m` před autem, autopilot
  spustí skok (`specs/hop.md`), jednou za záběr.
- Po dopadu autopilot dojede trasu; záběr končí po `demo.duration_s`.
- Počasí jasno, den, ostatní provoz a chodci podle seedu `demo.seed` (všechny náhodné seedy hry).
- Bez úvodní karty, ladicího HUD, telefonu a tlačítek; jen svět (kamera jako ve hře).

## Pevný krok

- Každý vykreslený snímek posune hru přesně o `1 / demo.fps` s. V režimu nahrávání
  (`?demo=roadster&rec`) se snímek posune jen voláním `metro.demo.frame()`; skript po každém
  snímku uloží obrázek. Výsledek nezávisí na rychlosti počítače.
- Shoda: dvě nahrání dají v čase 10 s stejnou polohu auta (na 1 cm).

## Nahrání (`web/scripts/demo.ts`)

- Na výšku 1080 × 1920 (CSS 360 × 640, DPR 3), `demo.duration_s` × `demo.fps` snímků →
  `run/media/demo_roadster.webm` (VP9, mimo git).
- Snímek na šířku 1200 × 630 v čase `demo.og_at_s` → `web/public/og.png` (náhled odkazu, README).
- Skript vypíše polohu auta v 10. sekundě.
