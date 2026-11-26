import 'core.dart';
import 'kinds/akort.dart';
import 'kinds/beat.dart';
import 'kinds/daily.dart';
import 'kinds/dictation.dart';
import 'kinds/drum.dart';
import 'kinds/ek4.dart';
import 'kinds/ear.dart';
import 'kinds/garden.dart';
import 'kinds/guitar.dart';
import 'kinds/makam.dart';
import 'kinds/memory.dart';
import 'kinds/pitch.dart';
import 'kinds/staff.dart';
import 'kinds/tiles.dart';

/// Müzik ve Ritim oyun türleri.
const Map<String, MuzikKind> kMuzikKinds = {
  'nota-karolari': TilesKind(),
  'ritim-vurusu': BeatKind(),
  'davul-dersi': DrumKind(),
  'kulak-egitimi': EarKind(),
  'gitar-akorlari': GuitarKind(),
  'melodi-hafizasi': MemoryKind(),
  'nota-ogrenme': StaffKind(),
  'gunluk-ritim': DailyRhythmKind(),
  'makam-yolculugu': MakamKind(),
  'ezgi-bahcesi': GardenKind(),
  'akort': AkortKind(),
  'ritim-diktesi': RDictKind(),
  'ton-tutma': PitchKind(),
  'ritim-kosusu': RunKind(),
  'usul-tala': UsulKind(),
  'kalimba-gamelan': KalimbaKind(),
  'melodi-bulmacasi': MelPuzKind(),
};

MuzikRules muzikRulesFor(String gameId, String kind) => muzikRules(gameId, kMuzikKinds[kind]!);
