# Jízda – model auta (M0)

**version: 1** · P1 (±5 %) · scénáře `scenarios/drive/`

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
2. **Podélně:** bez vstupu plyn do `speed_mps.cruise` (boost do `top`), síla `power · (1 − (v/top)²)` na zadní nápravě;
   nad cílem + `overspeed_mps` brzdí `engine_brake_mps2`; brzda nad `brake_min_mps` = `brake`, pod ní couvání
   `power · reverse_power` do `reverse_max_mps`.
3. **Ruční brzda:** zpomalení `handbrake_decel_mps2`, nad `handbrake_min_mps` úhlový impuls
   `−steer · I · handbrake_yaw · min(v / handbrake_yaw_ref_mps, handbrake_yaw_max) · dt`; zadní grip × `drift_bias`.
4. **Odpor:** `m · (drag_linear + drag_quadratic · |v|) · v`.
5. **Pneumatiky:** na každé nápravě (vzdálenost `axle_offset · půldélky`) zrušit boční rychlost impulsem
   omezeným `grip · m/2 · dt`; přebytek = smyk.
6. **Vrstvy:** auto přejde jen na hranu sdílející uzel s aktuální (do `width/2 + layers.switch_margin_m`);
   jinak hledá hranu ve stejné vrstvě. Ve vrstvě ≠ 0 drží auto zábradlí (`rail_margin`, `rail_bounce`), budovy
   kolidují jen ve vrstvě 0.

## Scénáře (D1, nahraje F)
Rozjezd na cestovní rychlost, maximální rychlost, brzdná dráha, poloměr ustáleného zatáčení při 15 m/s,
úhel driftu po ruční brzdě při 20 m/s, čas kola na testovací dráze.
