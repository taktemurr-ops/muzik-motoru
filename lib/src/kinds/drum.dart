import 'package:flutter/material.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';

import '../audio.dart';
import '../core.dart';
import '../rhythm.dart';
import '../texts.dart';
import '../theory.dart';
import '../tools.dart';

/// Davul Dersi: kalıbı dinle, sonra metronomla birlikte pedlerde çal.
/// Batı tarzlarının yanında usuller: düyek, sofyan, çiftetelli, aksak (9/8),
/// devr-i hindi (7/8) ve curcuna (10/8).
class DrumStyle {
  final String key;
  final int bpb;
  final int spb; // vuruş başına adım
  final int minD;
  final int minBpm;
  final int maxBpm;
  final Map<String, List<int>> base; // ped -> bir ölçüdeki adımlar
  const DrumStyle(this.key, this.bpb, this.spb, this.minD, this.minBpm, this.maxBpm, this.base);
  int get steps => bpb * spb;
  bool get usul => base.containsKey('dr_dum');
}

const List<DrumStyle> kDrumStyles = [
  DrumStyle('rock', 4, 2, 1, 72, 120, {
    'dr_kick': [0, 4],
    'dr_snare': [2, 6],
    'dr_hat': [0, 1, 2, 3, 4, 5, 6, 7],
  }),
  DrumStyle('pop', 4, 2, 2, 80, 118, {
    'dr_kick': [0, 3, 4],
    'dr_snare': [2, 6],
    'dr_hat': [0, 1, 2, 3, 4, 5, 6, 7],
  }),
  DrumStyle('halftime', 4, 2, 3, 70, 96, {
    'dr_kick': [0, 5],
    'dr_snare': [4],
    'dr_hat': [0, 1, 2, 3, 4, 5, 6, 7],
  }),
  DrumStyle('disco', 4, 2, 4, 96, 120, {
    'dr_kick': [0, 2, 4, 6],
    'dr_snare': [2, 6],
    'dr_open': [1, 3, 5, 7],
  }),
  DrumStyle('duyek', 4, 2, 2, 76, 104, {
    'dr_dum': [0, 5],
    'dr_tek': [2, 3, 6],
  }),
  DrumStyle('sofyan', 4, 2, 1, 72, 100, {
    'dr_dum': [0],
    'dr_tek': [4, 6],
  }),
  DrumStyle('ciftetelli', 4, 2, 3, 80, 104, {
    'dr_dum': [0, 4],
    'dr_tek': [3, 6],
  }),
  DrumStyle('devrihindi', 7, 1, 5, 120, 170, {
    'dr_dum': [0],
    'dr_tek': [2, 4, 5],
  }),
  DrumStyle('aksak', 9, 1, 5, 140, 200, {
    'dr_dum': [0, 4],
    'dr_tek': [2, 6, 7],
  }),
  DrumStyle('curcuna', 10, 1, 7, 150, 200, {
    'dr_dum': [0, 5],
    'dr_tek': [3, 7],
  }),
  DrumStyle('funk', 4, 4, 6, 84, 104, {
    'dr_kick': [0, 3, 10],
    'dr_snare': [4, 12],
    'dr_hat': [0, 2, 4, 6, 8, 10, 12, 14],
  }),
  DrumStyle('shuffle', 4, 3, 6, 80, 110, {
    'dr_kick': [0, 6],
    'dr_snare': [3, 9],
    'dr_hat': [0, 2, 3, 5, 6, 8, 9, 11],
  }),
];

class DrumPuzzle extends MPuzzle {
  final String style;
  final int bpm;
  final int bpb;
  final int spb;
  final int bars;
  final List<String> pads;
  final List<(int, String)> hits; // (adım, ped), adım tüm kalıp boyunca
  const DrumPuzzle(this.style, this.bpm, this.bpb, this.spb, this.bars, this.pads, this.hits);

  int get stepsPerBar => bpb * spb;
  int get totalSteps => stepsPerBar * bars;
  double get stepMs => 60000 / bpm / spb;
  double get beatMs => 60000 / bpm;

  @override
  Set<String> get samples => {...pads, 'mt_hi', 'mt_lo'};
}

const int kDrumRepeats = 2;

class DrumKind extends MuzikKind {
  @override
  String get id => 'davul-dersi';
  const DrumKind();

  @override
  MPuzzle? make(int d, SeededRandom r, {bool short = false}) {
    final pool = [for (final s in kDrumStyles) if (s.minD <= d) s];
    final st = r.pick(pool);
    final bars = short || d <= 3 ? 2 : 4;
    final bpm = st.minBpm + ((st.maxBpm - st.minBpm) * clampD((d - st.minD) / 6, 0, 1)).round() + r.range(-2, 2);
    final hits = <(int, String)>{};
    for (var b = 0; b < bars; b++) {
      final off = b * st.steps;
      for (final e in st.base.entries) {
        final pad = e.key;
        // İlk bölümlerde zil sadeleştirilir (yalnız vuruş başları).
        if (d <= 1 && (pad == 'dr_hat' || pad == 'dr_open')) continue;
        for (final s in e.value) {
          if (d <= 2 && pad == 'dr_hat' && s % st.spb != 0) continue;
          hits.add((off + s, pad));
        }
      }
      // Çeşitleme: zorluk arttıkça ek vuruşlar.
      final extra = d <= 3 ? 0 : (d <= 6 ? 1 : 2);
      for (var k = 0; k < extra; k++) {
        final s = r.nextInt(st.steps);
        final pad = st.usul ? (r.chance(0.5) ? 'dr_ka' : 'dr_tek') : (r.chance(0.6) ? 'dr_kick' : 'dr_snare');
        final busy = hits.any((h) => h.$1 == off + s && h.$2 != 'dr_hat' && h.$2 != 'dr_open');
        if (!busy) hits.add((off + s, pad));
      }
      // Son ölçüde dolgu (tom ya da ka).
      if (b == bars - 1 && d >= 4) {
        final last = st.steps - st.spb;
        hits.removeWhere((h) => h.$1 >= off + last && h.$2 != 'dr_kick' && h.$2 != 'dr_dum');
        if (st.usul) {
          for (var s = last; s < st.steps; s++) {
            hits.add((off + s, 'dr_ka'));
          }
        } else {
          hits.add((off + last, 'dr_tom1'));
          if (st.spb >= 2) hits.add((off + last + st.spb ~/ 2, 'dr_tom2'));
        }
      }
      if (b == 0 && d >= 5 && !st.usul) {
        hits.removeWhere((h) => h.$1 == 0 && (h.$2 == 'dr_hat' || h.$2 == 'dr_open'));
        hits.add((0, 'dr_crash'));
      }
    }
    final list = hits.toList()..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
    final order = [for (final p in kPads) p.$1];
    final pads = {for (final h in list) h.$2}.toList()..sort((a, b) => order.indexOf(a).compareTo(order.indexOf(b)));
    return DrumPuzzle(st.key, bpm, st.bpb, st.spb, bars, pads, list);
  }

  @override
  bool check(MPuzzle p) {
    if (p is! DrumPuzzle) return false;
    if (p.hits.length < 4 || p.pads.isEmpty || p.pads.length > 6 || p.bpm < 50 || p.bpm > 220) return false;
    final lastAt = <String, int>{};
    for (final h in p.hits) {
      if (h.$1 < 0 || h.$1 >= p.totalSteps || !p.pads.contains(h.$2)) return false;
      final l = lastAt[h.$2];
      if (l != null && (h.$1 - l) * p.stepMs < 95) return false;
      lastAt[h.$2] = h.$1;
    }
    for (final pad in p.pads) {
      if (!p.hits.any((h) => h.$2 == pad)) return false;
    }
    // Aynı adımda en çok üç ped (iki el + ayak).
    for (var s = 0; s < p.totalSteps; s++) {
      if (p.hits.where((h) => h.$1 == s).length > 3) return false;
    }
    return p.totalSteps * p.stepMs * (kDrumRepeats + 1) < 90000;
  }

  @override
  List<GameStat> get stats => const [
        GameStat('rounds_won', 'Geçilen ders', 'Lessons passed', scale: 10),
        GameStat('perfect', 'Kusursuz ders', 'Perfect lessons', scale: 10),
        GameStat('drum_hits', 'Davul vuruşu', 'Drum hits', scale: 200),
      ];

  @override
  List<MissionTemplate> get missions => const [
        MissionTemplate('win', 'rounds_won', [3, 10, 25]),
        MissionTemplate('hits', 'drum_hits', [100, 400, 1200]),
        MissionTemplate('perfect', 'perfect', [1, 5, 15]),
      ];

  @override
  Widget build(MuzikPlay play) => _DrumView(play: play);
}

class _DrumView extends StatefulWidget {
  final MuzikPlay play;
  const _DrumView({required this.play});
  @override
  State<_DrumView> createState() => _DrumViewState();
}

class _DrumViewState extends State<_DrumView> with SingleTickerProviderStateMixin, SongClock<_DrumView>, Clock<_DrumView> {
  late final DrumPuzzle p = widget.play.puzzle as DrumPuzzle;
  int phase = 0; // 0 hazır, 1 dinleme, 2 çalma, 3 bitti
  bool practice = false;
  int hints = 0, extraHits = 0, lastStep = -99, lastBeat = -99;
  final Tally tally = Tally();
  late List<int> hitState = List.filled(p.hits.length * kDrumRepeats, 0); // 0 bekliyor, 1 vuruldu, 2 kaçtı
  String? litPad;
  double flash = 0;

  double get stepMs => p.stepMs / (practice ? 1.25 : 1.0);
  double get beatMs => stepMs * p.spb;
  double get loopMs => p.totalSteps * stepMs;
  JudgeWindow get win => JudgeWindow.forLevel(widget.play.d, practice: practice);

  double expMs(int k) => (k ~/ p.hits.length) * loopMs + p.hits[k % p.hits.length].$1 * stepMs;

  void _listen() {
    setState(() {
      phase = 1;
      lastStep = -99;
      lastBeat = -99;
    });
    startSong(leadMs: beatMs * p.bpb);
  }

  void _play() {
    setState(() {
      phase = 2;
      hitState = List.filled(p.hits.length * kDrumRepeats, 0);
      extraHits = 0;
      lastStep = -99;
      lastBeat = -99;
      tally
        ..perfect = 0
        ..great = 0
        ..good = 0
        ..miss = 0
        ..combo = 0
        ..score = 0;
    });
    startClock();
    startSong(leadMs: beatMs * p.bpb);
  }

  @override
  void onFrame() {
    final t = effMs;
    final bi = (t / beatMs).floor();
    if (bi != lastBeat) {
      lastBeat = bi;
      final down = ((bi % p.bpb) + p.bpb) % p.bpb == 0;
      // Metronom: sayımda yüksek, çalarken hafif.
      widget.play.sample(down ? 'mt_hi' : 'mt_lo', volume: t < 0 ? 1.0 : 0.35);
      if (t < 0) Haptic.beat(strong: down);
      flash = down ? 0.8 : 0.4;
    }
    flash *= 0.88;
    final loops = phase == 1 ? 1 : kDrumRepeats;
    // Dinleme: kalıbı motor çalar. Pratikte çalarken rehber ses de duyulur.
    final si = (songMs / stepMs).floor();
    if (si != lastStep && si >= 0) {
      for (var s = lastStep + 1; s <= si; s++) {
        if (s < 0 || s >= p.totalSteps * loops) continue;
        final local = s % p.totalSteps;
        if (phase == 1 || practice) {
          for (final h in p.hits) {
            if (h.$1 == local) widget.play.sample(h.$2, volume: phase == 1 ? 1.0 : 0.35);
          }
        }
      }
      lastStep = si;
    }
    if (phase == 2) {
      for (var k = 0; k < hitState.length; k++) {
        if (hitState[k] == 0 && t - expMs(k) > win.good) {
          hitState[k] = 2;
          tally.add(Judge.miss);
        }
      }
    }
    if (t > p.totalSteps * stepMs * loops + 300) {
      stopSong();
      if (phase == 1) {
        setState(() => phase = 0);
      } else if (phase == 2) {
        _finish();
      }
    }
  }

  void _pad(String pad) {
    widget.play.sample(pad);
    Haptic.hit();
    setState(() => litPad = pad);
    later(110, () => setState(() => litPad = null));
    if (phase != 2 || !running) return;
    final t = effMs;
    var best = -1;
    var be = 1e9;
    for (var k = 0; k < hitState.length; k++) {
      if (hitState[k] != 0 || p.hits[k % p.hits.length].$2 != pad) continue;
      final e = (t - expMs(k)).abs();
      if (e < be) {
        be = e;
        best = k;
      }
    }
    if (best >= 0 && be <= win.good) {
      hitState[best] = 1;
      tally.add(win.judge(t - expMs(best)));
    } else if (t >= 0) {
      extraHits++;
      tally.combo = 0;
    }
  }

  void _finish() {
    phase = 3;
    final expected = hitState.length;
    final acc = clampD(tally.accuracy - extraHits * 0.5 / expected, 0, 1);
    final pass = practice || acc >= 0.7;
    if (pass) {
      final stars = starsByAccuracy(acc, practice: practice, hints: hints);
      later(500, () => widget.play.win(score: tally.score, stars: stars, seconds: seconds, hints: hints, extra: {'drum_hits': tally.hits}));
    } else {
      widget.play.sfx(Sfx.lose);
      later(500, () => widget.play.lose(score: tally.score, seconds: seconds, headline: '${(acc * 100).round()}%'));
    }
    setState(() {});
  }

  Future<void> _hint() async {
    if (phase == 2) return;
    if (await widget.play.ctx.requestHint()) {
      setState(() {
        hints++;
        practice = true;
      });
    }
  }

  void _paintGrid(Canvas c) {
    final n = p.stepsPerBar;
    final rows = p.pads.length;
    const double cw = 40, rh = 46, left = 96;
    final w = left + n * cw + 8;
    final hgt = rows * rh + 30;
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, hgt), const Radius.circular(14)), fill(MColors.stage));
    final t = phase == 0 ? -1.0 : effMs;
    final loops = phase == 1 ? 1 : kDrumRepeats;
    final gStep = t < 0 ? -1 : (t / stepMs).floor();
    final local = gStep < 0 ? -1 : gStep % p.totalSteps;
    final bar = local < 0 ? 0 : local ~/ n;
    final loop = gStep < 0 ? 0 : gStep ~/ p.totalSteps;
    for (var s = 0; s < n; s++) {
      final x = left + s * cw;
      final beatStart = s % p.spb == 0;
      c.drawRect(Rect.fromLTWH(x, 20, cw - 2, rows * rh), fill(Colors.white.withValues(alpha: beatStart ? 0.07 : 0.03)));
      if (beatStart) drawLabel(c, '${s ~/ p.spb + 1}', Offset(x + cw / 2, 10), 12, Colors.white54);
    }
    for (var ri = 0; ri < rows; ri++) {
      final pad = p.pads[ri];
      final y = 20 + ri * rh;
      final name = mt(widget.play.lang, kPads.firstWhere((e) => e.$1 == pad).$2);
      drawLabel(c, name, Offset(left / 2, y + rh / 2), 14, MColors.lanes[ri % MColors.lanes.length]);
      for (var hi = 0; hi < p.hits.length; hi++) {
        final h = p.hits[hi];
        if (h.$2 != pad || h.$1 ~/ n != bar) continue;
        final s = h.$1 % n;
        final o = Offset(left + s * cw + cw / 2 - 1, y + rh / 2);
        var col = MColors.lanes[ri % MColors.lanes.length];
        if (phase >= 2 && loop < loops) {
          final st = hitState[loop * p.hits.length + hi];
          if (st == 1) col = MColors.good;
          if (st == 2) col = MColors.bad;
        }
        c.drawCircle(o, 14, fill(col));
      }
    }
    if (local >= 0 && loop < loops) {
      final x = left + (local % n) * cw;
      c.drawRect(Rect.fromLTWH(x, 18, cw - 2, rows * rh + 4), stroke(Colors.white.withValues(alpha: 0.5 + 0.5 * flash), 3));
    }
    drawLabel(c, '${bar + 1}/${p.bars}', Offset(left / 2, 10), 12, Colors.white54);
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.play.lang;
    final n = p.stepsPerBar;
    final gw = 96 + n * 40 + 8.0, gh = p.pads.length * 46 + 30.0;
    Widget board;
    if (phase == 0) {
      board = Column(children: [
        Expanded(
          child: StartCard(
            title: mt(lang, 'drum_${p.style}'),
            subtitle: '${p.bpm} BPM · ${p.bpb}/${p.spb == 1 ? 8 : 4}\n${mt(lang, 'drumHelp')}',
            button: mt(lang, 'listen'),
            onStart: _listen,
            icon: Icons.headphones,
          ),
        ),
        FilledButton.icon(onPressed: _play, icon: const Icon(Icons.sports_handball), label: Text(mt(lang, 'playAlong'))),
      ]);
    } else {
      board = ValueListenableBuilder<int>(
        valueListenable: frame,
        builder: (_, __, ___) => TapCanvas(w: gw, h: gh, paint: _paintGrid),
      );
    }
    final padRow = Row(children: [
      for (var i = 0; i < p.pads.length; i++)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Semantics(
              button: true,
              label: mt(lang, kPads.firstWhere((e) => e.$1 == p.pads[i]).$2),
              child: Listener(
                onPointerDown: (_) => _pad(p.pads[i]),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 60),
                  height: 96,
                  decoration: BoxDecoration(
                    color: litPad == p.pads[i] ? Colors.white : MColors.lanes[i % MColors.lanes.length],
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24, width: 3),
                  ),
                  alignment: Alignment.center,
                  child: FittedBox(
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Text(mt(lang, kPads.firstWhere((e) => e.$1 == p.pads[i]).$2),
                          style: const TextStyle(color: MColors.ink, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
    ]);
    return MScreen(
      flash: phase == 0 ? 0 : flash,
      bar: MBar(
        play: widget.play,
        left: phase == 2 ? '${(tally.accuracy * 100).round()}%' : '',
        status: phase == 1 ? mt(lang, 'listen') : (phase == 2 ? mt(lang, 'playAlong') : mt(lang, 'drum_${p.style}')),
        practice: phase == 0 ? practice : null,
        onPractice: (v) => setState(() => practice = v),
        onHint: phase == 0 ? _hint : null,
        tools: phase == 0,
      ),
      board: board,
      bottom: padRow,
    );
  }
}
