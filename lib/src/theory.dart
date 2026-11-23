import 'package:studio_core/core/rng.dart';

/// Ses örneklerinin kapsadığı en pes ve en tiz nota (MIDI): E2..C6.
const int kLowMidi = 40;
const int kHighMidi = 84;

int clampI(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);
double clampD(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

/// Piyano örneğinin adı (assets/sfx/pnNN.wav).
String pianoSample(int midi) => 'pn${clampI(midi, kLowMidi, kHighMidi)}';

/// Gitar akoru örneği (assets/sfx/gt_<kök>_<tür>.wav). Tür: M, m, 7, m7.
String guitarSample(int rootPc, String q) => 'gt_${rootPc % 12}_$q';

/// Davul ve darbuka örnekleri.
const List<String> kDrumSamples = [
  'dr_kick', 'dr_snare', 'dr_hat', 'dr_open', 'dr_tom1', 'dr_tom2', //
  'dr_crash', 'dr_clap', 'dr_rim', 'dr_dum', 'dr_tek', 'dr_ka',
];

/// Bir nota: başlangıç ve süre vuruş (beat) cinsinden.
class MNote {
  final double beat;
  final double dur;
  final int midi;
  const MNote(this.beat, this.dur, this.midi);
  MNote shift(int semis) => MNote(beat, dur, midi + semis);
}

/// Dizi kalıpları (yarım ses adımları, kökten).
class ScaleDef {
  final String key;
  final List<int> steps;
  const ScaleDef(this.key, this.steps);
}

const ScaleDef kMajor = ScaleDef('major', [0, 2, 4, 5, 7, 9, 11]);
const ScaleDef kMinor = ScaleDef('minor', [0, 2, 3, 5, 7, 8, 10]);
const ScaleDef kHarmonic = ScaleDef('harmonic', [0, 2, 3, 5, 7, 8, 11]);
const ScaleDef kPentaMajor = ScaleDef('penta', [0, 2, 4, 7, 9]);
const ScaleDef kPentaMinor = ScaleDef('pentaMinor', [0, 3, 5, 7, 10]);
const ScaleDef kDorian = ScaleDef('dorian', [0, 2, 3, 5, 7, 9, 10]);

/// Hicaz dizisinin eşit tamperamanlı yaklaşık hâli (koma sesler olmadan).
const ScaleDef kHicaz = ScaleDef('hicaz', [0, 1, 4, 5, 7, 8, 10]);

const List<ScaleDef> kScales = [kMajor, kMinor, kHarmonic, kPentaMajor, kPentaMinor, kDorian, kHicaz];

/// Akor türleri: sembol eki ve aralıkları.
class ChordDef {
  final String q;
  final String symbol;
  final List<int> iv;
  const ChordDef(this.q, this.symbol, this.iv);
}

const Map<String, ChordDef> kChords = {
  'M': ChordDef('M', '', [0, 4, 7]),
  'm': ChordDef('m', 'm', [0, 3, 7]),
  'dim': ChordDef('dim', '°', [0, 3, 6]),
  'aug': ChordDef('aug', '+', [0, 4, 8]),
  'sus2': ChordDef('sus2', 'sus2', [0, 2, 7]),
  'sus4': ChordDef('sus4', 'sus4', [0, 5, 7]),
  '7': ChordDef('7', '7', [0, 4, 7, 10]),
  'maj7': ChordDef('maj7', 'maj7', [0, 4, 7, 11]),
  'm7': ChordDef('m7', 'm7', [0, 3, 7, 10]),
  'm7b5': ChordDef('m7b5', 'ø7', [0, 3, 6, 10]),
};

/// Aralıkların evrensel kısaltmaları (yarım ses sayısına göre).
const List<String> kIntervalAbbr = ['P1', 'm2', 'M2', 'm3', 'M3', 'P4', 'TT', 'P5', 'm6', 'M6', 'm7', 'M7', 'P8'];

const List<String> _letters = ['C', 'C♯', 'D', 'E♭', 'E', 'F', 'F♯', 'G', 'A♭', 'A', 'B♭', 'B'];

/// Akor sembolünde kullanılan kök adı (harf sistemi; evrensel).
String rootLetter(int pc) => _letters[pc % 12];

String chordSymbol(int rootPc, String q) => '${rootLetter(rootPc)}${kChords[q]!.symbol}';

/// Dillere göre do-re-mi / harf adları (C D E F G A B sırasıyla).
const Map<String, List<String>> kNoteNames = {
  'tr': ['Do', 'Re', 'Mi', 'Fa', 'Sol', 'La', 'Si'],
  'en': ['C', 'D', 'E', 'F', 'G', 'A', 'B'],
  'de': ['C', 'D', 'E', 'F', 'G', 'A', 'H'],
  'es': ['Do', 'Re', 'Mi', 'Fa', 'Sol', 'La', 'Si'],
  'fr': ['Do', 'Ré', 'Mi', 'Fa', 'Sol', 'La', 'Si'],
  'ar': ['دو', 'ري', 'مي', 'فا', 'صول', 'لا', 'سي'],
  'fa': ['دو', 'ر', 'می', 'فا', 'سل', 'لا', 'سی'],
  'he': ['דו', 'רה', 'מי', 'פה', 'סול', 'לה', 'סי'],
  'ur': ['C', 'D', 'E', 'F', 'G', 'A', 'B'],
  'ru': ['До', 'Ре', 'Ми', 'Фа', 'Соль', 'Ля', 'Си'],
  'uk': ['До', 'Ре', 'Мі', 'Фа', 'Соль', 'Ля', 'Сі'],
  'pl': ['C', 'D', 'E', 'F', 'G', 'A', 'H'],
  'cs': ['C', 'D', 'E', 'F', 'G', 'A', 'H'],
  'ro': ['Do', 'Re', 'Mi', 'Fa', 'Sol', 'La', 'Si'],
  'hu': ['C', 'D', 'E', 'F', 'G', 'A', 'H'],
  'el': ['Ντο', 'Ρε', 'Μι', 'Φα', 'Σολ', 'Λα', 'Σι'],
  'it': ['Do', 'Re', 'Mi', 'Fa', 'Sol', 'La', 'Si'],
  'pt': ['Dó', 'Ré', 'Mi', 'Fá', 'Sol', 'Lá', 'Si'],
  'nl': ['C', 'D', 'E', 'F', 'G', 'A', 'B'],
  'sv': ['C', 'D', 'E', 'F', 'G', 'A', 'H'],
  'da': ['C', 'D', 'E', 'F', 'G', 'A', 'H'],
  'nb': ['C', 'D', 'E', 'F', 'G', 'A', 'H'],
  'fi': ['C', 'D', 'E', 'F', 'G', 'A', 'H'],
  'ja': ['ド', 'レ', 'ミ', 'ファ', 'ソ', 'ラ', 'シ'],
  'ko': ['도', '레', '미', '파', '솔', '라', '시'],
  'zh': ['C', 'D', 'E', 'F', 'G', 'A', 'B'],
  'hi': ['C', 'D', 'E', 'F', 'G', 'A', 'B'],
  'bn': ['C', 'D', 'E', 'F', 'G', 'A', 'B'],
  'id': ['Do', 'Re', 'Mi', 'Fa', 'Sol', 'La', 'Si'],
  'ms': ['Do', 'Re', 'Mi', 'Fa', 'So', 'La', 'Ti'],
  'th': ['โด', 'เร', 'มี', 'ฟา', 'ซอล', 'ลา', 'ที'],
  'vi': ['Đô', 'Rê', 'Mi', 'Fa', 'Son', 'La', 'Si'],
  'fil': ['Do', 'Re', 'Mi', 'Fa', 'So', 'La', 'Ti'],
};

const List<int> _naturalPc = [0, 2, 4, 5, 7, 9, 11];

/// Doğal nota sırası (0..6) ve diyez/bemol işareti.
(int, int) spell(int pc) {
  final p = pc % 12;
  final i = _naturalPc.indexOf(p);
  if (i >= 0) return (i, 0);
  // Siyah tuşlar diyezle yazılır (C♯, D♯, F♯, G♯, A♯).
  return (_naturalPc.indexOf(p - 1), 1);
}

/// Notanın dile göre adı; [octave] verilirse oktav numarası eklenir.
String noteName(int midi, String lang, {bool octave = false}) {
  final names = kNoteNames[lang] ?? kNoteNames['en']!;
  final (i, acc) = spell(midi % 12);
  final s = '${names[i]}${acc == 1 ? '♯' : ''}';
  return octave ? '$s${midi ~/ 12 - 1}' : s;
}

bool isBlack(int midi) => const [1, 3, 6, 8, 10].contains(midi % 12);

/// Dizi seslerini [lo]..[hi] aralığında listeler.
List<int> scaleNotes(int rootPc, ScaleDef s, int lo, int hi) => [
      for (var m = lo; m <= hi; m++)
        if (s.steps.contains(((m - rootPc) % 12 + 12) % 12)) m,
    ];

/// Ritim hücreleri (vuruş cinsinden; her biri iki vuruş tutar).
const List<List<double>> _cellsEasy = [
  [2],
  [1, 1],
  [1, 1],
  [1.5, 0.5],
];
const List<List<double>> _cellsMid = [
  [1, 1],
  [1, 0.5, 0.5],
  [0.5, 0.5, 1],
  [1.5, 0.5],
  [0.5, 0.5, 0.5, 0.5],
  [2],
];
const List<List<double>> _cellsHard = [
  [0.5, 0.5, 0.5, 0.5],
  [0.75, 0.25, 1],
  [0.5, 1, 0.5],
  [1, 0.5, 0.5],
  [0.25, 0.25, 0.5, 1],
  [1.5, 0.5],
];

/// Kulağa müzikal gelen, ezgisel kurala uyan özgün melodi üretir.
/// Yapı: A A' B A (dört ölçülük cümleler), çoğunlukla adım adım ilerleme,
/// sıçramalardan sonra ters yönde adım, sonda durak sesine iniş.
List<MNote> genMelody(
  SeededRandom r, {
  required int rootPc,
  required ScaleDef scale,
  int bars = 4,
  int beatsPerBar = 4,
  int level = 1,
  int lo = 60,
  int hi = 81,
}) {
  final pool = scaleNotes(rootPc, scale, lo, hi);
  final cells = level <= 3 ? _cellsEasy : (level <= 6 ? _cellsMid : _cellsHard);
  // Bir ölçülük ritim kalıpları.
  List<double> barRhythm() {
    final out = <double>[];
    var left = beatsPerBar.toDouble();
    while (left > 0.001) {
      if (left < 2) {
        out.add(left);
        break;
      }
      out.addAll(r.pick(cells));
      left -= 2;
    }
    return out;
  }

  final tonicIdx = <int>[for (var i = 0; i < pool.length; i++) if ((pool[i] - rootPc) % 12 == 0) i];
  var idx = tonicIdx.isEmpty ? pool.length ~/ 2 : tonicIdx[tonicIdx.length > 1 ? 1 : 0];
  if (idx >= pool.length - 2) idx = pool.length ~/ 2;
  final notes = <MNote>[];
  final rhythmA = [barRhythm(), barRhythm()];
  final pitchA = <int>[];
  var beat = 0.0;
  var lastMove = 0, same = 0;

  int step() {
    final x = r.nextInt(100);
    int mv;
    if (lastMove.abs() >= 3) {
      mv = lastMove > 0 ? -1 : 1;
    } else if (x < 58) {
      mv = r.chance(0.5) ? 1 : -1;
    } else if (x < 82) {
      mv = r.chance(0.5) ? 2 : -2;
    } else if (x < 88) {
      mv = 0;
    } else {
      mv = r.chance(0.5) ? r.range(3, 4) : -r.range(3, 4);
    }
    if (mv == 0 && same >= 1) mv = r.chance(0.5) ? 1 : -1;
    var n = idx + mv;
    if (n < 0 || n >= pool.length) n = idx - mv;
    n = clampI(n, 0, pool.length - 1);
    same = n == idx ? same + 1 : 0;
    lastMove = n - idx;
    return n;
  }

  for (var bar = 0; bar < bars; bar++) {
    final phrasePos = bar % 4;
    final last = bar == bars - 1;
    List<double> rh;
    if (phrasePos < 2) {
      rh = rhythmA[phrasePos];
    } else if (phrasePos == 2) {
      rh = barRhythm();
    } else {
      rh = rhythmA[1];
    }
    if (last) {
      // Son ölçü: kısa bir giriş ve uzun durak sesi.
      final first = beatsPerBar >= 3 ? <double>[1, 1] : <double>[1];
      final rest = beatsPerBar - first.fold<double>(0, (a, b) => a + b);
      rh = [...first, rest];
    }
    for (var i = 0; i < rh.length; i++) {
      final isEnd = last && i == rh.length - 1;
      if (isEnd) {
        // En yakın durak sesine in.
        var best = idx, bd = 99;
        for (final t in tonicIdx) {
          final dd = (t - idx).abs();
          if (dd < bd) {
            bd = dd;
            best = t;
          }
        }
        idx = best;
      } else {
        idx = step();
      }
      if (bar < 2) pitchA.add(idx);
      notes.add(MNote(beat, rh[i], pool[idx]));
      beat += rh[i];
    }
  }
  // Tekrarlanan A bölümünde ilk iki ölçünün ezgisini yinele (cümle hissi).
  if (bars >= 8 && pitchA.isNotEmpty) {
    final aLen = pitchA.length;
    final startB = notes.indexWhere((n) => n.beat >= 4.0 * beatsPerBar);
    if (startB >= 0 && startB + aLen < notes.length) {
      for (var k = 0; k < aLen; k++) {
        final n = notes[startB + k];
        notes[startB + k] = MNote(n.beat, n.dur, pool[pitchA[k]]);
      }
    }
  }
  return notes;
}

/// Bir melodinin ezgisel kurallara uyduğunu denetler.
bool melodyOk(List<MNote> m, {int lo = kLowMidi, int hi = kHighMidi, double minDur = 0.25}) {
  if (m.length < 4) return false;
  var run = 0;
  for (var i = 0; i < m.length; i++) {
    final n = m[i];
    if (n.midi < lo || n.midi > hi || n.dur < minDur - 1e-6) return false;
    if (i > 0) {
      final p = m[i - 1];
      if (n.beat < p.beat + p.dur - 1e-6) return false;
      if ((n.midi - p.midi).abs() > 12) return false;
      run = n.midi == p.midi ? run + 1 : 0;
      if (run >= 3) return false;
    }
  }
  return true;
}

/// "E4:1 D#4:0.5 R:1" biçimindeki yazımı notalara çevirir (R = sus).
List<MNote> parseTune(String s) {
  final out = <MNote>[];
  var beat = 0.0;
  for (final tok in s.split(' ')) {
    if (tok.isEmpty) continue;
    final parts = tok.split(':');
    final dur = double.parse(parts[1]);
    if (parts[0] != 'R') out.add(MNote(beat, dur, parseNote(parts[0])));
    beat += dur;
  }
  return out;
}

int parseNote(String n) {
  const base = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11};
  var pc = base[n[0]]!;
  var i = 1;
  if (n[i] == '#') {
    pc++;
    i++;
  } else if (n[i] == 'b') {
    pc--;
    i++;
  }
  final oct = int.parse(n.substring(i));
  return (oct + 1) * 12 + pc;
}

/// Notaları [lo]..[hi] aralığına sığacak biçimde oktav kaydırır.
List<MNote> fitRange(List<MNote> m, int lo, int hi) {
  var mn = 999, mx = -1;
  for (final n in m) {
    if (n.midi < mn) mn = n.midi;
    if (n.midi > mx) mx = n.midi;
  }
  var sh = 0;
  while (mn + sh < lo) {
    sh += 12;
  }
  while (mx + sh > hi && mn + sh - 12 >= lo) {
    sh -= 12;
  }
  return [for (final n in m) n.shift(sh)];
}
