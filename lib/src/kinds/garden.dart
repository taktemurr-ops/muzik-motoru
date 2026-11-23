import 'dart:async';
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

/// Ezgi Bahçesi: beşli (pentatonik) dizide 8 adımlık döngü. Her çiçek bir sestir.
/// Bölüm hedefi: kuşun söylediği ezgiyi kulaktan bulup bahçeye ekmek.
const List<int> kGardenScale = [60, 62, 64, 67, 69, 72, 74, 76];
const int kGardenSteps = 8;

class GardenPuzzle extends MPuzzle {
  final int rows;

  /// Hedef: sütun -> o sütundaki sıralar (alttan 0).
  final List<List<int>> target;

  /// Bir sütunda en çok kaç çiçek olabilir.
  final int perCol;
  final int bpm;
  const GardenPuzzle(this.rows, this.target, this.perCol, this.bpm);

  int get flowers => target.fold<int>(0, (a, c) => a + c.length);

  @override
  Set<String> get samples => {for (var r = 0; r < rows; r++) pianoSample(kGardenScale[r])};
}

class GardenKind extends MuzikKind {
  @override
  String get id => 'ezgi-bahcesi';
  const GardenKind();

  @override
  MPuzzle? make(int d, SeededRandom r, {bool short = false}) {
    final rows = d <= 3 ? 5 : (d <= 6 ? 6 : 8);
    final perCol = d >= 8 ? 2 : 1;
    final used = short ? 4 : math.min<int>(kGardenSteps, 3 + d ~/ 2 + (d >= 6 ? 1 : 0));
    final cols = List<int>.generate(kGardenSteps, (i) => i);
    r.shuffle(cols);
    final on = cols.take(used).toSet();
    final target = <List<int>>[];
    var row = r.nextInt(math.min<int>(rows, 4));
    for (var c = 0; c < kGardenSteps; c++) {
      if (!on.contains(c)) {
        target.add(const []);
        continue;
      }
      final jump = d <= 2 ? 1 : (d <= 5 ? 2 : 3);
      row = clampI(row + r.range(-jump, jump), 0, rows - 1);
      final notes = <int>[row];
      if (perCol == 2 && r.chance(0.35)) {
        final up = row + 2 < rows ? row + 2 : row - 2;
        if (up >= 0 && up != row) notes.add(up);
      }
      notes.sort();
      target.add(notes);
    }
    // Ezgi son çiçeğinde dizinin köküne (en alt ya da beşinci sıradaki do) yaslanır.
    final last = [for (var c = 0; c < kGardenSteps; c++) if (target[c].isNotEmpty) c].last;
    target[last] = [r.chance(0.5) || rows < 6 ? 0 : 5];
    return GardenPuzzle(rows, target, perCol, d <= 4 ? 84 : (d <= 7 ? 96 : 108));
  }

  @override
  bool check(MPuzzle p) {
    if (p is! GardenPuzzle || p.target.length != kGardenSteps) return false;
    if (p.rows < 5 || p.rows > kGardenScale.length || p.perCol < 1 || p.perCol > 2) return false;
    if (p.flowers < 3) return false;
    for (final col in p.target) {
      if (col.length > p.perCol || col.toSet().length != col.length) return false;
      if (col.any((x) => x < 0 || x >= p.rows)) return false;
    }
    return p.bpm >= 60 && p.bpm <= 140;
  }

  @override
  List<GameStat> get stats => const [
        GameStat('rounds_won', 'Yeşeren bahçe', 'Gardens grown', scale: 10),
        GameStat('perfect', 'İlk denemede bahçe', 'First-try gardens', scale: 10),
        GameStat('flowers', 'Dikilen çiçek', 'Flowers planted', scale: 100),
      ];

  @override
  List<MissionTemplate> get missions => const [
        MissionTemplate('win', 'rounds_won', [3, 10, 25]),
        MissionTemplate('flowers', 'flowers', [30, 120, 400]),
        MissionTemplate('perfect', 'perfect', [1, 5, 15]),
      ];

  @override
  Widget build(MuzikPlay play) => _GardenView(play: play);
}

class _GardenView extends StatefulWidget {
  final MuzikPlay play;
  const _GardenView({required this.play});
  @override
  State<_GardenView> createState() => _GardenViewState();
}

class _GardenViewState extends State<_GardenView> with Clock<_GardenView> {
  late final GardenPuzzle p = widget.play.puzzle as GardenPuzzle;
  late final List<Set<int>> mine = List.generate(kGardenSteps, (_) => <int>{});
  bool started = false, free = false, looping = false;
  int step = -1, checks = 0, hints = 0, planted = 0;

  /// 'bird' hedef çalıyor, 'mine' oyuncunun bahçesi çalıyor.
  String who = '';
  Timer? _loop;
  String note = '';

  int get rows => free ? kGardenScale.length : p.rows;

  @override
  void dispose() {
    _loop?.cancel();
    super.dispose();
  }

  void _stop() {
    _loop?.cancel();
    _loop = null;
    setState(() {
      step = -1;
      who = '';
      looping = false;
    });
  }

  /// Sekiz adımı bir kez (ya da döngüde) çalar.
  void _run(List<Iterable<int>> grid, String w, {bool loop = false}) {
    _loop?.cancel();
    final ms = (60000 / p.bpm / 2).round();
    var i = 0;
    setState(() {
      who = w;
      looping = loop;
    });
    void tick() {
      if (!mounted) return;
      if (i >= kGardenSteps) {
        if (!loop) {
          _stop();
          return;
        }
        i = 0;
      }
      final col = grid[i];
      for (final r in col) {
        widget.play.note(kGardenScale[r], volume: 0.9);
      }
      if (col.isNotEmpty) Haptic.beat(strong: w == 'bird');
      setState(() => step = i);
      i++;
    }

    tick();
    _loop = Timer.periodic(Duration(milliseconds: ms), (_) => tick());
  }

  void _bird() => _run(p.target, 'bird');

  void _mine() => looping ? _stop() : _run(mine, 'mine', loop: free);

  void _begin() {
    setState(() => started = true);
    startClock();
    _bird();
  }

  void _tap(Offset o) {
    final cw = 360 / kGardenSteps, rh = 300 / rows;
    final c = (o.dx / cw).floor(), r = rows - 1 - (o.dy / rh).floor();
    if (c < 0 || c >= kGardenSteps || r < 0 || r >= rows || ended) return;
    setState(() {
      final col = mine[c];
      if (col.contains(r)) {
        col.remove(r);
      } else {
        if (!free && col.length >= p.perCol) col.remove(col.first);
        col.add(r);
        planted++;
      }
      note = '';
    });
    widget.play.note(kGardenScale[r]);
  }

  int get _rightCols => [for (var c = 0; c < kGardenSteps; c++) if (_same(c)) c].length;

  bool _same(int c) => mine[c].length == p.target[c].length && p.target[c].every(mine[c].contains);

  void _compare() {
    checks++;
    final right = _rightCols;
    if (right == kGardenSteps) {
      ended = true;
      _stop();
      widget.play.sfx(Sfx.win);
      Haptic.hit();
      final stars = checks == 1 ? 3 : (checks <= 3 ? 2 : 1);
      _run(mine, 'mine');
      later(2200, () => widget.play.win(score: 800 - checks * 60 - seconds, stars: stars - hints, seconds: seconds, hints: hints, extra: {'flowers': planted}));
      return;
    }
    widget.play.sfx(Sfx.error);
    Haptic.miss();
    setState(() => note = '$right/$kGardenSteps ${mt(widget.play.lang, 'colsRight')}');
    if (checks >= 10) {
      ended = true;
      _stop();
      widget.play.lose(seconds: seconds, headline: '$right/$kGardenSteps');
    }
  }

  Future<void> _hint() async {
    final wrong = [for (var c = 0; c < kGardenSteps; c++) if (!_same(c)) c];
    if (wrong.isEmpty) return;
    if (await widget.play.ctx.requestHint()) {
      final c = wrong.first;
      setState(() {
        hints++;
        mine[c]
          ..clear()
          ..addAll(p.target[c]);
      });
    }
  }

  void _toggleFree(bool v) {
    _stop();
    setState(() {
      free = v;
      for (final col in mine) {
        col.clear();
      }
      note = '';
    });
  }

  void _clear() => setState(() {
        for (final col in mine) {
          col.clear();
        }
        note = '';
      });

  @override
  Widget build(BuildContext context) {
    final lang = widget.play.lang;
    if (!started) {
      return MScreen(
        bar: MBar(play: widget.play, status: mt(lang, 'gardenTitle')),
        board: StartCard(
          title: mt(lang, 'gardenTitle'),
          subtitle: mt(lang, 'gardenHelp'),
          button: mt(lang, 'start'),
          onStart: _begin,
          icon: Icons.local_florist,
        ),
      );
    }
    return MScreen(
      bar: MBar(
        play: widget.play,
        left: free ? '' : '${p.flowers}',
        status: free ? mt(lang, 'freeGarden') : mt(lang, 'gardenTitle'),
        practice: free,
        onPractice: _toggleFree,
        onHint: free ? null : _hint,
        onReset: _clear,
      ),
      flash: who == 'bird' && step >= 0 && p.target[step].isNotEmpty ? 0.5 : 0.0,
      flashColor: MColors.ok,
      top: note.isEmpty
          ? Text(free ? mt(lang, 'freeGarden') : mt(lang, 'gardenHelp'),
              textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 14))
          : Text(note, textAlign: TextAlign.center, style: const TextStyle(color: MColors.ok, fontSize: 17, fontWeight: FontWeight.w800)),
      board: TapCanvas(
        w: 360,
        h: 300,
        semantics: mt(lang, 'gardenTitle'),
        onTap: _tap,
        paint: (c) => _paintGarden(c, rows, mine, who == 'bird' ? -1 : step, who == 'bird' && MusicPrefs.flash ? step : -1, free ? const [] : p.target),
      ),
      bottom: Row(children: [
        if (!free) ...[
          Expanded(child: OutlinedButton.icon(onPressed: _bird, icon: const Icon(Icons.flutter_dash), label: FittedBox(child: Text(mt(lang, 'birdSong'))))),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _mine,
            icon: Icon(looping ? Icons.stop : Icons.play_arrow),
            label: FittedBox(child: Text(mt(lang, 'myGarden'))),
          ),
        ),
        if (!free) ...[
          const SizedBox(width: 6),
          Expanded(child: FilledButton.icon(onPressed: ended ? null : _compare, icon: const Icon(Icons.check), label: FittedBox(child: Text(mt(lang, 'compare'))))),
        ],
      ]),
    );
  }
}

/// Bahçe: sıralar toprak şeritleri, çiçekler sıranın rengiyle açar.
/// [play] oyuncunun çalan sütunu, [bird] kuşun söylediği sütun (görsel destek).
void _paintGarden(Canvas c, int rows, List<Set<int>> mine, int play, int bird, List<List<int>> target) {
  const w = 360.0, h = 300.0;
  final cw = w / kGardenSteps, rh = h / rows;
  c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, w, h), const Radius.circular(16)), fill(const Color(0xFF2F3D2B)));
  for (var r = 0; r < rows; r++) {
    final y = h - (r + 1) * rh;
    c.drawRect(Rect.fromLTWH(0, y + rh * 0.7, w, rh * 0.22), fill(const Color(0xFF4A3B2A).withValues(alpha: 0.8)));
  }
  for (var s = 0; s < kGardenSteps; s++) {
    if (s == play) c.drawRect(Rect.fromLTWH(s * cw, 0, cw, h), fill(Colors.white.withValues(alpha: 0.08)));
    // Kuş söylerken yalnızca ses gelen adım ışır; perdeyi kulak bulur.
    if (s == bird && target[s].isNotEmpty) c.drawRect(Rect.fromLTWH(s * cw, 0, cw, h), fill(MColors.ok.withValues(alpha: 0.14)));
    if (s % 2 == 0) c.drawLine(Offset(s * cw, 0), Offset(s * cw, h), stroke(Colors.white10, 1));
  }
  for (var s = 0; s < kGardenSteps; s++) {
    for (final r in mine[s]) {
      final cx = s * cw + cw / 2, cy = h - r * rh - rh / 2;
      final col = MColors.lanes[r % MColors.lanes.length];
      final rad = math.min(cw, rh) * (s == play ? 0.36 : 0.3);
      c.drawLine(Offset(cx, cy + rad * 0.6), Offset(cx, h - r * rh - rh * 0.1), stroke(const Color(0xFF6FA35A), 2.5));
      for (var k = 0; k < 5; k++) {
        final a = k * 2 * math.pi / 5 + r * 0.3;
        c.drawCircle(Offset(cx + math.cos(a) * rad * 0.55, cy + math.sin(a) * rad * 0.55), rad * 0.42, fill(col));
      }
      c.drawCircle(Offset(cx, cy), rad * 0.3, fill(const Color(0xFFF6E7B0)));
    }
  }
}
