import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Kodla anında sentezlenen sesler: komalı (53 eşit bölümlü) makam sesleri ve
/// akort vuruları gibi örnek dosyayla verilemeyen perdeler için.
/// Örnekleme hızı düşük tutulur; ses bir kez üretilip önbelleğe alınır.
class Synth {
  static const int rate = 22050;

  /// 53 koma = bir oktav. [k] Rast'tan (Sol, 196 Hz) koma uzaklığı.
  static double komaHz(int k, {double rast = 196.0}) => rast * math.pow(2, k / 53).toDouble();

  /// Ney ve kanun arası yumuşak bir ses: temel + birkaç harmonik, hafif üfleme.
  static List<double> note(double f, double dur, {double vol = 0.5, double attack = 0.03, double release = 0.12, int seed = 1}) {
    final n = (rate * dur).round();
    final out = List<double>.filled(n, 0);
    var s = seed * 7919 + 13;
    for (var i = 0; i < n; i++) {
      final t = i / rate;
      final vib = 1 + 0.004 * math.sin(2 * math.pi * 5.2 * t) * math.min(1.0, t * 3);
      final ph = 2 * math.pi * f * vib * t;
      var v = math.sin(ph) + 0.32 * math.sin(2 * ph) + 0.12 * math.sin(3 * ph) + 0.05 * math.sin(4 * ph);
      s = (s * 1103515245 + 12345) & 0x7fffffff;
      v += 0.025 * ((s / 0x7fffffff) * 2 - 1);
      final a = math.min(1.0, t / attack);
      final r = math.min(1.0, (n - i) / (rate * release));
      out[i] = vol * 0.6 * v * a * r;
    }
    return out;
  }

  /// İki sesin birlikte çalınması: akortta vuru (dalgalanma) duyulur.
  static List<double> pair(double fRef, double f, double dur, {double vol = 0.5}) {
    final n = (rate * dur).round();
    final out = List<double>.filled(n, 0);
    for (var i = 0; i < n; i++) {
      final t = i / rate;
      double voice(double hz) {
        final ph = 2 * math.pi * hz * t;
        return math.sin(ph) + 0.4 * math.sin(2 * ph) + 0.15 * math.sin(3 * ph);
      }

      final a = math.min(1.0, t / 0.04) * math.min(1.0, (n - i) / (rate * 0.2));
      out[i] = vol * 0.32 * (voice(fRef) + voice(f)) * a;
    }
    return out;
  }

  /// Ardışık sesler (süreler saniye).
  static List<double> sequence(List<double> freqs, List<double> durs, {double vol = 0.5}) {
    final out = <double>[];
    for (var i = 0; i < freqs.length; i++) {
      out.addAll(note(freqs[i], durs[i], vol: vol, seed: i + 1));
    }
    return out;
  }

  /// 16 bit tek kanallı WAV.
  static Uint8List wav(List<double> pcm) {
    final n = pcm.length;
    final b = ByteData(44 + n * 2);
    void str(int o, String s) {
      for (var i = 0; i < s.length; i++) {
        b.setUint8(o + i, s.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    b.setUint32(4, 36 + n * 2, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    b.setUint32(16, 16, Endian.little);
    b.setUint16(20, 1, Endian.little);
    b.setUint16(22, 1, Endian.little);
    b.setUint32(24, rate, Endian.little);
    b.setUint32(28, rate * 2, Endian.little);
    b.setUint16(32, 2, Endian.little);
    b.setUint16(34, 16, Endian.little);
    str(36, 'data');
    b.setUint32(40, n * 2, Endian.little);
    for (var i = 0; i < n; i++) {
      final x = pcm[i];
      final v = x > 1.0 ? 1.0 : (x < -1.0 ? -1.0 : x);
      b.setInt16(44 + i * 2, (v * 32000).round(), Endian.little);
    }
    return b.buffer.asUint8List();
  }
}

/// Testlerde gerçek oynatıcı kurulmaz.
bool get _synthUsable {
  if (kIsWeb) return true;
  try {
    return !io.Platform.environment.containsKey('FLUTTER_TEST');
  } catch (_) {
    return false;
  }
}

/// Sentezlenen sesleri çalar. Aynı anahtar ikinci kez üretilmez.
/// Mobilde geçici dosyaya, web'de veri adresine yazılır.
class SynthVoice {
  bool sound;
  final Map<String, Source> _cache = {};
  final List<AudioPlayer> _players = [];
  int _next = 0;
  bool _failed = !_synthUsable;
  bool _disposed = false;
  SynthVoice({this.sound = true});

  /// Önbellekteki ses sayısı (testler için).
  int get cached => _cache.length;

  Future<Source?> _source(String key, List<double> Function() gen) async {
    final c = _cache[key];
    if (c != null) return c;
    final bytes = Synth.wav(gen());
    Source s;
    if (kIsWeb) {
      s = UrlSource('data:audio/wav;base64,${base64Encode(bytes)}');
    } else {
      final safe = key.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
      final f = io.File('${io.Directory.systemTemp.path}/muzik_$safe.wav');
      await f.writeAsBytes(bytes, flush: true);
      s = DeviceFileSource(f.path);
    }
    if (_cache.length > 160) _cache.remove(_cache.keys.first);
    _cache[key] = s;
    return s;
  }

  /// [key] ile önbelleğe alınan sesi çalar; yoksa [gen] ile üretir.
  void play(String key, List<double> Function() gen, {double volume = 1.0}) {
    if (!sound || _disposed || _failed) return;
    unawaited(_play(key, gen, volume));
  }

  /// Önceden üretip önbelleğe alır (çalmaz).
  void prepare(String key, List<double> Function() gen) {
    if (_disposed || _failed) return;
    unawaited(_source(key, gen).then((_) {}, onError: (_) {}));
  }

  Future<void> _play(String key, List<double> Function() gen, double volume) async {
    try {
      final s = await _source(key, gen);
      if (s == null || _disposed) return;
      if (_players.length < 4) _players.add(AudioPlayer());
      final p = _players[_next % _players.length];
      _next++;
      await p.stop();
      await p.setVolume(volume);
      await p.play(s);
    } catch (_) {
      _failed = true;
    }
  }

  /// Çalan bütün sesleri susturur.
  void stopAll() {
    for (final p in _players) {
      try {
        unawaited(p.stop());
      } catch (_) {}
    }
  }

  void dispose() {
    _disposed = true;
    for (final p in _players) {
      try {
        unawaited(p.dispose());
      } catch (_) {}
    }
    _players.clear();
  }
}
