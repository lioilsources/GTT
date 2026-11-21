# Release appky (klient F)

Pipeline je převzatá z Distribution (golden šablony), upravená pro monorepo:
`release-ios.yml` a `release-android.yml` místo vlastní instalace Flutteru používají
`.github/actions/setup-shared` (stejný Flutter jako CI) a před buildem pustí
`citypack pull all` + `metro sync`, aby appka měla balíček NYC v `app/assets/shared/`.
Golden `ci.yml` se nepoužívá, jeho roli má `flutter.yml`.

| | |
|---|---|
| Bundle id / applicationId | `com.ol1n.metropole` |
| Jméno ve storech | Metropole |
| Složka v Distribution | `Apple/Metropole/`, `Android/Metropole/` |
| Spuštění | tag `v*` (např. `v0.1.0`) nebo ručně `workflow_dispatch` |
| iOS výstup | TestFlight + IPA v GitHub Release |
| Android výstup | Firebase App Distribution (skupina `Alfa`) + AAB/APK v GitHub Release |

## Ruční kroky (jednou)

### Apple
1. developer.apple.com → Identifiers: App ID `com.ol1n.metropole` (bez zvláštních capabilities).
2. Profiles: **App Store** distribuční profil pro `com.ol1n.metropole`; stáhnout do
   `Distribution/Apple/Metropole/` (jediný `*.mobileprovision` ve složce).
3. App Store Connect → Apps → New App: název Metropole, bundle `com.ol1n.metropole`, SKU `metropole`.
   - Privacy Policy URL: `https://lioilsources.github.io/GTT/privacy.html`
   - Support URL: `https://lioilsources.github.io/GTT/support.html`
   - Marketing URL: `https://olin.now/metropole`
4. TestFlight → interní testeři (vlastní účet).

### Firebase (Android)
1. Firebase konzole → projekt pro appky → Add app → Android, package `com.ol1n.metropole`.
2. Stáhnout `google-services.json` do `Distribution/Android/Metropole/`
   (do repa nepatří; appka Firebase SDK nepoužívá, slouží jen pro App Distribution app id).
3. App Distribution → skupina `Alfa` existuje / přidat testery.

### Secrets v GitHubu
```bash
Distribution/scripts/setup-gh-secrets.sh --repo lioilsources/GTT --app Metropole
```
Vytvoří i Android upload keystore (`Android/Metropole/upload-keystore.jks`), pokud ještě není,
a heslo uloží do Bitwardenu.

## Vydání
```bash
git tag v0.1.0 && git push origin v0.1.0
```
Verze se bere z tagu, build number z čísla běhu. Postup a kontrola: skill `release-flutter`.

## Lokálně
- iOS Release konfigurace je ruční podpis s `CI_PROFILE_NAME` (CI dosadí UUID profilu);
  na telefon proto lokálně `flutter run --profile` (Debug/Profile podepisuje Automatic).
- Android release bez `android/key.properties` podepisuje debug klíčem.
