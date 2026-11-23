import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';

import '../audio.dart';
import '../core.dart';
import '../texts.dart';
import '../theory.dart';

/// Melodi Hafızası: çiçeğin yaprakları birer nota. Her turda ezgi bir nota
/// uzar; dinle ve aynısını çal. İleri bölümlerde bazı turlar tersten
/// istenir, yapraklar her turda yer değiştirir.
class MemPuzzle extends MPuzzle {
  final int root;
  final List<int> petals; // artan sıralı MIDI
  final List<int> melody; // yaprak sırası
  final int startLen;
  final List<bool> reverse; // tur başına (uzunluk startLen..L)
  final bool spin;
  const MemPuzzle(this.root, this.petals, this.melody, this.startLen, this.reverse, this.spin);

  @override
  Set<String> get samples => {for (final m in petals) pianoSample(m)};
}

class MemoryKind extends MuzikKind {
  @override
  String get id => 'melodi-hafizasi';
  const MemoryKind();

  @override
  MPuzzle? make(int d, SeededRandom r, {bool short = false}) {
    final n = 4 + math.min<int>(d ~/ 2, 4);
    final sc = d <= 5 ? kPentaMajor : r.pick(const [kMajor, kMinor, kDorian, kPentaMinor]);
    final root = r.nextInt(12);
    final lo = 60 + root > 66 ? 48 + root : 60 + root;
    final pool = scaleNotes(root, sc, lo, lo + 24);
    if (pool.length < n) return null;
    final petals = pool.sublist(0, n);
    final len = short ? math.min<int>(4 + d ~/ 2, 7) : 4 + d;
    final mel = <int>[0];
    var run = 0;
    for (var i = 1; i < len; i++) {
      final prev = mel.last;
      int nx;
      final x = r.nextInt(100);
      if (x < 55) {
        nx = prev + (r.chance(0.5) ? 1 : -1);
      } else if (x < 85) {
        nx = prev + (r.chance(0.5) ? 2 : -2);
      } else if (x < 92) {
        nx = prev;
      } else {
        nx = prev + (r.chance(0.5) ? 3 : -3);
      }
      if (nx < 0 || nx >= n) nx = prev - (nx - prev);
      nx = clampI(nx, 0, n - 1);
      run = nx == prev ? run + 1 : 0;
      if (run >= 2) {
        nx = prev == 0 ? 1 : prev - 1;
        run = 0;
      }
      mel.add(nx);
    }
    // Son nota durak sesi (kök).
    mel[mel.length - 1] = mel[mel.length - 2] == 0 ? (n > 5 ? 5 : 0) : 0;
    if ((petals[mel.last] - root) % 12 != 0) mel[mel.length - 1] = 0;
    final start = d <= 3 ? 2 : 3;
    final reverse = <bool>[for (var k = start; k <= len; k++) d >= 6 && k > start && r.chance(0.25)];
    return MemPuzzle(root, petals, mel, start, reverse, d >= 8);
  }

  @override
  bool check(MPuzzle p) {
    if (p is! MemPuzzle) return false;
    if (p.petals.length < 4 || p.petals.length > 8 || p.melody.length < 4) return false;
    for (var i = 1; i < p.petals.length; i++) {
      if (p.petals[i] <= p.petals[i - 1]) return false;
    }
    if (p.petals.any((m) => m < kLowMidi || m > kHighMidi)) return false;
    var run = 0;
    for (var i = 0; i < p.melody.length; i++) {
      final m = p.melody[i];
      if (m < 0 || m >= p.petals.length) return false;
      if (i > 0) {
        if ((m - p.melody[i - 1]).abs() > 5) return false;
        run = m == p.melody[i - 1] ? run + 1 : 0;
        if (run >= 2) return false;
      }
    }
    if ((p.petals[p.melody.last] - p.root) % 12 != 0) return false;
    return p.startLen >= 2 && p.startLen <= p.melody.length && p.reverse.length == p.melody.length - p.startLen + 1;
  }

  @override
  List<GameStat> get stats => const [
        GameStat('rounds_won', 'Ezberlenen ezgi', 'Melodies memorized', scale: 10),
        GameStat('perfect', 'Hatasız ezgi', 'Flawless melodies', scale: 10),
        GameStat('longest', 'En uzun dizi', 'Longest sequence', scale: 20),
      ];

  @override
  List<MissionTemplate> get missions => const [
        MissionTemplate('win', 'rounds_won', [3, 10, 25]),
        MissionTemplate('longest', 'longest', [10, 40, 120]),
        MissionTemplate('perfect', 'perfect', [1, 5, 15]),
      ];

  @override
  Widget build(MuzikPlay play) => _MemoryView(play: play);
}

class _MemoryView extends StatefulWidget {
  final MuzikPlay play;
  const _MemoryView({required this.play});
  @override
  State<_MemoryView> createState() => _MemoryViewState();
}

class _MemoryViewState extends State<_MemoryView> with Clock<_MemoryView> {
  late final MemPuzzle p = widget.play.puzzle as MemPuzzle;
  late int len = p.startLen;
  int pos = 0, lives = 3, mistakes = 0, hints = 0, rot = 0;
  bool demo = false, started = false, practice = false;
  int lit = -1, hintPetal = -1;
  double flash = 0;

  int get n => p.petals.length;
  bool get rev => p.reverse[len - p.startLen];
  List<int> get target {
    final s = p.melody.sublist(0, len);
    return rev ? s.reversed.toList() : s;
  }

  int get gapMs => clampI(620 - widget.play.d * 25, 360, 620) + (practice ? 150 : 0);

  void _begin() {
    setState(() => started = true);
    startClock();
    _demo();
  }

  void _demo() {
    cancelLater();
    setState(() {
      demo = true;
      pos = 0;
      hintPetal = -1;
    });
    final seq = p.melody.sublist(0, len);
    for (var i = 0; i < seq.length; i++) {
      later(500 + i * gapMs, () => _light(seq[i]));
    }
    later(500 + seq.length * gapMs, () => setState(() {
          demo = false;
          lit = -1;
        }));
  }

  void _light(int petal) {
    widget.play.note(p.petals[petal]);
    Haptic.beat(strong: petal == 0);
    setState(() {
      lit = petal;
      flash = 1;
    });
    later(gapMs - 80, () => setState(() {
          if (lit == petal) lit = -1;
          flash = 0;
        }));
  }

  double _angle(int i) => -math.pi / 2 + 2 * math.pi * ((i + rot) % n) / n;
  Offset _petalPos(int i) => const Offset(200, 200) + Offset(math.cos(_angle(i)), math.sin(_angle(i))) * 120;

  void _tap(Offset o) {
    if (!started || demo || ended) return;
    var best = -1;
    var bd = 1e9;
    for (var i = 0; i < n; i++) {
      final d = (_petalPos(i) - o).distance;
      if (d < bd) {
        bd = d;
        best = i;
      }
    }
    if (best < 0 || bd > 70) return;
    _light(best);
    if (best == target[pos]) {
      pos++;
      if (pos >= len) _roundDone();
    } else {
      mistakes++;
      widget.play.sfx(Sfx.error);
      Haptic.miss();
      if (!practice) lives--;
      if (lives <= 0) {
        ended = true;
        later(600, () => widget.play.lose(score: (len - 1) * 50, seconds: seconds, headline: '${len - 1}/${p.melody.length}'));
        setState(() {});
        return;
      }
      later(700, _demo);
    }
  }

  void _roundDone() {
    widget.play.sfx(Sfx.place);
    if (len >= p.melody.length) {
      ended = true;
      final stars = practice ? 1 : (mistakes == 0 ? 3 : (mistakes == 1 ? 2 : 1));
      later(500, () => widget.play.win(score: len * 80, stars: stars - hints, seconds: seconds, hints: hints, extra: {'longest': len}));
      setState(() {});
      return;
    }
    setState(() {
      len++;
      if (p.spin) rot = (rot + 1) % n;
    });
    later(650, _demo);
  }

  Future<void> _hint() async {
    if (demo || !started || ended) return;
    if (await widget.play.ctx.requestHint()) {
      setState(() {
        hints++;
        hintPetal = target[pos];
      });
    }
  }

  void _paint(Canvas c) {
    c.drawCircle(const Offset(200, 200), 196, fill(MColors.stage));
    c.drawCircle(const Offset(200, 200), 60, fill(Color.lerp(MColors.soft, MColors.ok, MusicPrefs.flash ? flash * 0.5 : 0)!));
    for (var i = 0; i < n; i++) {
      final o = _petalPos(i);
      final col = MColors.lanes[i % MColors.lanes.length];
      final on = lit == i;
      c.save();
      c.translate(o.dx, o.dy);
      c.rotate(_angle(i) + math.pi / 2);
      final r = Rect.fromCenter(center: Offset.zero, width: on ? 92 : 78, height: on ? 120 : 104);
      if (on) c.drawOval(r.inflate(14), fill(col.withValues(alpha: 0.35)));
      c.drawOval(r, fill(on ? Color.lerp(col, Colors.white, 0.45)! : col.withValues(alpha: 0.85)));
      if (hintPetal == i) c.drawOval(r.inflate(6), stroke(Colors.white, 4));
      c.restore();
      if (widget.play.d <= 4 || practice) drawLabel(c, noteName(p.petals[i], widget.play.lang), o, 18, MColors.ink);
    }
    drawLabel(c, demo ? '♪' : (rev ? '⟲' : '$pos/$len'), const Offset(200, 200), 26, Colors.white);
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.play.lang;
    if (!started) {
      return MScreen(
        bar: MBar(play: widget.play, practice: practice, onPractice: (v) => setState(() => practice = v), status: mt(lang, 'memTitle')),
        board: StartCard(
          title: mt(lang, 'memTitle'),
          subtitle: '${p.melody.length} ${mt(lang, 'notes')}${p.spin ? '\n${mt(lang, 'spinInfo')}' : ''}',
          button: mt(lang, 'start'),
          onStart: _begin,
          icon: Icons.local_florist,
        ),
      );
    }
    return MScreen(
      bar: MBar(
        play: widget.play,
        left: practice ? '∞' : '♥' * clampI(lives, 0, 9),
        status: demo ? mt(lang, 'listen') : (rev ? mt(lang, 'playReverse') : mt(lang, 'yourTurn')),
        onHint: demo ? null : _hint,
        tools: false,
        extra: [IconButton(onPressed: demo ? null : _demo, tooltip: mt(lang, 'listen'), icon: const Icon(Icons.replay))],
      ),
      top: LinearProgressIndicator(value: len / p.melody.length, color: MColors.ok, backgroundColor: Colors.white12),
      board: TapCanvas(w: 400, h: 400, paint: _paint, onDown: _tap, semantics: mt(lang, 'memTitle')),
    );
  }
}
