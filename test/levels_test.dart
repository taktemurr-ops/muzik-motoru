import 'package:flutter_test/flutter_test.dart';
import 'package:muzik_motoru/muzik_motoru.dart';
import 'package:studio_core/core/level_plan.dart';

void main() {
  for (final e in kMuzikKinds.entries) {
    test('${e.key}: bölümler kurulur ve doğrulanır', () {
      final rules = muzikRulesFor('oyun-test-${e.key}', e.key);
      final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: const []);
      for (final n in const [1, 2, 7, 40, 300, 5000, 33333, 99999]) {
        expect(rules.build(planner.spec(n)).validation.ok, isTrue, reason: '${e.key} $n');
      }
    });
  }

  test('telifsiz ezgiler çözümlenir ve 1929 öncesidir', () {
    for (final t in kPdTunes) {
      expect(t.year < 1929, isTrue, reason: t.id);
      final m = parseTune(t.notes);
      expect(m.length >= 8, isTrue, reason: t.id);
    }
  });

  test('metinler 33 dilde', () {
    for (final e in kMuzikTexts.entries) {
      expect(e.value.length, 33, reason: e.key);
    }
  });
}
