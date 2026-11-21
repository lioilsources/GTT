# M0 – co testovat na telefonu

Build: profile (měří se reálný výkon). Pravý horní roh: FPS overlay
(`fps`, `ms` snímku, `bld` = vykreslené budovy, `prep` = příprava bufferu budov, `chunks`, schéma).
Zelené číslo = ≥ 57 fps, červené = pod.

## 1. Výkon (brána R3)

| Trasa | Co zapsat |
|---|---|
| Start (7th Ave) → dolů přes Times Square na 42nd St | min. fps, max. `prep` ms |
| 42nd St od Hudsonu k East River a zpět | min. fps, zasekávání při načítání chunků |
| Noc (☀︎ vpravo nahoře), stejná trasa | min. fps |
| 5 min volné jízdy | zahřátí telefonu, pokles fps v čase |

Cíl: 60 fps, `prep` ≤ 4 ms. Telefony: Pixel 8a, iPhone 12 mini.

## 2. Ovládání (výběr schématu)

Přepnutí: ⚙ → Ovládání. Každé schéma aspoň 5 min.

- **A** – auto jede samo; tah palcem do stran řídí, tah dolů brzdí/couvá, tah nahoru = plný plyn,
  druhý prst kdekoli = ruční brzda.
- **B** – drž levou/pravou polovinu = zatáčka, obě poloviny = brzda/couvání.
- **C** – volant dole uprostřed, vpravo pedál brzdy, vlevo ruční brzda.

Zapiš: které je nejpřirozenější jednou rukou, jde zatočit do kolmé ulice bez nárazu, jde smyk
na ruční brzdu a vyrovnat ho, couvání z nárazu do zdi.

## 3. Pocit z jízdy (tuning)

⚙ → posuvníky mění hodnoty hned. Zkus hlavně `view_width_m.slow/fast` (přiblížení), `car_scale`,
`extrusion.k` (výška budov), `speed_mps.cruise`, `grip_*`, `drift_bias`.
Až to sedí: **Kopírovat tuning.yaml** a pošli mi obsah schránky.

## 4. Město

- Najdi: Empire State (5th Ave × 34th), Chrysler (Lexington × 42nd), Grand Central (Park Ave × 42nd),
  Times Square (7th Ave/Broadway × 42.–47.), jižní okraj Central Parku (59th St).
- Mosty a tunely: Park Avenue viadukt kolem Grand Central (most nad ulicemi), Queensboro Bridge
  (59th/60th St × 2nd Ave), Lincoln Tunnel (u 40th St × Dyer Ave), Queens-Midtown Tunnel (36th St × 2nd Ave).
  Pod mostem musí auto zůstat dole, na mostě nesmí propadnout dolů ani vyjet z boku.
- Okraj mapy: silnice ven končí oranžovou uzavírkou a hláškou.
- HUD: sedí jméno ulice a čtvrti?

## 5. Co hlásit

Screenshot + kde (ulice) + co se stalo: propad fps, prosvítající stěny budov, auto zaseknuté v budově,
divná kolize, chybějící chunk (prázdné místo), pád appky.

## Slepý test (akceptace M0)

3 lidi, každému pusť jízdu kolem Empire State, Chrysleru, Grand Central, Times Square a okraje
Central Parku bez HUD textu (zakryj horní lištu) a zeptej se „kde to je?“.
