import '../../teams/domain/team.dart';

/// Em que parte da partida o relógio está.
enum MatchPhase {
  first('1º tempo'),
  interval('Intervalo'),
  second('2º tempo'),
  finished('Fim de jogo');

  const MatchPhase(this.label);

  final String label;

  static MatchPhase? fromName(String? value) => value == null
      ? null
      : MatchPhase.values.firstWhere((phase) => phase.name == value);
}

/// Ações do relógio (função game_clock no banco).
enum ClockAction { start, pause, resume, endHalf, startSecond, finish, reset }

/// Relógio da partida, controlado por quem marcou o jogo e salvo no banco:
/// [elapsed] é o tempo acumulado até a última pausa e [startedAt], quando
/// corre, o instante em que voltou a correr.
class MatchClock {
  const MatchClock({
    required this.phase,
    this.startedAt,
    this.elapsed = Duration.zero,
    this.periodMinutes,
  });

  /// Nulo quando o relógio ainda não foi iniciado.
  static MatchClock? fromMap(Map<String, dynamic> map) {
    final phase = MatchPhase.fromName(map['match_phase'] as String?);
    if (phase == null) return null;
    return MatchClock(
      phase: phase,
      startedAt: switch (map['clock_started_at']) {
        final String value => DateTime.parse(value).toLocal(),
        _ => null,
      },
      elapsed: Duration(seconds: map['clock_elapsed'] as int? ?? 0),
      periodMinutes: map['period_minutes'] as int?,
    );
  }

  final MatchPhase phase;
  final DateTime? startedAt;
  final Duration elapsed;

  /// Duração de cada tempo.
  final int? periodMinutes;

  bool get running => startedAt != null;

  /// Se ainda se joga (1º tempo, intervalo ou 2º tempo).
  bool get inPlay => phase != MatchPhase.finished;

  /// Tempo corrido no tempo atual.
  Duration elapsedAt(DateTime now) {
    final startedAt = this.startedAt;
    if (startedAt == null) return elapsed;
    final running = now.difference(startedAt);
    return elapsed + (running.isNegative ? Duration.zero : running);
  }

  /// Passou da duração do tempo (acréscimo).
  bool overtimeAt(DateTime now) {
    final minutes = periodMinutes;
    return minutes != null &&
        (phase == MatchPhase.first || phase == MatchPhase.second) &&
        elapsedAt(now) >= Duration(minutes: minutes);
  }

  /// Duração sugerida de cada tempo pela modalidade.
  static int defaultPeriodMinutes(Modality? modality) => switch (modality) {
    Modality.futsal => 20,
    Modality.society => 25,
    Modality.field => 45,
    Modality.beach => 15,
    Modality.challenge || null => 10,
  };
}

/// "12:34" (minutos podem passar de 60: "75:02").
String formatClock(Duration duration) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(duration.inMinutes)}:${two(duration.inSeconds % 60)}';
}
