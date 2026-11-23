import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzik_motoru/muzik_motoru.dart';
import 'package:studio_core/app/game_api.dart';
import 'package:studio_core/core/game_rules.dart';
import 'package:studio_core/core/level_plan.dart';

PlayContext fakeCtx(GeneratedLevel gl, String lang, List<RoundResult> results) => PlayContext(
      spec: gl.spec,
      generated: gl,
      resume: const {},
      pieceColors: const [Color(0xFF3E6FB0), Color(0xFFC8553D), Color(0xFF4F9A6E)],
      background: const [Color(0xFF203040), Color(0xFF304050)],
      colorBlind: false,
      reducedMotion: false,
      leftHanded: false,
      lang: lang,
      t: (k, [p = const {}]) => k,
      finish: results.add,
      saveResume: (_) {},
      requestHint: () async => true,
      requestBooster: () async => true,
      requestContinue: () async => false,
      sfx: (_) {},
    );

void main() {
  for (final e in kMuzikKinds.entries) {
    for (final lang in const ['tr', 'en', 'ar']) {
      testWidgets('${e.key} ($lang): ekran açılır, oynanır, dokunuşlara dayanır', (tester) async {
        tester.view.physicalSize = const Size(1080, 2280);
        tester.view.devicePixelRatio = 2.75;
        addTearDown(tester.view.reset);
        final rules = muzikRulesFor('oyun-test-${e.key}', e.key);
        final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: const []);
        final gl = rules.build(planner.spec(5));
        final results = <RoundResult>[];
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: SafeArea(child: MuzikStage(ctx: fakeCtx(gl, lang, results), rules: rules))),
        ));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        // Başlat / Dinle düğmesine bas.
        for (final icon in const [Icons.play_arrow, Icons.headphones]) {
          final f = find.byIcon(icon);
          if (f.evaluate().isNotEmpty) {
            await tester.tap(f.first);
            await tester.pump(const Duration(milliseconds: 200));
          }
        }
        final size = tester.view.physicalSize / tester.view.devicePixelRatio;
        for (var k = 0; k < 3; k++) {
          for (var y = 120.0; y < size.height - 10; y += size.height / 8) {
            for (var x = 20.0; x < size.width; x += size.width / 5) {
              await tester.tapAt(Offset(x, y));
              await tester.pump(const Duration(milliseconds: 90));
            }
          }
          await tester.pump(const Duration(seconds: 1));
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      });
    }
  }

  testWidgets('araçlar: metronom, serbest çalgı, ayarlar açılır', (tester) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final rules = muzikRulesFor('oyun-test-araclar', 'nota-karolari');
    final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: const []);
    final gl = rules.build(planner.spec(3));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SafeArea(child: MuzikStage(ctx: fakeCtx(gl, 'tr', []), rules: rules))),
    ));
    await tester.pump(const Duration(milliseconds: 200));
    for (final icon in const [Icons.av_timer, Icons.piano, Icons.tune]) {
      await tester.tap(find.byIcon(icon).first);
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      // Sayfadaki bazı düğmelere dokun.
      final size = tester.view.physicalSize / tester.view.devicePixelRatio;
      for (var y = size.height * 0.4; y < size.height - 10; y += size.height / 10) {
        for (var x = 30.0; x < size.width; x += size.width / 4) {
          await tester.tapAt(Offset(x, y));
          await tester.pump(const Duration(milliseconds: 80));
        }
      }
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
      // Sayfayı kapat.
      await tester.tapAt(const Offset(5, 5));
      await tester.pump(const Duration(milliseconds: 600));
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 8));
  });
}
