import 'dart:async';
import 'dart:io' show Platform;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:studio_core/app/app_state.dart';

/// Kalıcı müzik ayarları: ses gecikmesi, görsel vuruş, titreşim, metronom.
class MusicPrefs {
  static int latencyMs = 0;
  static bool flash = true;
  static bool vibe = true;
  static int metroBpm = 90;
  static int metroMeter = 2;
  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      latencyMs = p.getInt('muzik.latency') ?? 0;
      flash = p.getBool('muzik.flash') ?? true;
      vibe = p.getBool('muzik.vibe') ?? true;
      metroBpm = p.getInt('muzik.metroBpm') ?? 90;
      metroMeter = p.getInt('muzik.metroMeter') ?? 2;
    } catch (_) {}
  }

  static Future<void> save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt('muzik.latency', latencyMs);
      await p.setBool('muzik.flash', flash);
      await p.setBool('muzik.vibe', vibe);
      await p.setInt('muzik.metroBpm', metroBpm);
      await p.setInt('muzik.metroMeter', metroMeter);
    } catch (_) {}
  }
}

/// Testlerde ve sesi desteklemeyen ortamlarda gerçek oynatıcı kurulmaz.
bool get _audioUsable {
  if (kIsWeb) return true;
  try {
    return !Platform.environment.containsKey('FLUTTER_TEST');
  } catch (_) {
    return false;
  }
}

/// Uygulamanın ses ve titreşim tercihleri (ayarlar ekranından).
class MusicEnv {
  final bool sound;
  final bool haptics;
  final AppState? app;
  const MusicEnv(this.sound, this.haptics, this.app);

  static MusicEnv of(BuildContext context) {
    try {
      final app = ProviderScope.containerOf(context, listen: false).read(appStateProvider);
      return MusicEnv(app.save.sound, app.save.haptics, app);
    } catch (_) {
      return const MusicEnv(true, true, null);
    }
  }

  /// Oyun sırasında arka plan müziği susturulur, çıkışta geri gelir.
  void pauseMusic() {
    try {
      unawaited(app?.audio.pauseAll());
    } catch (_) {}
  }

  void resumeMusic() {
    try {
      unawaited(app?.audio.resumeAll());
    } catch (_) {}
  }
}

/// Düşük gecikmeli çalgı sesi havuzu. Örnekler merkez uygulamasının
/// assets/sfx klasöründe (tool/generate_assets.py ile üretilir).
/// Oynatıcı kurulamazsa [fallback] (merkezin ses servisi) kullanılır.
class MusicVoice {
  final void Function(String name) fallback;
  bool sound;
  final Map<String, AudioPlayer> _players = {};
  bool _failed = !_audioUsable;
  bool _disposed = false;
  MusicVoice(this.fallback, {this.sound = true});

  Future<void> preload(Iterable<String> names) async {
    if (_failed) return;
    for (final n in names) {
      if (_disposed || _players.containsKey(n)) continue;
      if (_players.length >= 48) break;
      try {
        final p = AudioPlayer();
        await p.setPlayerMode(PlayerMode.lowLatency);
        await p.setReleaseMode(ReleaseMode.stop);
        await p.setSource(AssetSource('sfx/$n.wav'));
        if (_disposed) {
          unawaited(p.dispose());
          return;
        }
        _players[n] = p;
      } catch (_) {
        _failed = true;
        return;
      }
    }
  }

  void play(String name, {double volume = 1.0}) {
    if (!sound || _disposed) return;
    final p = _players[name];
    if (p == null || _failed) {
      if (_failed) {
        fallback(name);
      } else {
        unawaited(preload([name]).then((_) {
          final q = _players[name];
          if (q == null) {
            fallback(name);
          } else {
            _start(q, volume);
          }
        }));
      }
      return;
    }
    _start(p, volume);
  }

  void _start(AudioPlayer p, double volume) {
    try {
      unawaited(p.stop().then((_) => p.setVolume(volume)).then((_) => p.resume()).catchError((_) {}));
    } catch (_) {}
  }

  void dispose() {
    _disposed = true;
    for (final p in _players.values) {
      try {
        unawaited(p.dispose());
      } catch (_) {}
    }
    _players.clear();
  }
}

/// İşitme engelli oyuncular için vuruşların titreşim karşılığı.
class Haptic {
  static bool enabled = true;
  static void beat({bool strong = false}) {
    if (!enabled || !MusicPrefs.vibe) return;
    try {
      if (strong) {
        HapticFeedback.mediumImpact();
      } else {
        HapticFeedback.selectionClick();
      }
    } catch (_) {}
  }

  static void hit() {
    if (!enabled || !MusicPrefs.vibe) return;
    try {
      HapticFeedback.lightImpact();
    } catch (_) {}
  }

  static void miss() {
    if (!enabled || !MusicPrefs.vibe) return;
    try {
      HapticFeedback.heavyImpact();
    } catch (_) {}
  }
}
