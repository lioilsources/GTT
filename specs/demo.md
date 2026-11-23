# Demo záběr (`?demo=roadster`)

**version: 1** · P2 (jen W, prezentace) · plán: `Prompts/05-METROPOLE_LAUNCH_PLAN.md` L-S9 ·
parita F-077 · čísla `content/tuning.yaml` → `demo`, trasa `content/bench/prague-demo.json`

## Účel

Krátký záběr pro post a náhled odkazu: Vega Roadster jede v Praze do kopce, před ním stojí kolona
za tramvají, auto ji přeskočí s přemetem, dopadne a jede dál. Záběr se dá nahrát dvakrát
se stejným výsledkem.

## Scéna

- Město `prague`, auto `vega_roadster`, trasa `content/bench/prague-demo.json` (Vinohradská od
  Legerovy do kopce, u Italské doleva do Italské k Mánesově; formát `specs/bench.md`), autopilot
  ze `specs/bench.md`. Křižovatka = konec prvního úseku trasy (Vinohradská × Italská).
- Tramvaj: na koleji nejbližší křižovatce (do `demo.track_search_m`), čelem ve směru trasy před
  křižovatkou, zadní konec `demo.tram_past_m` za křižovatkou. Stojí po celý záběr (zastávka bez
  konce).
- Kolona: `demo.queue_cars` stojících aut na čáře trasy před křižovatkou; přední konec prvního
  `demo.queue_stop_m` před křižovatkou, mezery `demo.queue_gap_m`. Modely = první auta
  pražského výběru zaparkovaných aut (`specs/cars.md`). Jsou to zaparkovaná auta (dají se odtlačit).
- Skok: jakmile je zadní konec posledního auta kolony do `demo.hop_at_m` před přídí auta,
  spustí se skok (`specs/hop.md`), jednou za záběr. Po dopadu autopilot odbočí a dojede trasu.
- Záběr končí po `demo.duration_s`.
- Počasí jasno, den; všechny náhodné seedy hry = `demo.seed`.
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
