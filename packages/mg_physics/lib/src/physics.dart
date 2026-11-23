import 'dart:math' as math;

/// Integer minigame physics, specs/minigames/fyzika.md version 1, shared by kulecnik, bowling and
/// minigolf (full world) and cihly, hokej (arithmetic and closest point). P0: integers only, every
/// formula rounds exactly as the spec says, so both clients move bodies bit for bit alike.
const physicsSpecVersion = 1;

/// Quotient rounded toward zero (Dart ints have no −0).
int trunc(int a, int b) => a ~/ b;

/// Largest s with s² ≤ n (n ≥ 0), exact.
int isqrt(int n) {
  if (n <= 0) return 0;
  var s = math.sqrt(n.toDouble()).floor();
  while (s * s > n) {
    s--;
  }
  while ((s + 1) * (s + 1) <= n) {
    s++;
  }
  return s;
}

int clampInt(int v, int lo, int hi) => math.min(math.max(v, lo), hi);

/// A moving body: centre, velocity (u per step), radius, mass ≥ 1, [on] while in play.
class Body {
  Body({required this.x, required this.y, this.vx = 0, this.vy = 0, required this.r, this.m = 1, this.on = true});

  int x, y, vx, vy;
  final int r, m;
  bool on;
}

/// A static rectangle [x0, x1] × [y0, y1] or circle (cx, cy, r) with restitution [e] (per mille).
sealed class Static {
  const Static(this.e);

  final int e;
}

class RectStatic extends Static {
  const RectStatic(this.x0, this.y0, this.x1, this.y1, int e) : super(e);

  final int x0, y0, x1, y1;
}

class CircleStatic extends Static {
  const CircleStatic(this.cx, this.cy, this.r, int e) : super(e);

  final int cx, cy, r;
}

/// A game's world: bodies, statics in the game's order and the game's hooks.
class World {
  World({
    required this.bodies,
    required this.statics,
    required this.eBody,
    required this.dec,
    this.capture,
    this.onHit,
  });

  final List<Body> bodies;
  final List<Static> statics;

  /// Restitution of a body–body pair (per mille).
  final int eBody;

  /// Step 5: deceleration of body i (may depend on where it is).
  final int Function(int i, Body b) dec;

  /// Step 2: may switch bodies off (pockets, goals, water); true ends the simulation now.
  final bool Function(World w)? capture;

  /// Step 3: called for each pair that collided (0 < d2 < R², vn < 0).
  final void Function(int i, int j)? onHit;
}

void off(Body b) {
  b.on = false;
  b.vx = 0;
  b.vy = 0;
}

/// Body–body collision ("Srážka dvou těles"); true when it happened (0 < d2 < R² and vn < 0).
bool collideBodies(Body a, Body b, int e) {
  final dx = b.x - a.x, dy = b.y - a.y;
  final d2 = dx * dx + dy * dy;
  final rr = a.r + b.r;
  if (d2 >= rr * rr || d2 == 0) return false;
  final vn = (b.vx - a.vx) * dx + (b.vy - a.vy) * dy;
  if (vn >= 0) return false;
  final k = trunc(vn * (1000 + e) * 1000, (a.m + b.m) * d2);
  a.vx += trunc(k * b.m * dx, 1000000);
  a.vy += trunc(k * b.m * dy, 1000000);
  b.vx -= trunc(k * a.m * dx, 1000000);
  b.vy -= trunc(k * a.m * dy, 1000000);
  return true;
}

/// Closest point of a static to (x, y).
({int x, int y}) closest(Static s, int x, int y) => switch (s) {
  RectStatic() => (x: clampInt(x, s.x0, s.x1), y: clampInt(y, s.y0, s.y1)),
  CircleStatic() => (x: s.cx, y: s.cy),
};

/// Body–static collision ("Srážka se statikou").
void collideStatic(Body b, Static s) {
  final q = closest(s, b.x, b.y);
  final dx = b.x - q.x, dy = b.y - q.y;
  final d2 = dx * dx + dy * dy;
  final reach = switch (s) {
    RectStatic() => b.r,
    CircleStatic() => b.r + s.r,
  };
  if (d2 <= 0 || d2 >= reach * reach) return;
  final vn = b.vx * dx + b.vy * dy;
  if (vn >= 0) return;
  final k = trunc(vn * (1000 + s.e) * 1000, d2);
  b.vx -= trunc(k * dx, 1000000);
  b.vy -= trunc(k * dy, 1000000);
}

/// Friction ("Tření") with deceleration [dec] ≥ 0.
void friction(Body b, int dec) {
  final s = isqrt(b.vx * b.vx + b.vy * b.vy);
  if (s <= dec) {
    b.vx = 0;
    b.vy = 0;
    return;
  }
  b.vx -= trunc(b.vx * dec, s);
  b.vy -= trunc(b.vy * dec, s);
}

/// One step in the fixed order: move, capture, body–body, statics, friction. True when capture
/// ended the simulation (steps 3–5 are then skipped).
bool step(World w) {
  final bs = w.bodies;
  for (final b in bs) {
    if (!b.on) continue;
    b.x += b.vx;
    b.y += b.vy;
  }
  final cap = w.capture;
  if (cap != null && cap(w)) return true;
  for (var i = 0; i < bs.length; i++) {
    for (var j = i + 1; j < bs.length; j++) {
      final a = bs[i], b = bs[j];
      if (!a.on || !b.on) continue;
      if (collideBodies(a, b, w.eBody)) w.onHit?.call(i, j);
    }
  }
  for (final b in bs) {
    if (!b.on) continue;
    for (final s in w.statics) {
      collideStatic(b, s);
    }
  }
  for (var i = 0; i < bs.length; i++) {
    final b = bs[i];
    if (b.on) friction(b, w.dec(i, b));
  }
  return false;
}

bool moving(World w) => w.bodies.any((b) => b.on && (b.vx != 0 || b.vy != 0));

/// "Konec simulace úderu": checks for motion before every step (also the first), at most
/// [maxSteps]; leftover velocities are zeroed. [onStep] (UI) sees the world after each whole step.
({int steps, bool captured}) simulate(World w, int maxSteps, {void Function(World w)? onStep}) {
  var n = 0;
  var captured = false;
  while (n < maxSteps && moving(w)) {
    captured = step(w);
    n++;
    onStep?.call(w);
    if (captured) break;
  }
  for (final b in w.bodies) {
    b.vx = 0;
    b.vy = 0;
  }
  return (steps: n, captured: captured);
}

/// "Úder": velocity of speed [sp] from (x, y) towards (ax, ay); null when the aim is the centre.
({int vx, int vy})? shotVelocity(int x, int y, int ax, int ay, int sp) {
  final dx = ax - x, dy = ay - y;
  final l = isqrt(dx * dx + dy * dy);
  if (l == 0) return null;
  return (vx: trunc(sp * dx, l), vy: trunc(sp * dy, l));
}

const aimR = 100000;

/// "Normované míření": the aim point moved to [aimR] from (x, y); null when L = 0.
({int x, int y})? normalizedAim(int x, int y, int ax, int ay) {
  final dx = ax - x, dy = ay - y;
  final l = isqrt(dx * dx + dy * dy);
  if (l == 0) return null;
  return (x: x + trunc(dx * aimR, l), y: y + trunc(dy * aimR, l));
}
