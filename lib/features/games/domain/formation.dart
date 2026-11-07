import '../../teams/domain/team.dart';

/// Uma posição no campo: a sigla e onde fica. [x] vai da esquerda (0) à
/// direita (1); [y] vai do ataque (0, o gol adversário no alto) à defesa
/// (1, o próprio gol embaixo).
class FieldSpot {
  const FieldSpot(this.label, this.x, this.y);

  final String label;
  final double x;
  final double y;
}

/// Formação tática: o nome ("4-3-3") e as posições, sempre na mesma
/// quantidade dos titulares da modalidade. A posição 0 é o goleiro.
class Formation {
  const Formation(this.name, this.spots);

  final String name;
  final List<FieldSpot> spots;
}

/// Tipo de campo desenhado para a modalidade.
enum PitchKind {
  /// Campo de 11 (105 x 68).
  field(105 / 68),

  /// Society (de 7).
  society(50 / 30),

  /// Quadra de futsal e areia (de 5).
  court(40 / 20);

  const PitchKind(this.heightRatio);

  /// Altura dividida pela largura.
  final double heightRatio;
}

PitchKind pitchFor(Modality? modality) => switch (modality) {
  Modality.field => PitchKind.field,
  Modality.society => PitchKind.society,
  Modality.futsal ||
  Modality.beach ||
  Modality.challenge ||
  null => PitchKind.court,
};

const _gk = FieldSpot('GOL', 0.5, 0.94);

// Linhas (y) do campo de 11.
const _def = 0.78;
const _defMid = 0.64;
const _mid = 0.5;
const _att = 0.3;
const _fwd = 0.13;

/// Formações do campo (11 jogadores).
const fieldFormations = [
  Formation('4-3-3', [
    _gk,
    FieldSpot('ZAG', 0.35, _def + 0.03),
    FieldSpot('ZAG', 0.65, _def + 0.03),
    FieldSpot('LTE', 0.1, _defMid + 0.06),
    FieldSpot('LTD', 0.9, _defMid + 0.06),
    FieldSpot('VOL', 0.5, _defMid - 0.03),
    FieldSpot('MEI', 0.3, 0.44),
    FieldSpot('MEI', 0.7, 0.44),
    FieldSpot('ATA', 0.1, _att - 0.04),
    FieldSpot('ATA', 0.9, _att - 0.04),
    FieldSpot('CTA', 0.5, _fwd),
  ]),
  Formation('4-4-2', [
    _gk,
    FieldSpot('ZAG', 0.35, _def + 0.03),
    FieldSpot('ZAG', 0.65, _def + 0.03),
    FieldSpot('LTE', 0.1, _def - 0.02),
    FieldSpot('LTD', 0.9, _def - 0.02),
    FieldSpot('VOL', 0.35, _defMid - 0.06),
    FieldSpot('VOL', 0.65, _defMid - 0.06),
    FieldSpot('MEI', 0.1, _mid - 0.06),
    FieldSpot('MEI', 0.9, _mid - 0.06),
    FieldSpot('ATA', 0.35, _fwd + 0.04),
    FieldSpot('ATA', 0.65, _fwd + 0.04),
  ]),
  Formation('3-5-2', [
    _gk,
    FieldSpot('ZAG', 0.2, _def),
    FieldSpot('ZAG', 0.5, _def + 0.03),
    FieldSpot('ZAG', 0.8, _def),
    FieldSpot('ALA', 0.08, _mid),
    FieldSpot('ALA', 0.92, _mid),
    FieldSpot('VOL', 0.35, _defMid - 0.04),
    FieldSpot('VOL', 0.65, _defMid - 0.04),
    FieldSpot('MEI', 0.5, _att + 0.08),
    FieldSpot('ATA', 0.35, _fwd + 0.02),
    FieldSpot('ATA', 0.65, _fwd + 0.02),
  ]),
  Formation('4-2-4', [
    _gk,
    FieldSpot('ZAG', 0.35, _def + 0.03),
    FieldSpot('ZAG', 0.65, _def + 0.03),
    FieldSpot('LTE', 0.1, _def - 0.02),
    FieldSpot('LTD', 0.9, _def - 0.02),
    FieldSpot('VOL', 0.35, _mid + 0.04),
    FieldSpot('MEI', 0.65, _mid + 0.04),
    FieldSpot('PE', 0.1, _att - 0.04),
    FieldSpot('PD', 0.9, _att - 0.04),
    FieldSpot('ATA', 0.35, _fwd),
    FieldSpot('ATA', 0.65, _fwd),
  ]),
  Formation('3-4-3', [
    _gk,
    FieldSpot('ZAG', 0.2, _def),
    FieldSpot('ZAG', 0.5, _def + 0.03),
    FieldSpot('ZAG', 0.8, _def),
    FieldSpot('ALA', 0.1, _mid),
    FieldSpot('VOL', 0.37, _defMid - 0.04),
    FieldSpot('VOL', 0.63, _defMid - 0.04),
    FieldSpot('ALA', 0.9, _mid),
    FieldSpot('PE', 0.12, _att - 0.04),
    FieldSpot('CTA', 0.5, _fwd),
    FieldSpot('PD', 0.88, _att - 0.04),
  ]),
  Formation('4-5-1', [
    _gk,
    FieldSpot('ZAG', 0.35, _def + 0.03),
    FieldSpot('ZAG', 0.65, _def + 0.03),
    FieldSpot('LTE', 0.1, _def - 0.02),
    FieldSpot('LTD', 0.9, _def - 0.02),
    FieldSpot('VOL', 0.5, _defMid - 0.02),
    FieldSpot('MEI', 0.1, _mid - 0.04),
    FieldSpot('MEI', 0.32, _mid - 0.04),
    FieldSpot('MEI', 0.68, _mid - 0.04),
    FieldSpot('MEI', 0.9, _mid - 0.04),
    FieldSpot('CTA', 0.5, _fwd + 0.04),
  ]),
  Formation('4-2-3-1', [
    _gk,
    FieldSpot('ZAG', 0.35, _def + 0.03),
    FieldSpot('ZAG', 0.65, _def + 0.03),
    FieldSpot('LTE', 0.1, _def - 0.02),
    FieldSpot('LTD', 0.9, _def - 0.02),
    FieldSpot('VOL', 0.35, _defMid - 0.04),
    FieldSpot('VOL', 0.65, _defMid - 0.04),
    FieldSpot('PE', 0.12, _att + 0.06),
    FieldSpot('MEI', 0.5, _att + 0.08),
    FieldSpot('PD', 0.88, _att + 0.06),
    FieldSpot('CTA', 0.5, _fwd),
  ]),
  Formation('5-3-2', [
    _gk,
    FieldSpot('ZAG', 0.25, _def + 0.02),
    FieldSpot('ZAG', 0.5, _def + 0.04),
    FieldSpot('ZAG', 0.75, _def + 0.02),
    FieldSpot('ALA', 0.07, _defMid),
    FieldSpot('ALA', 0.93, _defMid),
    FieldSpot('VOL', 0.5, _mid + 0.04),
    FieldSpot('MEI', 0.27, _mid - 0.06),
    FieldSpot('MEI', 0.73, _mid - 0.06),
    FieldSpot('ATA', 0.35, _fwd + 0.02),
    FieldSpot('ATA', 0.65, _fwd + 0.02),
  ]),
];

/// Formações do society (7 jogadores).
const societyFormations = [
  Formation('2-3-1', [
    _gk,
    FieldSpot('ZAG', 0.3, 0.75),
    FieldSpot('ZAG', 0.7, 0.75),
    FieldSpot('ALA', 0.12, 0.48),
    FieldSpot('MEI', 0.5, 0.52),
    FieldSpot('ALA', 0.88, 0.48),
    FieldSpot('ATA', 0.5, 0.18),
  ]),
  Formation('3-2-1', [
    _gk,
    FieldSpot('LTE', 0.15, 0.72),
    FieldSpot('ZAG', 0.5, 0.76),
    FieldSpot('LTD', 0.85, 0.72),
    FieldSpot('MEI', 0.3, 0.46),
    FieldSpot('MEI', 0.7, 0.46),
    FieldSpot('ATA', 0.5, 0.18),
  ]),
  Formation('2-2-2', [
    _gk,
    FieldSpot('ZAG', 0.3, 0.75),
    FieldSpot('ZAG', 0.7, 0.75),
    FieldSpot('MEI', 0.3, 0.5),
    FieldSpot('MEI', 0.7, 0.5),
    FieldSpot('ATA', 0.3, 0.2),
    FieldSpot('ATA', 0.7, 0.2),
  ]),
  Formation('3-1-2', [
    _gk,
    FieldSpot('LTE', 0.15, 0.72),
    FieldSpot('ZAG', 0.5, 0.76),
    FieldSpot('LTD', 0.85, 0.72),
    FieldSpot('VOL', 0.5, 0.52),
    FieldSpot('ATA', 0.3, 0.22),
    FieldSpot('ATA', 0.7, 0.22),
  ]),
  Formation('1-3-2', [
    _gk,
    FieldSpot('ZAG', 0.5, 0.76),
    FieldSpot('ALA', 0.12, 0.5),
    FieldSpot('MEI', 0.5, 0.52),
    FieldSpot('ALA', 0.88, 0.5),
    FieldSpot('ATA', 0.3, 0.22),
    FieldSpot('ATA', 0.7, 0.22),
  ]),
];

/// Formações da quadra: futsal, areia e desafio (5 jogadores).
const courtFormations = [
  Formation('2-2', [
    _gk,
    FieldSpot('FIXO', 0.28, 0.7),
    FieldSpot('FIXO', 0.72, 0.7),
    FieldSpot('ALA', 0.28, 0.32),
    FieldSpot('PIVÔ', 0.72, 0.32),
  ]),
  Formation('1-2-1', [
    _gk,
    FieldSpot('FIXO', 0.5, 0.72),
    FieldSpot('ALA', 0.15, 0.48),
    FieldSpot('ALA', 0.85, 0.48),
    FieldSpot('PIVÔ', 0.5, 0.2),
  ]),
  Formation('3-1', [
    _gk,
    FieldSpot('ALA', 0.15, 0.62),
    FieldSpot('FIXO', 0.5, 0.7),
    FieldSpot('ALA', 0.85, 0.62),
    FieldSpot('PIVÔ', 0.5, 0.24),
  ]),
  Formation('4-0', [
    _gk,
    FieldSpot('ALA', 0.15, 0.5),
    FieldSpot('FIXO', 0.38, 0.6),
    FieldSpot('FIXO', 0.62, 0.6),
    FieldSpot('ALA', 0.85, 0.5),
  ]),
];

/// Formações da modalidade (a primeira é a padrão).
List<Formation> formationsFor(Modality? modality) =>
    switch (pitchFor(modality)) {
      PitchKind.field => fieldFormations,
      PitchKind.society => societyFormations,
      PitchKind.court => courtFormations,
    };

/// A formação [name] da modalidade, ou a padrão.
Formation formationNamed(Modality? modality, String? name) {
  final formations = formationsFor(modality);
  return formations.where((f) => f.name == name).firstOrNull ??
      formations.first;
}

/// Coloca os titulares: quem já tem posição ([slots], atleta -> posição)
/// fica nela; os outros [starters] ocupam as posições livres, na ordem.
/// Devolve posição -> atleta.
Map<int, String> placeStarters({
  required int spots,
  required List<String> starters,
  Map<String, int> slots = const {},
}) {
  final placed = <int, String>{};
  for (final athlete in starters) {
    final slot = slots[athlete];
    if (slot != null &&
        slot >= 0 &&
        slot < spots &&
        !placed.containsKey(slot)) {
      placed[slot] = athlete;
    }
  }
  var next = 0;
  for (final athlete in starters) {
    if (placed.containsValue(athlete)) continue;
    while (next < spots && placed.containsKey(next)) {
      next++;
    }
    if (next >= spots) break;
    placed[next] = athlete;
  }
  return placed;
}
