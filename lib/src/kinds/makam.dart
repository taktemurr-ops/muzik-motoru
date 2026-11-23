import 'package:flutter/material.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';

import '../audio.dart';
import '../core.dart';
import '../synth.dart';
import '../texts.dart';
import '../theory.dart' show clampD, clampI;

/// Türk müziği makamı: 53 komalı oktavda aralıklar (Arel-Ezgi-Uzdilek dizgesine göre),
/// karar (durak) sesi, güçlü sesi ve seyir yönü.
class MakamDef {
  final String key;

  /// Durağın Rast'tan koma uzaklığı.
  final int durak;

  /// Durak'tan oktava yedi aralık (toplamı 53 koma).
  final List<int> steps;

  /// Güçlü sesin dizideki sırası (0 = durak).
  final int guclu;

  /// 'up' çıkıcı, 'down' inici-çıkıcı.
  final String seyir;
  const MakamDef(this.key, this.durak, this.steps, this.guclu, this.seyir);
}

const List<MakamDef> kMakams = [
  MakamDef('rast', 0, [9, 8, 5, 9, 9, 8, 5], 4, 'up'),
  MakamDef('ussak', 9, [8, 5, 9, 9, 4, 9, 9], 3, 'up'),
  MakamDef('hicaz', 9, [5, 12, 5, 9, 8, 5, 9], 3, 'down'),
  MakamDef('kurdi', 9, [4, 9, 9, 9, 4, 9, 9], 3, 'up'),
  MakamDef('nihavent', 0, [9, 4, 9, 9, 5, 12, 5], 4, 'down'),
  MakamDef('huseyni', 9, [8, 5, 9, 9, 8, 5, 9], 4, 'down'),
  MakamDef('segah', 17, [5, 9, 5, 12, 5, 9, 8], 2, 'up'),
];

MakamDef makamOf(String key) => kMakams.firstWhere((m) => m.key == key);

/// Dizinin sesleri: durak'tan [from] basamak aşağıdan [to] basamağa kadar (koma).
List<int> makamDegrees(MakamDef m, {int from = 0, int to = 7}) {
  int pos(int i) {
    final oct = i >= 0 ? i ~/ 7 : -((-i + 6) ~/ 7);
    final r = i - oct * 7;
    var k = m.durak + oct * 53;
    for (var j = 0; j < r; j++) {
      k += m.steps[j];
    }
    return k;
  }

  return [for (var i = from; i <= to; i++) pos(i)];
}

/// Makamın perde sınıfları (oktavdan bağımsız, 0..52).
Set<int> makamClasses(MakamDef m) => {for (final k in makamDegrees(m)) ((k % 53) + 53) % 53};

const Map<int, String> _perde = {
  0: 'Rast',
  9: 'Dügâh',
  13: 'Kürdî',
  14: 'Dik Kürdî',
  17: 'Segâh',
  22: 'Çârgâh',
  26: 'Hicaz',
  31: 'Nevâ',
  36: 'Hisar',
  40: 'Hüseynî',
  44: 'Acem',
  48: 'Eviç',
};

/// Perde adı (Türk müziği terimi, her dilde aynı yazılır). Üst oktav "Tiz", alt oktav "Kaba".
String perdeName(int k) {
  final c = ((k % 53) + 53) % 53;
  final base = _perde[c] ?? '·';
  if (k >= 53) return 'Tiz $base';
  if (k < 0) return 'Kaba $base';
  return base;
}

/// Makam adları: Arap, Fars, Kiril vb. yazılar için yerel yazım; diğer dillerde Türkçe adı.
const Map<String, List<String>> _mkNames = {
  // rast, ussak, hicaz, kurdi, nihavent, huseyni, segah
  'tr': ['Rast', 'Uşşak', 'Hicaz', 'Kürdî', 'Nihâvent', 'Hüseynî', 'Segâh'],
  'ar': ['راست', 'عشاق', 'حجاز', 'كرد', 'نهاوند', 'حسيني', 'سيكاه'],
  'fa': ['راست', 'عشاق', 'حجاز', 'کرد', 'نهاوند', 'حسینی', 'سه‌گاه'],
  'ur': ['راست', 'عشاق', 'حجاز', 'کرد', 'نہاوند', 'حسینی', 'سیگاہ'],
  'he': ['ראסט', 'עושאק', 'חיג׳אז', 'כורדי', 'נהאוונד', 'חוסייני', 'סיגה'],
  'ru': ['Раст', 'Ушшак', 'Хиджаз', 'Кюрди', 'Нихавент', 'Хюсейни', 'Сегях'],
  'uk': ['Раст', 'Ушшак', 'Хіджаз', 'Кюрді', 'Нігавент', 'Гюсейні', 'Сегях'],
  'el': ['Ραστ', 'Ουσάκ', 'Χιτζάζ', 'Κιουρντί', 'Νιχαβέντ', 'Χουσεϊνί', 'Σεγκιάχ'],
  'ja': ['ラスト', 'ウッシャーク', 'ヒジャーズ', 'キュルディー', 'ニハーヴェント', 'ヒュセイニー', 'セギャー'],
  'ko': ['라스트', '우샤크', '히자즈', '퀴르디', '니하벤트', '휘세이니', '세가'],
  'zh': ['拉斯特', '乌沙克', '希贾兹', '库尔迪', '尼哈文特', '胡赛尼', '塞加'],
  'hi': ['रास्त', 'उश्शाक़', 'हिजाज़', 'कुर्दी', 'निहावेंत', 'हुसैनी', 'सेगाह'],
  'bn': ['রাস্ত', 'উশশাক', 'হিজাজ', 'কুর্দি', 'নিহাভেন্ত', 'হুসেইনি', 'সেগাহ'],
  'th': ['ราสต์', 'อุชชาก', 'ฮิจาซ', 'เคอร์ดี', 'นิฮาเวนต์', 'ฮูเซย์นี', 'เซกาห์'],
};

String makamName(String key, String lang) {
  final i = kMakams.indexWhere((m) => m.key == key);
  if (i < 0) return key;
  final l = _mkNames[lang] ?? _mkNames['tr']!;
  return l[i];
}

class MakamQ {
  /// 'which' makamı bul, 'durak' karar sesini bul, 'odd' yanlış perdeyi bul.
  final String type;
  final String makam;
  final List<int> notes;
  final List<double> durs;

  /// 'mk:<anahtar>', 'p:<koma>' veya 'i:<sıra>'.
  final List<String> options;
  final int answer;
  const MakamQ(this.type, this.makam, this.notes, this.durs, this.options, this.answer);
}

class MakamPuzzle extends MPuzzle {
  final List<MakamQ> qs;
  final int need;
  const MakamPuzzle(this.qs, this.need);
}

/// Sorunun doğru yanıtı, yalnızca seslerden ve tanımlardan yeniden hesaplanır.
String? makamTruth(MakamQ q) {
  if (q.notes.isEmpty) return null;
  final m = makamOf(q.makam);
  final cls = makamClasses(m);
  int c(int k) => ((k % 53) + 53) % 53;
  switch (q.type) {
    case 'which':
      bool fitsMakam(String o) {
        if (!o.startsWith('mk:')) return false;
        final mm = makamOf(o.substring(3));
        final cc = makamClasses(mm);
        return c(q.notes.last) == c(mm.durak) && q.notes.every((n) => cc.contains(c(n)));
      }

      final fits = [for (final o in q.options) if (fitsMakam(o)) o];
      return fits.length == 1 ? fits.first : null;
    case 'durak':
      if (!q.notes.every((n) => cls.contains(c(n)))) return null;
      final t = 'p:${m.durak}';
      return q.options.contains(t) ? t : null;
    case 'odd':
      final bad = [for (var i = 0; i < q.notes.length; i++) if (!cls.contains(c(q.notes[i]))) i];
      if (bad.length != 1) return null;
      final i = bad.first;
      if (i == 0 || i == q.notes.length - 1) return null;
      if (!(q.notes[i - 1] < q.notes[i] && q.notes[i] < q.notes[i + 1])) return null;
      return 'i:$i';
  }
  return null;
}

class MakamKind extends MuzikKind {
  @override
  String get id => 'makam-yolculugu';
  const MakamKind();

  List<String> _pool(int d) => d <= 2
      ? const ['rast', 'hicaz', 'kurdi']
      : (d <= 4 ? const ['rast', 'hicaz', 'kurdi', 'ussak', 'nihavent'] : [for (final m in kMakams) m.key]);

  /// Üretilmiş seyir: güçlüye uğrar, durakta karar verir.
  (List<int>, List<double>) _seyir(MakamDef m, int d, SeededRandom r) {
    final deg = makamDegrees(m, from: -1, to: 9); // sıra 0 = durak'ın bir altı
    int at(int i) => deg[i + 1];
    final g = m.guclu;
    final targets = m.seyir == 'up'
        ? [g, r.chance(0.5) ? 7 : g + 1, g, 1, 0]
        : [r.chance(0.5) ? 7 : g + 2, g, 2, -1, 0];
    var cur = m.seyir == 'up' ? r.range(0, 1) : targets.first;
    final idx = <int>[cur];
    final maxLen = 8 + d;
    for (final t in targets) {
      var guard = 0;
      while (cur != t && guard++ < 20 && idx.length < maxLen + 6) {
        final dir = t > cur ? 1 : -1;
        // Ara sıra bir geri adım (süsleme), çoğu zaman hedefe doğru.
        final back = idx.length > 2 && r.chance(0.18);
        var step = back ? -dir : dir;
        if (!back && (t - cur).abs() >= 3 && r.chance(0.25)) step = 2 * dir;
        cur = clampI(cur + step, -1, 9);
        idx.add(cur);
      }
    }
    if (idx.last != 0) idx.add(0);
    // Karar: son ses durak, bir öncesi üstten ya da alttan yaklaşır.
    final notes = [for (final i in idx) at(i)];
    final durs = [
      for (var i = 0; i < idx.length; i++)
        i == idx.length - 1 ? 1.1 : (idx[i] == g ? 0.6 : (r.chance(0.2) ? 0.55 : 0.36))
    ];
    return (notes, durs);
  }

  MakamQ? _q(String type, int d, SeededRandom r) {
    final pool = _pool(d);
    final m = makamOf(r.pick(pool));
    switch (type) {
      case 'which':
        final (notes, durs) = _seyir(m, d, r);
        final others = [for (final k in pool) if (k != m.key) k];
        r.shuffle(others);
        final n = pool.length >= 4 ? 4 : pool.length;
        final opts = ['mk:${m.key}', for (final k in others.take(n - 1)) 'mk:$k'];
        r.shuffle(opts);
        final q = MakamQ(type, m.key, notes, durs, opts, opts.indexOf('mk:${m.key}'));
        return makamTruth(q) == 'mk:${m.key}' ? q : null;
      case 'durak':
        final (notes, durs) = _seyir(m, d, r);
        // Karar sesi çalınmaz; oyuncu onu bulur.
        final shown = notes.sublist(0, notes.length - 1);
        final sd = durs.sublist(0, durs.length - 1);
        final deg = makamDegrees(m, from: 0, to: 6);
        final cand = [for (final k in deg.skip(1)) k];
        r.shuffle(cand);
        final opts = ['p:${m.durak}', for (final k in cand.take(3)) 'p:$k'];
        r.shuffle(opts);
        final q = MakamQ(type, m.key, shown, sd, opts, opts.indexOf('p:${m.durak}'));
        return makamTruth(q) == 'p:${m.durak}' ? q : null;
      case 'odd':
        final deg = makamDegrees(m, from: 0, to: 7);
        final i = r.range(1, 6);
        final lo = deg[i - 1], hi = deg[i + 1];
        final small = d >= 8 ? 3 : (d >= 6 ? 4 : 5);
        final cls = makamClasses(m);
        final cands = <int>[
          for (var k = lo + 2; k <= hi - 2; k++)
            if ((k - deg[i]).abs() >= small && !cls.contains(((k % 53) + 53) % 53)) k
        ];
        if (cands.isEmpty) return null;
        final notes = [...deg];
        notes[i] = r.pick(cands);
        final opts = [for (var j = 1; j < notes.length - 1; j++) 'i:$j'];
        final q = MakamQ(type, m.key, notes, [for (var j = 0; j < notes.length; j++) j == notes.length - 1 ? 0.9 : 0.45], opts, opts.indexOf('i:$i'));
        return makamTruth(q) == 'i:$i' ? q : null;
    }
    return null;
  }

  List<String> _types(int d) => ['which', if (d >= 2) 'durak', if (d >= 4) 'odd'];

  @override
  MPuzzle? make(int d, SeededRandom r, {bool short = false}) {
    final types = _types(d);
    final n = short ? 4 : 8;
    final qs = <MakamQ>[];
    var g = 0;
    while (qs.length < n && g++ < 300) {
      final t = r.chance(0.4) ? types.last : r.pick(types);
      final q = _q(t, d, r);
      if (q != null) qs.add(q);
    }
    if (qs.length < n) return null;
    return MakamPuzzle(qs, short ? 3 : (d <= 3 ? 5 : 6));
  }

  @override
  bool check(MPuzzle p) {
    if (p is! MakamPuzzle || p.qs.length < 4 || p.need > p.qs.length) return false;
    for (final q in p.qs) {
      if (q.notes.length != q.durs.length || q.notes.length < 4) return false;
      if (q.options.length < 2 || q.options.toSet().length != q.options.length) return false;
      if (q.answer < 0 || q.answer >= q.options.length) return false;
      if (q.notes.any((k) => k < -20 || k > 140)) return false;
      final t = makamTruth(q);
      if (t == null || q.options[q.answer] != t) return false;
    }
    return true;
  }

  @override
  List<GameStat> get stats => const [
        GameStat('rounds_won', 'Tamamlanan yolculuk', 'Journeys completed', scale: 10),
        GameStat('perfect', 'Kusursuz yolculuk', 'Perfect journeys', scale: 10),
        GameStat('makam_correct', 'Doğru yanıt', 'Correct answers', scale: 100),
      ];

  @override
  List<MissionTemplate> get missions => const [
        MissionTemplate('win', 'rounds_won', [3, 10, 25]),
        MissionTemplate('correct', 'makam_correct', [25, 100, 300]),
        MissionTemplate('perfect', 'perfect', [1, 5, 15]),
      ];

  @override
  Widget build(MuzikPlay play) => _MakamView(play: play);
}

String _seqKey(List<int> notes, List<double> durs) => 'mk_${notes.join('.')}_${durs.map((x) => (x * 100).round()).join('.')}';

class _MakamView extends StatefulWidget {
  final MuzikPlay play;
  const _MakamView({required this.play});
  @override
  State<_MakamView> createState() => _MakamViewState();
}

class _MakamViewState extends State<_MakamView> with Clock<_MakamView> {
  late final MakamPuzzle p = widget.play.puzzle as MakamPuzzle;
  late final SynthVoice synth = SynthVoice(sound: widget.play.voice.sound);
  int qi = 0, correct = 0, hints = 0;
  int? chosen, picked;
  bool started = false, playing = false;
  int lit = -1;
  final Set<int> removed = {};

  MakamQ get q => p.qs[qi];

  @override
  void dispose() {
    synth.dispose();
    super.dispose();
  }

  void _playSeq(List<int> notes, List<double> durs) {
    cancelLater();
    synth.play(_seqKey(notes, durs), () => Synth.sequence([for (final k in notes) Synth.komaHz(k)], durs));
    setState(() => playing = true);
    var at = 0;
    for (var i = 0; i < notes.length; i++) {
      final ii = i;
      later(at, () {
        Haptic.beat(strong: ii == notes.length - 1);
        setState(() => lit = ii);
      });
      at += (durs[i] * 1000).round();
    }
    later(at, () => setState(() {
          playing = false;
          lit = -1;
        }));
  }

  void _playQ() => _playSeq(q.notes, q.durs);

  void _playNote(int k) => synth.play('mkn_$k', () => Synth.note(Synth.komaHz(k), 0.8));

  void _scale() {
    final m = makamOf(q.makam);
    final deg = makamDegrees(m);
    _playSeq(deg, [for (var i = 0; i < deg.length; i++) i == deg.length - 1 ? 0.8 : 0.4]);
  }

  void _begin() {
    setState(() => started = true);
    startClock();
    _playQ();
  }

  void _tapOption(int i) {
    if (chosen != null || removed.contains(i)) return;
    final o = q.options[i];
    if (q.type == 'durak') {
      _playNote(int.parse(o.substring(2)));
      setState(() => picked = i);
      return;
    }
    if (q.type == 'odd') _playNote(q.notes[int.parse(o.substring(2))]);
    _answer(i);
  }

  void _answer(int i) {
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
    later(500, () {
      if (q.type == 'durak') {
        _playSeq([...q.notes, makamOf(q.makam).durak], [...q.durs, 1.1]);
      } else {
        _playQ();
      }
    });
  }

  void _next() {
    if (qi + 1 >= p.qs.length) {
      ended = true;
      final wrong = p.qs.length - correct;
      if (correct >= p.need) {
        final stars = wrong == 0 ? 3 : (correct >= p.need + 1 ? 2 : 1);
        widget.play.win(score: correct * 120, stars: stars - hints, seconds: seconds, hints: hints, extra: {'makam_correct': correct});
      } else {
        widget.play.lose(score: correct * 120, seconds: seconds, headline: '$correct/${p.qs.length}');
      }
      return;
    }
    cancelLater();
    setState(() {
      qi++;
      chosen = null;
      picked = null;
      removed.clear();
    });
    later(300, _playQ);
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

  String _label(String o, String lang) {
    if (o.startsWith('mk:')) return makamName(o.substring(3), lang);
    if (o.startsWith('p:')) return perdeName(int.parse(o.substring(2)));
    if (o.startsWith('i:')) return '${int.parse(o.substring(2)) + 1}';
    return o;
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.play.lang;
    if (!started) {
      return MScreen(
        bar: MBar(play: widget.play, status: mt(lang, 'makamTitle')),
        board: StartCard(
          title: mt(lang, 'makamTitle'),
          subtitle: '${p.qs.length} · ${mt(lang, 'needCorrect')} ${p.need}',
          button: mt(lang, 'start'),
          onStart: _begin,
          icon: Icons.explore,
        ),
      );
    }
    final reveal = chosen != null;
    final m = makamOf(q.makam);
    final prompt = mt(lang, switch (q.type) { 'which' => 'askMakam', 'durak' => 'askDurak', _ => 'askOdd' });
    final ladder = q.type == 'odd';
    return MScreen(
      bar: MBar(play: widget.play, left: '${qi + 1}/${p.qs.length}', status: '✓ $correct', onHint: chosen == null ? _hint : null),
      flash: playing && lit >= 0 ? 0.6 : 0.0,
      flashColor: MColors.accent,
      top: Text(prompt, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
      board: Column(children: [
        const SizedBox(height: 6),
        Semantics(
          button: true,
          label: mt(lang, 'listen'),
          child: GestureDetector(
            onTap: playing ? null : _playQ,
            child: Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(shape: BoxShape.circle, color: playing ? MColors.accent : MColors.soft, border: Border.all(color: Colors.white24, width: 4)),
              child: Icon(playing ? Icons.graphic_eq : Icons.replay, color: Colors.white, size: 48),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(height: 64, child: _PerdeStrip(notes: q.notes, lit: MusicPrefs.flash ? lit : -1)),
        const SizedBox(height: 8),
        if (reveal)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '${makamName(m.key, lang)} · ${mt(lang, 'durak')}: ${perdeName(m.durak)} · ${mt(lang, 'guclu')}: ${perdeName(makamDegrees(m)[m.guclu])}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        Expanded(
          child: ladder
              ? Row(children: [
                  for (var i = 0; i < q.options.length; i++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: Opacity(
                          opacity: removed.contains(i) ? 0.25 : 1,
                          child: MChip(
                            color: !reveal ? MColors.lanes[i % MColors.lanes.length] : (i == q.answer ? MColors.good : (i == chosen ? MColors.bad : MColors.soft)),
                            onTap: reveal ? null : () => _tapOption(i),
                            child: FittedBox(child: Text(_label(q.options[i], lang), style: const TextStyle(fontSize: 22))),
                          ),
                        ),
                      ),
                    ),
                ])
              : GridView.count(
                  crossAxisCount: 2,
                  childAspectRatio: 2.6,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  children: [
                    for (var i = 0; i < q.options.length; i++)
                      Opacity(
                        opacity: removed.contains(i) ? 0.25 : 1,
                        child: MChip(
                          selected: picked == i,
                          color: !reveal ? MColors.soft : (i == q.answer ? MColors.good : (i == chosen ? MColors.bad : MColors.soft)),
                          onTap: reveal ? null : () => _tapOption(i),
                          child: FittedBox(child: Text(_label(q.options[i], lang), style: const TextStyle(fontSize: 17))),
                        ),
                      ),
                  ],
                ),
        ),
      ]),
      bottom: reveal
          ? Row(children: [
              Expanded(child: OutlinedButton.icon(onPressed: playing ? null : _scale, icon: const Icon(Icons.stairs), label: FittedBox(child: Text(mt(lang, 'scaleBtn'))))),
              const SizedBox(width: 8),
              Expanded(child: FilledButton.icon(onPressed: _next, icon: const Icon(Icons.arrow_forward), label: FittedBox(child: Text(mt(lang, 'next'))))),
            ])
          : (q.type == 'durak'
              ? FilledButton.icon(
                  onPressed: picked == null ? null : () => _answer(picked!),
                  icon: const Icon(Icons.check),
                  label: Text(mt(lang, 'confirm')),
                )
              : null),
    );
  }
}

/// Perde şeridi: çalan ezginin sesleri koma çizgisi üzerinde gösterilir (görsel destek).
class _PerdeStrip extends StatelessWidget {
  final List<int> notes;
  final int lit;
  const _PerdeStrip({required this.notes, required this.lit});

  @override
  Widget build(BuildContext context) {
    return TapCanvas(
      w: 360,
      h: 64,
      semantics: 'perde',
      paint: (c) {
        final lo = notes.reduce((a, b) => a < b ? a : b) - 4;
        final hi = notes.reduce((a, b) => a > b ? a : b) + 4;
        double x(int k) => 12 + (k - lo) / (hi - lo) * 336;
        c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 360, 64), const Radius.circular(14)), fill(MColors.stage));
        for (var k = lo; k <= hi; k++) {
          c.drawLine(Offset(x(k), 40), Offset(x(k), k % 53 == 0 ? 28 : 34), stroke(Colors.white24, 1));
        }
        for (final k in notes.toSet()) {
          c.drawCircle(Offset(x(k), 40), 5, fill(Colors.white38));
        }
        if (lit >= 0 && lit < notes.length) {
          c.drawCircle(Offset(x(notes[lit]), 40), 11, fill(MColors.ok));
          drawLabel(c, perdeName(notes[lit]), Offset(clampD(x(notes[lit]), 40, 320), 14), 12, Colors.white);
        }
      },
    );
  }
}
