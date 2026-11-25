import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';

import '../audio.dart';
import '../core.dart';
import '../mic.dart';
import '../synth.dart';
import '../texts.dart';
import '../theory.dart';

/// Ses aralıkları: kalın ses C3'ten, ince ses C4'ten başlar (bir oktav).
const int kPitchLowBase = 48;
const int kPitchHighBase = 60;

class PitchPuzzle extends MPuzzle {
  /// Aralığın tabanına göre yarım ses uzaklıkları (0..12).
  final List<int> offs;

  /// Kabul edilen sapma (sent).
  final int tol;

  /// Perdenin tutulması gereken süre (ms).
  final int holdMs;

  /// Her nota için süre (saniye).
  final int timeS;

  /// Oktav farkı önemsiz mi (kolay bölümler).
  final bool anyOctave;
  const PitchPuzzle(this.offs, this.tol, this.holdMs, this.timeS, this.anyOctave);

  @override
  Set<String> get samples => {
        for (final o in offs) ...{pianoSample(kPitchLowBase + o), pianoSample(kPitchHighBase + o)},
      };
}

int pitchMaxStep(int d) => d <= 2 ? 2 : (d <= 4 ? 4 : (d <= 7 ? 7 : 12));

/// İki perde arasındaki sapma (sent); [anyOctave] ise en yakın oktava katlanır.
double pitchCents(double midi, int target, {bool anyOctave = false}) {
  var c = (midi - target) * 100;
  if (anyOctave) {
    c = ((c + 600) % 1200 + 1200) % 1200 - 600;
  }
  return c;
}

class PitchKind extends MuzikKind {
  @override
  String get id => 'ton-tutma';
  const PitchKind();

  @override
  MPuzzle? make(int d, SeededRandom r, {bool short = false}) {
    final n = short ? 2 : math.min<int>(8, 3 + d ~/ 2);
    final step = pitchMaxStep(d);
    // Do majör dizisi kolay; ileride kromatik sesler de gelir.
    const major = [0, 2, 4, 5, 7, 9, 11, 12];
    final pool = d <= 5 ? major : [for (var i = 0; i <= 12; i++) i];
    final offs = <int>[pool[r.nextInt(pool.length)]];
    for (var i = 1; i < n; i++) {
      final cand = [for (final o in pool) if (o != offs.last && (o - offs.last).abs() <= step) o];
      if (cand.isEmpty) return null;
      offs.add(cand[r.nextInt(cand.length)]);
    }
    final tol = math.max<int>(15, 55 - d * 4);
    final hold = 500 + d * 100;
    final time = d <= 4 ? 15 : (d <= 7 ? 12 : 10);
    return PitchPuzzle(offs, tol, hold, time, d <= 3);
  }

  @override
  bool check(MPuzzle p) {
    if (p is! PitchPuzzle) return false;
    if (p.offs.isEmpty || p.offs.length > 8) return false;
    if (p.offs.any((o) => o < 0 || o > 12)) return false;
    for (var i = 1; i < p.offs.length; i++) {
      if (p.offs[i] == p.offs[i - 1] || (p.offs[i] - p.offs[i - 1]).abs() > 12) return false;
    }
    if (p.tol < 15 || p.tol > 55 || p.holdMs < 500 || p.holdMs > 1600 || p.timeS < 8 || p.timeS > 20) return false;
    // Hedefler piyano örneklerinin içinde kalmalı.
    return p.offs.every((o) => kPitchLowBase + o >= kLowMidi && kPitchHighBase + o <= kHighMidi);
  }

  @override
  List<GameStat> get stats => const [
        GameStat('rounds_won', 'Tamamlanan bölüm', 'Levels completed', scale: 10),
        GameStat('perfect', 'Kusursuz bölüm', 'Perfect levels', scale: 10),
        GameStat('notes_held', 'Tutturulan ses', 'Notes matched', scale: 100),
      ];

  @override
  List<MissionTemplate> get missions => const [
        MissionTemplate('win', 'rounds_won', [3, 10, 25]),
        MissionTemplate('notes', 'notes_held', [15, 60, 200]),
        MissionTemplate('perfect', 'perfect', [1, 5, 15]),
      ];

  @override
  Widget build(MuzikPlay play) => _PitchView(play: play);
}

class _PitchView extends StatefulWidget {
  final MuzikPlay play;
  const _PitchView({required this.play});
  @override
  State<_PitchView> createState() => _PitchViewState();
}

class _PitchViewState extends State<_PitchView> with Clock<_PitchView> {
  late final PitchPuzzle p = widget.play.puzzle as PitchPuzzle;
  late final SynthVoice synth = SynthVoice(sound: widget.play.voice.sound);
  final PitchMic mic = PitchMic();
  Timer? tick;
  bool started = false, high = false, useMic = true;
  int i = 0, lives = 3, hints = 0, misses = 0;
  double? det; // algılanan perde (MIDI, kesirli)
  double level = 0, held = 0, left = 0;
  double slider = 6;
  final List<double> devs = [];
  final List<double> accs = [];
  final List<bool> res = [];
  double tolBoost = 1;
  String note = '';
  Color noteColor = Colors.white70;
  DateTime last = DateTime.now();

  String get lang => widget.play.lang;
  int get base => high ? kPitchHighBase : kPitchLowBase;
  int get target => base + p.offs[i];
  double get tol => p.tol * tolBoost;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPrefs());
  }

  Future<void> _loadPrefs() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final h = sp.getBool('muzik.voiceHigh') ?? false;
      if (mounted) setState(() => high = h);
    } catch (_) {}
  }

  Future<void> _savePrefs() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool('muzik.voiceHigh', high);
    } catch (_) {}
  }

  Future<bool> _rationale() async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (sp.getBool('muzik.micOk') ?? false) return true;
      if (!mounted) return false;
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          icon: const Icon(Icons.mic_rounded),
          title: Text(mt(lang, 'ttTitle')),
          content: Text(mt(lang, 'micWhy')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(mt(lang, 'ttSlider'))),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(mt(lang, 'micAllow'))),
          ],
        ),
      );
      if (ok == true) await sp.setBool('muzik.micOk', true);
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    tick?.cancel();
    unawaited(mic.stop());
    synth.dispose();
    super.dispose();
  }

  Future<void> _begin({required bool withMic}) async {
    var on = false;
    if (withMic && micUsable && await _rationale()) {
      mic.onPitch = _onPitch;
      on = await mic.start();
      if (!on && mounted) {
        note = mt(lang, 'micDenied');
        noteColor = MColors.ok;
      }
    }
    if (!mounted) return;
    setState(() {
      started = true;
      useMic = on;
      left = p.timeS.toDouble();
      slider = p.offs[i] - 3.0 < 0 ? p.offs[i] + 3.0 : p.offs[i] - 3.0;
    });
    startClock();
    last = DateTime.now();
    tick = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
    later(250, _ref);
  }

  void _ref() {
    widget.play.note(target);
    Haptic.beat();
  }

  void _onPitch(double? hz, double lv) {
    if (!mounted || ended || !started) return;
    final now = DateTime.now();
    final dt = now.difference(last).inMilliseconds.toDouble();
    last = now;
    setState(() {
      level = lv;
      det = hz == null ? null : hzToMidi(hz);
      final m = det;
      if (m == null) {
        held = math.max(0.0, held - dt * 0.5);
        return;
      }
      final c = pitchCents(m, target, anyOctave: p.anyOctave);
      if (c.abs() <= tol) {
        held += dt;
        devs.add(c.abs());
      } else {
        held = math.max(0.0, held - dt);
      }
    });
    if (held >= p.holdMs) _lock();
  }

  void _tick() {
    if (!mounted || ended || !started) return;
    setState(() => left = math.max(0.0, left - 0.1));
    if (left <= 0) _miss();
  }

  void _lock() {
    final acc = devs.isEmpty ? 0.0 : devs.reduce((a, b) => a + b) / devs.length;
    accs.add(acc);
    res.add(true);
    widget.play.sfx(Sfx.place);
    Haptic.hit();
    _advance(mt(lang, 'tuneOk'), MColors.good);
  }

  /// Süre doldu: can gider, sonraki sese geçilir.
  void _miss() {
    res.add(false);
    if (_loseLife()) return;
    _advance(mt(lang, 'jMiss'), MColors.bad);
  }

  /// Can düşer; oyun bittiyse true.
  bool _loseLife() {
    misses++;
    lives--;
    widget.play.sfx(Sfx.error);
    Haptic.miss();
    if (lives <= 0) {
      ended = true;
      tick?.cancel();
      unawaited(mic.stop());
      setState(() {
        note = mt(lang, 'jMiss');
        noteColor = MColors.bad;
      });
      later(800, () => widget.play.lose(seconds: seconds, headline: '${accs.length}/${p.offs.length}'));
      return true;
    }
    return false;
  }

  void _advance(String msg, Color col) {
    final done = i + 1 >= p.offs.length;
    setState(() {
      note = msg;
      noteColor = col;
      held = 0;
      devs.clear();
      tolBoost = 1;
      if (!done) {
        i++;
        left = p.timeS.toDouble();
        slider = clampD(slider, 0, 12);
      }
    });
    if (done) {
      ended = true;
      tick?.cancel();
      unawaited(mic.stop());
      final mean = accs.isEmpty ? 100.0 : accs.reduce((a, b) => a + b) / accs.length;
      final stars = (misses == 0 ? (mean <= p.tol / 2 ? 3 : 2) : (misses == 1 ? 2 : 1)) - hints;
      final score = accs.fold<double>(0, (s, a) => s + 100 - a).round() * 3 - seconds;
      later(800, () => widget.play.win(score: score, stars: stars, seconds: seconds, hints: hints, extra: {'notes_held': accs.length}));
      return;
    }
    later(700, _ref);
  }

  // ------------------------------------------------ kaydırıcıyla oynama (mikrofonsuz)

  double get sliderMidi => base + slider;

  void _hearSlider() {
    final m = sliderMidi;
    final key = (m * 20).round();
    synth.play('tt_$key', () => Synth.note(440.0 * math.pow(2, (key / 20 - 69) / 12).toDouble(), 0.9, release: 0.25));
  }

  void _confirmSlider() {
    if (ended) return;
    final c = pitchCents(sliderMidi, target, anyOctave: p.anyOctave);
    if (c.abs() <= tol) {
      devs
        ..clear()
        ..add(c.abs());
      _lock();
    } else {
      setState(() {
        note = mt(lang, c > 0 ? 'tooHigh' : 'tooLow');
        noteColor = MColors.ok;
      });
      // Yanlış onay: can gider, aynı seste kalınır.
      _loseLife();
    }
  }

  Future<void> _hint() async {
    if (ended || !started) return;
    if (await widget.play.ctx.requestHint()) {
      setState(() {
        hints++;
        tolBoost = 1.6;
        left = p.timeS.toDouble();
      });
      _ref();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!started) {
      return MScreen(
        bar: MBar(play: widget.play, status: mt(lang, 'ttTitle')),
        board: Center(
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              StartCard(
                title: mt(lang, 'ttTitle'),
                subtitle: '${mt(lang, 'ttHelp')}${p.anyOctave ? '\n${mt(lang, 'anyOctave')}' : ''}',
                button: mt(lang, 'ttSing'),
                onStart: () => _begin(withMic: true),
                icon: Icons.mic_rounded,
              ),
              Wrap(spacing: 8, alignment: WrapAlignment.center, children: [
                MChip(
                  selected: !high,
                  onTap: () {
                    setState(() => high = false);
                    unawaited(_savePrefs());
                  },
                  child: Text(mt(lang, 'voiceLow')),
                ),
                MChip(
                  selected: high,
                  onTap: () {
                    setState(() => high = true);
                    unawaited(_savePrefs());
                  },
                  child: Text(mt(lang, 'voiceHigh')),
                ),
              ]),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: () => _begin(withMic: false),
                icon: const Icon(Icons.linear_scale, color: Colors.white70),
                label: Text(mt(lang, 'ttSlider'), style: const TextStyle(color: Colors.white70)),
              ),
            ]),
          ),
        ),
      );
    }
    final m = useMic ? det : sliderMidi;
    final cents = m == null ? null : pitchCents(m, target, anyOctave: p.anyOctave);
    return MScreen(
      flash: useMic ? clampD(held / p.holdMs, 0, 1) * 0.5 : 0,
      flashColor: MColors.good,
      bar: MBar(
        play: widget.play,
        left: '${i + 1}/${p.offs.length}',
        status: '${'♥' * lives}  ${left.ceil()}s',
        onHint: _hint,
      ),
      top: Text(note.isEmpty ? mt(lang, useMic ? 'ttHelp' : 'ttSliderHelp') : note,
          textAlign: TextAlign.center, style: TextStyle(color: note.isEmpty ? Colors.white : noteColor, fontSize: 15, fontWeight: note.isEmpty ? FontWeight.w400 : FontWeight.w800)),
      board: Column(children: [
        Text(noteName(target, lang, octave: !p.anyOctave),
            style: const TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.w900)),
        Text(m == null ? '—' : '${noteName(m.round(), lang, octave: !p.anyOctave)}  ${cents == null ? '' : '${cents >= 0 ? '+' : ''}${cents.round()}'}',
            style: TextStyle(color: cents != null && cents.abs() <= tol ? MColors.good : Colors.white70, fontSize: 18, fontWeight: FontWeight.w700)),
        Expanded(
          child: Semantics(
            label: mt(lang, 'ttTitle'),
            value: cents == null ? '' : '${cents.round()}',
            child: TapCanvas(
              w: 360,
              h: 220,
              paint: (c) => _paintMeter(c, cents, tol, useMic ? held / p.holdMs : 0, level, left / p.timeS),
            ),
          ),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var k = 0; k < p.offs.length; k++)
            Container(
              width: 12,
              height: 12,
              margin: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: k < res.length ? (res[k] ? MColors.good : MColors.bad) : (k == i ? MColors.ok : MColors.soft),
              ),
            ),
        ]),
        if (!useMic)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              const Icon(Icons.south, color: Colors.white54),
              Expanded(
                child: Slider(
                  value: slider,
                  min: -1,
                  max: 13,
                  divisions: 280,
                  onChanged: ended ? null : (v) => setState(() => slider = v),
                  onChangeEnd: (_) => _hearSlider(),
                ),
              ),
              const Icon(Icons.north, color: Colors.white54),
            ]),
          ),
      ]),
      bottom: Row(children: [
        Expanded(child: OutlinedButton.icon(onPressed: _ref, icon: const Icon(Icons.headphones), label: FittedBox(child: Text(mt(lang, 'refTone'))))),
        if (!useMic) ...[
          const SizedBox(width: 6),
          Expanded(child: OutlinedButton.icon(onPressed: _hearSlider, icon: const Icon(Icons.graphic_eq), label: FittedBox(child: Text(mt(lang, 'listen'))))),
          const SizedBox(width: 6),
          Expanded(child: FilledButton.icon(onPressed: ended ? null : _confirmSlider, icon: const Icon(Icons.check), label: FittedBox(child: Text(mt(lang, 'confirm'))))),
        ],
      ]),
    );
  }
}

/// Sapma göstergesi: -100..+100 sent yayı, yeşil kabul bölgesi, ibre,
/// tutma halkası, ses düzeyi ve kalan süre.
void _paintMeter(Canvas c, double? cents, double tol, double hold, double level, double timeLeft) {
  const cx = 180.0, cy = 200.0, r = 160.0;
  double ang(double v) => math.pi + (clampD(v, -100, 100) + 100) / 200 * math.pi;
  final arc = Rect.fromCircle(center: const Offset(cx, cy), radius: r);
  c.drawArc(arc, math.pi, math.pi, false, stroke(MColors.soft, 18));
  c.drawArc(arc, ang(-tol), ang(tol) - ang(-tol), false, stroke(MColors.good, 18));
  for (var v = -100; v <= 100; v += 25) {
    final a = ang(v.toDouble());
    final o = Offset(cx + math.cos(a) * (r - 18), cy + math.sin(a) * (r - 18));
    final i2 = Offset(cx + math.cos(a) * (r - (v == 0 ? 36 : 28)), cy + math.sin(a) * (r - (v == 0 ? 36 : 28)));
    c.drawLine(o, i2, stroke(Colors.white54, v == 0 ? 3 : 1.5));
  }
  drawLabel(c, '♭', Offset(cx - r + 10, cy - 30), 26, Colors.white70);
  drawLabel(c, '♯', Offset(cx + r - 10, cy - 30), 26, Colors.white70);
  // Tutma halkası.
  c.drawCircle(const Offset(cx, cy), 34, fill(MColors.stage));
  c.drawArc(Rect.fromCircle(center: const Offset(cx, cy), radius: 30), -math.pi / 2, 2 * math.pi * clampD(hold, 0, 1), false, stroke(MColors.good, 7));
  // Ses düzeyi.
  c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx - 50, cy + 8, 100 * clampD(level, 0, 1), 6), const Radius.circular(3)), fill(MColors.accent));
  // Kalan süre.
  c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(20, 12, 320 * clampD(timeLeft, 0, 1), 6), const Radius.circular(3)), fill(timeLeft < 0.3 ? MColors.bad : MColors.ok));
  final v = cents;
  if (v != null) {
    final a = ang(v);
    final ok = v.abs() <= tol;
    c.drawLine(const Offset(cx, cy), Offset(cx + math.cos(a) * (r - 6), cy + math.sin(a) * (r - 6)), stroke(ok ? MColors.good : MColors.ok, 5));
  }
  c.drawCircle(const Offset(cx, cy), 7, fill(Colors.white));
}
