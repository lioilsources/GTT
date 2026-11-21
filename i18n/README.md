# Texty

`<locale>.json` je jediný zdroj textů obou klientů. Šablona je `en.json` (s `@klíč` metadaty
placeholderů ve formátu ARB); ostatní jazyky mají stejné klíče a stejné `{placeholdery}`.
`metro gen` z nich dělá ARB pro Flutter (`packages/shared_gen/l10n`) a `web/src/gen/i18n.ts`.
