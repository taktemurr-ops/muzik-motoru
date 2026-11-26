import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';

import '../audio.dart';
import '../core.dart';
import '../rhythm.dart';
import '../studio_chrome.dart';
import '../synth.dart';
import '../texts.dart';
import '../theory.dart';

// ================================================================ Ritim Koşusu

/// Koşu olayı: [beat] anında engel; [type] 0 zıpla (yerde blok), 1 kay (kemer).
class RunEv {
  final double beat;
  final int type;
  final int midi;
  const RunEv(this.beat, this.type, this.midi);
}

class RunPuzzle extends MPuzzle {
  final int bpm;
  final int bars;
  final List<RunEv> evs;
  final List<(double, String)> drums;
  final List<MNote> bass;
  const RunPuzzle(this.bpm, this.bars, this.evs, this.drums, this.bass);

  double get beatMs => 60000 / bpm;
  double get lengthBeats => evs.last.beat + 3;

  @override
  Set<String> get samples => {
        for (final d in drums) d.$2,
        for (final e in evs) pianoSample(e.midi),
        for (final b in bass) pianoSample(b.midi),
        'mt_hi',
        'mt_lo',
      };
}

class RunKind extends MuzikKind {
  @override
  String get id => 'ritim-kosusu';
  const RunKind();

  @override
  MPuzzle? make(int d, SeededRandom r, {bool short = false}) {
    final bpm = 84 + d * 6 + r.range(-4, 4);
    final bars = short ? 4 : (d <= 2 ? 8 : (d <= 6 ? 12 : 16));
    final step = d <= 3 ? 1.0 : 0.5;
    // Art arda iki engel arasında en az 300 ms kalsın.
    final minGap = math.max(d <= 2 ? 2.0 : (d <= 5 ? 1.0 : 0.5), 300 * bpm / 60000);
    final root = r.nextInt(12);
    final pool = scaleNotes(root, kPentaMajor, 62, 79);
    var idx = pool.length ~/ 2;
    final evs = <RunEv>[];
    var last = 1.0; // ilk ölçü ısınma
    for (var b = 1; b < bars; b++) {
      final slots = (4 / step).round();
      for (var s = 0; s < slots; s++) {
        final beat = b * 4 + s * step;
        if (beat - last < minGap - 1e-9) continue;
        final strong = s * step == 0 || s * step == 2;
        final p = strong ? 0.55 + d * 0.03 : 0.18 + d * 0.03;
        if (!r.chance(p)) continue;
        final type = d >= 4 && r.chance(0.3) ? 1 : 0;
        idx = clampI(idx + r.range(-2, 2), 0, pool.length - 1);
        evs.add(RunEv(beat, type, pool[idx]));
        last = beat;
      }
    }
    final drums = <(double, String)>[];
    for (var b = 0; b < bars + 1; b++) {
      final base = b * 4.0;
      drums.addAll([(base, 'dr_kick'), (base + 1, 'dr_snare'), (base + 2, 'dr_kick'), (base + 3, 'dr_snare')]);
      for (var h = 0; h < 8; h++) {
        drums.add((base + h * 0.5, 'dr_hat'));
      }
    }
    drums.sort((a, b) => a.$1.compareTo(b.$1));
    final bass = [for (var b = 0; b < bars + 1; b++) MNote(b * 4.0, 4, 40 + ((root - 4) % 12 + 12) % 12)];
    return RunPuzzle(bpm, bars, evs, drums, bass);
  }

  @override
  bool check(MPuzzle p) {
    if (p is! RunPuzzle) return false;
    if (p.evs.length < 8 || p.bpm < 70 || p.bpm > 170) return false;
    final bm = p.beatMs;
    for (var i = 0; i < p.evs.length; i++) {
      final e = p.evs[i];
      if (e.type < 0 || e.type > 1 || e.midi < kLowMidi || e.midi > kHighMidi) return false;
      if (e.beat < 4) return false;
      if (i > 0 && (e.beat - p.evs[i - 1].beat) * bm < 260) return false;
    }
    return p.lengthBeats * bm < 110000;
  }

  @override
  List<GameStat> get stats => const [
        GameStat('rounds_won', 'Tamamlanan koşu', 'Runs completed', scale: 10),
        GameStat('perfect', 'Kusursuz koşu', 'Perfect runs', scale: 10),
        GameStat('best_combo', 'En uzun seri', 'Best combo', scale: 50),
      ];

  @override
  List<MissionTemplate> get missions => const [
        MissionTemplate('win', 'rounds_won', [3, 10, 25]),
        MissionTemplate('combo', 'best_combo', [20, 60, 150]),
        MissionTemplate('perfect', 'perfect', [1, 5, 15]),
      ];

  @override
  Widget build(MuzikPlay play) => _RunView(play: play);
}

class _RunView extends StatefulWidget {
  final MuzikPlay play;
  const _RunView({required this.play});
  @override
  State<_RunView> createState() => _RunViewState();
}

class _RunViewState extends State<_RunView> with SingleTickerProviderStateMixin, SongClock<_RunView>, Clock<_RunView> {
  late final RunPuzzle p = widget.play.puzzle as RunPuzzle;
  static const double w = 400, h = 640, groundY = 470, runX = 110, pxBeat = 120;
  bool started = false, practice = false, over = false;
  int energy = 100, hints = 0;
  final Tally tally = Tally();
  late List<int> state = List.filled(p.evs.length, 0); // 0 bekliyor, 1 bitti
  final List<Burst> bursts = [];
  int nextDrum = 0, nextBass = 0, lastBeat = -99;
  double actAt = -1e9;
  int act = -1; // 0 zıplama, 1 kayma
  double stumbleAt = -1e9;

  double get speed => practice ? 0.8 : 1.0;
  double get beatMs => p.beatMs / speed;
  double evMs(RunEv e) => e.beat * beatMs;
  JudgeWindow get win => JudgeWindow.forLevel(widget.play.d, practice: practice);
  double get endMs => p.lengthBeats * beatMs;

  void _start() {
    setState(() {
      started = true;
      over = false;
      energy = 100 + 40 * hints;
      state = List.filled(p.evs.length, 0);
      nextDrum = 0;
      nextBass = 0;
      lastBeat = -99;
    });
    startClock();
    startSong(leadMs: beatMs * 4);
  }

  @override
  void onFrame() {
    if (over) return;
    final t = effMs;
    final bi = (t / beatMs).floor();
    if (bi != lastBeat) {
      lastBeat = bi;
      if (t < 0) {
        widget.play.sample(bi % 4 == 0 ? 'mt_hi' : 'mt_lo');
        Haptic.beat(strong: bi % 4 == 0);
      }
    }
    while (nextDrum < p.drums.length && p.drums[nextDrum].$1 * beatMs <= songMs) {
      widget.play.sample(p.drums[nextDrum].$2, volume: 0.7);
      nextDrum++;
    }
    while (nextBass < p.bass.length && p.bass[nextBass].beat * beatMs <= songMs) {
      widget.play.note(p.bass[nextBass].midi, volume: 0.3);
      nextBass++;
    }
    for (var i = 0; i < p.evs.length; i++) {
      if (state[i] != 0) continue;
      final tm = evMs(p.evs[i]);
      if (t - tm > win.good) {
        state[i] = 1;
        _miss();
      } else if (tm > t + win.good) {
        break;
      }
    }
    pruneBursts(bursts, t);
    if (t > endMs) _finish();
  }

  void _miss() {
    tally.add(Judge.miss);
    stumbleAt = effMs;
    bursts.add(Burst(const Offset(runX, groundY - 90), effMs, MColors.bad, judgeText(widget.play.lang, Judge.miss)));
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

  void _down(Offset pos) {
    if (!started || over || !running) return;
    final type = pos.dy < h / 2 ? 0 : 1;
    final t = effMs;
    act = type;
    actAt = t;
    var best = -1;
    var be = 1e9;
    for (var i = 0; i < p.evs.length; i++) {
      if (state[i] != 0) continue;
      final e = (t - evMs(p.evs[i])).abs();
      if (e < be) {
        be = e;
        best = i;
      }
      if (evMs(p.evs[i]) > t + win.good) break;
    }
    if (best < 0 || be > win.good) return;
    state[best] = 1;
    final ev = p.evs[best];
    if (ev.type != type) {
      _miss();
      return;
    }
    final j = win.judge(t - evMs(ev));
    tally.add(j);
    widget.play.note(ev.midi);
    Haptic.hit();
    energy = math.min<int>(100 + 40 * hints, energy + 3);
    bursts.add(Burst(const Offset(runX, groundY - 90), t, judgeColor(j), judgeText(widget.play.lang, j)));
    setState(() {});
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
    // Üst ve alt dokunma yarıları.
    c.drawRect(const Rect.fromLTWH(0, 0, w, h / 2), fill(MColors.lanes[2].withValues(alpha: 0.05)));
    c.drawRect(const Rect.fromLTWH(0, h / 2, w, h / 2), fill(MColors.lanes[4].withValues(alpha: 0.06)));
    // Zemin ve vuruş çizgileri (her vuruşta bir çizgi akar).
    c.drawRect(const Rect.fromLTWH(0, groundY, w, 24), fill(MColors.soft));
    final first = (t / beatMs).floor() - 1;
    for (var b = first; b < first + 6; b++) {
      final x = runX + (b * beatMs - t) / beatMs * pxBeat;
      if (x < -10 || x > w + 10) continue;
      c.drawLine(Offset(x, groundY), Offset(x, groundY + 24), stroke(Colors.white.withValues(alpha: b % 4 == 0 ? 0.5 : 0.2), 2));
    }
    c.drawLine(const Offset(runX, 120), const Offset(runX, groundY + 24), stroke(Colors.white24, 2));
    // Engeller.
    for (var i = 0; i < p.evs.length; i++) {
      final e = p.evs[i];
      final x = runX + (evMs(e) - t) / beatMs * pxBeat;
      if (x > w + 40) break;
      if (x < -40) continue;
      final col = state[i] == 1 ? Colors.white24 : (e.type == 0 ? MColors.lanes[2] : MColors.lanes[4]);
      if (e.type == 0) {
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x - 14, groundY - 32, 28, 32), const Radius.circular(5)), fill(col));
      } else {
        c.drawRect(Rect.fromLTWH(x - 20, 300, 6, groundY - 300), fill(col.withValues(alpha: 0.6)));
        c.drawRect(Rect.fromLTWH(x + 14, 300, 6, groundY - 300), fill(col.withValues(alpha: 0.6)));
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x - 22, 300, 44, groundY - 340), const Radius.circular(6)), fill(col));
      }
    }
    // Koşucu.
    final since = (t - actAt) / beatMs;
    var y = groundY;
    var crouch = false;
    if (act == 0 && since >= 0 && since < 0.7) y -= math.sin(since / 0.7 * math.pi) * 70;
    if (act == 1 && since >= 0 && since < 0.7) crouch = true;
    final stumble = t - stumbleAt < 300;
    final body = Colors.white.withValues(alpha: stumble ? 0.5 : 1);
    final legPhase = math.sin(t / beatMs * math.pi);
    if (crouch) {
      c.drawCircle(Offset(runX + 10, y - 18), 9, fill(body));
      c.drawLine(Offset(runX - 14, y - 12), Offset(runX + 6, y - 14), stroke(body, 6));
      c.drawLine(Offset(runX - 14, y - 12), Offset(runX - 24, y - 2), stroke(body, 5));
    } else {
      c.drawCircle(Offset(runX, y - 62), 10, fill(body));
      c.drawLine(Offset(runX, y - 52), Offset(runX - 2, y - 26), stroke(body, 6));
      c.drawLine(Offset(runX - 2, y - 26), Offset(runX - 10 + legPhase * 8, y), stroke(body, 5));
      c.drawLine(Offset(runX - 2, y - 26), Offset(runX + 10 - legPhase * 8, y), stroke(body, 5));
      c.drawLine(Offset(runX, y - 46), Offset(runX + 14, y - 36 - legPhase * 6), stroke(body, 4));
    }
    paintBursts(c, bursts, t);
    if (started) paintCountIn(c, t, beatMs, const Offset(w / 2, 220));
    final lang = widget.play.lang;
    drawLabel(c, '▲ ${mt(lang, 'jump')}', const Offset(w - 80, 40), 18, Colors.white54);
    drawLabel(c, '▼ ${mt(lang, 'slide')}', const Offset(w - 80, h - 60), 18, Colors.white54);
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(20, h - 30, w - 40, 12), const Radius.circular(6)), fill(Colors.white12));
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(20, h - 30, (w - 40) * clampI(energy, 0, 100) / 100, 12), const Radius.circular(6)),
        fill(energy > 35 ? MColors.good : MColors.bad));
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
              builder: (_, __, ___) => TapCanvas(w: w, h: h, paint: _paint, onDown: _down, semantics: mt(lang, 'runHelp')),
            )
          : StartCard(
              title: mt(lang, 'runTitle'),
              subtitle: '${p.bpm} BPM · ${p.evs.length}\n${mt(lang, 'runHelp')}${hints > 0 ? '\n${mt(lang, 'extraEnergy')}' : ''}',
              button: mt(lang, 'start'),
              onStart: _start,
              icon: Icons.directions_run,
            ),
    );
  }
}

// ================================================================ Usul ve Tala

/// Bir ritim devri: ad (özel ad, her dilde aynı), bölge (0 Türk usulü, 1 Arap
/// ikaı, 2 Hint talası), vuruşlar (D kalın, T ince, K hafif, . sus), birim (4 dörtlük, 8 sekizlik),
/// isteğe bağlı bol (hece) adları.
class UsulDef {
  final String name;
  final int region;
  final String strokes;
  final int unit;
  final String bols;
  const UsulDef(this.name, this.region, this.strokes, this.unit, [this.bols = '']);
  int get n => strokes.length;
}

/// Geleneksel (kamu malı) devirler; vuruşlar temel iskelettir.
const List<UsulDef> kUsuls = [
  UsulDef('Nim Sofyan', 0, 'DT', 4),
  UsulDef('Semai', 0, 'DTT', 4),
  UsulDef('Sofyan', 0, 'D.TK', 4),
  UsulDef('Türk Aksağı', 0, 'D.TT.', 8),
  UsulDef('Devr-i Hindi', 0, 'D..T.T.', 8),
  UsulDef('Düyek', 0, 'DT.TD.T.', 8),
  UsulDef('Çiftetelli', 0, 'D..TDDT.', 8),
  UsulDef('Aksak', 0, 'D.T.D.TK.', 8),
  UsulDef('Curcuna', 0, 'D..T.D.T..', 8),
  UsulDef('Malfuf', 1, 'D..T..T.', 8),
  UsulDef('Maqsum', 1, 'DT.TD.T.', 8),
  UsulDef('Baladi', 1, 'DD.TD.T.', 8),
  UsulDef('Saidi', 1, 'DT.DD.T.', 8),
  UsulDef('Ayyub', 1, 'D.KDT.', 8),
  UsulDef('Wahda', 1, 'D...T.K.', 8),
  UsulDef('Sama’i Thaqil', 1, 'D..T.DDT..', 8),
  UsulDef('Dadra', 2, 'DDTDTT', 4, 'dha dhi na | dha ti na'),
  UsulDef('Rupak', 2, 'TTTDTDT', 4, 'tin tin na | dhi na | dhi na'),
  UsulDef('Keharwa', 2, 'DDTTTKDT', 4, 'dha ge na ti | na ka dhi na'),
  UsulDef('Jhaptaal', 2, 'DTDDTTTDDT', 4, 'dhi na | dhi dhi na | ti na | dhi dhi na'),
  UsulDef('Teentaal', 2, 'DDDDDDDDDTTTTDDD', 4, 'dha dhin dhin dha | dha dhin dhin dha | dha tin tin ta | ta dhin dhin dha'),
];

class UsulPuzzle extends MPuzzle {
  final int usul;
  final int bpm;
  final int cycles;

  /// 0 eşlik vuruşları duyulur, 1 yalnız nabız, 2 yalnız devir başı.
  final int guide;
  final bool ka;
  const UsulPuzzle(this.usul, this.bpm, this.cycles, this.guide, this.ka);

  UsulDef get def => kUsuls[usul];
  String get pattern => ka ? def.strokes : def.strokes.replaceAll('K', 'T');
  double get pulseMs => 60000 / bpm;

  @override
  Set<String> get samples => const {'dr_dum', 'dr_tek', 'dr_ka', 'mt_hi', 'mt_lo'};
}

class UsulKind extends MuzikKind {
  @override
  String get id => 'usul-tala';
  const UsulKind();

  @override
  MPuzzle? make(int d, SeededRandom r, {bool short = false}) {
    final maxN = d <= 2 ? 4 : (d <= 4 ? 8 : (d <= 6 ? 10 : 16));
    final pool = [for (var i = 0; i < kUsuls.length; i++) if (kUsuls[i].n <= maxN) i];
    final u = r.pick(pool);
    final def = kUsuls[u];
    final bpm = def.unit == 8 ? 150 + d * 12 + r.range(-6, 6) : 72 + d * 7 + r.range(-4, 4);
    final cycles = short ? 2 : math.max(2, math.min(6, (24 + d * 3) ~/ def.n));
    return UsulPuzzle(u, bpm, cycles, d <= 3 ? 0 : (d <= 7 ? 1 : 2), d >= 5);
  }

  @override
  bool check(MPuzzle p) {
    if (p is! UsulPuzzle || p.usul < 0 || p.usul >= kUsuls.length) return false;
    final pat = p.pattern;
    final strokes = pat.replaceAll('.', '').length;
    if (strokes < 2 || !pat.startsWith('D') && !pat.startsWith('T')) return false;
    if (p.bpm < 60 || p.bpm > 300 || p.cycles < 2) return false;
    // Arka arkaya iki vuruş arası en az 180 ms.
    if (p.pulseMs < 180) return false;
    return (p.cycles + 1) * pat.length * p.pulseMs < 100000;
  }

  @override
  Widget build(MuzikPlay play) => _UsulView(play: play);
}

String _strokeSample(String s) => s == 'D' ? 'dr_dum' : (s == 'K' ? 'dr_ka' : 'dr_tek');

class _UsulView extends StatefulWidget {
  final MuzikPlay play;
  const _UsulView({required this.play});
  @override
  State<_UsulView> createState() => _UsulViewState();
}

class _UsulViewState extends State<_UsulView> with SingleTickerProviderStateMixin, SongClock<_UsulView>, Clock<_UsulView> {
  late final UsulPuzzle p = widget.play.puzzle as UsulPuzzle;
  static const double w = 400, h = 560;
  static const Offset c0 = Offset(200, 210);
  bool started = false, practice = false, over = false;
  int hints = 0, lastPulse = -999;
  final Tally tally = Tally();
  final List<Burst> bursts = [];
  late final String pat = p.pattern;
  late final List<(double, String)> evs = [
    for (var c = 1; c <= p.cycles; c++)
      for (var i = 0; i < pat.length; i++)
        if (pat[i] != '.') ((c * pat.length + i).toDouble(), pat[i]),
  ];
  late List<int> state = List.filled(evs.length, 0);

  double get pulseMs => p.pulseMs / (practice ? 0.8 : 1.0);
  JudgeWindow get win => JudgeWindow.forLevel(widget.play.d, practice: practice);
  double get endMs => ((p.cycles + 1) * pat.length + 1) * pulseMs;

  void _start() {
    setState(() {
      started = true;
      over = false;
      state = List.filled(evs.length, 0);
      lastPulse = -999;
    });
    startClock();
    startSong(leadMs: pulseMs * 4);
  }

  @override
  void onFrame() {
    if (over) return;
    final t = effMs;
    final pi = (t / pulseMs).floor();
    if (pi != lastPulse) {
      lastPulse = pi;
      if (pi < 0) {
        widget.play.sample(pi == -4 ? 'mt_hi' : 'mt_lo');
      } else {
        final cyc = pi ~/ pat.length, k = pi % pat.length;
        final s = k < pat.length ? pat[k] : '.';
        if (cyc == 0) {
          // Dinleme devri: bütün vuruşlar çalınır.
          if (s != '.') widget.play.sample(_strokeSample(s));
          Haptic.beat(strong: s == 'D');
        } else if (cyc <= p.cycles) {
          final g = practice ? 0 : p.guide;
          if (g == 0 && s != '.') widget.play.sample(_strokeSample(s), volume: 0.3);
          if (g <= 1 && k != 0) widget.play.sample('mt_lo', volume: 0.35);
          if (k == 0) widget.play.sample('mt_hi', volume: 0.5);
        }
      }
    }
    for (var i = 0; i < evs.length; i++) {
      if (state[i] != 0) continue;
      final tm = evs[i].$1 * pulseMs;
      if (t - tm > win.good) {
        state[i] = 1;
        tally.add(Judge.miss);
        bursts.add(Burst(c0, t, MColors.bad, judgeText(widget.play.lang, Judge.miss)));
      } else if (tm > t + win.good) {
        break;
      }
    }
    pruneBursts(bursts, t);
    if (t > endMs) _finish();
  }

  void _pad(String s) {
    widget.play.sample(_strokeSample(s));
    if (!started || over || !running) return;
    final t = effMs;
    var best = -1;
    var be = 1e9;
    for (var i = 0; i < evs.length; i++) {
      if (state[i] != 0) continue;
      final e = (t - evs[i].$1 * pulseMs).abs();
      if (e < be) {
        be = e;
        best = i;
      }
      if (evs[i].$1 * pulseMs > t + win.good) break;
    }
    if (best < 0 || be > win.good) return;
    state[best] = 1;
    final j = evs[best].$2 == s ? win.judge(t - evs[best].$1 * pulseMs) : Judge.miss;
    tally.add(j);
    if (j == Judge.miss) {
      Haptic.miss();
    } else {
      Haptic.hit();
    }
    bursts.add(Burst(c0, t, judgeColor(j), judgeText(widget.play.lang, j)));
    setState(() {});
  }

  void _finish() {
    if (over) return;
    over = true;
    stopSong();
    final acc = tally.accuracy;
    if (acc >= 0.6 || practice) {
      final stars = starsByAccuracy(acc, practice: practice, hints: hints);
      later(400, () => widget.play.win(score: tally.score, stars: stars, seconds: seconds, hints: hints));
    } else {
      widget.play.sfx(Sfx.lose);
      later(600, () => widget.play.lose(score: tally.score, seconds: seconds, headline: '${(acc * 100).round()}%'));
    }
  }

  Future<void> _hint() async {
    if (started) return;
    if (await widget.play.ctx.requestHint()) setState(() => practice = true);
  }

  void _paint(Canvas c) {
    final t = effMs;
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, w, h), const Radius.circular(18)), fill(MColors.stage));
    const r = 140.0;
    c.drawCircle(c0, r, stroke(Colors.white24, 2));
    c.drawCircle(c0, 62, fill(const Color(0xFFF1DFC0)));
    c.drawCircle(c0, 62, stroke(const Color(0xFF7A4A24), 6));
    final n = pat.length;
    final pos = t / pulseMs;
    final cyc = pos < 0 ? -1 : pos ~/ n;
    for (var i = 0; i < n; i++) {
      final a = -math.pi / 2 + i * 2 * math.pi / n;
      final o = c0 + Offset(math.cos(a), math.sin(a)) * r;
      final s = pat[i];
      final col = s == 'D' ? MColors.bad : (s == 'T' ? MColors.ok : (s == 'K' ? MColors.accent : Colors.white24));
      final rad = s == 'D' ? 17.0 : (s == '.' ? 5.0 : 12.0);
      c.drawCircle(o, rad, fill(col));
      if (s != '.') {
        final lab = s == 'D' ? mt(widget.play.lang, 'dum') : (s == 'T' ? mt(widget.play.lang, 'tekS') : mt(widget.play.lang, 'kaS'));
        drawLabel(c, lab, o + Offset(math.cos(a), math.sin(a)) * 32, 13, Colors.white70);
      }
    }
    if (pos >= 0) {
      final frac = pos - (pos ~/ n) * n;
      final a = -math.pi / 2 + frac * 2 * math.pi / n;
      c.drawLine(c0, c0 + Offset(math.cos(a), math.sin(a)) * (r - 20), stroke(Colors.white, 4));
    }
    final lang = widget.play.lang;
    drawLabel(c, cyc <= 0 ? mt(lang, 'listen') : '${mt(lang, 'cycle')} $cyc/${p.cycles}', c0, 20, MColors.ink, weight: FontWeight.w900);
    if (p.def.bols.isNotEmpty) drawLabel(c, p.def.bols, const Offset(w / 2, 395), 14, Colors.white70);
    paintBursts(c, bursts, t);
    if (started) paintCountIn(c, t, pulseMs, const Offset(w / 2, 470));
  }

  Widget _padBtn(String s, Color col, {double flex = 1}) => Expanded(
        flex: (flex * 10).round(),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (_) => _pad(s),
            child: Container(
              height: 96,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(22), boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 3))]),
              child: Text(s == 'D' ? mt(widget.play.lang, 'dum') : (s == 'T' ? mt(widget.play.lang, 'tekS') : mt(widget.play.lang, 'kaS')),
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final lang = widget.play.lang;
    final region = mt(lang, ['regTr', 'regAr', 'regIn'][p.def.region]);
    return MScreen(
      bar: MBar(
        play: widget.play,
        left: '${tally.combo}×',
        status: '${p.def.name} · ${mt(lang, 'score')} ${tally.score}',
        practice: started ? null : practice,
        onPractice: (v) => setState(() => practice = v),
        onHint: started ? null : _hint,
        tools: !started,
      ),
      board: started
          ? ValueListenableBuilder<int>(valueListenable: frame, builder: (_, __, ___) => TapCanvas(w: w, h: h, paint: _paint, semantics: mt(lang, 'usulHelp')))
          : StartCard(
              title: p.def.name,
              subtitle: '$region · ${pat.length} · ${p.bpm} BPM\n${mt(lang, 'usulHelp')}',
              button: mt(lang, 'start'),
              onStart: _start,
              icon: Icons.album,
            ),
      bottom: Directionality(
        textDirection: TextDirection.ltr,
        child: Row(children: [
          _padBtn('D', const Color(0xFFB4523A), flex: 1.4),
          if (p.ka) _padBtn('K', const Color(0xFF4E6FB5), flex: 0.8),
          _padBtn('T', const Color(0xFFC9962E)),
        ]),
      ),
    );
  }
}

// ================================================================ Kalimba ve Gamelan

/// Çalgı: 0 kalimba (Do majör, 10 dil), 1 gamelan slendro (7 çubuk), 2 gamelan pelog (7 çubuk).
int kalKeys(int instr) => instr == 0 ? 10 : 7;

double kalFreq(int instr, int k) {
  if (instr == 0) {
    const midi = [60, 62, 64, 65, 67, 69, 71, 72, 74, 76];
    return 440 * math.pow(2, (midi[k] - 69) / 12).toDouble();
  }
  if (instr == 1) return 270 * math.pow(2, k * 240 / 1200).toDouble();
  const pelog = [0, 120, 270, 540, 670, 785, 950];
  return 290 * math.pow(2, pelog[k] / 1200).toDouble();
}

/// Kalimba: kısa tıkırtılı başlangıç, metalik üst ses, hızlı sönüm.
List<double> kalimbaPcm(double f) {
  const rate = Synth.rate;
  final n = (rate * 1.3).round();
  final out = List<double>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    final t = i / rate;
    final v = math.sin(2 * math.pi * f * t) * math.exp(-3.2 * t) +
        0.22 * math.sin(2 * math.pi * f * 5.43 * t) * math.exp(-11 * t) +
        0.08 * math.sin(2 * math.pi * f * 2 * t) * math.exp(-6 * t);
    final a = math.min(1.0, t / 0.004);
    out[i] = 0.55 * v * a;
  }
  return out;
}

/// Gamelan çubuğu: uyumsuz kısmi sesler ve ikiz telin dalgalanması (ombak).
List<double> gamelanPcm(double f, {double dur = 2.2, double decay = 1.5}) {
  const rate = Synth.rate;
  final n = (rate * dur).round();
  final out = List<double>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    final t = i / rate;
    final base = 0.5 * (math.sin(2 * math.pi * f * t) + math.sin(2 * math.pi * f * 1.004 * t));
    final v = base + 0.42 * math.sin(2 * math.pi * f * 2.76 * t) * math.exp(-3 * t) + 0.16 * math.sin(2 * math.pi * f * 5.4 * t) * math.exp(-7 * t);
    final a = math.min(1.0, t / 0.006);
    out[i] = 0.45 * v * a * math.exp(-decay * t);
  }
  return out;
}

class KalPuzzle extends MPuzzle {
  final int instr;
  final List<List<int>> phrases;
  final int noteMs;
  const KalPuzzle(this.instr, this.phrases, this.noteMs);
}

class KalimbaKind extends MuzikKind {
  @override
  String get id => 'kalimba-gamelan';
  const KalimbaKind();

  @override
  MPuzzle? make(int d, SeededRandom r, {bool short = false}) {
    final instr = d <= 2 ? 0 : r.nextInt(3);
    final keys = kalKeys(instr);
    final rounds = short ? 3 : 4 + d ~/ 2;
    final phrases = <List<int>>[];
    final span = instr == 0 ? math.min(keys, 5 + d ~/ 2) : keys;
    for (var i = 0; i < rounds; i++) {
      final len = 3 + d ~/ 3 + i ~/ 2;
      final ph = <int>[];
      var k = r.nextInt(span);
      for (var j = 0; j < len; j++) {
        ph.add(k);
        final stepMax = d <= 3 ? 2 : 3;
        var nk = k + r.range(-stepMax, stepMax);
        if (nk == k) nk += r.chance(0.5) ? 1 : -1;
        k = clampI(nk, 0, span - 1);
      }
      phrases.add(ph);
    }
    return KalPuzzle(instr, phrases, math.max(260, 560 - d * 28));
  }

  @override
  bool check(MPuzzle p) {
    if (p is! KalPuzzle || p.phrases.length < 3) return false;
    final keys = kalKeys(p.instr);
    for (var i = 0; i < p.phrases.length; i++) {
      final ph = p.phrases[i];
      if (ph.length < 3 || ph.length > 14) return false;
      if (i > 0 && ph.length < p.phrases[i - 1].length) return false;
      if (ph.any((k) => k < 0 || k >= keys)) return false;
      if (ph.toSet().length < 2) return false;
    }
    return p.noteMs >= 200;
  }

  @override
  Widget build(MuzikPlay play) => _KalView(play: play);
}

class _KalView extends StatefulWidget {
  final MuzikPlay play;
  const _KalView({required this.play});
  @override
  State<_KalView> createState() => _KalViewState();
}

class _KalViewState extends State<_KalView> with Clock<_KalView> {
  late final KalPuzzle p = widget.play.puzzle as KalPuzzle;
  late final SynthVoice synth = SynthVoice(sound: widget.play.voice.sound);
  static const double w = 400, h = 420;

  /// 0 başlangıç, 1 dinle, 2 sıra sende, 3 bitti; 9 serbest çalma.
  int phase = 0;
  int round = 0, pos = 0, mistakes = 0, hints = 0, token = 0;
  int lit = -1;

  int get keys => kalKeys(p.instr);

  @override
  void dispose() {
    synth.dispose();
    super.dispose();
  }

  void _tone(int k) {
    final f = kalFreq(p.instr, k);
    if (p.instr == 0) {
      synth.play('kal0_$k', () => kalimbaPcm(f));
    } else {
      synth.play('gam${p.instr}_$k', () => gamelanPcm(f));
    }
  }

  void _gong() => synth.play('gong', () => gamelanPcm(68, dur: 3.2, decay: 0.7), volume: 0.9);

  void _start() {
    setState(() => phase = 1);
    startClock();
    _playPhrase();
  }

  void _playPhrase() {
    final ph = p.phrases[round];
    final my = ++token;
    setState(() {
      phase = 1;
      pos = 0;
    });
    for (var i = 0; i < ph.length; i++) {
      later(500 + i * p.noteMs, () {
        if (my != token) return;
        _tone(ph[i]);
        setState(() => lit = ph[i]);
        later(p.noteMs * 2 ~/ 3, () {
          if (my == token && lit == ph[i]) setState(() => lit = -1);
        });
      });
    }
    later(500 + ph.length * p.noteMs, () {
      if (my != token) return;
      if (p.instr != 0) _gong();
      setState(() {
        phase = 2;
        lit = -1;
      });
    });
  }

  void _key(int k) {
    _tone(k);
    setState(() => lit = k);
    final my = token;
    later(180, () {
      if (my == token && lit == k) setState(() => lit = -1);
    });
    if (phase != 2) return;
    final ph = p.phrases[round];
    if (ph[pos] == k) {
      pos++;
      if (pos >= ph.length) {
        widget.play.sfx(Sfx.clear);
        if (round + 1 >= p.phrases.length) return _finish();
        setState(() {
          round++;
          phase = 1;
        });
        later(700, _playPhrase);
      }
      return;
    }
    widget.play.sfx(Sfx.error);
    Haptic.miss();
    mistakes++;
    if (mistakes >= 3 + hints) {
      ended = true;
      setState(() => phase = 3);
      widget.play.sfx(Sfx.lose);
      later(500, () => widget.play.lose(seconds: seconds, headline: '${round + 1}/${p.phrases.length}'));
      return;
    }
    later(500, _playPhrase);
  }

  void _finish() {
    ended = true;
    setState(() => phase = 3);
    widget.play.sfx(Sfx.win);
    final stars = mistakes == 0 ? 3 : (mistakes == 1 ? 2 : 1);
    later(500, () => widget.play.win(score: p.phrases.fold<int>(0, (a, b) => a + b.length * 20) - mistakes * 30, stars: stars - hints, seconds: seconds, hints: hints));
  }

  Future<void> _hint() async {
    if (phase != 2) return;
    if (await widget.play.ctx.requestHint()) {
      setState(() => hints++);
      _playPhrase();
    }
  }

  /// Kalimbada dillerin dizilişi: en kalın ortada, sırayla sağa ve sola.
  List<int> get _order {
    if (p.instr != 0) return [for (var i = 0; i < keys; i++) i];
    final o = <int>[];
    for (var i = keys - 1; i >= 0; i--) {
      if (i.isEven) {
        o.insert(0, i);
      } else {
        o.add(i);
      }
    }
    return o;
  }

  int _hit(Offset at) {
    final o = _order;
    final col = clampI((at.dx - 20) * o.length ~/ (w - 40), 0, o.length - 1);
    return o[col];
  }

  void _paint(Canvas c) {
    final o = _order;
    final colW = (w - 40) / o.length;
    if (p.instr == 0) {
      final body = RRect.fromRectAndRadius(const Rect.fromLTWH(10, 20, w - 20, h - 40), const Radius.circular(40));
      c.drawRRect(body, Paint()..shader = const LinearGradient(colors: [Color(0xFFD9A066), Color(0xFF9C6431)]).createShader(body.outerRect));
      c.drawCircle(const Offset(w / 2, h - 110), 34, fill(const Color(0xFF5B3A24)));
      c.drawRect(const Rect.fromLTWH(20, 150, w - 40, 10), fill(const Color(0xFF8A8F98)));
      for (var col = 0; col < o.length; col++) {
        final k = o[col];
        final len = 60 + (keys - 1 - k) * 12.0;
        final x = 20 + col * colW + colW * 0.25;
        final r = RRect.fromRectAndRadius(Rect.fromLTWH(x, 150 - len * 0.9, colW * 0.5, len + 20), const Radius.circular(6));
        c.drawRRect(r, fill(lit == k ? Colors.white : const Color(0xFFD6DCE3)));
        if (lit == k) c.drawRRect(r.inflate(4), stroke(MColors.ok, 3));
      }
    } else {
      final frame = RRect.fromRectAndRadius(const Rect.fromLTWH(10, 60, w - 20, h - 120), const Radius.circular(16));
      c.drawRRect(frame, fill(const Color(0xFF6B2E1E)));
      c.drawRRect(frame, stroke(const Color(0xFFD9A441), 4));
      for (var col = 0; col < o.length; col++) {
        final k = o[col];
        final bh = 210 - k * 14.0;
        final x = 20 + col * colW + 4;
        final r = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x + (colW - 8) / 2, h / 2), width: colW - 8, height: bh), const Radius.circular(8));
        c.drawRRect(r, Paint()..shader = LinearGradient(colors: lit == k ? [Colors.white, const Color(0xFFFFE08A)] : [const Color(0xFFF2C14E), const Color(0xFFB57F16)]).createShader(r.outerRect));
        c.drawCircle(Offset(r.center.dx, r.top + 12), 4, fill(Colors.black38));
        c.drawCircle(Offset(r.center.dx, r.bottom - 12), 4, fill(Colors.black38));
        drawLabel(c, '${k + 1}', Offset(r.center.dx, r.center.dy), 18, MColors.ink);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.play.lang;
    final name = mt(lang, ['kalimba', 'slendro', 'pelog'][p.instr]);
    final status = switch (phase) {
      1 => mt(lang, 'listen'),
      2 => mt(lang, 'yourTurn'),
      _ => name,
    };
    final board = TapCanvas(w: w, h: h, paint: _paint, onDown: (at) => _key(_hit(at)), semantics: mt(lang, 'kalHelp'));
    return MScreen(
      bar: MBar(
        play: widget.play,
        left: phase == 0 || phase == 9 ? '' : '${round + 1}/${p.phrases.length}',
        status: status,
        onHint: phase == 2 ? _hint : null,
        tools: phase == 0,
      ),
      top: Text(phase == 0 ? '' : '${'●' * clampI(3 + hints - mistakes, 0, 9)}  ${phase == 2 ? '$pos/${p.phrases[round].length}' : ''}',
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
      board: phase == 0
          ? StartCard(title: name, subtitle: mt(lang, 'kalHelp'), button: mt(lang, 'start'), onStart: _start, icon: Icons.music_note)
          : board,
      bottom: phase == 0 || phase == 9
          ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              MChip(
                selected: phase == 9,
                onTap: phase == 9 ? _start : () => setState(() => phase = 9),
                child: Text(phase == 9 ? mt(lang, 'start') : mt(lang, 'freeTry')),
              ),
            ])
          : null,
    );
  }
}

// ================================================================ Melodi Bulmacası

class MelPuzPuzzle extends MPuzzle {
  final List<MNote> notes;

  /// Parça başlangıç vuruşları (artan), son eleman ezginin sonu.
  final List<double> cuts;

  /// Havuzdaki gösterim sırası (parça kimlikleri).
  final List<int> order;
  final int bpm;
  final bool contour;
  final bool lockFirst;
  const MelPuzPuzzle(this.notes, this.cuts, this.order, this.bpm, this.contour, this.lockFirst);

  int get pieces => cuts.length - 1;
  List<MNote> piece(int i) => [for (final n in notes) if (n.beat >= cuts[i] - 1e-9 && n.beat < cuts[i + 1] - 1e-9) n];
  double get beatMs => 60000 / bpm;

  @override
  Set<String> get samples => {for (final n in notes) pianoSample(n.midi)};
}

String _pieceKey(List<MNote> ps, double start) => ps.map((n) => '${(n.beat - start).toStringAsFixed(2)}/${n.dur.toStringAsFixed(2)}/${n.midi}').join(',');

class MelPuzKind extends MuzikKind {
  @override
  String get id => 'melodi-bulmacasi';
  const MelPuzKind();

  @override
  MPuzzle? make(int d, SeededRandom r, {bool short = false}) {
    final bars = d <= 3 ? 3 : 4;
    final perBar = d >= 7 ? 2 : 1;
    final root = r.nextInt(12);
    final sc = d <= 3 ? kPentaMajor : (r.chance(0.6) ? kMajor : kMinor);
    final mel = genMelody(r, rootPc: root, scale: sc, bars: bars, beatsPerBar: 4, level: d, lo: 60, hi: 79);
    if (!melodyOk(mel, lo: 57, hi: 84)) return null;
    final step = 4.0 / perBar;
    final cuts = [for (var i = 0; i <= bars * perBar; i++) i * step];
    for (var i = 0; i < cuts.length - 1; i++) {
      if (!mel.any((n) => (n.beat - cuts[i]).abs() < 1e-9)) return null;
    }
    final order = perm(cuts.length - 1, r);
    return MelPuzPuzzle(mel, cuts, order, 84 + d * 4, d <= 3, d <= 2);
  }

  @override
  bool check(MPuzzle p) {
    if (p is! MelPuzPuzzle) return false;
    final k = p.pieces;
    if (k < 3 || k > 8 || p.order.length != k || p.order.toSet().length != k) return false;
    if (p.order.any((x) => x < 0 || x >= k)) return false;
    var identity = true;
    for (var i = 0; i < k; i++) {
      if (p.order[i] != i) identity = false;
    }
    if (identity) return false;
    final keys = <String>{};
    for (var i = 0; i < k; i++) {
      final ps = p.piece(i);
      if (ps.isEmpty) return false;
      if (!keys.add(_pieceKey(ps, p.cuts[i]))) return false;
    }
    return melodyOk(p.notes, lo: 57, hi: 84);
  }

  @override
  Widget build(MuzikPlay play) => _MelPuzView(play: play);
}

List<int> perm(int n, SeededRandom r) {
  final l = [for (var i = 0; i < n; i++) i];
  r.shuffle(l);
  return l;
}

class _MelPuzView extends StatefulWidget {
  final MuzikPlay play;
  const _MelPuzView({required this.play});
  @override
  State<_MelPuzView> createState() => _MelPuzViewState();
}

class _MelPuzViewState extends State<_MelPuzView> with Clock<_MelPuzView> {
  late final MelPuzPuzzle p = widget.play.puzzle as MelPuzPuzzle;
  late List<int> slots = List.filled(p.pieces, -1);
  late List<bool> locked = List.filled(p.pieces, false);
  int sel = -1, lives = 3, hints = 0, token = 0, playing = -1, lastOk = -1;

  @override
  void initState() {
    super.initState();
    if (p.lockFirst) {
      slots[0] = 0;
      locked[0] = true;
    }
    startClock();
  }

  List<int> get pool => [for (final i in p.order) if (!slots.contains(i)) i];

  void _playNotes(List<MNote> ns, double start, {int tag = -1}) {
    final my = ++token;
    setState(() => playing = tag);
    for (final n in ns) {
      later(((n.beat - start) * p.beatMs).round(), () {
        if (my == token) widget.play.note(n.midi);
      });
    }
    final end = ns.isEmpty ? 0.0 : ns.last.beat + ns.last.dur - start;
    later((end * p.beatMs).round() + 50, () {
      if (my == token) setState(() => playing = -1);
    });
  }

  void _playPiece(int i) => _playNotes(p.piece(i), p.cuts[i], tag: i);

  void _playAll() {
    final ns = <MNote>[];
    var t = 0.0;
    for (final s in slots) {
      if (s < 0) {
        t += p.cuts[1] - p.cuts[0];
        continue;
      }
      for (final n in p.piece(s)) {
        ns.add(MNote(t + n.beat - p.cuts[s], n.dur, n.midi));
      }
      t += p.cuts[s + 1] - p.cuts[s];
    }
    _playNotes(ns, 0, tag: 99);
  }

  void _tapPool(int piece) {
    _playPiece(piece);
    setState(() => sel = piece);
  }

  void _tapSlot(int i) {
    if (locked[i]) {
      if (slots[i] >= 0) _playPiece(slots[i]);
      return;
    }
    if (sel >= 0) {
      setState(() {
        final from = slots.indexOf(sel);
        if (from >= 0) slots[from] = slots[i];
        slots[i] = sel;
        sel = -1;
      });
      widget.play.sfx(Sfx.place);
      return;
    }
    if (slots[i] >= 0) {
      _playPiece(slots[i]);
      setState(() => sel = slots[i]);
    }
  }

  void _clearSlot(int i) {
    if (locked[i] || slots[i] < 0) return;
    setState(() => slots[i] = -1);
  }

  void _check() {
    if (slots.contains(-1) || ended) return;
    var ok = 0;
    for (var i = 0; i < slots.length; i++) {
      if (slots[i] == i) ok++;
    }
    if (ok == slots.length) {
      ended = true;
      widget.play.sfx(Sfx.win);
      _playAll();
      final stars = (lives == 3 ? 3 : (lives == 2 ? 2 : 1)) - hints;
      later(1200, () => widget.play.win(score: 300 + lives * 100 - hints * 50, stars: stars, seconds: seconds, hints: hints));
      return;
    }
    widget.play.sfx(Sfx.error);
    Haptic.miss();
    setState(() {
      lives--;
      lastOk = ok;
    });
    if (lives <= 0) {
      ended = true;
      later(500, () => widget.play.lose(seconds: seconds, headline: '${mt(widget.play.lang, 'inPlace')}: $ok/${slots.length}'));
    }
  }

  Future<void> _hint() async {
    var i = -1;
    for (var k = 0; k < slots.length; k++) {
      if (slots[k] != k) {
        i = k;
        break;
      }
    }
    if (i < 0 || ended) return;
    if (!await widget.play.ctx.requestHint()) return;
    setState(() {
      hints++;
      // Doğru parça başka kutudaysa oradan alınır; kutudaki yanlış parça havuza döner.
      final from = slots.indexOf(i);
      if (from >= 0) slots[from] = -1;
      slots[i] = i;
      locked[i] = true;
      sel = -1;
    });
  }

  Widget _card(int piece, {int slot = -1}) {
    final look = StudioLook.of(context);
    final active = sel == piece || playing == piece;
    final ns = piece >= 0 ? p.piece(piece) : const <MNote>[];
    return Container(
      height: 74,
      decoration: BoxDecoration(
        color: piece < 0 ? Colors.white10 : (active ? Color.lerp(look.card, look.accent, 0.55) : Color.lerp(look.card, Colors.white, 0.1)),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: slot >= 0 && locked[slot] ? MColors.good : (active ? look.accent : Colors.white24), width: active ? 2.5 : 1.2),
      ),
      child: piece < 0
          ? Center(child: Text('${slot + 1}', style: const TextStyle(color: Colors.white54, fontSize: 20, fontWeight: FontWeight.w800)))
          : CustomPaint(painter: _PiecePainter(ns, p.cuts[piece], p.cuts[piece + 1] - p.cuts[piece], p.contour, MColors.lanes[piece % MColors.lanes.length])),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.play.lang;
    final k = p.pieces;
    return MScreen(
      bar: MBar(
        play: widget.play,
        left: '♥' * lives,
        status: lastOk >= 0 ? '${mt(lang, 'inPlace')}: $lastOk/$k' : clock(),
        onHint: ended ? null : _hint,
        tools: false,
      ),
      top: Text(mt(lang, 'puzHelp'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
      board: Directionality(
        textDirection: TextDirection.ltr,
        child: Column(children: [
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: k <= 4 ? k : 4,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.1,
            children: [
              for (var i = 0; i < k; i++)
                GestureDetector(onTap: () => _tapSlot(i), onLongPress: () => _clearSlot(i), child: _card(slots[i], slot: i)),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(color: Colors.white24),
          const SizedBox(height: 8),
          Expanded(
            child: GridView.count(
              crossAxisCount: 4,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.1,
              children: [for (final i in pool) GestureDetector(onTap: () => _tapPool(i), child: _card(i))],
            ),
          ),
        ]),
      ),
      bottom: Row(children: [
        Expanded(child: StudioButton(label: mt(lang, 'playAll'), icon: Icons.play_arrow_rounded, onPressed: _playAll)),
        const SizedBox(width: 8),
        Expanded(child: StudioButton(label: mt(lang, 'checkIt'), icon: Icons.check_rounded, onPressed: slots.contains(-1) || ended ? null : _check)),
      ]),
    );
  }
}

class _PiecePainter extends CustomPainter {
  final List<MNote> ns;
  final double start;
  final double len;
  final bool contour;
  final Color color;
  _PiecePainter(this.ns, this.start, this.len, this.contour, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    // Ezgi çizgisi kolay bölümlerde görünür; sonrasında yalnızca nota sayısı kadar nokta.
    final lo = ns.map((n) => n.midi).reduce((a, b) => a < b ? a : b) - 2;
    final hi = ns.map((n) => n.midi).reduce((a, b) => a > b ? a : b) + 2;
    for (final n in ns) {
      final x = 10 + (n.beat - start) / len * (size.width - 20);
      final y = contour ? size.height - 10 - (n.midi - lo) / (hi - lo) * (size.height - 20) : size.height / 2;
      final wd = math.max(6.0, n.dur / len * (size.width - 20) - 3);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y - 4, wd, 8), const Radius.circular(4)), Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _PiecePainter old) => old.ns != ns || old.contour != contour;
}
