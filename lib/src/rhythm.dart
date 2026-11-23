import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'audio.dart';
import 'core.dart';
import 'texts.dart';

/// Şarkı saati: kare başına güncellenen şarkı zamanı (ms). Ses gecikmesi
/// ayarı [effMs] ile hem çizime hem değerlendirmeye uygulanır.
mixin SongClock<T extends StatefulWidget> on State<T>, TickerProvider {
  Ticker? _tk;
  double songMs = 0;
  double _base = 0;
  bool running = false;
  final ValueNotifier<int> frame = ValueNotifier<int>(0);

  /// Gecikme düzeltilmiş şarkı zamanı.
  double get effMs => songMs - MusicPrefs.latencyMs;

  void startSong({double leadMs = 2000}) {
    _base = -leadMs;
    songMs = _base;
    final tk = _tk ??= createTicker(_tick);
    if (tk.isActive) tk.stop();
    tk.start();
    running = true;
  }

  void stopSong() {
    _tk?.stop();
    running = false;
  }

  void _tick(Duration el) {
    songMs = _base + el.inMicroseconds / 1000.0;
    onFrame();
    frame.value++;
  }

  void onFrame();

  @override
  void dispose() {
    _tk?.dispose();
    frame.dispose();
    super.dispose();
  }
}

/// Vuruş değerlendirmesi.
enum Judge { perfect, great, good, miss }

class JudgeWindow {
  final double perfect;
  final double great;
  final double good;
  const JudgeWindow(this.perfect, this.great, this.good);

  /// Kolay bölümlerde pencereler biraz daha geniştir.
  factory JudgeWindow.forLevel(int d, {bool practice = false}) {
    final k = practice ? 1.35 : (d <= 3 ? 1.2 : (d <= 6 ? 1.05 : 1.0));
    return JudgeWindow(45 * k, 90 * k, 150 * k);
  }

  Judge judge(double errMs) {
    final e = errMs.abs();
    if (e <= perfect) return Judge.perfect;
    if (e <= great) return Judge.great;
    if (e <= good) return Judge.good;
    return Judge.miss;
  }
}

double judgeWeight(Judge j) => switch (j) {
      Judge.perfect => 1.0,
      Judge.great => 0.85,
      Judge.good => 0.6,
      Judge.miss => 0.0,
    };

Color judgeColor(Judge j) => switch (j) {
      Judge.perfect => MColors.ok,
      Judge.great => MColors.good,
      Judge.good => MColors.accent,
      Judge.miss => MColors.bad,
    };

String judgeText(String lang, Judge j) => mt(lang, switch (j) {
      Judge.perfect => 'jPerfect',
      Judge.great => 'jGreat',
      Judge.good => 'jGood',
      Judge.miss => 'jMiss',
    });

/// İsabet sayacı.
class Tally {
  int perfect = 0, great = 0, good = 0, miss = 0, combo = 0, best = 0, score = 0;

  void add(Judge j) {
    switch (j) {
      case Judge.perfect:
        perfect++;
      case Judge.great:
        great++;
      case Judge.good:
        good++;
      case Judge.miss:
        miss++;
    }
    if (j == Judge.miss) {
      combo = 0;
    } else {
      combo++;
      if (combo > best) best = combo;
      score += (judgeWeight(j) * 100).round() * (1 + combo ~/ 10);
    }
  }

  int get total => perfect + great + good + miss;
  double get accuracy => total == 0 ? 0 : (perfect + great * 0.85 + good * 0.6) / total;
  int get hits => perfect + great + good;
}

/// Kısa ömürlü görsel efekt (halka / yazı).
class Burst {
  final Offset at;
  final double bornMs;
  final Color color;
  final String text;
  const Burst(this.at, this.bornMs, this.color, [this.text = '']);
}

void paintBursts(Canvas c, List<Burst> bursts, double nowMs) {
  for (final b in bursts) {
    final t = (nowMs - b.bornMs) / 420.0;
    if (t < 0 || t > 1) continue;
    c.drawCircle(b.at, 18 + 46 * t, stroke(b.color.withValues(alpha: 1 - t), 5 * (1 - t) + 1));
    if (b.text.isNotEmpty) drawLabel(c, b.text, b.at - Offset(0, 40 + 30 * t), 22, b.color.withValues(alpha: 1 - t));
  }
}

void pruneBursts(List<Burst> bursts, double nowMs) => bursts.removeWhere((b) => nowMs - b.bornMs > 450);

/// Sayım (4-3-2-1) çizimi.
void paintCountIn(Canvas c, double effMs, double beatMs, Offset center) {
  if (effMs >= 0) return;
  final n = (-effMs / beatMs).ceil();
  if (n > 4 || n < 1) return;
  final frac = ((-effMs) % beatMs) / beatMs;
  c.drawCircle(center, 56 + 10 * frac, fill(Colors.white.withValues(alpha: 0.08 + 0.12 * frac)));
  drawLabel(c, '$n', center, 64, Colors.white.withValues(alpha: 0.5 + 0.5 * frac), weight: FontWeight.w900);
}
