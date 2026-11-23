# Jízda – model auta (M0)

**version: 2** · P1 (±5 %) · scénáře `scenarios/drive/`, `scenarios/flow/`, `scenarios/nature/`, `scenarios/terrain/`

## Účel
Pocit z jízdy shodný v obou klientech. Čísla jsou v `content/tuning.yaml` (`drive`, `layers`,
`speed_mps`, `car_scale`) a v `content/cars/<id>.json`; v kódu žádná.

## Stav
2D tuhé těleso (Box2D v3 ve F, planck.js ve W): poloha, natočení, rychlost, úhlová rychlost;
úhel kol; vrstva −1/0/+1; aktuální hrana grafu.

## Krok (pevný 1 / `drive.step_hz`, `drive.substeps`)
1. **Řízení:** zámek = `steer_lock_rad − steer_lock_drop_rad · min(v / top, 1)`; cíl = −steer · zámek;
   při driftu (v > `countersteer_min_mps`, |β| > `countersteer_min_slip_rad`, |steer| < `countersteer_max_input`)
   + `countersteer_gain · β`; kola se natáčí rychlostí `steer_speed` z auta.
2. **Podélně:** chtěná rychlost `want` = `speed_mps.cruise` (městské tempo, v2: 14 m/s), s boostem `top`.
   Bez vstupu plyn do `want`, síla `power · (1 − (v/top)²)` na zadní nápravě; nad `want` + `overspeed_mps`
   brzdí `engine_brake_mps2`; brzda nad `brake_min_mps` = `brake`, pod ní couvání
   `power · reverse_power` do `reverse_max_mps`.
   **Držení tempa (v2):** při automatickém plynu (`throttle` = 0, `brake` = 0, bez boostu, ruční brzdy
   a `coast`) na zemi a při `v ≥ want` motor navíc ruší složku síly svahu ve směru jízdy:
   `hold = clamp(a_svah · směr, 0, cruise_hold_mps2)` (`a_svah` ze `specs/terrain.md` „Svah“ ze stejného
   kroku, na rovině a v balíčku bez výšek 0) a zrychlení motoru je `−hold` (v pásmu `want … want + overspeed`)
   nebo `−engine_brake_mps2 − hold` (nad pásmem). Z kopce tak auto drží `want` a nerozjíždí se; do kopce
   se nic nemění (složka je záporná, `hold` = 0; výkon motoru je omezen `power`).
3. **Ruční brzda:** zpomalení `handbrake_decel_mps2`, nad `handbrake_min_mps` úhlový impuls
   `−steer · I · handbrake_yaw · min(v / handbrake_yaw_ref_mps, handbrake_yaw_max) · dt`; zadní grip × `drift_bias`.
4. **Odpor:** `m · (drag_linear + drag_quadratic · |v|) · v`.
5. **Pneumatiky:** na každé nápravě (vzdálenost `axle_offset · půldélky`) zrušit boční rychlost impulsem
   omezeným `grip · m/2 · dt`; přebytek = smyk.
6. **Vrstvy:** auto přejde jen na hranu sdílející uzel s aktuální (do `width/2 + layers.switch_margin_m`);
   jinak hledá hranu ve stejné vrstvě. Ve vrstvě ≠ 0 drží auto zábradlí (`rail_margin`, `rail_bounce`), budovy
   kolidují jen ve vrstvě 0.

## Změny verzí
- v2: `speed_mps.cruise` 25 → 14 m/s (bez vstupu auto jezdí městským tempem, rychleji jen s boostem do
  `top`), držení tempa z kopce (`drive.cruise_hold_mps2`). Scénáře `flow`, `nature` a `terrain`, které
  jedou automatickým plynem, se nahrály znovu (vede W).

## Scénáře (D1, nahraje F)
Rozjezd na cestovní rychlost, maximální rychlost, brzdná dráha, poloměr ustáleného zatáčení při 15 m/s,
úhel driftu po ruční brzdě při 20 m/s, čas kola na testovací dráze.
