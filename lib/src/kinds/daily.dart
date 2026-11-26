import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';

import '../core.dart';
import '../studio_chrome.dart';
import '../texts.dart';
import 'beat.dart';
import 'drum.dart';
import 'ear.dart';
import 'guitar.dart';
import 'memory.dart';
import 'staff.dart';
import 'tiles.dart';

/// Günlük Ritim'de karışan kısa oyunlar.
const Map<String, MuzikKind> kDailyPool = {
  'nota-karolari': TilesKind(),
  'ritim-vurusu': BeatKind(),
  'davul-dersi': DrumKind(),
  'kulak-egitimi': EarKind(),
  'melodi-hafizasi': MemoryKind(),
  'nota-ogrenme': StaffKind(),
  'gitar-akorlari': GuitarKind(),
};

class DailyPuzzle extends MPuzzle {
  final List<String> kinds;
  final List<MPuzzle> parts;
  final int d;
  const DailyPuzzle(this.kinds, this.parts, this.d);

  @override
  Set<String> get samples => {for (final p in parts) ...p.samples};
}

/// Günlük Ritim: her gün üç kısa müzik görevi (çal, dinle, oku).
class DailyRhythmKind extends MuzikKind {
  @override
  String get id => 'gunluk-ritim';
  const DailyRhythmKind();

  @override
  MPuzzle? make(int d, SeededRandom r, {bool short = false}) {
    // Biri çalma, biri dinleme, biri okuma/kurma görevi olsun.
    final play = r.pick(const ['nota-karolari', 'ritim-vurusu', 'davul-dersi']);
    final ear = r.pick(const ['kulak-egitimi', 'melodi-hafizasi']);
    final read = r.pick(const ['nota-ogrenme', 'gitar-akorlari']);
    final pick = [play, ear, read];
    r.shuffle(pick);
    final sd = math.max<int>(1, d - 2);
    final parts = <MPuzzle>[];
    for (final k in pick) {
      MPuzzle? p;
      for (var a = 0; a < 20 && p == null; a++) {
        final c = kDailyPool[k]!.make(sd, r, short: true);
        if (c != null && kDailyPool[k]!.check(c)) p = c;
      }
      if (p == null) return null;
      parts.add(p);
    }
    return DailyPuzzle(pick, parts, sd);
  }

  @override
  bool check(MPuzzle p) {
    if (p is! DailyPuzzle || p.parts.length != 3 || p.kinds.toSet().length != 3) return false;
    for (var i = 0; i < 3; i++) {
      final k = kDailyPool[p.kinds[i]];
      if (k == null || !k.check(p.parts[i])) return false;
    }
    return true;
  }

  @override
  List<GameStat> get stats => const [
        GameStat('rounds_won', 'Tamamlanan gün', 'Days completed', scale: 7),
        GameStat('perfect', 'Üç yıldızlı gün', 'Three-star days', scale: 7),
      ];

  @override
  List<MissionTemplate> get missions => const [
        MissionTemplate('win', 'rounds_won', [2, 7, 21]),
        MissionTemplate('perfect', 'perfect', [1, 4, 12]),
      ];

  @override
  Widget build(MuzikPlay play) => _DailyView(play: play);
}

class _DailyView extends StatefulWidget {
  final MuzikPlay play;
  const _DailyView({required this.play});
  @override
  State<_DailyView> createState() => _DailyViewState();
}

class _DailyViewState extends State<_DailyView> {
  late final DailyPuzzle p = widget.play.puzzle as DailyPuzzle;
  int part = 0, stars = 0, wins = 0;

  void _done(bool won, int s) {
    if (won) {
      wins++;
      stars += s;
    }
    if (part + 1 >= p.parts.length) {
      if (wins >= 2) {
        widget.play.win(stars: (stars / 3).round(), score: wins * 400);
      } else {
        widget.play.lose(headline: '$wins/3');
      }
      return;
    }
    setState(() => part++);
  }

  @override
  Widget build(BuildContext context) {
    final sub = MuzikPlay(ctx: widget.play.ctx, puzzle: p.parts[part], d: p.d, seed: widget.play.seed + part, voice: widget.play.voice, relay: _done);
    return Column(children: [
      Container(
        padding: const EdgeInsets.only(top: 4, bottom: 2),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < 3; i++)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: i <= part ? Color.lerp(StudioLook.of(context).base, StudioLook.of(context).accent, 0.5) : Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: i <= part ? StudioLook.of(context).accent : Colors.white24),
              ),
              child: Text(mt(widget.play.lang, 'daily_${p.kinds[i]}'), style: const TextStyle(color: Colors.white, fontSize: 11)),
            ),
        ]),
      ),
      Expanded(child: KeyedSubtree(key: ValueKey(part), child: kDailyPool[p.kinds[part]]!.build(sub))),
    ]);
  }
}
