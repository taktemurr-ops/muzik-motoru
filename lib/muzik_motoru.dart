/// Müzik ve Ritim ailesinin ortak motoru: nota karoları, ritim vuruşu,
/// davul dersi, kulak eğitimi, gitar akorları, melodi hafızası, nota okuma
/// ve günlük ritim; metronom, serbest çalgı, pratik modu, görsel vuruş.
library;

export 'src/catalog.dart';
export 'src/core.dart' show MuzikStage, MuzikRules, MuzikKind, MLevel, MPuzzle, muzikRules;
export 'src/texts.dart';
export 'src/theory.dart' show MNote, genMelody, melodyOk, parseTune, noteName;
export 'src/data/tunes.dart' show kPdTunes, PdTune;
export 'src/kinds/makam.dart' show kMakams, MakamDef, makamDegrees, makamTruth, perdeName, makamName;
export 'src/synth.dart' show Synth;
export 'src/kinds/dictation.dart' show kRCells, rdictCells, rdictSignature, rdictValid;
export 'src/kinds/pitch.dart' show pitchCents;
export 'src/mic.dart' show detectPitch, hzToMidi;
