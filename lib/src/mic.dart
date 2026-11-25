import 'dart:async';
import 'dart:io' as io;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

/// Testlerde mikrofon eklentisi çağrılmaz.
bool get micUsable {
  if (kIsWeb) return true;
  try {
    return !io.Platform.environment.containsKey('FLUTTER_TEST');
  } catch (_) {
    return false;
  }
}

/// Mikrofonu PCM olarak dinler ve perde bulur. Ses kaydedilmez, saklanmaz,
/// cihazdan çıkmaz: her parça işlenip atılır.
class PitchMic {
  static const int rate = 44100;
  AudioRecorder? _rec;
  StreamSubscription<Uint8List>? _sub;
  final List<double> _buf = [];
  final List<double> _recent = [];

  /// Bulunan perde (Hz; sessizlikte null) ve ses düzeyi (0..1).
  void Function(double? hz, double level)? onPitch;

  Future<bool> start() async {
    if (!micUsable) return false;
    try {
      final rec = AudioRecorder();
      _rec = rec;
      if (!await rec.hasPermission()) {
        await _close();
        return false;
      }
      final stream = await rec.startStream(
        const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: rate, numChannels: 1),
      );
      _sub = stream.listen(_onData, onError: (_) {});
      return true;
    } catch (_) {
      await _close();
      return false;
    }
  }

  void _onData(Uint8List data) {
    final bd = ByteData.sublistView(data);
    final n = data.lengthInBytes ~/ 2;
    // 2'ye indirerek (22 050 Hz) işlem yükü yarıya iner.
    for (var i = 0; i + 1 < n; i += 2) {
      _buf.add((bd.getInt16(i * 2, Endian.little) + bd.getInt16(i * 2 + 2, Endian.little)) / 65536.0);
    }
    const frame = 1536;
    while (_buf.length >= frame) {
      final x = Float64List.fromList(_buf.sublist(0, frame));
      _buf.removeRange(0, frame ~/ 2);
      var e = 0.0;
      for (final v in x) {
        e += v * v;
      }
      final level = math.min(1.0, math.sqrt(e / frame) * 8);
      final f = detectPitch(x, rate ~/ 2);
      // Kısa sıçramalara karşı son üç ölçümün ortancası.
      if (f == null) {
        _recent.clear();
        onPitch?.call(null, level);
      } else {
        _recent.add(f);
        if (_recent.length > 3) _recent.removeAt(0);
        final s = [..._recent]..sort();
        onPitch?.call(s[s.length ~/ 2], level);
      }
    }
  }

  Future<void> _close() async {
    await _sub?.cancel();
    _sub = null;
    final r = _rec;
    _rec = null;
    if (r != null) {
      try {
        await r.stop();
      } catch (_) {}
      try {
        await r.dispose();
      } catch (_) {}
    }
  }

  Future<void> stop() async {
    _buf.clear();
    _recent.clear();
    await _close();
  }
}

/// YIN yöntemiyle temel frekans (65–1100 Hz). Sessizlik ya da gürültüde null.
double? detectPitch(Float64List x, int rate) {
  final n = x.length;
  var energy = 0.0;
  for (final v in x) {
    energy += v * v;
  }
  if (math.sqrt(energy / n) < 0.008) return null;
  final minLag = rate ~/ 1100, maxLag = math.min<int>(rate ~/ 65, n ~/ 2);
  final d = Float64List(maxLag + 1);
  final w = n - maxLag;
  for (var lag = 1; lag <= maxLag; lag++) {
    var s = 0.0;
    for (var i = 0; i < w; i++) {
      final diff = x[i] - x[i + lag];
      s += diff * diff;
    }
    d[lag] = s;
  }
  var run = 0.0;
  final cmnd = Float64List(maxLag + 1)..[0] = 1.0;
  for (var lag = 1; lag <= maxLag; lag++) {
    run += d[lag];
    cmnd[lag] = run == 0 ? 1.0 : d[lag] * lag / run;
  }
  var best = -1;
  for (var lag = minLag; lag <= maxLag; lag++) {
    if (cmnd[lag] < 0.15) {
      while (lag + 1 <= maxLag && cmnd[lag + 1] < cmnd[lag]) {
        lag++;
      }
      best = lag;
      break;
    }
  }
  if (best < 0) return null;
  var lag = best.toDouble();
  if (best > 1 && best < maxLag) {
    final a = cmnd[best - 1], b = cmnd[best], c = cmnd[best + 1];
    final den = a - 2 * b + c;
    if (den != 0) lag = best + (a - c) / (2 * den);
  }
  return rate / lag;
}

/// Frekansın MIDI karşılığı (kesirli).
double hzToMidi(double hz) => 69 + 12 * math.log(hz / 440.0) / math.ln2;
