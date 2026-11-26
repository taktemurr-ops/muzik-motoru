import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'audio.dart';
import 'core.dart';
import 'texts.dart';
import 'theory.dart';

/// Ölçü (vuruş vurguları: 2 güçlü, 1 orta, 0 zayıf). Aksak ölçüler dahil.
class MeterDef {
  final String label;
  final List<int> accents;
  const MeterDef(this.label, this.accents);
}

const List<MeterDef> kMeters = [
  MeterDef('2/4', [2, 0]),
  MeterDef('3/4', [2, 0, 0]),
  MeterDef('4/4', [2, 0, 1, 0]),
  MeterDef('5/8', [2, 0, 1, 0, 0]),
  MeterDef('6/8', [2, 0, 0, 1, 0, 0]),
  MeterDef('7/8', [2, 0, 1, 0, 1, 0, 0]),
  MeterDef('9/8', [2, 0, 1, 0, 1, 0, 1, 0, 0]),
  MeterDef('10/8', [2, 0, 0, 1, 0, 1, 0, 1, 0, 0]),
];

Future<void> showMetronome(BuildContext context, MuzikPlay play) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(child: _MetronomeSheet(play: play)),
    );

Future<void> showFreePlay(BuildContext context, MuzikPlay play) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(child: FractionallySizedBox(heightFactor: 0.86, child: FreePlayPanel(play: play))),
    );

Future<void> showMusicSettings(BuildContext context, MuzikPlay play) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(child: _SettingsSheet(play: play)),
    );

TextStyle get _white => const TextStyle(color: Colors.white);

// ---------------------------------------------------------------- metronom

class _MetronomeSheet extends StatefulWidget {
  final MuzikPlay play;
  const _MetronomeSheet({required this.play});
  @override
  State<_MetronomeSheet> createState() => _MetronomeSheetState();
}

class _MetronomeSheetState extends State<_MetronomeSheet> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  int bpm = MusicPrefs.metroBpm;
  int meter = clampI(MusicPrefs.metroMeter, 0, kMeters.length - 1);
  bool running = false;
  int pulse = -1;
  double nextMs = 0;
  double flash = 0;
  final List<int> taps = [];

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    unawaited(widget.play.voice.preload(const ['mt_hi', 'mt_mid', 'mt_lo']));
  }

  void _onTick(Duration el) {
    final ms = el.inMicroseconds / 1000.0;
    var changed = false;
    while (ms >= nextMs) {
      pulse = (pulse + 1) % kMeters[meter].accents.length;
      final a = kMeters[meter].accents[pulse];
      widget.play.sample(a == 2 ? 'mt_hi' : (a == 1 ? 'mt_mid' : 'mt_lo'));
      Haptic.beat(strong: a == 2);
      flash = a == 2 ? 1 : 0.55;
      nextMs += 60000 / bpm;
      changed = true;
    }
    final f = flash * 0.9;
    if (changed || (flash - f).abs() > 0.01) {
      setState(() => flash = f < 0.02 ? 0 : f);
    }
  }

  void _toggle() {
    setState(() {
      running = !running;
      if (running) {
        pulse = -1;
        nextMs = 0;
        _ticker.start();
      } else {
        _ticker.stop();
        flash = 0;
      }
    });
  }

  void _setBpm(int v) {
    setState(() => bpm = clampI(v, 30, 240));
    MusicPrefs.metroBpm = bpm;
    unawaited(MusicPrefs.save());
    if (running) {
      _ticker.stop();
      pulse = -1;
      nextMs = 0;
      _ticker.start();
    }
  }

  void _tap() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (taps.isNotEmpty && now - taps.last > 2500) taps.clear();
    taps.add(now);
    if (taps.length > 6) taps.removeAt(0);
    if (taps.length >= 3) {
      final span = (taps.last - taps.first) / (taps.length - 1);
      if (span > 0) _setBpm((60000 / span).round());
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.play.lang;
    final acc = kMeters[meter].accents;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(mt(lang, 'metronome'), style: _white.copyWith(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        AnimatedContainer(
          duration: const Duration(milliseconds: 60),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Color.lerp(Colors.white.withValues(alpha: 0.08), MColors.ok, MusicPrefs.flash ? flash * 0.6 : 0),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(onPressed: () => _setBpm(bpm - 1), icon: const Icon(Icons.remove, color: Colors.white)),
              Text('$bpm', style: _white.copyWith(fontSize: 44, fontWeight: FontWeight.w900)),
              Text(' BPM', style: _white.copyWith(color: Colors.white60)),
              IconButton(onPressed: () => _setBpm(bpm + 1), icon: const Icon(Icons.add, color: Colors.white)),
            ]),
            Wrap(alignment: WrapAlignment.center, spacing: 6, children: [
              for (var i = 0; i < acc.length; i++)
                Container(
                  width: acc[i] == 2 ? 22 : 16,
                  height: acc[i] == 2 ? 22 : 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == pulse && running ? (acc[i] == 2 ? MColors.bad : MColors.ok) : Colors.white24,
                  ),
                ),
            ]),
          ]),
        ),
        Slider(value: bpm.toDouble(), min: 30, max: 240, onChanged: (v) => _setBpm(v.round())),
        Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [
          for (var i = 0; i < kMeters.length; i++)
            ChoiceChip(
              label: Text(kMeters[i].label),
              selected: i == meter,
              onSelected: (_) {
                setState(() {
                  meter = i;
                  pulse = -1;
                });
                MusicPrefs.metroMeter = i;
                unawaited(MusicPrefs.save());
              },
            ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: OutlinedButton.icon(onPressed: _tap, icon: const Icon(Icons.touch_app), label: Text(mt(lang, 'tapTempo')))),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              onPressed: _toggle,
              icon: Icon(running ? Icons.stop : Icons.play_arrow),
              label: Text(running ? mt(lang, 'stop') : mt(lang, 'start')),
            ),
          ),
        ]),
      ]),
    );
  }
}

// ---------------------------------------------------------------- serbest çalgı

/// Davul ve darbuka pedleri (örnek adı, metin anahtarı).
const List<(String, String)> kPads = [
  ('dr_kick', 'kick'),
  ('dr_snare', 'snare'),
  ('dr_hat', 'hihat'),
  ('dr_open', 'openHat'),
  ('dr_tom1', 'tomHigh'),
  ('dr_tom2', 'tomLow'),
  ('dr_crash', 'crash'),
  ('dr_clap', 'clap'),
  ('dr_rim', 'rim'),
  ('dr_dum', 'dum'),
  ('dr_tek', 'tek'),
  ('dr_ka', 'ka'),
];

/// Serbest çalgı: piyano, davul/darbuka, gitar akorları; kayıt ve tekrar çalma.
class FreePlayPanel extends StatefulWidget {
  final MuzikPlay play;
  const FreePlayPanel({super.key, required this.play});
  @override
  State<FreePlayPanel> createState() => _FreePlayPanelState();
}

class _FreePlayPanelState extends State<FreePlayPanel> {
  int tab = 0;
  int lo = 60;
  int root = 0;
  bool recording = false;
  bool playing = false;
  int recStart = 0;
  final List<(int, String)> rec = [];
  final List<Timer> timers = [];
  final Map<int, Color> lit = {};
  String? litPad;

  @override
  void initState() {
    super.initState();
    unawaited(widget.play.voice.preload([for (final p in kPads) p.$1]));
  }

  void _sound(String name) {
    widget.play.sample(name);
    Haptic.hit();
    if (recording) rec.add((DateTime.now().millisecondsSinceEpoch - recStart, name));
  }

  void _key(int m) {
    _sound(pianoSample(m));
    setState(() => lit[m] = MColors.lanes[m % MColors.lanes.length]);
    timers.add(Timer(const Duration(milliseconds: 180), () {
      if (mounted) setState(() => lit.remove(m));
    }));
  }

  void _pad(String s) {
    _sound(s);
    setState(() => litPad = s);
    timers.add(Timer(const Duration(milliseconds: 120), () {
      if (mounted) setState(() => litPad = null);
    }));
  }

  void _rec() {
    setState(() {
      if (recording) {
        recording = false;
      } else {
        rec.clear();
        recording = true;
        recStart = DateTime.now().millisecondsSinceEpoch;
      }
    });
  }

  void _playBack() {
    for (final t in timers) {
      t.cancel();
    }
    timers.clear();
    lit.clear();
    litPad = null;
    if (playing || rec.isEmpty) {
      setState(() => playing = false);
      return;
    }
    setState(() {
      playing = true;
      recording = false;
    });
    for (final e in rec) {
      timers.add(Timer(Duration(milliseconds: e.$1), () {
        if (!mounted) return;
        widget.play.sample(e.$2);
        Haptic.beat();
      }));
    }
    timers.add(Timer(Duration(milliseconds: rec.last.$1 + 600), () {
      if (mounted) setState(() => playing = false);
    }));
  }

  @override
  void dispose() {
    for (final t in timers) {
      t.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.play.lang;
    Widget body;
    if (tab == 0) {
      body = Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(onPressed: lo > 48 ? () => setState(() => lo -= 12) : null, icon: const Icon(Icons.chevron_left, color: Colors.white)),
          Text('${noteName(lo, lang)}${lo ~/ 12 - 1} – ${noteName(lo + 24, lang)}${(lo + 24) ~/ 12 - 1}', style: _white),
          IconButton(onPressed: lo < 60 ? () => setState(() => lo += 12) : null, icon: const Icon(Icons.chevron_right, color: Colors.white)),
        ]),
        Expanded(child: PianoKeys(lo: lo, hi: lo + 24, onKey: _key, lit: lit, lang: lang)),
      ]);
    } else if (tab == 1) {
      body = GridView.count(
        crossAxisCount: 4,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        children: [
          for (var i = 0; i < kPads.length; i++)
            Listener(
              onPointerDown: (_) => _pad(kPads[i].$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 60),
                decoration: BoxDecoration(
                  color: litPad == kPads[i].$1 ? Colors.white : MColors.lanes[i % MColors.lanes.length],
                  borderRadius: BorderRadius.circular(18),
                ),
                alignment: Alignment.center,
                padding: const EdgeInsets.all(4),
                child: FittedBox(child: Text(mt(lang, kPads[i].$2), style: const TextStyle(color: MColors.ink, fontWeight: FontWeight.w800))),
              ),
            ),
        ],
      );
    } else {
      body = Column(children: [
        Wrap(spacing: 4, runSpacing: 4, alignment: WrapAlignment.center, children: [
          for (var pc = 0; pc < 12; pc++)
            ChoiceChip(label: Text(rootLetter(pc)), selected: pc == root, onSelected: (_) => setState(() => root = pc)),
        ]),
        const SizedBox(height: 10),
        Expanded(
          child: GridView.count(crossAxisCount: 2, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 2.2, children: [
            for (final q in const ['M', 'm', '7', 'm7'])
              MChip(
                color: MColors.lanes[['M', 'm', '7', 'm7'].indexOf(q)],
                onTap: () => _sound(guitarSample(root, q)),
                child: Text(chordSymbol(root, q), style: const TextStyle(fontSize: 24, color: MColors.ink)),
              ),
          ]),
        ),
      ]);
    }
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: SegmentedButton<int>(
              segments: [
                ButtonSegment(value: 0, icon: const Icon(Icons.piano), label: Text(mt(lang, 'piano'))),
                ButtonSegment(value: 1, icon: const Icon(Icons.album), label: Text(mt(lang, 'drums'))),
                ButtonSegment(value: 2, icon: const Icon(Icons.queue_music), label: Text(mt(lang, 'chords'))),
              ],
              selected: {tab},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => tab = s.first),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Expanded(child: body),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _rec,
              icon: Icon(recording ? Icons.stop_circle : Icons.fiber_manual_record, color: MColors.bad),
              label: Text(recording ? mt(lang, 'stop') : mt(lang, 'record')),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              onPressed: rec.isEmpty ? null : _playBack,
              icon: Icon(playing ? Icons.stop : Icons.replay),
              label: Text(playing ? mt(lang, 'stop') : mt(lang, 'playBack')),
            ),
          ),
        ]),
      ]),
    );
  }
}

// ---------------------------------------------------------------- ayarlar ve gecikme ölçümü

class _SettingsSheet extends StatefulWidget {
  final MuzikPlay play;
  const _SettingsSheet({required this.play});
  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  bool calibrating = false;
  final List<int> clicks = [];
  final List<int> offsets = [];
  final List<Timer> timers = [];
  int beat = -1;

  void _calibrate() {
    for (final t in timers) {
      t.cancel();
    }
    timers.clear();
    clicks.clear();
    offsets.clear();
    setState(() {
      calibrating = true;
      beat = -1;
    });
    final t0 = DateTime.now().millisecondsSinceEpoch + 400;
    for (var i = 0; i < 10; i++) {
      final at = t0 + i * 600;
      clicks.add(at);
      timers.add(Timer(Duration(milliseconds: at - DateTime.now().millisecondsSinceEpoch), () {
        if (!mounted) return;
        widget.play.sample(i % 4 == 0 ? 'mt_hi' : 'mt_lo');
        setState(() => beat = i);
      }));
    }
    timers.add(Timer(Duration(milliseconds: t0 + 10 * 600 + 300 - DateTime.now().millisecondsSinceEpoch), _finish));
  }

  void _tapCal() {
    if (!calibrating) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    var best = 1 << 30;
    for (final c in clicks) {
      final d = now - c;
      if (d.abs() < best.abs()) best = d;
    }
    if (best.abs() < 300) offsets.add(best);
  }

  void _finish() {
    if (!mounted) return;
    setState(() {
      calibrating = false;
      if (offsets.length >= 4) {
        offsets.sort();
        final mid = offsets.sublist(1, offsets.length - 1);
        final avg = mid.fold<int>(0, (a, b) => a + b) ~/ mid.length;
        MusicPrefs.latencyMs = clampI(avg, 0, 300);
        unawaited(MusicPrefs.save());
      }
    });
  }

  @override
  void dispose() {
    for (final t in timers) {
      t.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.play.lang;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(mt(lang, 'settings'), textAlign: TextAlign.center, style: _white.copyWith(fontSize: 18, fontWeight: FontWeight.w800)),
        SwitchListTile(
          title: Text(mt(lang, 'flashBeats'), style: _white),
          subtitle: Text(mt(lang, 'flashBeatsInfo'), style: _white.copyWith(color: Colors.white60)),
          value: MusicPrefs.flash,
          onChanged: (v) {
            setState(() => MusicPrefs.flash = v);
            unawaited(MusicPrefs.save());
          },
        ),
        SwitchListTile(
          title: Text(mt(lang, 'vibeBeats'), style: _white),
          value: MusicPrefs.vibe,
          onChanged: (v) {
            setState(() => MusicPrefs.vibe = v);
            unawaited(MusicPrefs.save());
          },
        ),
        const Divider(color: Colors.white24),
        Text('${mt(lang, 'latency')}: ${MusicPrefs.latencyMs} ms', style: _white),
        Slider(
          value: MusicPrefs.latencyMs.toDouble(),
          min: 0,
          max: 300,
          divisions: 30,
          onChanged: (v) {
            setState(() => MusicPrefs.latencyMs = v.round());
            unawaited(MusicPrefs.save());
          },
        ),
        Text(mt(lang, 'latencyInfo'), style: _white.copyWith(color: Colors.white60)),
        const SizedBox(height: 10),
        if (!calibrating)
          OutlinedButton.icon(onPressed: _calibrate, icon: const Icon(Icons.graphic_eq), label: Text(mt(lang, 'calibrate')))
        else
          GestureDetector(
            onTapDown: (_) => _tapCal(),
            child: Container(
              height: 120,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: beat >= 0 ? Color.lerp(MColors.stage, MColors.ok, beat.isEven ? 0.5 : 0.2) : MColors.stage,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text('${mt(lang, 'tapWithClick')}  ${beat + 1}/10', style: _white.copyWith(fontSize: 18)),
            ),
          ),
      ]),
    );
  }
}
