import 'package:flutter/material.dart';

import 'match_clock.dart';

/// Tipos de lance da súmula ao vivo (enum game_event_kind no banco).
enum GameEventKind {
  goal('Gol', Icons.sports_soccer),
  ownGoal('Gol contra', Icons.sports_soccer),
  penaltyMissed('Pênalti perdido', Icons.block),
  penaltySaved('Pênalti defendido', Icons.back_hand_outlined),
  yellowCard('Cartão amarelo', Icons.style),
  secondYellow('Segundo amarelo', Icons.style),
  redCard('Cartão vermelho', Icons.style),
  substitution('Substituição', Icons.swap_vert);

  const GameEventKind(this.label, this.icon);

  final String label;
  final IconData icon;

  /// Nome curto, para a grade de tipos do lançamento.
  String get shortLabel => switch (this) {
    GameEventKind.goal => 'Gol',
    GameEventKind.ownGoal => 'Gol contra',
    GameEventKind.penaltyMissed => 'Pên. perdido',
    GameEventKind.penaltySaved => 'Pên. defendido',
    GameEventKind.yellowCard => 'Amarelo',
    GameEventKind.secondYellow => '2º amarelo',
    GameEventKind.redCard => 'Vermelho',
    GameEventKind.substitution => 'Substituição',
  };

  /// Nome no banco (snake_case).
  String get dbName => switch (this) {
    GameEventKind.ownGoal => 'own_goal',
    GameEventKind.penaltyMissed => 'penalty_missed',
    GameEventKind.penaltySaved => 'penalty_saved',
    GameEventKind.yellowCard => 'yellow_card',
    GameEventKind.secondYellow => 'second_yellow',
    GameEventKind.redCard => 'red_card',
    _ => name,
  };

  static GameEventKind fromDb(String value) =>
      GameEventKind.values.firstWhere((kind) => kind.dbName == value);

  /// Gol e gol contra mudam o placar (só quem marcou o jogo lança).
  bool get isScoring =>
      this == GameEventKind.goal || this == GameEventKind.ownGoal;

  /// Cor do ícone: cartões na cor do cartão (o segundo amarelo é amarelo; a
  /// expulsão aparece no texto).
  Color? get color => switch (this) {
    GameEventKind.yellowCard ||
    GameEventKind.secondYellow => const Color(0xFFF5C518),
    GameEventKind.redCard => const Color(0xFFE53935),
    _ => null,
  };
}

/// Lado do jogo: quem marcou ou o adversário.
enum GameSide {
  host,
  opponent;

  static GameSide fromDb(String value) =>
      value == 'host' ? GameSide.host : GameSide.opponent;

  GameSide get other => this == host ? opponent : host;
}

/// Um lance do jogo, com o minuto tirado do relógio da partida.
class GameEvent {
  const GameEvent({
    required this.id,
    required this.gameId,
    required this.side,
    required this.kind,
    required this.createdAt,
    this.athleteId,
    this.athleteName,
    this.relatedAthleteId,
    this.relatedName,
    this.penalty = false,
    this.phase,
    this.clockSeconds,
  });

  factory GameEvent.fromMap(Map<String, dynamic> map) {
    String? nameOf(Object? athlete) => switch (athlete) {
      {'name': final String name, 'profile': final Object? profile} =>
        switch (profile) {
          {'nickname': final String nickname} when nickname.isNotEmpty =>
            nickname,
          _ => name,
        },
      _ => null,
    };
    return GameEvent(
      id: map['id'] as String,
      gameId: map['game_id'] as String,
      side: GameSide.fromDb(map['side'] as String),
      kind: GameEventKind.fromDb(map['kind'] as String),
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
      athleteId: map['athlete_id'] as String?,
      athleteName: nameOf(map['athlete']),
      relatedAthleteId: map['related_athlete_id'] as String?,
      relatedName: nameOf(map['related']),
      penalty: map['penalty'] as bool? ?? false,
      phase: MatchPhase.fromName(map['phase'] as String?),
      clockSeconds: map['clock_seconds'] as int?,
    );
  }

  final String id;
  final String gameId;

  /// Lado de quem fez o lance (no gol contra, o gol vale para o outro).
  final GameSide side;
  final GameEventKind kind;
  final DateTime createdAt;
  final String? athleteId;
  final String? athleteName;

  /// Assistência (gol) ou quem entrou (substituição).
  final String? relatedAthleteId;
  final String? relatedName;
  final bool penalty;
  final MatchPhase? phase;
  final int? clockSeconds;

  /// Lado que ganhou o gol (nulo se o lance não é gol).
  GameSide? get scoringSide => switch (kind) {
    GameEventKind.goal => side,
    GameEventKind.ownGoal => side.other,
    _ => null,
  };

  /// Gol ainda sem autor (o adversário da plataforma completa).
  bool get needsAthlete => athleteId == null;

  /// Quando o lance aconteceu: o tempo do cronômetro da partida ("12:05")
  /// ou, sem cronômetro iniciado, a hora do celular ("17:20").
  String get timeLabel {
    final seconds = clockSeconds;
    if (seconds != null) return formatClock(Duration(seconds: seconds));
    final hour = createdAt.hour.toString().padLeft(2, '0');
    final minute = createdAt.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  /// Para o leitor de tela: "aos 12:05 do 1º tempo" ou "às 17:20".
  String get timeSemantics => clockSeconds != null
      ? 'aos $timeLabel${phase == null ? '' : ' do ${phase!.label}'}'
      : 'às $timeLabel';

  /// Tempo do jogo em que o lance aconteceu: "1ºT" ou "2ºT" (nulo sem
  /// relógio).
  String? get periodLabel => switch (phase) {
    MatchPhase.first => '1ºT',
    MatchPhase.second => '2ºT',
    _ => null,
  };

  /// "23'", "45+2'" ou, no 2º tempo de 25 min, "31'"; vazio sem relógio.
  String minuteLabel(int? periodMinutes) =>
      formatEventMinute(phase, clockSeconds, periodMinutes);

  /// Linha principal do lance: "Gol de pênalti · Fulano".
  String get title {
    final what = switch (kind) {
      GameEventKind.goal when penalty => 'Gol de pênalti',
      _ => kind.label,
    };
    return switch (athleteName) {
      final name? => '$what · $name',
      null => what,
    };
  }

  /// Detalhe: assistência ou quem entrou.
  String? get detail => switch ((kind, relatedName)) {
    (GameEventKind.goal, final name?) => 'Assistência de $name',
    (GameEventKind.substitution, final name?) => 'Entrou $name',
    _ => null,
  };
}

/// Minuto do lance no padrão do futebol: no 2º tempo conta a partir da
/// duração do 1º; o acréscimo vira "45+2'".
String formatEventMinute(MatchPhase? phase, int? seconds, int? periodMinutes) {
  if (phase == null || seconds == null) return '';
  final minute = seconds ~/ 60 + 1;
  final period = periodMinutes;
  final offset = phase == MatchPhase.second && period != null ? period : 0;
  if (period != null && minute > period) {
    return "${offset + period}+${minute - period}'";
  }
  return "${offset + minute}'";
}
