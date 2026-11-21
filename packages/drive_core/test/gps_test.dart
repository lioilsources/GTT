import 'dart:io';
import 'dart:typed_data';

import 'package:drive_core/drive_core.dart';
import 'package:rules_core/vector_test_support.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:world_engine/core.dart';

void main() {
  final tuning = Tuning.fromYaml(File('../../content/tuning.yaml').readAsStringSync());
  final cost = tuning.route.classCost;

  test('polyline length uses floor(sqrt) per segment', () {
    expect(polylineDm([0, 0, 3, 4, 3, 5]), 6);
  });

  test('one-ways, alleys and the same node', () {
    final g = RouteGraph.fromConfig({
      'nodes': [0, 0, 100, 0, 200, 0],
      'edges': [
        [0, 1, 3, 0, 1, 0, 0, 100, 0],
        [1, 2, 3, 1, 1, 100, 0, 200, 0],
        [0, 2, 3, 0, 0, 0, 0, 200, 0],
      ],
      'classCost': cost,
    });
    expect(findRoute(g, 0, 2).toJson(), {
      'cost': 200 * cost[3],
      'nodes': [0, 1, 2],
      'edges': [0, 1],
    });
    expect(findRoute(g, 2, 0).cost, -1);
    expect(findRoute(g, 1, 1).nodes, [1]);
  });

  final vectors = File('$repoRoot/vectors/route.json').existsSync();
  test(
    'vectors/route.json',
    () => expect(checkVectors(RouteRules()), isEmpty),
    skip: !vectors || !flutterDone('vectors/route.json') ? 'pending in parity.yaml' : false,
  );

  final pack = Directory('../../build/packs/nyc');
  test('every NYC spot is reachable from the first one', () async {
    final city = await City.load(_FilePack('${pack.path}/'));
    final g = RouteGraph.fromPb(city.graphPb, cost);
    final a = city.graphPb.edges[city.spots.items.first.edge];
    for (final s in city.spots.items) {
      final b = city.graphPb.edges[s.edge];
      var r = findRoute(g, a.to, b.from);
      if (r.cost < 0) r = findRoute(g, a.to, b.to);
      expect(r.cost, greaterThanOrEqualTo(0), reason: s.id);
    }
  }, skip: pack.existsSync() ? false : 'no pack');
}

class _FilePack implements PackSource {
  _FilePack(this.root);
  final String root;
  @override
  Future<Uint8List> read(String path) async => File('$root$path').readAsBytes();
}
