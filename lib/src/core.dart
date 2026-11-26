import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/game_api.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/game_rules.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';

import 'audio.dart';
import 'texts.dart';
import 'theory.dart';
import 'tools.dart';
import 'studio_chrome.dart';

/// Müzik oyunlarından birinin kurulmuş bölümü.
abstract class MPuzzle {
  const MPuzzle();

  /// Bölümde çalınacak ses örnekleri (önceden yüklenir).
  Set<String> get samples => const {};
}

class MLevel {
  final String kind;
  final int d;
  final MPuzzle puzzle;
  const MLevel(this.kind, this.d, this.puzzle);
}

/// Müzik oyunu türü: bölüm üretir, kurallara uygunluğunu denetler, ekranı kurar.
abstract class MuzikKind {
  const MuzikKind();
  String get id;

  /// Zorluk 1..10 için deterministik bölüm (kurulamazsa null).
  /// [short] Günlük Ritim'deki kısa sürümü ister.
  MPuzzle? make(int d, SeededRandom r, {bool short = false});

  bool check(MPuzzle p);

  Widget build(MuzikPlay play);

  List<GameStat> get stats => const [
        GameStat('rounds_won', 'Tamamlanan bölüm', 'Levels completed', scale: 10),
        GameStat('perfect', 'Kusursuz bölüm', 'Perfect levels', scale: 10),
      ];

  List<MissionTemplate> get missions => const [
        MissionTemplate('win', 'rounds_won', [3, 10, 25]),
        MissionTemplate('perfect', 'perfect', [1, 5, 15]),
      ];
}

MPuzzle realizeMuzik(MuzikKind k, int d, int seed, {bool short = false}) {
  for (var dd = d; dd >= 1; dd--) {
    for (var a = 0; a < 30; a++) {
      MPuzzle? p;
      try {
        p = k.make(dd, SeededRandom(mixSeed([seed, a, dd, 4409])), short: short);
      } catch (_) {
        p = null;
      }
      if (p != null && k.check(p)) return p;
    }
  }
  throw StateError('müzik bölümü kurulamadı: ${k.id} $d');
}

class MuzikRules extends GameRules<MLevel> {
  @override
  final String gameId;
  final MuzikKind kind;
  final int levels;
  MuzikRules({required this.gameId, required this.kind, this.levels = 100000});

  @override
  int get levelCount => levels;

  @override
  List<String> get optionalMechanics => const [];

  @override
  List<GameModeId> get modes => const [GameModeId.campaign, GameModeId.daily, GameModeId.weekly, GameModeId.challenge];

  @override
  List<GameStat> get gameStats => kind.stats;

  @override
  List<MissionTemplate> get missionTemplates => kind.missions;

  @override
  MLevel generate(LevelSpec spec) {
    final d = clampI(spec.difficulty, 1, 10);
    return MLevel(kind.id, d, realizeMuzik(kind, d, spec.seed));
  }

  @override
  Validation validate(MLevel puzzle, LevelSpec spec) =>
      puzzle.kind == kind.id && kind.check(puzzle.puzzle) ? const Validation.ok() : const Validation.fail('invalid');
}

/// Bir bölümün oynanışı: ses, titreşim, sonuç bildirme.
class MuzikPlay {
  final PlayContext ctx;
  final MPuzzle puzzle;
  final int d;
  final int seed;
  final MusicVoice voice;

  /// Günlük Ritim'de alt oyunun sonucu ana oyuna aktarılır.
  final void Function(bool won, int stars)? relay;
  const MuzikPlay({required this.ctx, required this.puzzle, required this.d, required this.seed, required this.voice, this.relay});

  String get lang => ctx.lang;

  void sfx(Sfx s) => ctx.sfx(s);

  void note(int midi, {double volume = 1.0}) => voice.play(pianoSample(midi), volume: volume);

  void sample(String name, {double volume = 1.0}) => voice.play(name, volume: volume);

  void win({int score = 0, int stars = 3, int seconds = 0, int hints = 0, Map<String, int> extra = const {}}) {
    final s = clampI(stars, 1, 3);
    final r = relay;
    if (r != null) return r(true, s);
    ctx.finish(RoundResult(
      won: true,
      score: score < 0 ? 0 : score,
      stars: s,
      seconds: seconds,
      hintsUsed: hints,
      gameStats: {'rounds_won': 1, if (s == 3 && hints == 0) 'perfect': 1, ...extra},
    ));
  }

  void lose({int score = 0, int seconds = 0, String? headline}) {
    final r = relay;
    if (r != null) return r(false, 0);
    ctx.finish(RoundResult(won: false, score: score < 0 ? 0 : score, seconds: seconds, headline: headline));
  }
}

/// Müzik oyunlarının ortak sahnesi: ses havuzunu kurar, arka plan müziğini susturur.
class MuzikStage extends StatefulWidget {
  final PlayContext ctx;
  final MuzikRules rules;
  const MuzikStage({super.key, required this.ctx, required this.rules});

  @override
  State<MuzikStage> createState() => _MuzikStageState();
}

class _MuzikStageState extends State<MuzikStage> {
  late final MusicVoice voice = MusicVoice(widget.ctx.sound);
  MusicEnv? env;

  @override
  void initState() {
    super.initState();
    unawaited(MusicPrefs.load());
    final lv = widget.ctx.generated.puzzle as MLevel;
    unawaited(voice.preload(lv.puzzle.samples));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (env == null) {
      final e = MusicEnv.of(context);
      env = e;
      voice.sound = e.sound;
      Haptic.enabled = e.haptics;
      e.pauseMusic();
    }
  }

  @override
  void dispose() {
    env?.resumeMusic();
    voice.dispose();
    super.dispose();
  }

  /// Motorun bütün arayüzü (paneller, pencereler, düğmeler) onaylı koyu
  /// tasarımda; tahta çizimleri kendi renklerini korur.
  @override
  Widget build(BuildContext context) => StudioChrome(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    final lv = widget.ctx.generated.puzzle as MLevel;
    return widget.rules.kind.build(MuzikPlay(ctx: widget.ctx, puzzle: lv.puzzle, d: lv.d, seed: widget.ctx.spec.seed, voice: voice));
  }
}

MuzikRules muzikRules(String gameId, MuzikKind kind) => MuzikRules(gameId: gameId, kind: kind);

// ---------------------------------------------------------------- ortak yardımcılar

class MColors {
  static const night = Color(0xFF1B2233);
  static const stage = Color(0xFF242E44);
  static const paper = Color(0xFFF6F1E7);
  static const ink = Color(0xFF22303F);
  static const good = Color(0xFF5BAA7A);
  static const ok = Color(0xFFE2B04A);
  static const bad = Color(0xFFD5664F);
  static const accent = Color(0xFF6C8FD8);
  static const soft = Color(0xFF3A4660);
  static const line = Color(0xFF55627F);

  /// Şerit ve pedlerde kullanılan sıcak, yumuşak renkler.
  static const List<Color> lanes = [
    Color(0xFFE07A5F),
    Color(0xFF3D9A8B),
    Color(0xFFE9B949),
    Color(0xFF7D6CC9),
    Color(0xFF5B9BD5),
    Color(0xFFC8608F),
    Color(0xFF8BAA4E),
    Color(0xFFB07A4F),
  ];
}

/// Saat ve iptal edilebilen gecikmeler.
mixin Clock<T extends StatefulWidget> on State<T> {
  int seconds = 0;
  bool ended = false;
  Timer? _t;
  final List<Timer> _later = [];

  void startClock() {
    _t?.cancel();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!ended && mounted) setState(() => seconds++);
    });
  }

  void later(int ms, VoidCallback f) {
    _later.add(Timer(Duration(milliseconds: ms), () {
      if (mounted) f();
    }));
  }

  void cancelLater() {
    for (final t in _later) {
      t.cancel();
    }
    _later.clear();
  }

  @override
  void dispose() {
    _t?.cancel();
    cancelLater();
    super.dispose();
  }

  String clock([int? s]) {
    final v = s ?? seconds;
    return '${v ~/ 60}:${(v % 60).toString().padLeft(2, '0')}';
  }
}

/// İsabet oranına göre yıldız.
int starsByAccuracy(double acc, {bool practice = false, int hints = 0}) {
  var s = acc >= 0.95 ? 3 : (acc >= 0.8 ? 2 : 1);
  if (practice) s = 1;
  s -= hints;
  return s < 1 ? 1 : s;
}

/// Üst çubuk: bilgi, durum, araçlar (metronom, serbest çalgı, ayarlar),
/// pratik modu ve ipucu.
class MBar extends StatelessWidget {
  final MuzikPlay play;
  final String left;
  final String status;
  final VoidCallback? onHint;
  final VoidCallback? onReset;
  final bool? practice;
  final ValueChanged<bool>? onPractice;
  final bool tools;
  final List<Widget> extra;
  const MBar({
    super.key,
    required this.play,
    this.left = '',
    this.status = '',
    this.onHint,
    this.onReset,
    this.practice,
    this.onPractice,
    this.tools = true,
    this.extra = const [],
  });

  @override
  Widget build(BuildContext context) {
    final lang = play.lang;
    final pr = practice, op = onPractice;
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      height: 48,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: StudioLook.of(context).accent.withValues(alpha: 0.45), width: 1.2),
      ),
      child: IconTheme(
        data: const IconThemeData(color: Colors.white),
        child: DefaultTextStyle.merge(
          style: const TextStyle(color: Colors.white),
          child: Row(children: [
            if (left.isNotEmpty) Text(left, style: TextStyle(fontWeight: FontWeight.w900, color: StudioLook.of(context).number)),
            const SizedBox(width: 8),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(status, maxLines: 1, style: const TextStyle(fontWeight: FontWeight.w700, color: kStudioSubtle)),
              ),
            ),
            ...extra,
            if (pr != null && op != null)
              IconButton(
                tooltip: mt(lang, 'practice'),
                onPressed: () => op(!pr),
                icon: Icon(pr ? Icons.school : Icons.school_outlined, color: pr ? MColors.ok : Colors.white),
              ),
            if (tools) ...[
              IconButton(tooltip: mt(lang, 'metronome'), onPressed: () => showMetronome(context, play), icon: const Icon(Icons.av_timer)),
              IconButton(tooltip: mt(lang, 'freePlay'), onPressed: () => showFreePlay(context, play), icon: const Icon(Icons.piano)),
              IconButton(tooltip: mt(lang, 'settings'), onPressed: () => showMusicSettings(context, play), icon: const Icon(Icons.tune)),
            ],
            if (onReset != null) IconButton(tooltip: mt(lang, 'reset'), onPressed: onReset, icon: const Icon(Icons.restart_alt)),
            if (onHint != null)
              IconButton(tooltip: mt(lang, 'hint'), onPressed: onHint, icon: const Icon(Icons.lightbulb_rounded, color: StudioLook.gold)),
          ]),
        ),
      ),
    );
  }
}

/// Mantıksal birimlerle çizilen, dokunuşları aynı birimlere çeviren tuval.
class TapCanvas extends StatelessWidget {
  final double w;
  final double h;
  final void Function(Canvas c) paint;
  final void Function(Offset p)? onDown;
  final void Function(Offset p)? onUp;
  final void Function(Offset p)? onTap;
  final String? semantics;
  final Listenable? repaint;
  const TapCanvas({super.key, required this.w, required this.h, required this.paint, this.onDown, this.onUp, this.onTap, this.semantics, this.repaint});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final mw = box.maxWidth.isFinite ? box.maxWidth : 360.0;
      final mh = box.maxHeight.isFinite ? box.maxHeight : 360.0;
      final k = math.min(mw / w, mh / h);
      final size = Size(w * k, h * k);
      Offset lp(Offset o) => o / k;
      final dn = onDown, up = onUp, t = onTap;
      return Center(
        child: Semantics(
          label: semantics,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: dn == null ? null : (e) => dn(lp(e.localPosition)),
            onPointerUp: up == null ? null : (e) => up(lp(e.localPosition)),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: t == null ? null : (e) => t(lp(e.localPosition)),
              child: CustomPaint(size: size, painter: _FnPainter(paint, k, repaint)),
            ),
          ),
        ),
      );
    });
  }
}

class _FnPainter extends CustomPainter {
  final void Function(Canvas c) fn;
  final double k;
  _FnPainter(this.fn, this.k, Listenable? repaint) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(k);
    fn(canvas);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FnPainter old) => true;
}

Paint fill(Color c) => Paint()
  ..color = c
  ..isAntiAlias = true;

Paint stroke(Color c, double w) => Paint()
  ..color = c
  ..style = PaintingStyle.stroke
  ..strokeWidth = w
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..isAntiAlias = true;

void drawLabel(Canvas c, String s, Offset center, double size, Color color, {FontWeight weight = FontWeight.w700}) {
  if (s.isEmpty) return;
  final tp = TextPainter(
    text: TextSpan(text: s, style: TextStyle(fontSize: size, color: color, fontWeight: weight, height: 1.0)),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
  )..layout();
  tp.paint(c, center - Offset(tp.width / 2, tp.height / 2));
}

/// Tek sütun düzeni: çubuk, isteğe bağlı üst bilgi, sahne, alt düğmeler.
class MScreen extends StatelessWidget {
  final Widget bar;
  final Widget board;
  final Widget? top;
  final Widget? bottom;
  final double flash;
  final Color flashColor;
  const MScreen({super.key, required this.bar, required this.board, this.top, this.bottom, this.flash = 0, this.flashColor = Colors.white});

  @override
  Widget build(BuildContext context) {
    final t = top, b = bottom;
    final f = MusicPrefs.flash ? clampD(flash, 0, 1) : 0.0;
    // Onaylı tasarımın degrade zemini (merkezin paleti).
    return Container(
      decoration: BoxDecoration(
        gradient: StudioLook.of(context).backdrop,
        border: f > 0.01 ? Border.all(color: flashColor.withValues(alpha: 0.75 * f), width: 6) : null,
      ),
      child: Column(children: [
        bar,
        if (t != null) Padding(padding: const EdgeInsets.fromLTRB(12, 6, 12, 0), child: t),
        Expanded(child: Padding(padding: const EdgeInsets.all(8), child: board)),
        if (b != null) Padding(padding: const EdgeInsets.fromLTRB(8, 0, 8, 10), child: b),
      ]),
    );
  }
}

/// Yuvarlak köşeli seçim düğmesi.
class MChip extends StatelessWidget {
  final Widget child;
  final bool selected;
  final VoidCallback? onTap;
  final Color? color;
  const MChip({super.key, required this.child, this.selected = false, this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final look = StudioLook.of(context);
    final c = color ?? Color.lerp(look.card, Colors.white, 0.08)!;
    return Material(
      color: selected ? Color.lerp(c, look.accent, 0.35) : c,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: selected ? look.accent : Colors.white24, width: selected ? 2.5 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: DefaultTextStyle.merge(style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700), child: Center(child: child)),
        ),
      ),
    );
  }
}

/// Başlangıç kartı: başlık, alt bilgi ve "Başlat" düğmesi.
class StartCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String button;
  final VoidCallback onStart;
  final IconData icon;
  const StartCard({super.key, required this.title, required this.subtitle, required this.button, required this.onStart, this.icon = Icons.music_note});

  @override
  Widget build(BuildContext context) {
    // Yatay/küçük ekranda ve büyük yazıda kart kaydırılabilir (kesilmez).
    return Center(
      child: SingleChildScrollView(
        child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: StudioLook.of(context).tile,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: StudioLook.of(context).accent.withValues(alpha: 0.55), width: 1.4),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 16, offset: Offset(0, 6))],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          StudioIconBadge(icon, color: StudioLook.of(context).play, size: 56),
          const SizedBox(height: 10),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
          ],
          const SizedBox(height: 16),
          StudioButton(expand: false, icon: Icons.play_arrow, label: button, onPressed: onStart),
        ]),
        ),
      ),
    );
  }
}

/// Piyano klavyesi (dokunmatik). [lo]..[hi] MIDI aralığı; [lit] vurgulanan tuşlar.
class PianoKeys extends StatelessWidget {
  final int lo;
  final int hi;
  final Map<int, Color> lit;
  final void Function(int midi) onKey;
  final bool labels;
  final String lang;
  const PianoKeys({super.key, required this.lo, required this.hi, required this.onKey, this.lit = const {}, this.labels = true, this.lang = 'en'});

  @override
  Widget build(BuildContext context) {
    final whites = [for (var m = lo; m <= hi; m++) if (!isBlack(m)) m];
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth / whites.length;
      final h = box.maxHeight.isFinite ? box.maxHeight : 140.0;
      final children = <Widget>[];
      for (var i = 0; i < whites.length; i++) {
        final m = whites[i];
        children.add(Positioned(
          left: i * w,
          top: 0,
          width: w,
          height: h,
          child: _Key(midi: m, color: lit[m] ?? MColors.paper, onKey: onKey, label: labels ? noteName(m, lang) : '', dark: false),
        ));
      }
      for (var i = 0; i < whites.length; i++) {
        final m = whites[i] + 1;
        if (m > hi || !isBlack(m)) continue;
        children.add(Positioned(
          left: (i + 1) * w - w * 0.32,
          top: 0,
          width: w * 0.64,
          height: h * 0.6,
          child: _Key(midi: m, color: lit[m] ?? const Color(0xFF2A2A33), onKey: onKey, label: '', dark: true),
        ));
      }
      return Stack(children: children);
    });
  }
}

class _Key extends StatelessWidget {
  final int midi;
  final Color color;
  final void Function(int) onKey;
  final String label;
  final bool dark;
  const _Key({required this.midi, required this.color, required this.onKey, required this.label, required this.dark});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label.isEmpty ? '$midi' : label,
      child: Listener(
        onPointerDown: (_) => onKey(midi),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(6)),
            border: Border.all(color: Colors.black38),
          ),
          alignment: Alignment.bottomCenter,
          padding: const EdgeInsets.only(bottom: 6),
          child: label.isEmpty
              ? null
              : FittedBox(child: Text(label, style: TextStyle(color: dark ? Colors.white : MColors.ink, fontWeight: FontWeight.w700))),
        ),
      ),
    );
  }
}
