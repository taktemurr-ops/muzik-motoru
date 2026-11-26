import 'package:flutter_test/flutter_test.dart';
import 'package:muzik_motoru/muzik_motoru.dart';
import 'package:muzik_motoru/src/kinds/ek4.dart';
import 'package:muzik_motoru/src/texts_ek4.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/core/rng.dart';

void main() {
  test('4. tur müzik metinleri 33 dilde', () {
    for (final e in kMuzikTexts4.entries) {
      expect(e.value.length, 33, reason: e.key);
      expect(e.value.every((s) => s.trim().isNotEmpty), isTrue, reason: e.key);
    }
  });

  test('usul ve tala devirleri geçerli', () {
    final names = <String>{};
    for (final u in kUsuls) {
      expect(names.add(u.name), isTrue, reason: u.name);
      expect(RegExp(r'^[DTK.]+$').hasMatch(u.strokes), isTrue, reason: u.name);
      expect(u.strokes[0], isNot('.'), reason: u.name);
      expect(u.region, inInclusiveRange(0, 2));
      if (u.bols.isNotEmpty) {
        expect(u.bols.replaceAll('|', ' ').split(' ').where((s) => s.isNotEmpty).length, u.n, reason: u.name);
      }
    }
    for (var r = 0; r < 3; r++) {
      expect(kUsuls.where((u) => u.region == r).length, greaterThanOrEqualTo(5));
    }
  });

  test('kalimba ve gamelan sesleri üretilir', () {
    expect(kalimbaPcm(kalFreq(0, 0)).length, greaterThan(1000));
    expect(gamelanPcm(kalFreq(1, 3)).length, greaterThan(1000));
    for (final instr in [0, 1, 2]) {
      for (var k = 1; k < kalKeys(instr); k++) {
        expect(kalFreq(instr, k), greaterThan(kalFreq(instr, k - 1)));
      }
    }
  });

  test('100.000 bölümün geniş örneklemi kurulur ve doğrulanır', () {
    for (final k in ['ritim-kosusu', 'usul-tala', 'kalimba-gamelan', 'melodi-bulmacasi']) {
      final rules = muzikRulesFor('oyun-test-$k', k);
      expect(rules.levelCount, 100000);
      final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: const []);
      final r = SeededRandom(91);
      for (var i = 0; i < 300; i++) {
        final n = 1 + r.nextInt(100000);
        expect(rules.build(planner.spec(n)).validation.ok, isTrue, reason: '$k $n');
      }
    }
  });
}
