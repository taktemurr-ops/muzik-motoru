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

/// Çalgı: adı ve tellerinin doğru sesleri (MIDI, kalından inceye).
class AkortInst {
  final String key;
  final List<int> strings;
  const AkortInst(this.key, this.strings);
}

const List<AkortInst> kAkortInsts = [
  AkortInst('violin', [55, 62, 69, 76]),
  AkortInst('baglama', [57, 62, 67]),
  AkortInst('guitar', [40, 45, 50, 55, 59, 64]),
];

AkortInst akortInst(String key) => kAkortInsts.firstWhere((i) => i.key == key);

double midiHz(int m) => 440.0 * math.pow(2, (m - 69) / 12).toDouble();

/// Sent kayması uygulanmış frekans.
double centsHz(double hz, int cents) => hz * math.pow(2, cents / 1200).toDouble();

/// İki ses arasındaki vuru (dalgalanma) sayısı, saniyede.
double beatRate(double hz, int cents) => (centsHz(hz, cents) - hz).abs();

class AkortPuzzle extends MPuzzle {
  final String inst;

  /// Ayarlanacak tellerin sırası (çalgının tel listesinde).
  final List<int> order;

  /// Her telin başlangıçtaki kayması (sent).
  final List<int> start;

  /// Kabul edilen en büyük sapma (sent).
  final int tol;
  const AkortPuzzle(this.inst, this.order, this.start, this.tol);
}

const int kAkortRange = 80;

class AkortKind extends MuzikKind {
  @override
  String get id => 'akort';
  const AkortKind();

  @override
  MPuzzle? make(int d, SeededRandom r, {bool short = false}) {
    final inst = d <= 2 ? kAkortInsts[r.nextInt(2)] : (d <= 5 ? kAkortInsts[r.nextInt(3)] : kAkortInsts[2]);
    final n = short ? 2 : math.min<int>(inst.strings.length, d <= 3 ? 3 : (d <= 6 ? 4 : 6));
    final idx = List<int>.generate(inst.strings.length, (i) => i);
    r.shuffle(idx);
    final order = idx.take(n).toList()..sort();
    final tol = math.max<int>(3, 13 - d);
    final lo = math.max<int>(tol + 6, 32 - d * 2), hi = math.max<int>(lo + 6, 62 - d * 3);
    final start = [for (var i = 0; i < n; i++) (r.chance(0.5) ? 1 : -1) * r.range(lo, hi)];
    return AkortPuzzle(inst.key, order, start, tol);
  }

  @override
  bool check(MPuzzle p) {
    if (p is! AkortPuzzle) return false;
    final inst = kAkortInsts.where((i) => i.key == p.inst).toList();
    if (inst.isEmpty) return false;
    if (p.order.isEmpty || p.order.length != p.start.length || p.order.length > inst.first.strings.length) return false;
    if (p.order.toSet().length != p.order.length || p.order.any((i) => i < 0 || i >= inst.first.strings.length)) return false;
    if (p.tol < 3 || p.tol > 13) return false;
    // Başlangıç akortsuz olmalı ama sürgü aralığında kalmalı.
    return p.start.every((c) => c.abs() > p.tol + 3 && c.abs() <= kAkortRange - 10);
  }

  @override
  List<GameStat> get stats => const [
        GameStat('rounds_won', 'Akort edilen çalgı', 'Instruments tuned', scale: 10),
        GameStat('perfect', 'İlk denemede akort', 'Tuned first try', scale: 10),
        GameStat('strings_tuned', 'Akort edilen tel', 'Strings tuned', scale: 100),
      ];

  @override
  List<MissionTemplate> get missions => const [
        MissionTemplate('win', 'rounds_won', [3, 10, 25]),
        MissionTemplate('strings', 'strings_tuned', [10, 50, 150]),
        MissionTemplate('perfect', 'perfect', [1, 5, 15]),
      ];

  @override
  Widget build(MuzikPlay play) => _AkortView(play: play);
}

class _AkortView extends StatefulWidget {
  final MuzikPlay play;
  const _AkortView({required this.play});
  @override
  State<_AkortView> createState() => _AkortViewState();
}

class _AkortViewState extends State<_AkortView> with Clock<_AkortView>, SingleTickerProviderStateMixin {
  late final AkortPuzzle p = widget.play.puzzle as AkortPuzzle;
  late final AkortInst inst = akortInst(p.inst);
  late final SynthVoice synth = SynthVoice(sound: widget.play.voice.sound);
  late final AnimationController pulse = AnimationController(vsync: this, duration: const Duration(seconds: 3));
  late final List<int> cents = [...p.start];
  final Set<int> done = {};
  int si = 0, tries = 0, hints = 0;
  bool started = false, sounding = false;
  String note = '';
  Color noteColor = Colors.white70;

  int get midi => inst.strings[p.order[si]];
  double get hz => midiHz(midi);

  @override
  void dispose() {
    pulse.dispose();
    synth.dispose();
    super.dispose();
  }

  void _sound() {
    final c = cents[si];
    final m = midi;
    synth.play('ak_${m}_$c', () => Synth.pair(midiHz(m), centsHz(midiHz(m), c), 2.6));
    Haptic.beat();
    cancelLater();
    setState(() => sounding = true);
    pulse
      ..reset()
      ..forward();
    later(2600, () => setState(() => sounding = false));
  }

  void _ref() {
    final m = midi;
    synth.play('akr_$m', () => Synth.note(midiHz(m), 1.6, release: 0.4));
  }

  void _begin() {
    setState(() => started = true);
    startClock();
    _sound();
  }

  void _confirm() {
    tries++;
    final c = cents[si];
    if (c.abs() <= p.tol) {
      widget.play.sfx(Sfx.place);
      Haptic.hit();
      setState(() {
        done.add(si);
        note = '${mt(widget.play.lang, 'tuneOk')} (${c >= 0 ? '+' : ''}$c)';
        noteColor = MColors.good;
      });
      if (done.length == p.order.length) {
        ended = true;
        final n = p.order.length;
        final stars = tries <= n ? 3 : (tries <= n + 2 ? 2 : 1);
        later(700, () => widget.play.win(score: 1000 - seconds * 2 - tries * 40, stars: stars - hints, seconds: seconds, hints: hints, extra: {'strings_tuned': n}));
        return;
      }
      later(700, () {
        setState(() {
          si = [for (var i = 0; i < p.order.length; i++) if (!done.contains(i)) i].first;
          note = '';
        });
        _sound();
      });
      return;
    }
    widget.play.sfx(Sfx.error);
    Haptic.miss();
    setState(() {
      note = mt(widget.play.lang, c > 0 ? 'tooHigh' : 'tooLow');
      noteColor = MColors.ok;
    });
    if (tries > p.order.length * 4) {
      ended = true;
      widget.play.lose(seconds: seconds, headline: '${done.length}/${p.order.length}');
    }
  }

  Future<void> _hint() async {
    if (await widget.play.ctx.requestHint()) {
      setState(() {
        hints++;
        // İpucu: sapmayı yarıya indirir.
        cents[si] = cents[si] ~/ 2;
        note = mt(widget.play.lang, cents[si] > 0 ? 'tooHigh' : 'tooLow');
        noteColor = Colors.white70;
      });
      _sound();
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.play.lang;
    if (!started) {
      return MScreen(
        bar: MBar(play: widget.play, status: mt(lang, 'akortTitle')),
        board: StartCard(
          title: '${mt(lang, 'akortTitle')} · ${mt(lang, 'inst_${inst.key}')}',
          subtitle: mt(lang, 'akortHelp'),
          button: mt(lang, 'start'),
          onStart: _begin,
          icon: Icons.tune,
        ),
      );
    }
    final rate = beatRate(hz, cents[si]);
    return MScreen(
      bar: MBar(play: widget.play, left: '${done.length}/${p.order.length}', status: mt(lang, 'inst_${inst.key}'), onHint: _hint),
      top: Text(mt(lang, 'akortHelp'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 15)),
      board: Column(children: [
        Expanded(
          child: AnimatedBuilder(
            animation: pulse,
            builder: (context, _) {
              // Görsel vuru: halka, duyulan dalgalanma hızında nabız atar.
              final t = pulse.value * 2.6;
              final amp = sounding && MusicPrefs.flash ? (0.5 + 0.5 * math.cos(2 * math.pi * rate * t)).abs() : 1.0;
              return TapCanvas(
                w: 360,
                h: 300,
                semantics: mt(lang, 'inst_${inst.key}'),
                paint: (c) => _paintInst(c, inst, p.order, si, done, amp),
              );
            },
          ),
        ),
        if (note.isNotEmpty) Text(note, style: TextStyle(color: noteColor, fontSize: 18, fontWeight: FontWeight.w800)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(children: [
            const Icon(Icons.remove, color: Colors.white54),
            Expanded(
              child: Semantics(
                label: mt(lang, 'akortTitle'),
                child: Slider(
                  value: cents[si].toDouble(),
                  min: -kAkortRange.toDouble(),
                  max: kAkortRange.toDouble(),
                  divisions: kAkortRange * 2,
                  onChanged: (v) => setState(() => cents[si] = v.round()),
                  onChangeEnd: (_) => _sound(),
                ),
              ),
            ),
            const Icon(Icons.add, color: Colors.white54),
          ]),
        ),
      ]),
      bottom: Row(children: [
        Expanded(child: OutlinedButton.icon(onPressed: _ref, icon: const Icon(Icons.hearing), label: FittedBox(child: Text(mt(lang, 'refTone'))))),
        const SizedBox(width: 6),
        Expanded(child: OutlinedButton.icon(onPressed: _sound, icon: const Icon(Icons.graphic_eq), label: FittedBox(child: Text(mt(lang, 'listen'))))),
        const SizedBox(width: 6),
        Expanded(child: FilledButton.icon(onPressed: ended ? null : _confirm, icon: const Icon(Icons.check), label: FittedBox(child: Text(mt(lang, 'confirm'))))),
      ]),
    );
  }
}

/// Çalgının vektör çizimi; ayarlanan tel parlak, akortlu teller yeşil.
void _paintInst(Canvas c, AkortInst inst, List<int> order, int si, Set<int> done, double amp) {
  const wood = Color(0xFFB07A4F), dark = Color(0xFF6E4A2F);
  final n = inst.strings.length;
  switch (inst.key) {
    case 'guitar':
      c.drawOval(const Rect.fromLTWH(70, 150, 220, 140), fill(wood));
      c.drawOval(const Rect.fromLTWH(95, 95, 170, 110), fill(wood));
      c.drawCircle(const Offset(180, 200), 26, fill(dark));
      c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(160, 6, 40, 150), const Radius.circular(6)), fill(dark));
    case 'baglama':
      c.drawOval(const Rect.fromLTWH(110, 160, 140, 130), fill(wood));
      c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(168, 6, 24, 170), const Radius.circular(6)), fill(dark));
      for (var i = 0; i < 8; i++) {
        c.drawLine(Offset(168, 30 + i * 18.0), Offset(192, 30 + i * 18.0), stroke(Colors.white30, 1.5));
      }
    default:
      final body = Path()
        ..moveTo(180, 120)
        ..cubicTo(110, 120, 110, 190, 140, 200)
        ..cubicTo(100, 215, 100, 290, 180, 292)
        ..cubicTo(260, 290, 260, 215, 220, 200)
        ..cubicTo(250, 190, 250, 120, 180, 120);
      c.drawPath(body, fill(wood));
      c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(170, 6, 20, 150), const Radius.circular(6)), fill(dark));
      c.drawLine(const Offset(150, 190), const Offset(150, 225), stroke(dark, 3));
      c.drawLine(const Offset(210, 190), const Offset(210, 225), stroke(dark, 3));
  }
  final span = math.min(14.0 * (n - 1), 30.0);
  for (var i = 0; i < n; i++) {
    final x = 180 - span / 2 + (n == 1 ? 0 : span * i / (n - 1));
    final k = order.indexOf(i);
    final active = k == si && !done.contains(k);
    final ok = k >= 0 && done.contains(k);
    final col = ok ? MColors.good : (active ? MColors.ok : (k >= 0 ? Colors.white70 : Colors.white30));
    final w = active ? 2.5 + 3.5 * (1 - amp) : 2.0;
    c.drawLine(Offset(x, 12), Offset(x, 270), stroke(col, w));
  }
}
