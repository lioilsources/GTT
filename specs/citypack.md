# Citypack – formát balíčku města

**version: 1** · P0 · schéma `tools/citypack/proto/citypack.proto` (`format_version` 1)

## Účel
Jeden balíček města, který čtou oba klienti. Staví ho `citypack` (Go), čte F (`world_engine`) i W.

## Stav (soubory)
`manifest.pb`, `graph.pb`, `chunks/{x}_{y}.pb`, `landmarks.pb`, `spots.pb` – každý gzip protobuf.
Souřadnice: metry lokální rovinné projekce od `origin` (x = Δlon·cos(lat0)·R, y = Δlat·R, y na sever,
R = 6 371 008,8 m), v souborech decimetry `sint32`. Ploché seznamy `x0, y0, x1, y1, …`.

## Pravidla čtení
- `format_version` ≠ 1 → odmítnout balíček.
- Chunk (x, y) pokrývá [x·chunk_m, (x+1)·chunk_m) × [y·chunk_m, (y+1)·chunk_m).
- Budova: prstence za sebou, `ring_ends` = výhradní konce; prstenec 0 vnější (CCW), díry CW;
  `roof` = trojúhelníky do vrcholů všech prstenců; `min_height_m` > 0 = stohovaná část.
- Hrana: `points` včetně obou uzlů; `oneway` 1 = jen from→to, −1 = jen to→from; `kept` = provoz a GPS,
  jinak průjezdná ulička; vrstva v bodě t (0..1) = `layer_from`, pro t ≥ 0,5 `layer_to`.
- Země: `Mesh` = trojúhelníky jednoho druhu (`GroundKind`).

## Hraniční případy
- Uzel s `border` = silnice opouští oblast, kreslí se uzavírka.
- Chunk z manifestu, který nejde načíst, nesmí zastavit hru (zkusí se znovu po `streaming.retry_s`).

## Vektory
P0 kontrola dekódování: oba klienti musí z `build/packs/nyc` dostat stejné počty uzlů, hran, chunků,
budov a stejný start (D1).
