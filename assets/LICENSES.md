# Licence assetů

Všechny assety v `assets/` jsou vlastní generování (bez cizích obrázků jako vstupu), pokud níže
není uvedeno jinak. Reprodukce: `tools/art/` (prompty, seedy, parametry workflow ComfyUI).

| Cesta | Model / nástroj | Licence modelu | Licence výstupu | Poznámka |
|---|---|---|---|---|
| `npc/*.png` | Qwen-Image (fp8), text encoder Qwen2.5-VL 7B, ComfyUI | Apache 2.0 | vlastní dílo projektu GTT | várka 1, 22. 11. 2026, seedy 101–106 (jeden na postavu) |
| `npc/*.png` (alfa) | BiRefNet-general přes ComfyUI-RMBG | MIT | vlastní dílo projektu GTT | odstranění pozadí, refine_foreground |
| `postcards/nyc/*.png` | Qwen-Image (fp8), ComfyUI | Apache 2.0 | vlastní dílo projektu GTT | várka 1, seed 201 (carnegie_hall 203, federal_hall a met_museum 202), styl A, ořez 1080×1350, 256 barev |
| `postcards/prague/*.png` | Qwen-Image (fp8), ComfyUI | Apache 2.0 | vlastní dílo projektu GTT | várka 1, seed 201, styl C, ořez 1080×1350, 256 barev |
| `postcards/nyc/{guggenheim,msg}.png` | Qwen-Image (fp8), ComfyUI | Apache 2.0 | vlastní dílo projektu GTT | oprava 2, seed 214 (guggenheim) a 211 (msg), styl A, `tools/art/make_fix2.py` |
| `postcards/prague/old_new_synagogue.png` | Qwen-Image (fp8), ComfyUI | Apache 2.0 | vlastní dílo projektu GTT | oprava 2, seed 214, styl C, nápis v okraji papíru přebarven (`tools/art/post_fix2.py`) |
| `postcards/nyc/amnh.png` | Qwen-Image (fp8), ComfyUI | Apache 2.0 | vlastní dílo projektu GTT | oprava 3, seed 221 (`tools/art/make_fix3.py`), styl A, štít bez nápisu, podpis v rohu přebarven (`tools/art/post_fix3.py`) |
| `cars/lidovka/*.png` | vlastní skript (`tools/art/cars_proc.py`, PIL) | – | vlastní dílo projektu GTT | dávka cars2, procedurální vektor kolmo shora (nahrazuje body.png z opravy 1, Qwen-Image), 57×148 |
| `cars/{m0_coupe,taxi_metro,hatch_pip,sedan_harbor,sedan_crown,van_courier,mini_pebble,pickup_hauler,muscle_brute,traffic_sedan,police_patrol}/*.png` | vlastní skript (`tools/art/cars_proc.py`, PIL) | – | vlastní dílo projektu GTT | dávka cars1, procedurální vektor kolmo shora, bez modelu; siluety podle `specs/cars.md`, fiktivní tvary bez značek |
| `cars/<id>/*.png` (dávka 2: zbylých 33 aut z `docs/art-requests.md` kap. 3) | vlastní skript (`tools/art/cars_proc.py`, PIL) | – | vlastní dílo projektu GTT | dávka cars2, procedurální vektor kolmo shora, bez modelu; jezdci mikro a rikši stylizovaní dospělí bez rysů |
| `ui/*.png` (15 ikon HUD a telefonu) | vlastní skript (`tools/art/ui_icons.py`, PIL) | – | vlastní dílo projektu GTT | dávka ui1, procedurální plochý vektor, bílý glyf na alfě 256², tónovatelný, bez textu a značek |
| `garage/{decals,wheels}/*.png` (8 polepů, 6 kol) | vlastní skript (`tools/art/garage_cosmetics.py`, PIL) | – | vlastní dílo projektu GTT | dávka garage1, procedurální vektor; polepy bílý motiv na alfě 512×1024, kola 128² se světlým diskem, tónovatelné |
| `souvenirs/*.png` | Qwen-Image (fp8), ComfyUI + BiRefNet-general | Apache 2.0 / MIT | vlastní dílo projektu GTT | suvenýry 1, seedy 601–604 (`tools/art/make_souv1.py`), výběr a ořez 512² (`tools/art/post_souv.py`) |

Nepoužívat pro herní assety: modely s nekomerční licencí (např. FLUX.1-dev, RMBG-2.0) a modely
s omezující licencí (Illustrious-XL).

## Textury měst

| Cesta | Model / nástroj | Licence modelu | Licence výstupu | Poznámka |
|---|---|---|---|---|
| `cities/prague/{cobblestone,mosaic_sidewalk,roof_tiles}.png` | Qwen-Image (fp8), ComfyUI | Apache 2.0 | vlastní dílo projektu GTT | dávka tex1, seedy 403, 401, 402 (`tools/art/make_tex1.py`), 512², bezešvé (roll + prolnutí) |
| `cities/nyc/asphalt.png` | Qwen-Image (fp8), ComfyUI | Apache 2.0 | vlastní dílo projektu GTT | oprava 2, seed 413 (`tools/art/make_fix2.py`), 512², bezešvé (`tools/art/post_fix2.py`) |
| `cities/nyc/{sidewalk_concrete,roof_tar}.png` | vlastní skript (`tools/art/proc_tex.py`, numpy) | – | vlastní dílo projektu GTT | procedurální, bez modelu, seedy 511 a 512, 512² bezešvé |
| `cities/tokyo/{asphalt,sidewalk_tile,roof}.png` | vlastní skript (`tools/art/proc_tex_tokyo.py`, numpy) | – | vlastní dílo projektu GTT | procedurální, bez modelu, seedy 521–523, 512² bezešvé |

## Tokio (styl D, anime cel)

| Cesta | Model / nástroj | Licence modelu | Licence výstupu | Poznámka |
|---|---|---|---|---|
| `styleboard/tokyo/*.png` | Qwen-Image (fp8), ComfyUI | Apache 2.0 | vlastní dílo projektu GTT | kontrola stylu, seedy 11, 12 (`tools/art/make_tokyo1.py style`) |
| `postcards/tokyo/*.png` | Qwen-Image (fp8), ComfyUI | Apache 2.0 | vlastní dílo projektu GTT | várky tokyo3 (seedy 221–223) a tokyo4 (seedy 231–233, `tools/art/make_tokyo1.py`), výběr a ploché přebarvení zbylých falešných nápisů na štítech, cedulkách a lampionech (`tools/art/post_tokyo.py`), ořez 1080×1350, 256 barev |
