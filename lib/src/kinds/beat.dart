import 'dart:math' as math;

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

/// Ritim Vuruşu: üretilmiş özgün müziğe eşlik et. Halkalar merkezden açılır;
/// dış çembere değdiğinde sol ya da sağ yarıya dokun.
class BNote {
  final double beat;
  final int side; // 0 sol, 1 sağ, 2 iki yan
  final double hold; // vuruş; 0 = kısa
  final int midi;
  const BNote(this.beat, this.side, this.hold, this.midi);
}

/// Bir müzik tarzı: ölçü, bir ölçülük davul kalıbı (vuruş, örnek).
class BeatStyle {
  final String key;
  final int bpb;
  final int minBpm;
  final int maxBpm;
  final List<(double, String)> drums;
  const BeatStyle(this.key, this.bpb, this.minBpm, this.maxBpm, this.drums);
}

const List<BeatStyle> kBeatStyles = [
  BeatStyle('pop', 4, 92, 124, [
    (0, 'dr_kick'), (0, 'dr_hat'), (0.5, 'dr_hat'), (1, 'dr_snare'), (1, 'dr_hat'), (1.5, 'dr_hat'), //
    (2, 'dr_kick'), (2, 'dr_hat'), (2.5, 'dr_kick'), (2.5, 'dr_hat'), (3, 'dr_snare'), (3, 'dr_hat'), (3.5, 'dr_hat'),
  ]),
  BeatStyle('funk', 4, 96, 116, [
    (0, 'dr_kick'), (0, 'dr_hat'), (0.5, 'dr_hat'), (0.75, 'dr_kick'), (1, 'dr_snare'), (1.5, 'dr_hat'), //
    (1.75, 'dr_rim'), (2, 'dr_hat'), (2.25, 'dr_kick'), (2.5, 'dr_open'), (3, 'dr_snare'), (3.5, 'dr_hat'), (3.75, 'dr_snare'),
  ]),
  BeatStyle('waltz', 3, 84, 120, [
    (0, 'dr_kick'), (1, 'dr_hat'), (1, 'dr_rim'), (2, 'dr_hat'), (2, 'dr_rim'),
  ]),
  BeatStyle('shuffle', 4, 88, 112, [
    (0, 'dr_kick'), (0, 'dr_hat'), (0.67, 'dr_hat'), (1, 'dr_snare'), (1.67, 'dr_hat'), //
    (2, 'dr_kick'), (2, 'dr_hat'), (2.67, 'dr_hat'), (3, 'dr_snare'), (3.67, 'dr_hat'),
  ]),
  BeatStyle('ciftetelli', 4, 84, 104, [
    (0, 'dr_dum'), (0.75, 'dr_tek'), (1.5, 'dr_dum'), (2, 'dr_dum'), (2.5, 'dr_tek'), (3, 'dr_ka'), (3.5, 'dr_tek'),
  ]),
  BeatStyle('march', 2, 100, 128, [
    (0, 'dr_kick'), (0.5, 'dr_snare'), (1, 'dr_kick'), (1.5, 'dr_snare'), (1.75, 'dr_snare'),
  ]),
];

class BeatPuzzle extends MPuzzle {
  final String style;
  final int bpm;
  final int bpb;
  final List<(double, String)> drums;
  final List<MNote> backing;
  final List<BNote> notes;
  const BeatPuzzle(this.style, this.bpm, this.bpb, this.drums, this.backing, this.notes);

  double get beatMs => 60000 / bpm;
  double get lengthBeats => notes.last.beat + notes.last.hold + 2;

  @override
  Set<String> get samples => {
        for (final d in drums) d.$2,
        for (final b in backing) pianoSample(b.midi),
        for (final n in notes) pianoSample(n.midi),
        'mt_hi',
        'mt_lo',
      };
}

/// Akor ilerlemeleri (derece kökleri, majör/minör).
const List<List<(int, bool)>> _progs = [
  [(0, true), (7, true), (9, false), (5, true)],
  [(0, true), (5, true), (7, true), (0, true)],
  [(9, false), (5, true), (0, true), (7, true)],
  [(0, true), (9, false), (5, true), (7, true)],
  [(2, false), (7, true), (0, true), (0, true)],
];

class BeatKind extends MuzikKind {
  @override
  String get id => 'ritim-vurusu';
  const BeatKind();

  @override
  MPuzzle? make(int d, SeededRandom r, {bool short = false}) {
    final styles = d <= 2 ? [kBeatStyles[0], kBeatStyles[2], kBeatStyles[5]] : kBeatStyles;
    final st = r.pick(styles);
    final bpm = st.minBpm + ((st.maxBpm - st.minBpm) * (0.2 + 0.08 * d)).round() + r.range(-3, 3);
    final bars = short ? 4 : (d <= 2 ? 8 : (d <= 6 ? 12 : 16));
    final root = r.nextInt(12);
    final major = r.chance(0.6);
    final sc = major ? (d <= 3 ? kPentaMajor : kMajor) : (d <= 3 ? kPentaMinor : kMinor);
    final mel = genMelody(r, rootPc: root, scale: sc, bars: bars, beatsPerBar: st.bpb, level: d, lo: 62, hi: 81);
    if (!melodyOk(mel, lo: 60, hi: 84)) return null;
    // Davul: kalıp her ölçüde; dört ölçüde bir zil, son ölçüde dolgu.
    final drums = <(double, String)>[];
    for (var b = 0; b < bars; b++) {
      final base = b * st.bpb.toDouble();
      for (final e in st.drums) {
        drums.add((base + e.$1, e.$2));
      }
      if (b % 4 == 0) drums.add((base, 'dr_crash'));
      if (b % 4 == 3 && d >= 4) {
        drums.add((base + st.bpb - 1, 'dr_tom1'));
        drums.add((base + st.bpb - 0.5, 'dr_tom2'));
      }
    }
    // Eşlik: bas + akor (düşük ses).
    final prog = r.pick(_progs);
    final backing = <MNote>[];
    for (var b = 0; b < bars; b++) {
      final (deg, maj) = prog[b % 4];
      final pc = (root + (major ? deg : (deg + 9) % 12)) % 12;
      final isMaj = major ? maj : !maj;
      var bass = 40 + (pc - 4) % 12;
      if (bass < kLowMidi) bass += 12;
      backing.add(MNote(b * st.bpb.toDouble(), st.bpb.toDouble(), bass));
      if (st.bpb >= 3) backing.add(MNote(b * st.bpb + 2.0, 1, bass + 12 > 60 ? bass : bass + 12));
      final third = isMaj ? 4 : 3;
      final c0 = 55 + (pc - 7) % 12;
      for (final iv in [0, third, 7]) {
        backing.add(MNote(b * st.bpb.toDouble(), st.bpb.toDouble(), c0 + iv));
      }
    }
    // Oyuncu notaları ezgiden türetilir.
    final notes = <BNote>[];
    var side = r.nextInt(2);
    for (var i = 0; i < mel.length; i++) {
      final n = mel[i];
      if (i > 0) {
        final dir = n.midi.compareTo(mel[i - 1].midi);
        side = dir > 0 ? 1 : (dir < 0 ? 0 : 1 - side);
      }
      final phraseEnd = (n.beat + n.dur) % (4 * st.bpb) < 1e-6 && n.dur >= 1;
      final s = d >= 5 && phraseEnd ? 2 : side;
      final hold = d >= 3 && n.dur >= 2 ? n.dur - 0.5 : 0.0;
      notes.add(BNote(n.beat, s, hold, n.midi));
    }
    // Kolay bölümlerde çok sık notalar seyreltilir.
    final minGap = d <= 2 ? 1.0 : (d <= 5 ? 0.5 : 0.25);
    final thin = <BNote>[];
    for (final n in notes) {
      if (thin.isNotEmpty && n.beat - thin.last.beat < minGap - 1e-6) continue;
      thin.add(n);
    }
    return BeatPuzzle(st.key, bpm, st.bpb, drums, backing, thin);
  }

  @override
  bool check(MPuzzle p) {
    if (p is! BeatPuzzle) return false;
    if (p.notes.length < 8 || p.bpm < 60 || p.bpm > 170) return false;
    final bm = p.beatMs;
    final free = [-1e9, -1e9];
    for (var i = 0; i < p.notes.length; i++) {
      final n = p.notes[i];
      if (n.side < 0 || n.side > 2 || n.midi < kLowMidi || n.midi > kHighMidi || n.hold < 0) return false;
      if (i > 0 && n.beat <= p.notes[i - 1].beat) return false;
      final sides = n.side == 2 ? [0, 1] : [n.side];
      for (final s in sides) {
        if ((n.beat - free[s]) * bm < 130) return false;
      }
      if (n.side == 2) {
        if (i > 0 && (n.beat - p.notes[i - 1].beat) < 0.5) return false;
        if (i + 1 < p.notes.length && (p.notes[i + 1].beat - n.beat) < 0.5) return false;
      }
      for (final s in sides) {
        free[s] = n.beat + n.hold;
      }
      // Basılı tutulan notanın üzerine diğer yandan nota gelmesin.
      if (i > 0) {
        final q = p.notes[i - 1];
        if (q.hold > 0 && n.beat < q.beat + q.hold + 0.25) return false;
      }
    }
    return p.lengthBeats * bm < 110000;
  }

  @override
  List<GameStat> get stats => const [
        GameStat('rounds_won', 'Tamamlanan şarkı', 'Songs completed', scale: 10),
        GameStat('perfect', 'Kusursuz şarkı', 'Perfect songs', scale: 10),
        GameStat('best_combo', 'En uzun seri', 'Best combo', scale: 50),
      ];

  @override
  List<MissionTemplate> get missions => const [
        MissionTemplate('win', 'rounds_won', [3, 10, 25]),
        MissionTemplate('combo', 'best_combo', [30, 80, 200]),
        MissionTemplate('perfect', 'perfect', [1, 5, 15]),
      ];

  @override
  Widget build(MuzikPlay play) => _BeatView(play: play);
}

class _BeatView extends StatefulWidget {
  final MuzikPlay play;
  const _BeatView({required this.play});
  @override
  State<_BeatView> createState() => _BeatViewState();
}

class _BeatViewState extends State<_BeatView> with SingleTickerProviderStateMixin, SongClock<_BeatView>, Clock<_BeatView> {
  late final BeatPuzzle p = widget.play.puzzle as BeatPuzzle;
  static const double w = 400, h = 640;
  static const Offset c0 = Offset(200, 300);
  static const double ringR = 170;
  bool started = false, practice = false, over = false;
  int energy = 100, hints = 0;
  final Tally tally = Tally();
  late List<int> state = List.filled(p.notes.length, 0); // 0 bekliyor, 1 bitti, 3 basılı
  late List<int> bothMask = List.filled(p.notes.length, 0);
  late List<double> bothAt = List.filled(p.notes.length, 0);
  final List<Burst> bursts = [];
  int nextDrum = 0, nextBack = 0, lastBeat = -99;
  final List<int> holding = [-1, -1];
  double pulse = 0;

  double get speed => practice ? 0.8 : 1.0;
  double get beatMs => p.beatMs / speed;
  double noteMs(BNote n) => n.beat * beatMs;
  double get lookMs => (1900 - widget.play.d * 80) / speed;
  JudgeWindow get win => JudgeWindow.forLevel(widget.play.d, practice: practice);
  double get endMs => p.lengthBeats * beatMs;

  void _start() {
    setState(() {
      started = true;
      over = false;
      energy = 100 + 40 * hints;
      state = List.filled(p.notes.length, 0);
      bothMask = List.filled(p.notes.length, 0);
      nextDrum = 0;
      nextBack = 0;
      lastBeat = -99;
      holding[0] = -1;
      holding[1] = -1;
    });
    startClock();
    startSong(leadMs: beatMs * p.bpb);
  }

  @override
  void onFrame() {
    if (over) return;
    final t = effMs;
    final bi = (t / beatMs).floor();
    if (bi != lastBeat) {
      lastBeat = bi;
      final down = ((bi % p.bpb) + p.bpb) % p.bpb == 0;
      if (t < 0) {
        widget.play.sample(down ? 'mt_hi' : 'mt_lo');
        Haptic.beat(strong: down);
      }
      pulse = down ? 1 : 0.5;
    }
    pulse *= 0.9;
    while (nextDrum < p.drums.length && p.drums[nextDrum].$1 * beatMs <= songMs) {
      widget.play.sample(p.drums[nextDrum].$2, volume: 0.8);
      nextDrum++;
    }
    while (nextBack < p.backing.length && p.backing[nextBack].beat * beatMs <= songMs) {
      widget.play.note(p.backing[nextBack].midi, volume: 0.3);
      nextBack++;
    }
    for (var i = 0; i < p.notes.length; i++) {
      if (state[i] != 0) continue;
      final tm = noteMs(p.notes[i]);
      if (t - tm > win.good) {
        state[i] = 1;
        _miss(p.notes[i].side);
      } else if (tm > t + lookMs) {
        break;
      }
    }
    for (var s = 0; s < 2; s++) {
      final hi = holding[s];
      if (hi < 0) continue;
      final n = p.notes[hi];
      if (t >= (n.beat + n.hold) * beatMs) {
        state[hi] = 1;
        holding[s] = -1;
        tally.score += 60;
      }
    }
    pruneBursts(bursts, t);
    if (t > endMs) _finish();
  }

  Offset _sidePos(int side) => side == 2 ? c0 + const Offset(0, ringR) : c0 + Offset(side == 0 ? -ringR : ringR, 0);

  void _miss(int side) {
    tally.add(Judge.miss);
    bursts.add(Burst(_sidePos(side), effMs, MColors.bad, judgeText(widget.play.lang, Judge.miss)));
    Haptic.miss();
    if (!practice) {
      energy -= 12 + widget.play.d;
      if (energy <= 0) {
        energy = 0;
        over = true;
        stopSong();
        widget.play.sfx(Sfx.lose);
        later(700, () => widget.play.lose(score: tally.score, seconds: seconds, headline: '${(tally.accuracy * 100).round()}%'));
      }
    }
    setState(() {});
  }

  void _hit(int i, Judge j, int side) {
    final n = p.notes[i];
    tally.add(j);
    widget.play.note(n.midi);
    Haptic.hit();
    energy = math.min<int>(100 + 40 * hints, energy + 3);
    bursts.add(Burst(_sidePos(side), effMs, judgeColor(j), judgeText(widget.play.lang, j)));
    if (n.hold > 0 && n.side != 2) {
      state[i] = 3;
      holding[n.side] = i;
    } else {
      state[i] = 1;
    }
    setState(() {});
  }

  void _down(Offset pos) {
    if (!started || over || !running) return;
    final side = pos.dx < w / 2 ? 0 : 1;
    final t = effMs;
    var best = -1;
    var be = 1e9;
    for (var i = 0; i < p.notes.length; i++) {
      if (state[i] != 0) continue;
      final n = p.notes[i];
      if (n.side != side && n.side != 2) continue;
      final e = (t - noteMs(n)).abs();
      if (e < be) {
        be = e;
        best = i;
      }
      if (noteMs(n) > t + win.good) break;
    }
    if (best < 0 || be > win.good) return;
    final n = p.notes[best];
    if (n.side == 2) {
      bothMask[best] |= 1 << side;
      if (bothMask[best] == 1) {
        bothAt[best] = t;
      } else if (bothMask[best] == 2) {
        bothAt[best] = t;
      }
      if (bothMask[best] == 3) {
        final avg = (bothAt[best] + t) / 2;
        _hit(best, win.judge(avg - noteMs(n)), 2);
      }
      return;
    }
    _hit(best, win.judge(t - noteMs(n)), side);
  }

  void _up(Offset pos) {
    final side = pos.dx < w / 2 ? 0 : 1;
    final hi = holding[side];
    if (hi < 0) return;
    state[hi] = 1;
    holding[side] = -1;
  }

  void _finish() {
    if (over) return;
    over = true;
    stopSong();
    final stars = starsByAccuracy(tally.accuracy, practice: practice, hints: hints);
    later(400, () => widget.play.win(score: tally.score, stars: stars, seconds: seconds, hints: hints, extra: {'best_combo': tally.best}));
  }

  Future<void> _hint() async {
    if (started) return;
    if (await widget.play.ctx.requestHint()) setState(() => hints++);
  }

  void _paint(Canvas c) {
    final t = effMs;
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, w, h), const Radius.circular(18)), fill(MColors.stage));
    // Sol ve sağ yarı.
    c.drawRect(const Rect.fromLTWH(0, 0, w / 2, h), fill(MColors.lanes[0].withValues(alpha: 0.05)));
    c.drawRect(const Rect.fromLTWH(w / 2, 0, w / 2, h), fill(MColors.lanes[1].withValues(alpha: 0.05)));
    // Atan kalp gibi nabız halkası.
    final flashOn = MusicPrefs.flash;
    c.drawCircle(c0, ringR + 10 * pulse, stroke(Colors.white.withValues(alpha: 0.25 + (flashOn ? 0.45 * pulse : 0)), 6));
    c.drawCircle(c0, 26 + 6 * pulse, fill(Colors.white.withValues(alpha: 0.12 + 0.2 * pulse)));
    for (var i = 0; i < p.notes.length; i++) {
      if (state[i] == 1) continue;
      final n = p.notes[i];
      final tm = noteMs(n);
      if (tm > t + lookMs) break;
      final k = clampD(1 - (tm - t) / lookMs, 0, 1.2);
      final r = 26 + (ringR - 26) * k;
      final col = n.side == 2 ? MColors.lanes[2] : MColors.lanes[n.side];
      final rect = Rect.fromCircle(center: c0, radius: r);
      final width = state[i] == 3 ? 14.0 : 10.0;
      if (n.side == 2) {
        c.drawCircle(c0, r, stroke(col, width));
      } else {
        final start = n.side == 0 ? math.pi / 2 : -math.pi / 2;
        c.drawArc(rect, start + 0.25, math.pi - 0.5, false, stroke(col, width));
      }
      if (n.hold > 0) {
        final tailK = clampD(1 - ((n.beat + n.hold) * beatMs - t) / lookMs, 0, 1);
        final tr = 26 + (ringR - 26) * tailK;
        if (n.side != 2) {
          final start = n.side == 0 ? math.pi / 2 : -math.pi / 2;
          c.drawArc(Rect.fromCircle(center: c0, radius: tr), start + 0.6, math.pi - 1.2, false, stroke(col.withValues(alpha: 0.5), 4));
        }
      }
    }
    paintBursts(c, bursts, t);
    if (started) paintCountIn(c, t, beatMs, c0);
    // Enerji çubuğu.
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(20, h - 40, w - 40, 12), const Radius.circular(6)), fill(Colors.white12));
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(20, h - 40, (w - 40) * clampI(energy, 0, 100) / 100, 12), const Radius.circular(6)),
        fill(energy > 35 ? MColors.good : MColors.bad));
    drawLabel(c, mt(widget.play.lang, 'left'), const Offset(60, 26), 16, Colors.white54);
    drawLabel(c, mt(widget.play.lang, 'right'), const Offset(w - 60, 26), 16, Colors.white54);
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.play.lang;
    return MScreen(
      bar: MBar(
        play: widget.play,
        left: '${tally.combo}×',
        status: '${mt(lang, 'score')} ${tally.score}',
        practice: started ? null : practice,
        onPractice: (v) => setState(() => practice = v),
        onHint: started ? null : _hint,
        tools: !started,
      ),
      board: started
          ? ValueListenableBuilder<int>(
              valueListenable: frame,
              builder: (_, __, ___) => TapCanvas(w: w, h: h, paint: _paint, onDown: _down, onUp: _up, semantics: mt(lang, 'beatHelp')),
            )
          : StartCard(
              title: mt(lang, 'style_${p.style}'),
              subtitle: '${p.bpm} BPM · ${p.bpb}/4${hints > 0 ? '\n${mt(lang, 'extraEnergy')}' : ''}',
              button: mt(lang, 'start'),
              onStart: _start,
              icon: Icons.graphic_eq,
            ),
    );
  }
}
