// Onaylı tasarım: motorun her türü merkez benzeri ev sahibinde (koyu palet)
// açılır; oyun içi yazılar ve dokunuşla açılan pencereler okunur (3:1).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzik_motoru/muzik_motoru.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:studio_core/core/level_plan.dart';

import 'studio_readability.dart';
import 'views_test.dart' show fakeCtx;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final e in kMuzikKinds.entries) {
    testWidgets('${e.key}: onaylı koyu tasarımda yazılar ve pencereler okunur', (tester) async {
      tester.view.physicalSize = const Size(1080, 2280);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      final rules = muzikRulesFor('oyun-test-${e.key}', e.key);
      final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: const []);
      final gl = rules.build(planner.spec(5));
      await tester.pumpWidget(studioHost(MuzikStage(ctx: fakeCtx(gl, 'tr', []), rules: rules)));
      await tester.pump(const Duration(milliseconds: 400));
      final issues = await sweepReadability(tester, e.key);
      expect(issues, isEmpty, reason: 'Okunmayan yazı (${e.key}): ${issues.join('; ')}');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    });
  }

  testWidgets('araç sayfaları (metronom, serbest çalgı, ayarlar) onaylı koyu tasarımda okunur', (tester) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final rules = muzikRulesFor('oyun-test-araclar', 'nota-karolari');
    final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: const []);
    final gl = rules.build(planner.spec(3));
    await tester.pumpWidget(studioHost(MuzikStage(ctx: fakeCtx(gl, 'tr', []), rules: rules)));
    await tester.pump(const Duration(milliseconds: 300));
    for (final icon in const [Icons.av_timer, Icons.piano, Icons.tune]) {
      await tester.tap(find.byIcon(icon).first);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(BottomSheet), findsOneWidget);
      expectReadable(tester, where: 'araç sayfası $icon');
      await tester.tapAt(const Offset(5, 5));
      await tester.pump(const Duration(milliseconds: 600));
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 8));
  });
}
