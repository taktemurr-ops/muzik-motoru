import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';

import '../audio.dart';
import '../core.dart';
import '../synth.dart';
import '../texts.dart';

/// Bir vuruşluk ritim kalıbı: vuruş içindeki olaylar (başlangıç 0..1, nota mı sus mu).
/// Olay bir sonraki olaya ya da vuruş sonuna kadar sürer. Boş liste ('h') bağdır:
/// önceki nota bu vuruş boyunca da uzar.
class RCell {
  final String id;
  final List<double> at;
  final List<bool> note;
  const RCell(this.id, this.at, this.note);
  bool get isTie => at.isEmpty;
  bool get endsWithNote => at.isNotEmpty && note.last;
}

const double _third = 1 / 3;

const List<RCell> kRCells = [
  RCell('q', [0], [true]),
  RCell('ee', [0, 0.5], [true, true]),
  RCell('r', [0], [false]),
  RCell('h', [], []),
  RCell('ssss', [0, 0.25, 0.5, 0.75], [true, true, true, true]),
  RCell('ess', [0, 0.5, 0.75], [true, true, true]),
  RCell('sse', [0, 0.25, 0.5], [true, true, true]),
  RCell('re', [0, 0.5], [false, true]),
  RCell('er', [0, 0.5], [true, false]),
  RCell('des', [0, 0.75], [true, true]),
  RCell('ses', [0, 0.25, 0.75], [true, true, true]),
  RCell('tri', [0, _third, 2 * _third], [true, true, true]),
];

RCell rcell(String id) => kRCells.firstWhere((c) => c.id == id);

/// Zorluk basamağına göre açılan kalıplar (her basamak bir yenisini ekler).
List<String> rdictCells(int d) {
  const order = ['q', 'ee', 'r', 'h', 'ssss', 'ess', 'sse', 're', 'er', 'des', 'ses', 'tri'];
  final n = d <= 1 ? 2 : (d <= 4 ? d + 1 : (d <= 6 ? 7 + (d - 5) : math.min<int>(order.length, 9 + (d - 7))));
  return order.take(n).toList();
}

class RDictPuzzle extends MPuzzle {
  /// Ölçüdeki vuruş sayısı (2, 3, 4).
  final int beats;
  final int measures;
  final int bpm;

  /// Doğru yanıt: her vuruşun kalıbı.
  final List<String> cells;

  /// Seçilebilecek kalıplar.
  final List<String> palette;

  /// Çalarken vuruş tıklaması duyulur mu.
  final bool clicks;
  const RDictPuzzle(this.beats, this.measures, this.bpm, this.cells, this.palette, this.clicks);
  int get total => beats * measures;
}

/// Bir kalıp dizisinin geçerli olup olmadığı: bağ yalnızca çalan bir notadan sonra gelir.
bool rdictValid(List<String> cells) {
  if (cells.isEmpty) return false;
  for (var i = 0; i < cells.length; i++) {
    final c = rcell(cells[i]);
    if (!c.isTie) continue;
    if (i == 0) return false;
    // Geriye doğru ilk bağ olmayan kalıp nota ile bitmeli.
    var j = i - 1;
    while (j >= 0 && rcell(cells[j]).isTie) {
      j--;
    }
    if (j < 0 || !rcell(cells[j]).endsWithNote) return false;
  }
  return true;
}

/// Zaman çizelgesi: (başlangıç vuruşu, süre vuruş, nota mı).
List<(double, double, bool)> rdictTimeline(List<String> cells) {
  final ev = <(double, bool)>[];
  for (var i = 0; i < cells.length; i++) {
    final c = rcell(cells[i]);
    for (var k = 0; k < c.at.length; k++) {
      ev.add((i + c.at[k], c.note[k]));
    }
  }
  final out = <(double, double, bool)>[];
  for (var k = 0; k < ev.length; k++) {
    final end = k + 1 < ev.length ? ev[k + 1].$1 : cells.length.toDouble();
    out.add((ev[k].$1, end - ev[k].$1, ev[k].$2));
  }
  return out;
}

/// Duyulan ritmin imzası: nota başlangıçları ve sessiz bölgeler (1/12 vuruş ızgarası).
String rdictSignature(List<String> cells) {
  final b = StringBuffer();
  for (final e in rdictTimeline(cells)) {
    b.write('${(e.$1 * 12).round()}${e.$3 ? 'n' : 'r'}${(e.$2 * 12).round()};');
  }
  return b.toString();
}

class RDictKind extends MuzikKind {
  @override
  String get id => 'ritim-diktesi';
  const RDictKind();

  @override
  MPuzzle? make(int d, SeededRandom r, {bool short = false}) {
    final allowed = rdictCells(d);
    final beats = d <= 3 ? 4 : [2, 3, 4][r.nextInt(3)];
    final measures = short ? 1 : (d <= 3 ? 1 : (beats == 4 ? (d >= 7 ? 2 : 1) : 2));
    final total = beats * measures;
    final hasSub = allowed.any((c) => c == 'ssss' || c == 'tri' || c == 'des' || c == 'ses');
    final bpm = hasSub ? 60 + r.nextInt(5) * 4 : 72 + r.nextInt(6) * 4;
    final newest = allowed.last;
    for (var a = 0; a < 40; a++) {
      final cells = <String>[];
      for (var i = 0; i < total; i++) {
        // Yeni açılan kalıp daha sık gelir; bağ her zaman geçerli olmayabilir.
        final pick = r.chance(0.3) ? newest : allowed[r.nextInt(allowed.length)];
        cells.add(pick);
      }
      if (d >= 2 && !cells.contains(newest)) cells[r.nextInt(total)] = newest;
      if (!rdictValid(cells)) continue;
      if (cells.toSet().length < math.min<int>(2, allowed.length)) continue;
      // Uzun bağ zincirleri olmasın (en çok bir tam nota).
      var run = 0, worst = 0;
      for (final c in cells) {
        run = c == 'h' ? run + 1 : 0;
        worst = math.max<int>(worst, run);
      }
      if (worst > 3) continue;
      // Tamamen sus olan bölüm olmasın.
      if (cells.where((c) => c == 'r').length * 2 > total) continue;
      return RDictPuzzle(beats, measures, bpm, cells, allowed, d <= 6);
    }
    return null;
  }

  @override
  bool check(MPuzzle p) {
    if (p is! RDictPuzzle) return false;
    if (![2, 3, 4].contains(p.beats) || p.measures < 1 || p.measures > 2) return false;
    if (p.cells.length != p.total || p.bpm < 50 || p.bpm > 120) return false;
    if (p.palette.isEmpty || p.palette.any((c) => !kRCells.any((k) => k.id == c))) return false;
    if (p.cells.any((c) => !p.palette.contains(c))) return false;
    if (!rdictValid(p.cells)) return false;
    // Paletteki her kalıp farklı duyulmalı (yanıt tek).
    final sigs = {for (final c in p.palette) if (c != 'h') rdictSignature([c])};
    if (sigs.length != p.palette.where((c) => c != 'h').length) return false;
    return rdictTimeline(p.cells).any((e) => e.$3);
  }

  @override
  List<GameStat> get stats => const [
        GameStat('rounds_won', 'Yazılan dikte', 'Dictations written', scale: 10),
        GameStat('perfect', 'İlk denemede doğru', 'Right first time', scale: 10),
        GameStat('beats_written', 'Yazılan vuruş', 'Beats written', scale: 100),
      ];

  @override
  List<MissionTemplate> get missions => const [
        MissionTemplate('win', 'rounds_won', [3, 10, 25]),
        MissionTemplate('beats', 'beats_written', [20, 100, 300]),
        MissionTemplate('perfect', 'perfect', [1, 5, 15]),
      ];

  @override
  Widget build(MuzikPlay play) => _RDictView(play: play);
}

/// Ritmi tek bir ses dosyası olarak üretir: bir ölçü sayım, sonra ritim.
List<double> rdictPcm(List<String> cells, int beats, int bpm, {bool clicks = true, bool countIn = true}) {
  const rate = Synth.rate;
  final spb = 60.0 / bpm;
  final lead = countIn ? beats : 0;
  final total = (cells.length + lead) * spb + 0.4;
  final out = List<double>.filled((total * rate).round(), 0);
  void mix(List<double> pcm, double at) {
    final o = (at * rate).round();
    for (var i = 0; i < pcm.length && o + i < out.length; i++) {
      out[o + i] += pcm[i];
    }
  }

  List<double> click(bool strong) {
    final n = (0.035 * rate).round();
    final f = strong ? 2200.0 : 1500.0;
    return [for (var i = 0; i < n; i++) (strong ? 0.42 : 0.3) * math.sin(2 * math.pi * f * i / rate) * (1 - i / n)];
  }

  for (var b = 0; b < lead; b++) {
    mix(click(b == 0), b * spb);
  }
  if (clicks) {
    for (var b = 0; b < cells.length; b++) {
      final c = click(b % beats == 0);
      mix([for (final v in c) v * 0.45], (lead + b) * spb);
    }
  }
  for (final e in rdictTimeline(cells)) {
    if (!e.$3) continue;
    final dur = math.max(0.06, e.$2 * spb - 0.045);
    mix(Synth.note(523.25, dur, vol: 0.55, attack: 0.008, release: 0.04), (lead + e.$1) * spb);
  }
  return out;
}

class _RDictView extends StatefulWidget {
  final MuzikPlay play;
  const _RDictView({required this.play});
  @override
  State<_RDictView> createState() => _RDictViewState();
}

class _RDictViewState extends State<_RDictView> with Clock<_RDictView> {
  late final RDictPuzzle p = widget.play.puzzle as RDictPuzzle;
  late final SynthVoice synth = SynthVoice(sound: widget.play.voice.sound);
  late final List<String?> ans = List<String?>.filled(p.total, null);
  final Set<int> locked = {};
  Set<int> wrong = {};
  bool started = false;
  int lives = 3, tries = 0, plays = 0, hints = 0;
  String note = '';
  Color noteColor = Colors.white70;

  String get lang => widget.play.lang;

  @override
  void dispose() {
    synth.dispose();
    super.dispose();
  }

  void _playTarget() {
    plays++;
    synth.stopAll();
    synth.play('rd_${p.cells.join('.')}_${p.bpm}_${p.beats}_${p.clicks}', () => rdictPcm(p.cells, p.beats, p.bpm, clicks: p.clicks));
    Haptic.beat(strong: true);
  }

  void _playMine() {
    if (ans.any((a) => a == null)) return;
    final mine = [for (final a in ans) a!];
    if (!rdictValid(mine)) {
      setState(() {
        note = mt(lang, 'rdTieInfo');
        noteColor = MColors.ok;
      });
      return;
    }
    synth.stopAll();
    synth.play('rdm_${mine.join('.')}_${p.bpm}_${p.beats}', () => rdictPcm(mine, p.beats, p.bpm, clicks: true));
  }

  void _begin() {
    setState(() => started = true);
    startClock();
    _playTarget();
  }

  void _put(String id) {
    if (ended) return;
    final i = ans.indexWhere((a) => a == null);
    if (i < 0) return;
    widget.play.sfx(Sfx.tap);
    setState(() {
      ans[i] = id;
      wrong.remove(i);
      note = '';
    });
  }

  void _clear(int i) {
    if (ended || locked.contains(i) || ans[i] == null) return;
    setState(() {
      ans[i] = null;
      wrong.remove(i);
    });
  }

  void _reset() {
    setState(() {
      for (var i = 0; i < ans.length; i++) {
        if (!locked.contains(i)) ans[i] = null;
      }
      wrong = {};
      note = '';
    });
  }

  void _confirm() {
    if (ended || ans.any((a) => a == null)) return;
    final mine = [for (final a in ans) a!];
    tries++;
    // Aynı duyulan farklı yazımlar da kabul edilir (ör. imza eşitliği).
    if (rdictValid(mine) && rdictSignature(mine) == rdictSignature(p.cells)) {
      ended = true;
      widget.play.sfx(Sfx.win);
      Haptic.hit();
      setState(() {
        note = mt(lang, 'correct');
        noteColor = MColors.good;
        wrong = {};
      });
      final stars = (tries == 1 ? (plays <= 3 ? 3 : 2) : (tries == 2 ? 2 : 1)) - hints;
      later(800, () => widget.play.win(score: 400 + p.total * 60 - tries * 50 - plays * 10 - seconds, stars: stars, seconds: seconds, hints: hints, extra: {'beats_written': p.total}));
      return;
    }
    widget.play.sfx(Sfx.error);
    Haptic.miss();
    lives--;
    setState(() {
      wrong = {for (var i = 0; i < p.total; i++) if (mine[i] != p.cells[i]) i};
      note = mt(lang, 'rdWrong');
      noteColor = MColors.bad;
    });
    if (lives <= 0) {
      ended = true;
      later(900, () => widget.play.lose(seconds: seconds, headline: '${p.total - wrong.length}/${p.total}'));
    }
  }

  Future<void> _hint() async {
    if (ended) return;
    final i = [for (var k = 0; k < p.total; k++) if (!locked.contains(k) && ans[k] != p.cells[k]) k];
    if (i.isEmpty) return;
    if (await widget.play.ctx.requestHint()) {
      setState(() {
        hints++;
        ans[i.first] = p.cells[i.first];
        locked.add(i.first);
        wrong.remove(i.first);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!started) {
      return MScreen(
        bar: MBar(play: widget.play, status: mt(lang, 'rdTitle')),
        board: StartCard(
          title: '${mt(lang, 'rdTitle')} · ${p.beats}/4',
          subtitle: mt(lang, 'rdHelp'),
          button: mt(lang, 'start'),
          onStart: _begin,
          icon: Icons.edit_note,
        ),
      );
    }
    final filled = ans.every((a) => a != null);
    return MScreen(
      bar: MBar(
        play: widget.play,
        left: '${p.beats}/4',
        status: '${'♥' * lives}  ${clock()}',
        onReset: _reset,
        onHint: _hint,
      ),
      top: Text(note.isEmpty ? mt(lang, 'rdHelp') : note,
          textAlign: TextAlign.center, style: TextStyle(color: note.isEmpty ? Colors.white : noteColor, fontSize: 15, fontWeight: note.isEmpty ? FontWeight.w400 : FontWeight.w800)),
      board: Column(children: [
        Expanded(
          flex: 5,
          child: Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              runSpacing: 10,
              children: [
                for (var m = 0; m < p.measures; m++)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
                    decoration: BoxDecoration(
                      color: MColors.paper,
                      borderRadius: BorderRadius.circular(10),
                      border: const Border(right: BorderSide(color: MColors.ink, width: 3)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (m == 0) _TimeSig(p.beats),
                      for (var b = 0; b < p.beats; b++) _slot(m * p.beats + b),
                    ]),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          flex: 4,
          child: SingleChildScrollView(
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final id in p.palette)
                  Semantics(
                    button: true,
                    label: mt(lang, 'rc_$id'),
                    child: InkWell(
                      onTap: filled ? null : () => _put(id),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(color: filled ? MColors.paper.withValues(alpha: 0.5) : MColors.paper, borderRadius: BorderRadius.circular(10)),
                        child: CustomPaint(painter: RCellPainter(id, MColors.ink)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ]),
      bottom: Row(children: [
        Expanded(child: OutlinedButton.icon(onPressed: _playTarget, icon: const Icon(Icons.headphones), label: FittedBox(child: Text(mt(lang, 'listen'))))),
        const SizedBox(width: 6),
        Expanded(child: OutlinedButton.icon(onPressed: filled ? _playMine : null, icon: const Icon(Icons.graphic_eq), label: FittedBox(child: Text(mt(lang, 'rdMine'))))),
        const SizedBox(width: 6),
        Expanded(child: FilledButton.icon(onPressed: filled && !ended ? _confirm : null, icon: const Icon(Icons.check), label: FittedBox(child: Text(mt(lang, 'confirm'))))),
      ]),
    );
  }

  Widget _slot(int i) {
    final id = ans[i];
    final bad = wrong.contains(i);
    final lock = locked.contains(i);
    return Semantics(
      label: id == null ? '${i + 1}' : mt(lang, 'rc_$id'),
      button: id != null,
      child: GestureDetector(
        onTap: () => _clear(i),
        child: Container(
          width: 56,
          height: 70,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: bad ? MColors.bad.withValues(alpha: 0.25) : (lock ? MColors.good.withValues(alpha: 0.2) : Colors.transparent),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: id == null ? MColors.line : Colors.transparent, width: 1.5),
          ),
          child: id == null
              ? Center(child: Text('${i % p.beats + 1}', style: const TextStyle(color: MColors.line, fontSize: 18, fontWeight: FontWeight.w700)))
              : CustomPaint(painter: RCellPainter(id, bad ? MColors.bad : MColors.ink)),
        ),
      ),
    );
  }
}

class _TimeSig extends StatelessWidget {
  final int beats;
  const _TimeSig(this.beats);
  @override
  Widget build(BuildContext context) {
    const st = TextStyle(color: MColors.ink, fontSize: 20, fontWeight: FontWeight.w900, height: 1.0);
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Column(mainAxisSize: MainAxisSize.min, children: [Text('$beats', style: st), const Text('4', style: st)]),
    );
  }
}

/// Bir vuruşluk kalıbın nota yazısı: baş, sap, kiriş, bayrak, nokta, sus ve bağ.
class RCellPainter extends CustomPainter {
  final String id;
  final Color color;
  RCellPainter(this.id, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final cell = rcell(id);
    final w = size.width, h = size.height;
    final base = h * 0.7, top = h * 0.2;
    final ink = Paint()..color = color;
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.5, w / 34)
      ..strokeCap = StrokeCap.round;
    final beam = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(3.0, h / 14);
    double xAt(double t) => w * (cell.at.length <= 1 ? 0.42 : 0.2 + 0.62 * t / (cell.at.last == 0 ? 1 : cell.at.last));

    if (cell.isTie) {
      // Bağ: önceki notadan gelen yay ve uzayan ses çizgisi.
      final arc = Path()
        ..moveTo(0, base + h * 0.08)
        ..quadraticBezierTo(w * 0.3, base + h * 0.2, w * 0.55, base + h * 0.08);
      canvas.drawPath(arc, pen);
      canvas.drawLine(Offset(w * 0.25, base - h * 0.06), Offset(w * 0.85, base - h * 0.06), pen..strokeWidth = math.max(3.0, h / 16));
      return;
    }
    final n = cell.at.length;
    final durs = [for (var k = 0; k < n; k++) (k + 1 < n ? cell.at[k + 1] : 1.0) - cell.at[k]];
    final notes = <int>[for (var k = 0; k < n; k++) if (cell.note[k]) k];
    int flags(int k) {
      final d = durs[k];
      if (d >= 0.99) return 0;
      if (id == 'tri') return 1;
      return d >= 0.49 ? 1 : 2;
    }

    final stemX = <int, double>{};
    for (var k = 0; k < n; k++) {
      final x = xAt(cell.at[k]);
      if (!cell.note[k]) {
        _rest(canvas, Offset(x, (base + top) / 2), h, durs[k] >= 0.99, ink, pen);
        continue;
      }
      final head = Rect.fromCenter(center: Offset(x, base), width: w * 0.2, height: h * 0.13);
      canvas.save();
      canvas.translate(head.center.dx, head.center.dy);
      canvas.rotate(-0.35);
      canvas.translate(-head.center.dx, -head.center.dy);
      canvas.drawOval(head, ink);
      canvas.restore();
      final sx = head.right - pen.strokeWidth / 2;
      stemX[k] = sx;
      canvas.drawLine(Offset(sx, base - h * 0.02), Offset(sx, top), pen);
      if ((durs[k] - 0.75).abs() < 0.01) canvas.drawCircle(Offset(head.right + w * 0.07, base), w * 0.035, ink);
    }
    if (notes.length >= 2) {
      final a = stemX[notes.first]!, b = stemX[notes.last]!;
      canvas.drawLine(Offset(a, top + beam.strokeWidth / 2), Offset(b, top + beam.strokeWidth / 2), beam);
      final y2 = top + beam.strokeWidth * 1.9;
      for (var i = 0; i < notes.length; i++) {
        final k = notes[i];
        if (flags(k) < 2) continue;
        final x = stemX[k]!;
        final next = i + 1 < notes.length && flags(notes[i + 1]) >= 2 ? stemX[notes[i + 1]] : null;
        if (next != null) {
          canvas.drawLine(Offset(x, y2), Offset(next, y2), beam);
        } else {
          final prevTwo = i > 0 && flags(notes[i - 1]) >= 2;
          if (!prevTwo) {
            // Tek on altılık: komşusuna doğru kısa kiriş.
            final dir = i + 1 < notes.length ? 1.0 : -1.0;
            canvas.drawLine(Offset(x, y2), Offset(x + dir * w * 0.12, y2), beam);
          }
        }
      }
      if (id == 'tri') {
        final tp = TextPainter(
          text: TextSpan(text: '3', style: TextStyle(color: color, fontSize: h * 0.18, fontWeight: FontWeight.w800, fontStyle: FontStyle.italic)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset((a + b) / 2 - tp.width / 2, top - tp.height - 1));
      }
    } else if (notes.length == 1) {
      final k = notes.first;
      final f = flags(k);
      final x = stemX[k]!;
      for (var i = 0; i < f; i++) {
        final y = top + i * h * 0.1;
        final flag = Path()
          ..moveTo(x, y)
          ..quadraticBezierTo(x + w * 0.2, y + h * 0.1, x + w * 0.12, y + h * 0.24);
        canvas.drawPath(flag, pen);
      }
    }
  }

  void _rest(Canvas c, Offset o, double h, bool quarter, Paint ink, Paint pen) {
    if (quarter) {
      final s = h * 0.075;
      final z = Path()
        ..moveTo(o.dx - s * 0.6, o.dy - s * 2.6)
        ..lineTo(o.dx + s * 0.6, o.dy - s * 1.2)
        ..lineTo(o.dx - s * 0.5, o.dy + s * 0.1)
        ..lineTo(o.dx + s * 0.6, o.dy + s * 1.4)
        ..quadraticBezierTo(o.dx - s * 1.2, o.dy + s * 1.0, o.dx - s * 0.1, o.dy + s * 2.6);
      c.drawPath(z, pen);
      return;
    }
    final s = h * 0.07;
    c.drawCircle(Offset(o.dx - s * 0.5, o.dy - s), s * 0.55, ink);
    c.drawLine(Offset(o.dx - s * 0.5, o.dy - s * 0.6), Offset(o.dx + s * 0.8, o.dy - s * 1.2), pen);
    c.drawLine(Offset(o.dx + s * 0.8, o.dy - s * 1.2), Offset(o.dx - s * 0.2, o.dy + s * 2.2), pen);
  }

  @override
  bool shouldRepaint(covariant RCellPainter old) => old.id != id || old.color != color;
}
