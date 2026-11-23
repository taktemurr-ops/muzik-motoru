import 'package:flutter/material.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';

import '../audio.dart';
import '../core.dart';
import '../texts.dart';
import '../theory.dart';

/// Kulak Eğitimi: tiz-pes, yön, aralık, akor türü ve dizi tanıma.
/// Seçenekler "k:" ile başlarsa metin anahtarı, "l:" ile başlarsa doğrudan etikettir.
class EarQ {
  final String type;
  final List<List<int>> events; // her olay birlikte çalınan sesler
  final List<String> options;
  final int answer;
  const EarQ(this.type, this.events, this.options, this.answer);
  List<int> get allNotes => [for (final e in events) ...e];
}

class EarPuzzle extends MPuzzle {
  final List<EarQ> qs;
  final int need;
  const EarPuzzle(this.qs, this.need);

  @override
  Set<String> get samples => {for (final q in qs) for (final m in q.allNotes) pianoSample(m)};
}

const Map<String, List<int>> _qualityIv = {
  'M': [0, 4, 7],
  'm': [0, 3, 7],
  'dim': [0, 3, 6],
  'aug': [0, 4, 8],
  '7': [0, 4, 7, 10],
  'maj7': [0, 4, 7, 11],
  'm7': [0, 3, 7, 10],
  'm7b5': [0, 3, 6, 10],
};

const Map<String, ScaleDef> _scaleOf = {
  'major': kMajor,
  'minor': kMinor,
  'harmonic': kHarmonic,
  'penta': kPentaMajor,
  'hicaz': kHicaz,
  'dorian': kDorian,
};

String ivLabel(int s) => 'l:${kIntervalAbbr[s]} · $s';

/// Sorunun doğru yanıtını seslerden yeniden hesaplar (doğrulama için).
String? earTruth(EarQ q) {
  final e = q.events;
  switch (q.type) {
    case 'hl':
      if (e.length != 2 || e[0][0] == e[1][0]) return null;
      return e[0][0] > e[1][0] ? 'k:firstHigher' : 'k:secondHigher';
    case 'same':
      if (e.length != 2) return null;
      return e[0][0] == e[1][0] ? 'k:same' : 'k:different';
    case 'dir':
      final m = [for (final x in e) x[0]];
      bool inc(int a, int b) => m[b] > m[a];
      final up = List.generate(m.length - 1, (i) => inc(i, i + 1));
      if (m.any((x) => m.where((y) => y == x).length > 1)) return null;
      if (up.every((u) => u)) return 'k:up';
      if (up.every((u) => !u)) return 'k:down';
      final peak = up.indexWhere((u) => !u);
      if (peak > 0 && up.sublist(peak).every((u) => !u)) return 'k:upDown';
      final valley = up.indexWhere((u) => u);
      if (valley > 0 && up.sublist(valley).every((u) => u)) return 'k:downUp';
      return null;
    case 'iv':
      if (e.length != 2) return null;
      final s = (e[1][0] - e[0][0]).abs();
      return s >= 1 && s <= 12 ? ivLabel(s) : null;
    case 'hiv':
      if (e.length != 1 || e[0].length != 2) return null;
      final s = (e[0][1] - e[0][0]).abs();
      return s >= 1 && s <= 12 ? ivLabel(s) : null;
    case 'chord':
      final notes = e.last;
      final rel = [for (final n in notes) n - notes.first];
      for (final en in _qualityIv.entries) {
        if (en.value.length == rel.length && List.generate(rel.length, (i) => rel[i] == en.value[i]).every((x) => x)) return 'k:q_${en.key}';
      }
      return null;
    case 'scale':
      final m = [for (final x in e) x[0]];
      final rel = [for (final n in m) n - m.first];
      for (final en in _scaleOf.entries) {
        final st = [...en.value.steps, 12];
        if (st.length == rel.length && List.generate(rel.length, (i) => rel[i] == st[i]).every((x) => x)) return 'k:sc_${en.key}';
      }
      return null;
    case 'dict':
      return 'n:${[for (final x in e) x[0]].join(',')}';
  }
  return null;
}

class EarKind extends MuzikKind {
  @override
  String get id => 'kulak-egitimi';
  const EarKind();

  List<String> _typesFor(int d) => [
        if (d <= 3) 'hl',
        if (d <= 2) 'same',
        if (d >= 2 && d <= 5) 'dir',
        if (d >= 3) 'iv',
        if (d >= 4) 'chord',
        if (d >= 7) 'hiv',
        if (d >= 9) 'scale',
        if (d >= 10) 'dict',
      ];

  EarQ? _q(String type, int d, SeededRandom r) {
    List<String> opts(String truth, List<String> pool, int n) {
      final others = [for (final o in pool) if (o != truth) o];
      r.shuffle(others);
      final out = [truth, ...others.take(n - 1)];
      r.shuffle(out);
      return out;
    }

    EarQ mk(List<List<int>> ev, List<String> o, String truth) => EarQ(type, ev, o, o.indexOf(truth));
    switch (type) {
      case 'hl':
        final a = r.range(55, 70);
        final gap = d <= 1 ? r.range(4, 12) : r.range(1, 7);
        final b = r.chance(0.5) ? a + gap : a - gap;
        final ev = [
          [a],
          [b],
        ];
        return mk(ev, const ['k:firstHigher', 'k:secondHigher'], a > b ? 'k:firstHigher' : 'k:secondHigher');
      case 'same':
        final a = r.range(57, 74);
        final b = r.chance(0.5) ? a : a + (r.chance(0.5) ? 1 : -1) * r.range(1, 3);
        return mk([
          [a],
          [b],
        ], const ['k:same', 'k:different'], a == b ? 'k:same' : 'k:different');
      case 'dir':
        final shape = r.nextInt(4);
        final n = d <= 2 ? 3 : 4;
        final start = r.range(60, 70);
        final m = <int>[start];
        for (var i = 1; i < n; i++) {
          final up = switch (shape) { 0 => true, 1 => false, 2 => i < n ~/ 2 + 1, _ => i >= n ~/ 2 + 1 };
          m.add(m.last + (up ? 1 : -1) * r.range(2, 4));
        }
        final q = EarQ(type, [for (final x in m) [x]], const ['k:up', 'k:down', 'k:upDown', 'k:downUp'], 0);
        final t = earTruth(q);
        if (t == null) return null;
        return EarQ(type, q.events, q.options, q.options.indexOf(t));
      case 'iv':
      case 'hiv':
        final pool = d <= 4 ? const [2, 4, 5, 7, 12] : (d <= 6 ? const [1, 2, 3, 4, 5, 7, 8, 9, 12] : List.generate(12, (i) => i + 1));
        final s = r.pick(pool);
        final a = r.range(52, 72);
        final b = type == 'iv' && d >= 6 && r.chance(0.4) ? a - s : a + s;
        if (b < kLowMidi || b > kHighMidi) return null;
        final truth = ivLabel(s);
        final ev = type == 'iv'
            ? [
                [a],
                [b],
              ]
            : [
                [a, a + s],
              ];
        return mk(ev, opts(truth, [for (final x in pool) ivLabel(x)], 4), truth);
      case 'chord':
        final qs = d <= 5 ? const ['M', 'm'] : (d <= 7 ? const ['M', 'm', 'dim', 'aug'] : _qualityIv.keys.toList());
        final q = r.pick(qs);
        final root = r.range(50, 64);
        final notes = [for (final iv in _qualityIv[q]!) root + iv];
        // Önce arpej, sonra birlikte.
        final ev = [for (final n in notes) [n], notes];
        final truth = 'k:q_$q';
        return mk(ev, opts(truth, [for (final x in qs) 'k:q_$x'], qs.length >= 4 ? 4 : qs.length), truth);
      case 'scale':
        final key = r.pick(_scaleOf.keys.toList());
        final root = r.range(55, 64);
        final m = [for (final s in [..._scaleOf[key]!.steps, 12]) root + s];
        final truth = 'k:sc_$key';
        return mk([for (final x in m) [x]], opts(truth, [for (final k in _scaleOf.keys) 'k:sc_$k'], 4), truth);
      case 'dict':
        final root = r.range(60, 67);
        final pool = scaleNotes(root % 12, kMajor, root, root + 12);
        final m = [root, r.pick(pool), r.pick(pool)];
        if (m[1] == m[2] && m[0] == m[1]) return null;
        String lbl(List<int> x) => 'n:${x.join(',')}';
        final truth = lbl(m);
        final wrong = <String>{};
        var g = 0;
        while (wrong.length < 3 && g++ < 50) {
          final w = [root, r.pick(pool), r.pick(pool)];
          final l = lbl(w);
          if (l != truth) wrong.add(l);
        }
        if (wrong.length < 3) return null;
        final o = [truth, ...wrong];
        r.shuffle(o);
        return EarQ(type, [for (final x in m) [x]], o, o.indexOf(truth));
    }
    return null;
  }

  @override
  MPuzzle? make(int d, SeededRandom r, {bool short = false}) {
    final types = _typesFor(d);
    final n = short ? 5 : 10;
    final qs = <EarQ>[];
    var g = 0;
    while (qs.length < n && g++ < 200) {
      // Yeni açılan tür daha sık gelir.
      final t = r.chance(0.4) ? types.last : r.pick(types);
      final q = _q(t, d, r);
      if (q != null) qs.add(q);
    }
    if (qs.length < n) return null;
    final need = short ? (d <= 3 ? 3 : 4) : (d <= 3 ? 7 : 8);
    return EarPuzzle(qs, need);
  }

  @override
  bool check(MPuzzle p) {
    if (p is! EarPuzzle || p.qs.length < 5 || p.need > p.qs.length) return false;
    for (final q in p.qs) {
      if (q.options.length < 2 || q.options.length > 4 || q.options.toSet().length != q.options.length) return false;
      if (q.answer < 0 || q.answer >= q.options.length) return false;
      if (q.allNotes.any((m) => m < kLowMidi || m > kHighMidi)) return false;
      final t = earTruth(q);
      if (t == null || q.options[q.answer] != t) return false;
    }
    return true;
  }

  @override
  List<GameStat> get stats => const [
        GameStat('rounds_won', 'Geçilen test', 'Tests passed', scale: 10),
        GameStat('perfect', 'Tam puanlı test', 'Perfect tests', scale: 10),
        GameStat('ear_correct', 'Doğru yanıt', 'Correct answers', scale: 100),
      ];

  @override
  List<MissionTemplate> get missions => const [
        MissionTemplate('win', 'rounds_won', [3, 10, 25]),
        MissionTemplate('correct', 'ear_correct', [30, 120, 400]),
        MissionTemplate('perfect', 'perfect', [1, 5, 15]),
      ];

  @override
  Widget build(MuzikPlay play) => _EarView(play: play);
}

/// Seçenek etiketini dile göre yazar.
String optionText(String o, String lang) {
  if (o.startsWith('k:')) return mt(lang, o.substring(2));
  if (o.startsWith('l:')) return o.substring(2);
  if (o.startsWith('n:')) return [for (final x in o.substring(2).split(',')) noteName(int.parse(x), lang)].join(' – ');
  return o;
}

class _EarView extends StatefulWidget {
  final MuzikPlay play;
  const _EarView({required this.play});
  @override
  State<_EarView> createState() => _EarViewState();
}

class _EarViewState extends State<_EarView> with Clock<_EarView> {
  late final EarPuzzle p = widget.play.puzzle as EarPuzzle;
  int qi = 0, correct = 0, hints = 0;
  int? chosen;
  bool started = false, playing = false;
  final Set<int> removed = {};
  final Set<int> litNow = {};

  EarQ get q => p.qs[qi];

  void _playQ() {
    cancelLater();
    setState(() => playing = true);
    final melodic = q.type != 'hiv';
    var at = 0;
    for (final ev in q.events) {
      later(at, () {
        for (final m in ev) {
          widget.play.note(m);
        }
        Haptic.beat(strong: ev.length > 1);
        setState(() {
          litNow
            ..clear()
            ..addAll(MusicPrefs.flash ? ev : const []);
        });
      });
      at += melodic ? (ev.length > 1 ? 1200 : 650) : 1200;
    }
    later(at, () => setState(() {
          playing = false;
          litNow.clear();
        }));
  }

  void _begin() {
    setState(() => started = true);
    startClock();
    _playQ();
  }

  void _answer(int i) {
    if (chosen != null) return;
    final ok = i == q.answer;
    setState(() => chosen = i);
    if (ok) {
      correct++;
      widget.play.sfx(Sfx.place);
      Haptic.hit();
    } else {
      widget.play.sfx(Sfx.error);
      Haptic.miss();
    }
    // Doğru yanıtı gösterirken sesi yeniden çal (öğretici).
    later(350, _playQ);
  }

  void _next() {
    if (qi + 1 >= p.qs.length) {
      ended = true;
      final wrong = p.qs.length - correct;
      if (correct >= p.need) {
        final stars = wrong == 0 ? 3 : (correct >= p.need + 1 ? 2 : 1);
        widget.play.win(score: correct * 100, stars: stars - hints, seconds: seconds, hints: hints, extra: {'ear_correct': correct});
      } else {
        widget.play.lose(score: correct * 100, seconds: seconds, headline: '$correct/${p.qs.length}');
      }
      return;
    }
    cancelLater();
    setState(() {
      qi++;
      chosen = null;
      removed.clear();
    });
    later(250, _playQ);
  }

  Future<void> _hint() async {
    if (chosen != null) return;
    final wrong = [for (var i = 0; i < q.options.length; i++) if (i != q.answer && !removed.contains(i)) i];
    if (wrong.length <= 1) return;
    if (await widget.play.ctx.requestHint()) {
      setState(() {
        hints++;
        removed.add(wrong.first);
      });
    }
  }

  String _prompt(String lang) => mt(lang, switch (q.type) {
        'hl' => 'askHigher',
        'same' => 'askSame',
        'dir' => 'askDirection',
        'iv' || 'hiv' => 'askInterval',
        'chord' => 'askChord',
        'scale' => 'askScale',
        _ => 'askMelody',
      });

  @override
  Widget build(BuildContext context) {
    final lang = widget.play.lang;
    if (!started) {
      return MScreen(
        bar: MBar(play: widget.play, status: mt(lang, 'earTitle')),
        board: StartCard(
          title: mt(lang, 'earTitle'),
          subtitle: '${p.qs.length} · ${mt(lang, 'needCorrect')} ${p.need}',
          button: mt(lang, 'start'),
          onStart: _begin,
          icon: Icons.hearing,
        ),
      );
    }
    final notes = q.allNotes;
    final lo = ((notes.reduce((a, b) => a < b ? a : b) - 2) ~/ 12) * 12;
    final hi = clampI(lo + 24, lo + 12, kHighMidi);
    final reveal = chosen != null;
    final lit = <int, Color>{
      if (reveal) for (final m in notes) m: MColors.ok,
      for (final m in litNow) m: MColors.accent,
    };
    return MScreen(
      bar: MBar(
        play: widget.play,
        left: '${qi + 1}/${p.qs.length}',
        status: '✓ $correct',
        onHint: chosen == null ? _hint : null,
      ),
      top: Text(_prompt(lang), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
      board: Column(children: [
        const SizedBox(height: 8),
        Semantics(
          button: true,
          label: mt(lang, 'listen'),
          child: GestureDetector(
            onTap: playing ? null : _playQ,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: playing ? MColors.accent : MColors.soft,
                border: Border.all(color: Colors.white24, width: 4),
              ),
              child: Icon(playing ? Icons.graphic_eq : Icons.replay, color: Colors.white, size: 54),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: GridView.count(
            crossAxisCount: 2,
            childAspectRatio: 2.6,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              for (var i = 0; i < q.options.length; i++)
                Opacity(
                  opacity: removed.contains(i) ? 0.25 : 1,
                  child: MChip(
                    color: !reveal
                        ? MColors.soft
                        : (i == q.answer ? MColors.good : (i == chosen ? MColors.bad : MColors.soft)),
                    onTap: removed.contains(i) || reveal ? null : () => _answer(i),
                    child: FittedBox(child: Text(optionText(q.options[i], lang), style: const TextStyle(fontSize: 17))),
                  ),
                ),
            ],
          ),
        ),
        if (reveal || litNow.isNotEmpty)
          SizedBox(height: 92, child: PianoKeys(lo: lo, hi: hi, lit: lit, onKey: (m) => widget.play.note(m), lang: lang)),
      ]),
      bottom: reveal
          ? FilledButton.icon(onPressed: _next, icon: const Icon(Icons.arrow_forward), label: Text(mt(lang, 'next')))
          : null,
    );
  }
}
