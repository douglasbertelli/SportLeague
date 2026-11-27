import 'package:flutter_test/flutter_test.dart';
import 'package:sport_league/core/utils/error_messages.dart';
import 'package:sport_league/features/championships/domain/championship.dart';
import 'package:sport_league/features/games/domain/game.dart';
import 'package:sport_league/features/games/domain/opponent.dart';
import 'package:sport_league/features/sports/domain/sport_rules.dart';
import 'package:sport_league/features/teams/domain/team.dart';

/// Etapa 0 da Fase 2: o que vem do banco com um esporte ou uma modalidade que
/// esta versão do app não conhece (de uma versão mais nova) não quebra, e as
/// listas tiram essas linhas.
void main() {
  group('leitura tolerante', () {
    test('esporte e modalidade desconhecidos viram nulo', () {
      expect(Sport.tryFromName('football'), Sport.football);
      expect(Sport.tryFromName('curling'), isNull);
      expect(Sport.tryFromName(null), isNull);
      expect(Modality.tryFromName('futsal'), Modality.futsal);
      expect(Modality.tryFromName('curling_ice'), isNull);
      // As do vôlei são conhecidas pela chave do banco.
      expect(
        Modality.tryFromName('volleyball_indoor'),
        Modality.volleyballIndoor,
      );
      expect(Modality.tryFromName(null), isNull);
    });

    test('time de esporte desconhecido não quebra', () {
      final team = Team.fromMap({
        'id': 't',
        'owner_id': 'o',
        'name': 'Time',
        'sport': 'curling',
        'modalities': ['curling_ice', 'futsal'],
      });
      expect(team.name, 'Time');
      expect(team.modalities, {Modality.futsal});
    });

    test('jogo de modalidade desconhecida fica sem modalidade', () {
      final game = Game.fromMap({
        'id': 'g',
        'team_id': 't',
        'opponent': 'Rival',
        'scheduled_at': '2026-11-26T20:00:00Z',
        'modality': 'curling_ice',
      });
      expect(game.modality, isNull);
    });

    test('campeonato e fictício de modalidade desconhecida não quebram', () {
      final championship = Championship.fromMap({
        'id': 'c',
        'owner_id': 'o',
        'name': 'Copa',
        'modality': 'curling_ice',
        'format': 'league',
        'status': 'draft',
      });
      expect(championship.name, 'Copa');
      final guest = GuestTeam.fromMap({
        'id': 'x',
        'owner_id': 'o',
        'name': 'Fictício',
        'modality': 'curling_ice',
      });
      expect(guest.name, 'Fictício');
    });
  });

  group('as listas tiram o que não é de um esporte liberado', () {
    test('times pelo esporte', () {
      expect(isSupportedSportRow({'sport': 'football'}), isTrue);
      // Liberado no build +8.
      expect(isSupportedSportRow({'sport': 'volleyball'}), isTrue);
      // Conhecido pelo enum, mas ainda não liberado (sem regras).
      expect(isSupportedSportRow({'sport': 'basketball'}), isFalse);
      expect(isSupportedSportRow({'sport': 'curling'}), isFalse);
      expect(isSupportedSportRow({}), isFalse);
    });

    test('campeonatos e fictícios pela modalidade', () {
      for (final modality in availableModalities) {
        expect(isSupportedModalityRow({'modality': modality.key}), isTrue);
      }
      expect(isSupportedModalityRow({'modality': 'volleyball_indoor'}), isTrue);
      expect(isSupportedModalityRow({}), isFalse);
    });
  });

  test('abrir algo de outro esporte pede para atualizar o app', () {
    expect(
      friendlyErrorMessage(const UnsupportedSportException()),
      contains('Atualize o app'),
    );
  });
}
