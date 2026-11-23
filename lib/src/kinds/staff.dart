import 'package:flutter/material.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';

import '../audio.dart';
import '../core.dart';
import '../texts.dart';
import '../theory.dart';

/// Nota Okuma: dizekteki notayı tanı. Sol ve fa anahtarı, ek çizgiler,
/// diyezler; ileri bölümlerde tam oktavıyla klavyede bul.
class StaffNote {
  final int midi;
  final int clef; // 0 sol, 1 fa
  const StaffNote(this.midi, this.clef);
}

class StaffPuzzle extends MPuzzle {
  final List<StaffNote> notes;
  final bool accidentals;
  final bool exact;
  final int seconds;
  final int kbLo;
  final int kbHi;
  const StaffPuzzle(this.notes, this.accidentals, this.exact, this.seconds, this.kbLo, this.kbHi);

  @override
  Set<String> get samples => {for (final n in notes) pianoSample(n.midi)};
}

/// Diyatonik basamak numarası (C0 = 0).
int diatonic(int midi) {
  final (i, _) = spell(midi % 12);
  return (midi ~/ 12 - 1) * 7 + i;
}

/// Dizeğin alt çizgisinin basamağı: sol anahtarında E4, fa anahtarında G2.
int bottomLine(int clef) => clef == 0 ? diatonic(64) : diatonic(43);

class StaffKind extends MuzikKind {
  @override
  String get id => 'nota-ogrenme';
  const StaffKind();

  @override
  MPuzzle? make(int d, SeededRandom r, {bool short = false}) {
    final count = short ? 8 : 20;
    final acc = d >= 6;
    final exact = d >= 8;
    final notes = <StaffNote>[];
    // Basamak aralıkları (alt çizgiye göre): 0..8 dizek içi, eksiler/artılar ek çizgi.
    final spanLo = d <= 1 ? 0 : (d <= 2 ? -2 : -4);
    final spanHi = d <= 1 ? 8 : (d <= 2 ? 10 : 12);
    var g = 0;
    while (notes.length < count && g++ < 400) {
      final clef = d <= 3 ? 0 : (d == 4 ? 1 : (r.chance(0.5) ? 0 : 1));
      final step = r.range(spanLo, spanHi);
      final dia = bottomLine(clef) + step;
      // Basamaktan MIDI'ye.
      const nat = [0, 2, 4, 5, 7, 9, 11];
      var m = (dia ~/ 7 + 1) * 12 + nat[dia % 7];
      if (acc && r.chance(0.35) && const [0, 2, 5, 7, 9].contains(m % 12)) m += 1;
      if (m < kLowMidi || m > kHighMidi) continue;
      if (notes.isNotEmpty && notes.last.midi == m) continue;
      notes.add(StaffNote(m, clef));
    }
    if (notes.length < count) return null;
    var lo = notes.map((n) => n.midi).reduce((a, b) => a < b ? a : b);
    var hi = notes.map((n) => n.midi).reduce((a, b) => a > b ? a : b);
    lo = (lo ~/ 12) * 12;
    hi = ((hi ~/ 12) + 1) * 12 - 1;
    if (!exact) {
      lo = 60;
      hi = 71;
    }
    final secs = short ? 60 : (d <= 3 ? 150 : (d <= 6 ? 120 : 100));
    return StaffPuzzle(notes, acc, exact, secs, lo, hi);
  }

  @override
  bool check(MPuzzle p) {
    if (p is! StaffPuzzle || p.notes.length < 6) return false;
    for (final n in p.notes) {
      if (n.midi < kLowMidi || n.midi > kHighMidi || (n.clef != 0 && n.clef != 1)) return false;
      final step = diatonic(n.midi) - bottomLine(n.clef);
      if (step < -6 || step > 14) return false;
      if (!p.accidentals && isBlack(n.midi)) return false;
      if (p.exact && (n.midi < p.kbLo || n.midi > p.kbHi)) return false;
    }
    return p.kbHi - p.kbLo >= 11 && p.kbHi - p.kbLo <= 47;
  }

  @override
  List<GameStat> get stats => const [
        GameStat('rounds_won', 'Geçilen okuma', 'Reading drills passed', scale: 10),
        GameStat('perfect', 'Hatasız okuma', 'Flawless drills', scale: 10),
        GameStat('notes_read', 'Okunan nota', 'Notes read', scale: 200),
      ];

  @override
  List<MissionTemplate> get missions => const [
        MissionTemplate('win', 'rounds_won', [3, 10, 25]),
        MissionTemplate('read', 'notes_read', [60, 240, 800]),
        MissionTemplate('perfect', 'perfect', [1, 5, 15]),
      ];

  @override
  Widget build(MuzikPlay play) => _StaffView(play: play);
}

class _StaffView extends StatefulWidget {
  final MuzikPlay play;
  const _StaffView({required this.play});
  @override
  State<_StaffView> createState() => _StaffViewState();
}

class _StaffViewState extends State<_StaffView> with Clock<_StaffView> {
  late final StaffPuzzle p = widget.play.puzzle as StaffPuzzle;
  int i = 0, lives = 3, mistakes = 0, hints = 0;
  bool started = false, showName = false;
  int? wrongKey;

  StaffNote get n => p.notes[clampI(i, 0, p.notes.length - 1)];

  void _begin() {
    setState(() => started = true);
    startClock();
  }

  bool _matches(int midi) => p.exact ? midi == n.midi : midi % 12 == n.midi % 12;

  void _answer(int midi) {
    if (!started || ended) return;
    if (_matches(midi)) {
      widget.play.note(n.midi);
      Haptic.hit();
      setState(() {
        i++;
        wrongKey = null;
        showName = false;
      });
      if (i >= p.notes.length) {
        ended = true;
        final fast = seconds <= p.seconds * 0.6;
        final stars = mistakes == 0 ? (fast ? 3 : 2) : (mistakes <= 2 ? 2 : 1);
        later(400, () => widget.play.win(score: p.notes.length * 50 + (p.seconds - seconds).clamp(0, 999).toInt() * 5, stars: stars - hints, seconds: seconds, hints: hints, extra: {'notes_read': p.notes.length}));
      }
    } else {
      widget.play.note(midi, volume: 0.6);
      widget.play.sfx(Sfx.error);
      Haptic.miss();
      mistakes++;
      lives--;
      setState(() {
        wrongKey = midi;
        showName = true;
      });
      if (lives <= 0) {
        ended = true;
        later(600, () => widget.play.lose(score: i * 50, seconds: seconds, headline: '$i/${p.notes.length}'));
      }
    }
  }

  Future<void> _hint() async {
    if (!started || ended) return;
    if (await widget.play.ctx.requestHint()) {
      setState(() {
        hints++;
        showName = true;
      });
    }
  }

  void _paint(Canvas c) {
    const double w = 400, h = 260, gap = 16, x0 = 20, x1 = 380;
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, w, h), const Radius.circular(16)), fill(MColors.paper));
    const bottomY = 170.0;
    for (var k = 0; k < 5; k++) {
      final y = bottomY - k * gap;
      c.drawLine(Offset(x0, y), Offset(x1, y), stroke(MColors.ink, 2));
    }
    _clef(c, n.clef, bottomY, gap);
    final step = diatonic(n.midi) - bottomLine(n.clef);
    final y = bottomY - step * gap / 2;
    const nx = 230.0;
    // Ek çizgiler.
    for (var s = -2; s >= step; s -= 2) {
      final ly = bottomY - s * gap / 2;
      c.drawLine(Offset(nx - 22, ly), Offset(nx + 22, ly), stroke(MColors.ink, 2));
    }
    for (var s = 10; s <= step; s += 2) {
      final ly = bottomY - s * gap / 2;
      c.drawLine(Offset(nx - 22, ly), Offset(nx + 22, ly), stroke(MColors.ink, 2));
    }
    c.save();
    c.translate(nx, y);
    c.rotate(-0.35);
    c.drawOval(Rect.fromCenter(center: Offset.zero, width: 22, height: 15), fill(MColors.ink));
    c.restore();
    // Sap.
    final up = step < 4;
    c.drawLine(Offset(nx + (up ? 10 : -10), y), Offset(nx + (up ? 10 : -10), y + (up ? -52 : 52)), stroke(MColors.ink, 2.2));
    if (isBlack(n.midi)) drawLabel(c, '♯', Offset(nx - 30, y), 26, MColors.ink);
    if (showName) drawLabel(c, noteName(n.midi, widget.play.lang, octave: p.exact), Offset(nx + 80, y), 22, MColors.bad);
    // İlerleme noktaları.
    for (var k = 0; k < p.notes.length; k++) {
      final o = Offset(20 + k * (360 / (p.notes.length - 1)), 238);
      c.drawCircle(o, 4, fill(k < i ? MColors.good : const Color(0x33000000)));
    }
  }

  /// Özgün, sade anahtar çizimleri (sol: sarmal; fa: yay ve iki nokta).
  void _clef(Canvas c, int clef, double bottomY, double gap) {
    final ink = stroke(MColors.ink, 3.2);
    if (clef == 0) {
      final gy = bottomY - gap; // sol çizgisi
      final path = Path()
        ..moveTo(52, bottomY + 26)
        ..quadraticBezierTo(44, bottomY + 34, 40, bottomY + 24)
        ..lineTo(52, bottomY - 4 * gap - 10)
        ..quadraticBezierTo(66, bottomY - 4 * gap - 20, 60, bottomY - 3 * gap)
        ..quadraticBezierTo(30, gy - 10, 34, gy + 6)
        ..quadraticBezierTo(46, gy + 26, 64, gy + 6)
        ..quadraticBezierTo(66, gy - 12, 48, gy - 8);
      c.drawPath(path, ink);
      c.drawCircle(Offset(48, gy), 3.5, fill(MColors.ink));
    } else {
      final fy = bottomY - 3 * gap; // fa çizgisi
      final path = Path()
        ..moveTo(36, fy)
        ..quadraticBezierTo(40, fy - 16, 56, fy - 12)
        ..quadraticBezierTo(70, fy - 4, 58, fy + 20)
        ..quadraticBezierTo(48, fy + 34, 32, fy + 40);
      c.drawPath(path, ink);
      c.drawCircle(Offset(36, fy), 5, fill(MColors.ink));
      c.drawCircle(Offset(74, fy - gap / 2), 3, fill(MColors.ink));
      c.drawCircle(Offset(74, fy + gap / 2), 3, fill(MColors.ink));
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.play.lang;
    if (!started) {
      return MScreen(
        bar: MBar(play: widget.play, status: mt(lang, 'staffTitle')),
        board: StartCard(
          title: mt(lang, 'staffTitle'),
          subtitle: '${p.notes.length} ${mt(lang, 'notes')} · ${p.notes.any((x) => x.clef == 1) ? mt(lang, 'bothClefs') : mt(lang, 'trebleClef')}',
          button: mt(lang, 'start'),
          onStart: _begin,
          icon: Icons.music_note,
        ),
      );
    }
    final left = p.seconds - seconds;
    Widget answers;
    if (!p.accidentals && !p.exact) {
      final names = kNoteNames[lang] ?? kNoteNames['en']!;
      const nat = [0, 2, 4, 5, 7, 9, 11];
      answers = Row(children: [
        for (var k = 0; k < 7; k++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: MChip(
                color: wrongKey != null && wrongKey! % 12 == nat[k] ? MColors.bad : MColors.lanes[k],
                onTap: () => _answer(60 + nat[k]),
                child: FittedBox(child: Text(names[k], style: const TextStyle(color: MColors.ink, fontSize: 18))),
              ),
            ),
          ),
      ]);
    } else {
      final wk = wrongKey;
      answers = SizedBox(
        height: 130,
        child: PianoKeys(
          lo: p.kbLo,
          hi: p.kbHi,
          onKey: _answer,
          lit: {if (wk != null) wk: MColors.bad},
          labels: !p.exact,
          lang: lang,
        ),
      );
    }
    if (left <= 0 && !ended) {
      ended = true;
      later(100, () => widget.play.lose(score: i * 50, seconds: seconds, headline: '$i/${p.notes.length}'));
    }
    return MScreen(
      bar: MBar(play: widget.play, left: '♥' * clampI(lives, 0, 9), status: '${i + (ended ? 0 : 1)}/${p.notes.length} · ⏱ ${clock(left < 0 ? 0 : left)}', onHint: _hint),
      board: TapCanvas(w: 400, h: 260, paint: _paint, semantics: mt(lang, 'staffTitle')),
      bottom: answers,
    );
  }
}
