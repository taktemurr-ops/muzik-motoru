import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';
import 'package:studio_core/core/missions.dart';

import '../audio.dart';
import '../core.dart';
import '../data/tunes.dart';
import '../rhythm.dart';
import '../texts.dart';
import '../theory.dart';

/// Nota Karoları: dört şeritte inen karolara vaktinde dokun, ezgiyi sen çal.
class TTile {
  final double beat;
  final double dur;
  final int midi;
  final int lane;
  final bool hold;
  const TTile(this.beat, this.dur, this.midi, this.lane, {this.hold = false});
}

class TilesPuzzle extends MPuzzle {
  final String title;
  final String author;
  final int year;
  final int bpm;
  final int beatsPerBar;
  final List<TTile> tiles;
  final List<MNote> bass;
  const TilesPuzzle(this.title, this.author, this.year, this.bpm, this.beatsPerBar, this.tiles, this.bass);

  double get beatMs => 60000 / bpm;

  @override
  Set<String> get samples => {for (final t in tiles) pianoSample(t.midi), for (final b in bass) pianoSample(b.midi), 'mt_hi', 'mt_lo'};
}

const int kLanes = 4;

/// Notaları şeritlere dağıtır: ezgi yükselince sağa, inince sola.
List<TTile> laneTiles(List<MNote> m, SeededRandom r, {required bool holds, required double holdMin}) {
  final out = <TTile>[];
  var lane = r.nextInt(kLanes);
  for (var i = 0; i < m.length; i++) {
    final n = m[i];
    if (i > 0) {
      final p = m[i - 1];
      final dir = n.midi.compareTo(p.midi);
      if (dir == 0) {
        // Aynı nota: aynı şeritte kalmasın, yanına geç (hızlı çift dokunuşu önler).
        lane = lane == 0 ? 1 : (lane == kLanes - 1 ? kLanes - 2 : lane + (r.chance(0.5) ? 1 : -1));
      } else {
        final stepSize = (n.midi - p.midi).abs() >= 5 ? 2 : 1;
        var nl = lane + dir * stepSize;
        if (nl < 0 || nl >= kLanes) {
          final opts = [for (var k = 0; k < kLanes; k++) if (k != lane) k];
          nl = r.pick(opts);
        }
        lane = nl;
      }
    }
    out.add(TTile(n.beat, n.dur, n.midi, lane, hold: holds && n.dur >= holdMin));
  }
  return out;
}

class TilesKind extends MuzikKind {
  @override
  String get id => 'nota-karolari';
  const TilesKind();

  @override
  MPuzzle? make(int d, SeededRandom r, {bool short = false}) {
    String title = '', author = '';
    var year = 0, bpm = 0, bpb = 4;
    List<MNote> mel;
    final pd = r.chance(d <= 2 ? 0.6 : 0.35);
    if (pd) {
      final easy = d <= 3;
      final pool = [
        for (final t in kPdTunes)
          if (!easy || parseTune(t.notes).every((n) => n.dur >= 0.5)) t,
      ];
      final t = r.pick(pool);
      title = t.title;
      author = t.author;
      year = t.year;
      bpb = t.beatsPerBar;
      bpm = (t.bpm * (0.78 + 0.035 * d)).round();
      mel = fitRange(parseTune(t.notes), 60, 84);
    } else {
      final scales = d <= 3 ? const [kMajor, kPentaMajor] : (d <= 6 ? const [kMajor, kMinor, kPentaMinor, kDorian] : kScales);
      final sc = r.pick(scales);
      bpb = d >= 5 && r.chance(0.3) ? 3 : 4;
      final bars = short ? 4 : (d <= 3 ? 4 : (d <= 7 ? 8 : 12));
      bpm = 78 + d * 6 + r.range(-6, 6);
      mel = genMelody(r, rootPc: r.nextInt(12), scale: sc, bars: bars, beatsPerBar: bpb, level: d, lo: 60, hi: 81);
      if (!melodyOk(mel, lo: 60, hi: 84)) return null;
    }
    if (short && mel.length > 18) mel = mel.sublist(0, 18);
    var tiles = laneTiles(mel, r, holds: d >= 3, holdMin: 2);
    // Çift karo: zor bölümlerde ölçü başlarında bir üçlü aşağıdan eşlik.
    if (d >= 7) {
      final extra = <TTile>[];
      for (final t in tiles) {
        if ((t.beat % bpb).abs() < 1e-6 && r.chance(0.5) && t.midi - 4 >= 48) {
          final opts = [for (var k = 0; k < kLanes; k++) if ((k - t.lane).abs() >= 2) k];
          if (opts.isEmpty) continue;
          extra.add(TTile(t.beat, t.dur, t.midi - (r.chance(0.5) ? 3 : 4), r.pick(opts)));
        }
      }
      tiles = [...tiles, ...extra]..sort((a, b) => a.beat.compareTo(b.beat));
      tiles = _dropConflicts(tiles, 60000 / bpm);
    }
    final bass = <MNote>[];
    if (d >= 2) {
      final barsN = ((mel.last.beat + mel.last.dur) / bpb).ceil();
      for (var b = 0; b < barsN; b++) {
        final at = b * bpb.toDouble();
        final n = mel.lastWhere((x) => x.beat <= at + 1e-6, orElse: () => mel.first);
        var m = 36 + n.midi % 12;
        while (m < kLowMidi) {
          m += 12;
        }
        bass.add(MNote(at, bpb.toDouble(), m));
      }
    }
    return TilesPuzzle(title, author, year, bpm, bpb, tiles, bass);
  }

  List<TTile> _dropConflicts(List<TTile> t, double beatMs) {
    final out = <TTile>[];
    for (final x in t) {
      final clash = out.any((o) => o.lane == x.lane && (x.beat - o.beat).abs() * beatMs < 160 + (o.hold ? o.dur * beatMs : 0));
      if (!clash) out.add(x);
    }
    return out;
  }

  @override
  bool check(MPuzzle p) {
    if (p is! TilesPuzzle) return false;
    if (p.tiles.length < 6 || p.bpm < 40 || p.bpm > 200) return false;
    final bm = p.beatMs;
    final last = <int, TTile>{};
    for (var i = 0; i < p.tiles.length; i++) {
      final t = p.tiles[i];
      if (t.lane < 0 || t.lane >= kLanes || t.midi < kLowMidi || t.midi > kHighMidi || t.dur <= 0) return false;
      if (i > 0 && t.beat < p.tiles[i - 1].beat - 1e-6) return false;
      final same = p.tiles.where((o) => (o.beat - t.beat).abs() < 1e-6).length;
      if (same > 2) return false;
      final pl = last[t.lane];
      if (pl != null) {
        final freeAt = pl.beat + (pl.hold ? pl.dur : 0);
        if ((t.beat - freeAt) * bm < 120) return false;
      }
      last[t.lane] = t;
    }
    final total = (p.tiles.last.beat + p.tiles.last.dur) * bm;
    return total < 150000;
  }

  @override
  List<GameStat> get stats => const [
        GameStat('rounds_won', 'Çalınan parça', 'Pieces played', scale: 10),
        GameStat('perfect', 'Kusursuz parça', 'Perfect pieces', scale: 10),
        GameStat('notes_hit', 'Çalınan nota', 'Notes played', scale: 200),
      ];

  @override
  List<MissionTemplate> get missions => const [
        MissionTemplate('win', 'rounds_won', [3, 10, 25]),
        MissionTemplate('notes', 'notes_hit', [100, 400, 1200]),
        MissionTemplate('perfect', 'perfect', [1, 5, 15]),
      ];

  @override
  Widget build(MuzikPlay play) => _TilesView(play: play);
}

class _TilesView extends StatefulWidget {
  final MuzikPlay play;
  const _TilesView({required this.play});
  @override
  State<_TilesView> createState() => _TilesViewState();
}

class _TilesViewState extends State<_TilesView> with SingleTickerProviderStateMixin, SongClock<_TilesView>, Clock<_TilesView> {
  late final TilesPuzzle p = widget.play.puzzle as TilesPuzzle;
  static const double w = 400, h = 700, hitY = 600;
  bool started = false, practice = false, over = false;
  int lives = 3, hints = 0;
  final Tally tally = Tally();
  late List<int> state = List.filled(p.tiles.length, 0); // 0 bekliyor, 1 vuruldu, 2 kaçtı, 3 basılı
  final List<Burst> bursts = [];
  int nextBass = 0, lastBeat = -99;
  double flash = 0;
  Color flashColor = Colors.white;
  int holding = -1;

  double get speed => practice ? 0.78 : 1.0;
  double get beatMs => p.beatMs / speed;
  double tileMs(TTile t) => t.beat * beatMs;
  double get lookMs => (2100 - widget.play.d * 90) / (practice ? 0.85 : 1.0);
  JudgeWindow get win => JudgeWindow.forLevel(widget.play.d, practice: practice);
  double get endMs => (p.tiles.last.beat + p.tiles.last.dur) * beatMs + 700;

  void _start() {
    setState(() {
      started = true;
      over = false;
      lives = 3 + hints;
      state = List.filled(p.tiles.length, 0);
      tally
        ..perfect = 0
        ..great = 0
        ..good = 0
        ..miss = 0
        ..combo = 0
        ..best = 0
        ..score = 0;
      nextBass = 0;
      lastBeat = -99;
      holding = -1;
    });
    startClock();
    startSong(leadMs: beatMs * 4);
  }

  @override
  void onFrame() {
    if (over) return;
    final t = effMs;
    // Sayım ve vuruş ışığı.
    final bi = (t / beatMs).floor();
    if (bi != lastBeat) {
      lastBeat = bi;
      final down = ((bi % p.beatsPerBar) + p.beatsPerBar) % p.beatsPerBar == 0;
      if (t < 0) {
        widget.play.sample(down ? 'mt_hi' : 'mt_lo');
        Haptic.beat(strong: down);
      }
      flash = down ? 0.55 : 0.25;
      flashColor = Colors.white;
    }
    flash *= 0.9;
    // Eşlik (bas) — gerçek şarkı zamanına göre tetiklenir.
    while (nextBass < p.bass.length && p.bass[nextBass].beat * beatMs <= songMs) {
      widget.play.note(p.bass[nextBass].midi, volume: 0.45);
      nextBass++;
    }
    // Kaçan karolar.
    for (var i = 0; i < p.tiles.length; i++) {
      if (state[i] != 0) continue;
      final tm = tileMs(p.tiles[i]);
      if (t - tm > win.good) {
        state[i] = 2;
        _miss(p.tiles[i].lane);
      } else if (tm > t + lookMs) {
        break;
      }
    }
    // Basılı tutulan karo bitti mi?
    if (holding >= 0) {
      final ht = p.tiles[holding];
      if (t >= (ht.beat + ht.dur) * beatMs - beatMs * 0.25) {
        state[holding] = 1;
        tally.score += 50;
        holding = -1;
      }
    }
    pruneBursts(bursts, t);
    if (t > endMs) _finish();
  }

  void _miss(int lane) {
    tally.add(Judge.miss);
    bursts.add(Burst(Offset(lane * 100 + 50, hitY), effMs, MColors.bad, judgeText(widget.play.lang, Judge.miss)));
    flash = 1;
    flashColor = MColors.bad;
    Haptic.miss();
    if (!practice) {
      lives--;
      widget.play.sfx(Sfx.error);
      if (lives <= 0) {
        over = true;
        stopSong();
        later(700, () => widget.play.lose(score: tally.score, seconds: seconds, headline: '${(tally.accuracy * 100).round()}%'));
      }
    }
    setState(() {});
  }

  void _down(Offset pos) {
    if (!started || over || !running) return;
    final lane = clampI((pos.dx / 100).floor(), 0, kLanes - 1);
    final t = effMs;
    var best = -1;
    var be = 1e9;
    for (var i = 0; i < p.tiles.length; i++) {
      if (state[i] != 0 || p.tiles[i].lane != lane) continue;
      final e = t - tileMs(p.tiles[i]);
      if (e.abs() < be) {
        be = e.abs();
        best = i;
      }
      if (tileMs(p.tiles[i]) > t + win.good) break;
    }
    if (best < 0 || be > win.good) {
      // Yakında başka şeritte karo varken yanlış şeride dokunmak hatadır.
      final near = [for (var i = 0; i < p.tiles.length; i++) if (state[i] == 0 && (tileMs(p.tiles[i]) - t).abs() < win.great) i];
      if (near.isNotEmpty && !practice) {
        state[near.first] = 2;
        _miss(lane);
      }
      return;
    }
    final tile = p.tiles[best];
    final j = win.judge(t - tileMs(tile));
    tally.add(j);
    widget.play.note(tile.midi);
    Haptic.hit();
    bursts.add(Burst(Offset(lane * 100 + 50, hitY), t, judgeColor(j), judgeText(widget.play.lang, j)));
    if (tile.hold) {
      state[best] = 3;
      holding = best;
    } else {
      state[best] = 1;
    }
    setState(() {});
  }

  void _up(Offset pos) {
    if (holding < 0) return;
    // Erken bırakılan uzun karo: yarım puan, can gitmez.
    state[holding] = 1;
    holding = -1;
  }

  void _finish() {
    if (over) return;
    over = true;
    stopSong();
    final stars = starsByAccuracy(tally.accuracy, practice: practice, hints: hints);
    later(400, () {
      if (lives > 0 || practice) {
        widget.play.win(score: tally.score, stars: stars, seconds: seconds, hints: hints, extra: {'notes_hit': tally.hits});
      }
    });
  }

  Future<void> _hint() async {
    if (started) return;
    if (await widget.play.ctx.requestHint()) setState(() => hints++);
  }

  void _paint(Canvas c) {
    final t = effMs;
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, w, h), const Radius.circular(18)), fill(MColors.stage));
    for (var l = 0; l < kLanes; l++) {
      final col = MColors.lanes[l];
      c.drawRect(Rect.fromLTWH(l * 100.0 + 2, 0, 96, h), fill(col.withValues(alpha: 0.06)));
      if (l > 0) c.drawLine(Offset(l * 100.0, 0), Offset(l * 100.0, h), stroke(Colors.white10, 1));
    }
    // Ölçü çizgileri.
    if (started) {
      final first = (t / beatMs).floor();
      for (var b = first; b < first + 12; b++) {
        final y = hitY - (b * beatMs - t) * hitY / lookMs;
        if (y < 0) break;
        final down = ((b % p.beatsPerBar) + p.beatsPerBar) % p.beatsPerBar == 0;
        c.drawLine(Offset(0, y), Offset(w, y), stroke(Colors.white.withValues(alpha: down ? 0.16 : 0.05), down ? 2 : 1));
      }
    }
    c.drawRect(const Rect.fromLTWH(0, hitY - 4, w, 8), fill(Colors.white.withValues(alpha: 0.35 + 0.4 * flash)));
    final names = practice || widget.play.d <= 3;
    for (var i = 0; i < p.tiles.length; i++) {
      final tile = p.tiles[i];
      if (state[i] == 1 || state[i] == 2) continue;
      final tm = tileMs(tile);
      if (tm > t + lookMs) break;
      final y = hitY - (tm - t) * hitY / lookMs;
      final len = tile.hold ? tile.dur * beatMs * hitY / lookMs : 70.0;
      final top = y - len;
      var col = MColors.lanes[tile.lane];
      if (state[i] == 3) col = Color.lerp(col, Colors.white, 0.4)!;
      final r = RRect.fromRectAndRadius(Rect.fromLTRB(tile.lane * 100.0 + 8, top, tile.lane * 100.0 + 92, y), const Radius.circular(12));
      c.drawRRect(r.shift(const Offset(0, 4)), fill(Colors.black26));
      c.drawRRect(r, fill(col));
      if (tile.hold) c.drawLine(Offset(tile.lane * 100.0 + 50, top + 12), Offset(tile.lane * 100.0 + 50, y - 12), stroke(Colors.white54, 6));
      if (names) drawLabel(c, noteName(tile.midi, widget.play.lang), Offset(tile.lane * 100.0 + 50, y - 22), 18, MColors.ink);
    }
    paintBursts(c, bursts, t);
    if (started) paintCountIn(c, t, beatMs, const Offset(w / 2, h / 2 - 60));
    // İlerleme.
    final prog = clampD(t / (endMs - 700), 0, 1);
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(10, h - 22, (w - 20) * prog, 8), const Radius.circular(4)), fill(MColors.ok));
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.play.lang;
    final sub = p.title.isEmpty
        ? '${mt(lang, 'originalTune')} · ${p.bpm} BPM'
        : '${p.author.isEmpty ? mt(lang, 'traditional') : p.author} · ${p.year} · ${p.bpm} BPM';
    return MScreen(
      flash: flash,
      flashColor: flashColor,
      bar: MBar(
        play: widget.play,
        left: '${'♥' * clampI(lives, 0, 9)}${practice ? ' ∞' : ''}',
        status: '${mt(lang, 'score')} ${tally.score} · ${mt(lang, 'combo')} ${tally.combo}',
        practice: started ? null : practice,
        onPractice: (v) => setState(() => practice = v),
        onHint: started ? null : _hint,
        tools: !started,
      ),
      board: started
          ? ValueListenableBuilder<int>(
              valueListenable: frame,
              builder: (_, __, ___) => TapCanvas(w: w, h: h, paint: _paint, onDown: _down, onUp: _up, semantics: mt(lang, 'tilesHelp')),
            )
          : StartCard(
              title: p.title.isEmpty ? mt(lang, 'originalTune') : p.title,
              subtitle: '$sub${hints > 0 ? '\n+$hints ♥' : ''}',
              button: mt(lang, 'start'),
              onStart: _start,
              icon: Icons.piano,
            ),
    );
  }
}

/// Testler için: bir bölümün süresini hesaplar (ms).
double tilesLengthMs(TilesPuzzle p) => (p.tiles.last.beat + p.tiles.last.dur) * p.beatMs;

/// Ezgideki en kısa aralık (ms) – zorluk denetimi için.
double tilesMinGapMs(TilesPuzzle p) {
  var g = double.infinity;
  for (var i = 1; i < p.tiles.length; i++) {
    final d = (p.tiles[i].beat - p.tiles[i - 1].beat) * p.beatMs;
    if (d > 0) g = math.min(g, d);
  }
  return g;
}
