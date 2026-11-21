/// Shared PRNG (specs/prng.md, version 1): xorshift32 with rejection sampling.
/// Bit-identical to web/src/rules/prng.ts; checked by vectors/prng.json.
class Prng {
  Prng(int seed) : _x = (seed & _mask) == 0 ? 0x9E3779B9 : seed & _mask;

  static const _mask = 0xFFFFFFFF;
  int _x;

  /// Current generator state (uint32).
  int get state => _x;

  int nextU32() {
    var x = _x;
    x ^= (x << 13) & _mask;
    x ^= x >> 17;
    x ^= (x << 5) & _mask;
    _x = x;
    return x;
  }

  /// Uniform integer in [0, n).
  int nextInt(int n) {
    if (n < 1 || n > 0x100000000) throw RangeError.value(n, 'n');
    final limit = (0x100000000 ~/ n) * n;
    while (true) {
      final r = nextU32();
      if (r < limit) return r % n;
    }
  }

  /// Fisher–Yates in place; returns the same list.
  List<T> shuffle<T>(List<T> a) {
    for (var i = a.length - 1; i >= 1; i--) {
      final j = nextInt(i + 1);
      final t = a[i];
      a[i] = a[j];
      a[j] = t;
    }
    return a;
  }
}
