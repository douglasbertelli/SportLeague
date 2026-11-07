import 'package:flutter_test/flutter_test.dart';
import 'package:sport_league/features/games/data/lineup_repository.dart';
import 'package:sport_league/features/games/domain/formation.dart';
import 'package:sport_league/features/teams/domain/team.dart';

void main() {
  test('cada formação tem os titulares da modalidade e o goleiro', () {
    for (final modality in Modality.values) {
      for (final formation in formationsFor(modality)) {
        expect(
          formation.spots,
          hasLength(startersFor(modality)),
          reason: '${modality.name} ${formation.name}',
        );
        expect(formation.spots.first.label, 'GOL');
        // O nome soma os jogadores de linha.
        final outfield = formation.name
            .split('-')
            .map(int.parse)
            .reduce((a, b) => a + b);
        expect(outfield, startersFor(modality) - 1, reason: formation.name);
        for (final spot in formation.spots) {
          expect(spot.x, inInclusiveRange(0, 1));
          expect(spot.y, inInclusiveRange(0, 1));
        }
      }
    }
  });

  test('campo e formações por modalidade', () {
    expect(pitchFor(Modality.field), PitchKind.field);
    expect(pitchFor(Modality.society), PitchKind.society);
    expect(pitchFor(Modality.futsal), PitchKind.court);
    expect(formationNamed(Modality.field, '4-4-2').name, '4-4-2');
    // Formação de outra modalidade: volta para a padrão.
    expect(formationNamed(Modality.futsal, '4-4-2').name, '2-2');
  });

  test('titulares: quem tem posição fica, os outros ocupam as livres', () {
    final placed = placeStarters(
      spots: 5,
      starters: ['a', 'b', 'c', 'd', 'e', 'f'],
      slots: {'c': 0, 'd': 0, 'e': 9},
    );
    expect(placed[0], 'c');
    expect(placed.values.toSet(), {'a', 'b', 'c', 'd', 'e'});
    // Seis titulares em cinco posições: o último fica de fora.
    expect(placed.containsValue('f'), isFalse);
  });
}
