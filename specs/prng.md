# PRNG – společný generátor náhodných čísel

**version: 1** · úroveň parity P0 · vektory `vectors/prng.json`

## Účel

Jediný zdroj náhody pro všechna pravidla P0 (rozdávání, kostky, AI). Oba klienti z téhož
`seed` vyrobí stejnou posloupnost bit po bitu.

## Stav

`x: uint32`, nikdy nula. Seed se převede na uint32 (`seed mod 2^32`); seed 0 se nahradí `0x9E3779B9`.

## Operace

```
nextU32():  x ^= x << 13;  x ^= x >>> 17;  x ^= x << 5;  vrať x     // vše na 32 bitech
nextInt(n): limit = floor(2^32 / n) * n;  opakuj r = nextU32() dokud r >= limit;  vrať r mod n
shuffle(a): pro i od délka-1 dolů do 1:  j = nextInt(i + 1);  prohoď a[i], a[j]
```

- Dart: po každém posunu doleva maskuj `& 0xFFFFFFFF`.
- TypeScript: po každém kroku `>>> 0`; `limit` počítej v `number` (2^32 je přesné).
- `nextInt(n)` pro `n < 1` nebo `n > 2^32` je chyba.
- `shuffle` mění pole na místě a vrací ho.

## Pravidla determinismu

- žádná desetinná čísla, žádný čas, žádné řazení závislé na jazyce
- jedna instance na partii; pořadí volání je součást pravidel modulu, který PRNG používá

## Hraniční případy

- seed 0 → `0x9E3779B9`
- `nextInt(1)` vrací vždy 0 a spotřebuje jedno `nextU32()`
