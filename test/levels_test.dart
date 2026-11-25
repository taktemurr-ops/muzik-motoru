import 'dart:math' as math;
import 'dart:typed_data';

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

  test('ritim diktesi: kalıplar farklı duyulur, bağ kuralı', () {
    final sigs = {for (final c in kRCells) if (c.id != 'h') rdictSignature([c.id])};
    expect(sigs.length, kRCells.length - 1);
    expect(rdictValid(['q', 'h']), isTrue);
    expect(rdictValid(['r', 'h']), isFalse);
    expect(rdictValid(['h', 'q']), isFalse);
    expect(rdictValid(['er', 'h']), isFalse);
    expect(rdictCells(10).length, kRCells.length);
  });

  test('ton tutma: perde bulucu ve oktav katlama', () {
    for (final hz in const [110.0, 196.0, 261.63, 440.0, 659.25]) {
      const rate = 22050;
      final x = Float64List.fromList([for (var i = 0; i < 1536; i++) 0.4 * math.sin(2 * math.pi * hz * i / rate) + 0.1 * math.sin(4 * math.pi * hz * i / rate)]);
      final f = detectPitch(x, rate);
      expect(f, isNotNull, reason: '$hz');
      expect((hzToMidi(f!) - hzToMidi(hz)).abs() < 0.1, isTrue, reason: '$hz -> $f');
    }
    expect(detectPitch(Float64List(1536), 22050), isNull);
    expect(pitchCents(72, 60, anyOctave: true).abs() < 1e-9, isTrue);
    expect(pitchCents(60.3, 60).round(), 30);
  });

  test('metinler 33 dilde', () {
    for (final e in kMuzikTexts.entries) {
      expect(e.value.length, 33, reason: e.key);
    }
  });
}
