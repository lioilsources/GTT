# Licence assetů

Všechny assety v `assets/` jsou vlastní generování (bez cizích obrázků jako vstupu), pokud níže
není uvedeno jinak. Reprodukce: `tools/art/` (prompty, seedy, parametry workflow ComfyUI).

| Cesta | Model / nástroj | Licence modelu | Licence výstupu | Poznámka |
|---|---|---|---|---|
| `npc/*.png` | Qwen-Image (fp8), text encoder Qwen2.5-VL 7B, ComfyUI | Apache 2.0 | vlastní dílo projektu GTT | várka 1, 22. 11. 2026, seedy 101–106 (jeden na postavu) |
| `npc/*.png` (alfa) | BiRefNet-general přes ComfyUI-RMBG | MIT | vlastní dílo projektu GTT | odstranění pozadí, refine_foreground |
| `postcards/nyc/*.png` | Qwen-Image (fp8), ComfyUI | Apache 2.0 | vlastní dílo projektu GTT | várka 1, seed 201 (carnegie_hall 203, federal_hall a met_museum 202), styl A, ořez 1080×1350, 256 barev |
| `postcards/prague/*.png` | Qwen-Image (fp8), ComfyUI | Apache 2.0 | vlastní dílo projektu GTT | várka 1, seed 201, styl C, ořez 1080×1350, 256 barev |

Nepoužívat pro herní assety: modely s nekomerční licencí (např. FLUX.1-dev, RMBG-2.0) a modely
s omezující licencí (Illustrious-XL).
