/// Telif süresi dolmuş (1929 öncesi) eserlerden ve halk ezgilerinden
/// kısa bölümler. Yazım: nota+oktav:vuruş (R = sus). Ezgiler oyun içinde
/// uygun oktava taşınır.
class PdTune {
  final String id;
  final String title;
  final String author; // boşsa geleneksel
  final int year;
  final int bpm;
  final int beatsPerBar;
  final String notes;
  const PdTune(this.id, this.title, this.author, this.year, this.bpm, this.beatsPerBar, this.notes);
}

const List<PdTune> kPdTunes = [
  PdTune('ode', 'An die Freude', 'L. van Beethoven', 1824, 104, 4,
      'E4:1 E4:1 F4:1 G4:1 G4:1 F4:1 E4:1 D4:1 C4:1 C4:1 D4:1 E4:1 E4:1.5 D4:0.5 D4:2 '
          'E4:1 E4:1 F4:1 G4:1 G4:1 F4:1 E4:1 D4:1 C4:1 C4:1 D4:1 E4:1 D4:1.5 C4:0.5 C4:2 '
          'D4:1 D4:1 E4:1 C4:1 D4:1 E4:0.5 F4:0.5 E4:1 C4:1 D4:1 E4:0.5 F4:0.5 E4:1 D4:1 C4:1 D4:1 G3:2 '
          'E4:1 E4:1 F4:1 G4:1 G4:1 F4:1 E4:1 D4:1 C4:1 C4:1 D4:1 E4:1 D4:1.5 C4:0.5 C4:2'),
  PdTune('twinkle', 'Ah! vous dirai-je, maman', '', 1761, 96, 4,
      'C4:1 C4:1 G4:1 G4:1 A4:1 A4:1 G4:2 F4:1 F4:1 E4:1 E4:1 D4:1 D4:1 C4:2 '
          'G4:1 G4:1 F4:1 F4:1 E4:1 E4:1 D4:2 G4:1 G4:1 F4:1 F4:1 E4:1 E4:1 D4:2 '
          'C4:1 C4:1 G4:1 G4:1 A4:1 A4:1 G4:2 F4:1 F4:1 E4:1 E4:1 D4:1 D4:1 C4:2'),
  PdTune('frere', 'Frère Jacques', '', 1780, 108, 4,
      'C4:1 D4:1 E4:1 C4:1 C4:1 D4:1 E4:1 C4:1 E4:1 F4:1 G4:2 E4:1 F4:1 G4:2 '
          'G4:0.5 A4:0.5 G4:0.5 F4:0.5 E4:1 C4:1 G4:0.5 A4:0.5 G4:0.5 F4:0.5 E4:1 C4:1 '
          'C4:1 G3:1 C4:2 C4:1 G3:1 C4:2'),
  PdTune('clair', 'Au clair de la lune', '', 1780, 100, 4,
      'C4:1 C4:1 C4:1 D4:1 E4:2 D4:2 C4:1 E4:1 D4:1 D4:1 C4:4 '
          'C4:1 C4:1 C4:1 D4:1 E4:2 D4:2 C4:1 E4:1 D4:1 D4:1 C4:4 '
          'D4:1 D4:1 D4:1 D4:1 A3:2 A3:2 D4:1 C4:1 B3:1 A3:1 G3:4 '
          'C4:1 C4:1 C4:1 D4:1 E4:2 D4:2 C4:1 E4:1 D4:1 D4:1 C4:4'),
  PdTune('mary', 'Mary Had a Little Lamb', '', 1830, 112, 4,
      'E4:1 D4:1 C4:1 D4:1 E4:1 E4:1 E4:2 D4:1 D4:1 D4:2 E4:1 G4:1 G4:2 '
          'E4:1 D4:1 C4:1 D4:1 E4:1 E4:1 E4:1 E4:1 D4:1 D4:1 E4:1 D4:1 C4:4'),
  PdTune('jingle', 'Jingle Bells', 'J. Pierpont', 1857, 120, 4,
      'E4:1 E4:1 E4:2 E4:1 E4:1 E4:2 E4:1 G4:1 C4:1.5 D4:0.5 E4:4 '
          'F4:1 F4:1 F4:1.5 F4:0.5 F4:1 E4:1 E4:1 E4:0.5 E4:0.5 E4:1 D4:1 D4:1 E4:1 D4:2 G4:2 '
          'E4:1 E4:1 E4:2 E4:1 E4:1 E4:2 E4:1 G4:1 C4:1.5 D4:0.5 E4:4 '
          'F4:1 F4:1 F4:1.5 F4:0.5 F4:1 E4:1 E4:1 E4:0.5 E4:0.5 G4:1 G4:1 F4:1 D4:1 C4:4'),
  PdTune('london', 'London Bridge', '', 1744, 104, 4,
      'G4:1.5 A4:0.5 G4:1 F4:1 E4:1 F4:1 G4:2 D4:1 E4:1 F4:2 E4:1 F4:1 G4:2 '
          'G4:1.5 A4:0.5 G4:1 F4:1 E4:1 F4:1 G4:2 D4:2 G4:2 E4:1 C4:3'),
  PdTune('greensleeves', 'Greensleeves', '', 1580, 84, 3,
      'A4:0.5 C5:1 D5:0.5 E5:0.75 F5:0.25 E5:0.5 D5:1 B4:0.5 G4:0.75 A4:0.25 B4:0.5 '
          'C5:1 A4:0.5 A4:0.75 G#4:0.25 A4:0.5 B4:1 G#4:0.5 E4:1 A4:0.5 '
          'C5:1 D5:0.5 E5:0.75 F5:0.25 E5:0.5 D5:1 B4:0.5 G4:0.75 A4:0.25 B4:0.5 '
          'C5:0.75 B4:0.25 A4:0.5 G#4:0.75 F#4:0.25 G#4:0.5 A4:1.5 A4:1'),
  PdTune('elise', 'Für Elise', 'L. van Beethoven', 1810, 80, 3,
      'E5:0.5 D#5:0.5 E5:0.5 D#5:0.5 E5:0.5 B4:0.5 D5:0.5 C5:0.5 A4:1 R:0.5 '
          'C4:0.5 E4:0.5 A4:0.5 B4:1 R:0.5 E4:0.5 G#4:0.5 B4:0.5 C5:1 R:0.5 '
          'E4:0.5 E5:0.5 D#5:0.5 E5:0.5 D#5:0.5 E5:0.5 B4:0.5 D5:0.5 C5:0.5 A4:1 R:0.5 '
          'C4:0.5 E4:0.5 A4:0.5 B4:1 R:0.5 E4:0.5 C5:0.5 B4:0.5 A4:2'),
  PdTune('canon', 'Kanon D-Dur', 'J. Pachelbel', 1694, 72, 4,
      'F#5:2 E5:2 D5:2 C#5:2 B4:2 A4:2 B4:2 C#5:2 D5:2 C#5:2 B4:2 A4:2 G4:2 F#4:2 G4:2 E4:2 '
          'D5:1 F#5:1 A5:1 G5:1 F#5:1 D5:1 F#5:1 E5:1 D5:1 B4:1 D5:1 A5:1 G5:1 B5:1 A5:1 G5:1'),
  PdTune('nachtmusik', 'Eine kleine Nachtmusik', 'W. A. Mozart', 1787, 112, 4,
      'G4:1 R:0.5 D4:0.5 G4:1 R:0.5 D4:0.5 G4:0.5 D4:0.5 G4:0.5 B4:0.5 D5:2 '
          'C5:1 R:0.5 A4:0.5 C5:1 R:0.5 A4:0.5 C5:0.5 A4:0.5 F#4:0.5 A4:0.5 D4:2'),
  PdTune('morning', 'Morgenstemning', 'E. Grieg', 1875, 84, 3,
      'G5:1 E5:1 D5:1 C5:1 D5:1 E5:1 G5:1 E5:1 D5:1 C5:1 D5:0.5 E5:0.5 D5:0.5 E5:0.5 '
          'G5:1 E5:1 G5:1 A5:1 E5:1 A5:1 G5:1 E5:1 D5:1 C5:3'),
  PdTune('mountain', 'I Dovregubbens hall', 'E. Grieg', 1875, 96, 4,
      'A3:0.5 B3:0.5 C4:0.5 D4:0.5 E4:0.5 C4:0.5 E4:1 D#4:0.5 B3:0.5 D#4:1 D4:0.5 A#3:0.5 D4:1 '
          'A3:0.5 B3:0.5 C4:0.5 D4:0.5 E4:0.5 C4:0.5 E4:0.5 A4:0.5 G4:0.5 E4:0.5 C4:0.5 E4:0.5 G4:2'),
  PdTune('turca', 'Rondo alla Turca', 'W. A. Mozart', 1783, 66, 4,
      'B4:0.25 A4:0.25 G#4:0.25 A4:0.25 C5:1 D5:0.25 C5:0.25 B4:0.25 C5:0.25 E5:1 '
          'F5:0.25 E5:0.25 D#5:0.25 E5:0.25 B5:0.25 A5:0.25 G#5:0.25 A5:0.25 B5:0.25 A5:0.25 G#5:0.25 A5:0.25 C6:2'),
];
