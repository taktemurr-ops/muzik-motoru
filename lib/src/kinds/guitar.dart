import 'package:flutter/material.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';

import '../audio.dart';
import '../core.dart';
import '../texts.dart';
import '../theory.dart';

/// Gitar Akorları: sapın üzerinde akoru kur, şekilden akoru tanı, kulaktan bul.
/// Kurulan her doğru parmak dizilişi kabul edilir (tek bir ezber şekil şart değil).
const List<int> kStrings = [40, 45, 50, 55, 59, 64];

class Shape {
  final int root;
  final String q;
  final List<int> frets; // -1 susturulmuş, 0 açık
  const Shape(this.root, this.q, this.frets);
}

const List<Shape> kOpenShapes = [
  Shape(0, 'M', [-1, 3, 2, 0, 1, 0]),
  Shape(9, 'M', [-1, 0, 2, 2, 2, 0]),
  Shape(7, 'M', [3, 2, 0, 0, 0, 3]),
  Shape(4, 'M', [0, 2, 2, 1, 0, 0]),
  Shape(2, 'M', [-1, -1, 0, 2, 3, 2]),
  Shape(9, 'm', [-1, 0, 2, 2, 1, 0]),
  Shape(4, 'm', [0, 2, 2, 0, 0, 0]),
  Shape(2, 'm', [-1, -1, 0, 2, 3, 1]),
  Shape(9, '7', [-1, 0, 2, 0, 2, 0]),
  Shape(2, '7', [-1, -1, 0, 2, 1, 2]),
  Shape(4, '7', [0, 2, 0, 1, 0, 0]),
  Shape(7, '7', [3, 2, 0, 0, 0, 1]),
  Shape(0, '7', [-1, 3, 2, 3, 1, 0]),
  Shape(11, '7', [-1, 2, 1, 2, 0, 2]),
  Shape(9, 'm7', [-1, 0, 2, 0, 1, 0]),
  Shape(4, 'm7', [0, 2, 0, 0, 0, 0]),
  Shape(2, 'm7', [-1, -1, 0, 2, 1, 1]),
];

/// Taşınabilir barre şekilleri: kök 6. telde (E şekli) ya da 5. telde (A şekli).
Shape barreShape(int root, String q, {required bool aShape}) {
  if (!aShape) {
    final f = ((root - 4) % 12 + 12) % 12;
    final b = f == 0 ? 12 : f;
    final rel = switch (q) {
      'M' => [0, 2, 2, 1, 0, 0],
      'm' => [0, 2, 2, 0, 0, 0],
      '7' => [0, 2, 0, 1, 0, 0],
      _ => [0, 2, 0, 0, 0, 0],
    };
    return Shape(root, q, [for (final x in rel) b + x]);
  }
  final f = ((root - 9) % 12 + 12) % 12;
  final b = f == 0 ? 12 : f;
  final rel = switch (q) {
    'M' => [0, 2, 2, 2, 0],
    'm' => [0, 2, 2, 1, 0],
    '7' => [0, 2, 0, 2, 0],
    _ => [0, 2, 0, 1, 0],
  };
  return Shape(root, q, [-1, for (final x in rel) b + x]);
}

List<int> soundingNotes(List<int> frets) => [for (var s = 0; s < 6; s++) if (frets[s] >= 0) kStrings[s] + frets[s]];

/// Diziliş akorun seslerini eksiksiz ve fazlasız çalıyor mu? [bass] kök basta olsun mu?
bool shapeMakes(List<int> frets, int root, String q, {bool bass = true}) {
  final notes = soundingNotes(frets);
  if (notes.length < 3) return false;
  final ivs = kChords[q]!.iv;
  final want = {for (final iv in ivs) (root + iv) % 12};
  final got = {for (final n in notes) n % 12};
  // Dörtlü akorlarda beşli ses atlanabilir (ör. açık C7).
  final fifth = (root + 7) % 12;
  final need = ivs.length >= 4 && ivs.contains(7) ? (Set.of(want)..remove(fifth)) : want;
  if (!want.containsAll(got) || !got.containsAll(need)) return false;
  if (bass) {
    final low = notes.reduce((a, b) => a < b ? a : b);
    if (low % 12 != root % 12) return false;
  }
  // Elle basılabilir mi: en çok 4 perdelik açıklık.
  final pressed = [for (final f in frets) if (f > 0) f];
  if (pressed.isNotEmpty) {
    final mn = pressed.reduce((a, b) => a < b ? a : b), mx = pressed.reduce((a, b) => a > b ? a : b);
    if (mx - mn > 4) return false;
  }
  return true;
}

class GTask {
  final String type; // build, name, ear
  final Shape shape;
  final List<String> options; // akor sembolleri ya da "k:" anahtarları
  final int answer;
  const GTask(this.type, this.shape, this.options, this.answer);
}

class GuitarPuzzle extends MPuzzle {
  final List<GTask> tasks;
  final bool bass;
  final bool names;
  const GuitarPuzzle(this.tasks, this.bass, this.names);

  @override
  Set<String> get samples => {
        for (final t in tasks) guitarSample(t.shape.root, t.shape.q),
        for (final t in tasks) for (final n in soundingNotes(t.shape.frets)) pianoSample(n),
      };
}

/// Bir anahtardaki diziye uygun akor dizisi (ilerleme) kökleri ve türleri.
const List<List<(int, String)>> _progressions = [
  [(0, 'M'), (5, 'M'), (7, 'M'), (0, 'M')],
  [(0, 'M'), (9, 'm'), (5, 'M'), (7, 'M')],
  [(0, 'M'), (7, 'M'), (9, 'm'), (5, 'M')],
  [(9, 'm'), (5, 'M'), (0, 'M'), (7, 'M')],
  [(0, 'M'), (4, 'm'), (5, 'M'), (7, '7')],
  [(2, 'm'), (7, '7'), (0, 'M'), (9, 'm')],
];

class GuitarKind extends MuzikKind {
  @override
  String get id => 'gitar-akorlari';
  const GuitarKind();

  Shape? _shapeFor(int root, String q, int d, SeededRandom r) {
    final open = [for (final s in kOpenShapes) if (s.root == root % 12 && s.q == q) s];
    if (open.isNotEmpty && (d < 6 || r.chance(0.5))) return open.first;
    if (d < 6) return null;
    final s = barreShape(root, q, aShape: r.chance(0.5));
    return s.frets.any((f) => f > 14) ? null : s;
  }

  @override
  MPuzzle? make(int d, SeededRandom r, {bool short = false}) {
    final n = short ? 3 : 6;
    final types = [
      'build',
      'name',
      if (d >= 2) 'ear',
    ];
    final qs = d <= 3 ? const ['M', 'm'] : const ['M', 'm', '7', 'm7'];
    // Bir anahtar seç, ilerlemeden akorlar üret; kolay bölümde açık akor bulunan anahtarlar.
    final keys = d < 6 ? const [0, 7, 2, 9, 4] : List.generate(12, (i) => i);
    final key = r.pick(keys);
    final prog = r.pick(_progressions);
    final tasks = <GTask>[];
    var g = 0;
    while (tasks.length < n && g++ < 80) {
      final step = prog[g % prog.length];
      var root = (key + step.$1) % 12;
      var q = qs.contains(step.$2) ? step.$2 : 'M';
      if (r.chance(0.25)) {
        root = r.nextInt(12);
        q = r.pick(qs);
      }
      final shape = _shapeFor(root, q, d, r);
      if (shape == null) continue;
      final type = r.pick(types);
      if (type == 'build') {
        tasks.add(GTask('build', shape, const [], 0));
      } else if (type == 'name') {
        final truth = chordSymbol(root, q);
        final others = <String>{};
        var k = 0;
        while (others.length < 3 && k++ < 40) {
          final o = chordSymbol(d <= 3 ? root : r.nextInt(12), r.pick(qs));
          final o2 = d <= 3 && o == truth ? chordSymbol(r.nextInt(12), q) : o;
          if (o2 != truth) others.add(o2);
        }
        final opts = [truth, ...others.take(3)];
        r.shuffle(opts);
        tasks.add(GTask('name', shape, opts, opts.indexOf(truth)));
      } else {
        if (!const ['M', 'm', '7', 'm7'].contains(q)) continue;
        final pool = d <= 5 ? const ['M', 'm'] : const ['M', 'm', '7', 'm7'];
        if (!pool.contains(q)) continue;
        final opts = [for (final x in pool) 'k:q_$x'];
        tasks.add(GTask('ear', shape, opts, opts.indexOf('k:q_$q')));
      }
    }
    if (tasks.length < n) return null;
    return GuitarPuzzle(tasks, d >= 3, d <= 3);
  }

  @override
  bool check(MPuzzle p) {
    if (p is! GuitarPuzzle || p.tasks.length < 3) return false;
    for (final t in p.tasks) {
      if (t.shape.frets.length != 6) return false;
      if (!shapeMakes(t.shape.frets, t.shape.root, t.shape.q, bass: true)) return false;
      if (t.type != 'build') {
        if (t.options.length < 2 || t.options.toSet().length != t.options.length) return false;
        if (t.answer < 0 || t.answer >= t.options.length) return false;
        final truth = t.type == 'name' ? chordSymbol(t.shape.root, t.shape.q) : 'k:q_${t.shape.q}';
        if (t.options[t.answer] != truth) return false;
      }
    }
    return true;
  }

  @override
  List<GameStat> get stats => const [
        GameStat('rounds_won', 'Tamamlanan çalışma', 'Sessions completed', scale: 10),
        GameStat('perfect', 'Hatasız çalışma', 'Flawless sessions', scale: 10),
        GameStat('chords_built', 'Kurulan akor', 'Chords built', scale: 50),
      ];

  @override
  List<MissionTemplate> get missions => const [
        MissionTemplate('win', 'rounds_won', [3, 10, 25]),
        MissionTemplate('chords', 'chords_built', [10, 40, 120]),
        MissionTemplate('perfect', 'perfect', [1, 5, 15]),
      ];

  @override
  Widget build(MuzikPlay play) => _GuitarView(play: play);
}

class _GuitarView extends StatefulWidget {
  final MuzikPlay play;
  const _GuitarView({required this.play});
  @override
  State<_GuitarView> createState() => _GuitarViewState();
}

class _GuitarViewState extends State<_GuitarView> with Clock<_GuitarView> {
  late final GuitarPuzzle p = widget.play.puzzle as GuitarPuzzle;
  int ti = 0, correct = 0, tries = 0, hints = 0, built = 0;
  List<int> frets = [-1, -1, -1, -1, -1, -1];
  int base = 1;
  bool done = false, revealed = false;
  int? chosen;
  final Set<int> plucked = {};

  GTask get t => p.tasks[ti];

  @override
  void initState() {
    super.initState();
    startClock();
    _setup();
  }

  void _setup() {
    frets = t.type == 'build' ? [-1, -1, -1, -1, -1, -1] : List.of(t.shape.frets);
    final pressed = [for (final f in t.shape.frets) if (f > 0) f];
    final mn = pressed.isEmpty ? 1 : pressed.reduce((a, b) => a < b ? a : b);
    base = mn <= 3 ? 1 : mn;
    done = false;
    revealed = false;
    chosen = null;
    tries = 0;
    if (t.type == 'ear') later(300, _strumTarget);
  }

  void _strumTarget() => widget.play.sample(guitarSample(t.shape.root, t.shape.q));

  void _strum(List<int> f) {
    final notes = soundingNotes(f);
    for (var i = 0; i < notes.length; i++) {
      later(i * 40, () {
        widget.play.note(notes[i], volume: 0.8);
        setState(() => plucked.add(i));
      });
    }
    later(notes.length * 40 + 300, () => setState(plucked.clear));
    Haptic.hit();
  }

  void _tapBoard(Offset o) {
    if (t.type != 'build' || done) return;
    final s = clampI(((o.dx - 40) / 56).round(), 0, 5);
    setState(() {
      if (o.dy < 56) {
        frets[s] = frets[s] == 0 ? -1 : 0;
      } else {
        final f = base + clampI(((o.dy - 60) / 48).floor(), 0, 4);
        frets[s] = frets[s] == f ? -1 : f;
        widget.play.note(kStrings[s] + f, volume: 0.7);
      }
    });
  }

  void _submit() {
    if (done) return;
    final ok = shapeMakes(frets, t.shape.root, t.shape.q, bass: p.bass);
    if (ok) {
      widget.play.sample(guitarSample(t.shape.root, t.shape.q));
      widget.play.sfx(Sfx.place);
      Haptic.hit();
      setState(() {
        done = true;
        built++;
        if (tries <= 2) correct++;
      });
    } else {
      _strum(frets);
      widget.play.sfx(Sfx.error);
      Haptic.miss();
      setState(() {
        tries++;
        if (tries >= 3) {
          revealed = true;
          done = true;
          frets = List.of(t.shape.frets);
          final pressed = [for (final f in frets) if (f > 0) f];
          base = pressed.isEmpty || pressed.reduce((a, b) => a < b ? a : b) <= 3 ? 1 : pressed.reduce((a, b) => a < b ? a : b);
        }
      });
    }
  }

  void _choose(int i) {
    if (done) return;
    final ok = i == t.answer;
    if (ok) {
      correct++;
      widget.play.sfx(Sfx.place);
    } else {
      widget.play.sfx(Sfx.error);
      Haptic.miss();
    }
    _strumTarget();
    setState(() {
      chosen = i;
      done = true;
    });
  }

  void _next() {
    if (ti + 1 >= p.tasks.length) {
      ended = true;
      final need = p.tasks.length - 1;
      if (correct >= need) {
        // Ödül: akorlar sırayla tekrar çalınır.
        for (var i = 0; i < p.tasks.length; i++) {
          later(i * 650, () => widget.play.sample(guitarSample(p.tasks[i].shape.root, p.tasks[i].shape.q)));
        }
        final stars = correct == p.tasks.length ? 3 : 2;
        later(p.tasks.length * 650 + 200,
            () => widget.play.win(score: correct * 150, stars: stars - hints, seconds: seconds, hints: hints, extra: {'chords_built': built}));
      } else {
        widget.play.lose(score: correct * 150, seconds: seconds, headline: '$correct/${p.tasks.length}');
      }
      setState(() {});
      return;
    }
    setState(() {
      ti++;
      _setup();
    });
  }

  Future<void> _hint() async {
    if (done || t.type != 'build') return;
    if (await widget.play.ctx.requestHint()) {
      // Doğru şeklin bir telini yerleştir.
      setState(() {
        hints++;
        for (var s = 0; s < 6; s++) {
          if (frets[s] != t.shape.frets[s]) {
            frets[s] = t.shape.frets[s];
            break;
          }
        }
      });
    }
  }

  void _paint(Canvas c) {
    const double w = 360, h = 320;
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, w, h), const Radius.circular(16)), fill(const Color(0xFF6B4A33)));
    // Perdeler.
    for (var f = 0; f <= 5; f++) {
      final y = 60 + f * 48.0;
      c.drawLine(Offset(40, y), Offset(320, y), stroke(f == 0 && base == 1 ? const Color(0xFFF3E9D2) : const Color(0xFFBFB6A0), f == 0 && base == 1 ? 7 : 3));
    }
    if (base > 1) drawLabel(c, '$base', const Offset(18, 84), 16, Colors.white);
    for (final f in const [3, 5, 7, 9, 12]) {
      final k = f - base;
      if (k >= 0 && k < 5) c.drawCircle(Offset(180, 60 + k * 48.0 + 24), 6, fill(const Color(0x55FFFFFF)));
    }
    for (var s = 0; s < 6; s++) {
      final x = 40 + s * 56.0;
      final vib = plucked.isNotEmpty ? 1.5 : 0.0;
      c.drawLine(Offset(x + vib, 60), Offset(x - vib, 300), stroke(const Color(0xFFE6E0D2), 1.5 + (5 - s) * 0.5));
      final fr = frets[s];
      if (fr < 0) {
        drawLabel(c, '×', Offset(x, 34), 22, const Color(0xFFE9A0A0));
      } else if (fr == 0) {
        c.drawCircle(Offset(x, 34), 10, stroke(Colors.white, 3));
      } else {
        final k = fr - base;
        if (k >= 0 && k < 5) {
          final o = Offset(x, 60 + k * 48.0 + 24);
          c.drawCircle(o, 17, fill(revealed ? MColors.ok : MColors.lanes[s]));
          if (p.names) drawLabel(c, noteName(kStrings[s] + fr, widget.play.lang), o, 12, MColors.ink);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.play.lang;
    final title = switch (t.type) {
      'build' => '${mt(lang, 'buildChord')}: ${chordSymbol(t.shape.root, t.shape.q)}',
      'name' => mt(lang, 'nameChord'),
      _ => mt(lang, 'earChord'),
    };
    final ok = t.type == 'build' ? done && !revealed : chosen == t.answer;
    Widget? bottom;
    if (done) {
      bottom = FilledButton.icon(onPressed: _next, icon: const Icon(Icons.arrow_forward), label: Text(mt(lang, 'next')));
    } else if (t.type == 'build') {
      bottom = Row(children: [
        IconButton(onPressed: base > 1 ? () => setState(() => base--) : null, icon: const Icon(Icons.keyboard_arrow_up, color: Colors.white)),
        IconButton(onPressed: base < 12 ? () => setState(() => base++) : null, icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white)),
        Expanded(
          child: FilledButton.icon(onPressed: _submit, icon: const Icon(Icons.music_note), label: Text('${mt(lang, 'strum')}  (${3 - tries})')),
        ),
      ]);
    } else {
      bottom = Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
        for (var i = 0; i < t.options.length; i++)
          SizedBox(
            width: 150,
            child: MChip(
              onTap: () => _choose(i),
              child: Text(t.options[i].startsWith('k:') ? mt(lang, t.options[i].substring(2)) : t.options[i], style: const TextStyle(fontSize: 20)),
            ),
          ),
      ]);
    }
    final chordTones = [for (final iv in kChords[t.shape.q]!.iv) noteName(t.shape.root + iv, lang)].join(' · ');
    return MScreen(
      bar: MBar(play: widget.play, left: '${ti + 1}/${p.tasks.length}', status: '✓ $correct', onHint: t.type == 'build' && !done ? _hint : null),
      top: Column(children: [
        Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
        if (t.type == 'build' && p.names) Text(chordTones, style: const TextStyle(color: Colors.white70)),
        if (done)
          Text(ok ? mt(lang, 'correct') : '${mt(lang, 'answerWas')} ${chordSymbol(t.shape.root, t.shape.q)}',
              style: TextStyle(color: ok ? MColors.ok : MColors.bad, fontWeight: FontWeight.w700)),
      ]),
      board: t.type == 'ear' && !done
          ? Center(
              child: IconButton.filled(
                iconSize: 72,
                onPressed: _strumTarget,
                icon: const Icon(Icons.replay),
                tooltip: mt(lang, 'listen'),
              ),
            )
          : TapCanvas(w: 360, h: 320, paint: _paint, onTap: _tapBoard, semantics: title),
      bottom: bottom,
    );
  }
}
