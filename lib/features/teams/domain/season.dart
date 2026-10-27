import 'package:flutter_riverpod/flutter_riverpod.dart';

const _monthNames = [
  'Janeiro',
  'Fevereiro',
  'Março',
  'Abril',
  'Maio',
  'Junho',
  'Julho',
  'Agosto',
  'Setembro',
  'Outubro',
  'Novembro',
  'Dezembro',
];

/// Nome do mês (1 a 12).
String monthName(int month) => _monthNames[month - 1];

/// Temporada das estatísticas: um ano inteiro ou um mês dele.
class Season {
  const Season(this.year, [this.month]);

  /// O ano atual inteiro.
  factory Season.current([DateTime? now]) =>
      Season((now ?? DateTime.now()).year);

  final int year;

  /// 1 a 12; nulo para o ano inteiro.
  final int? month;

  /// Início do período, no fuso do aparelho.
  DateTime get start => DateTime(year, month ?? 1);

  /// Fim do período (exclusivo).
  DateTime get end =>
      month == null ? DateTime(year + 1) : DateTime(year, month! + 1);

  /// "Temporada 2026" ou "Outubro de 2026".
  String get label =>
      month == null ? 'Temporada $year' : '${monthName(month!)} de $year';

  /// "2026" ou "Out/2026", para o botão.
  String get shortLabel =>
      month == null ? '$year' : '${monthName(month!).substring(0, 3)}/$year';

  @override
  bool operator ==(Object other) =>
      other is Season && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);
}

/// Temporada escolhida para as estatísticas (do time e dos atletas), a mesma
/// em todas as telas; começa no ano atual.
final seasonProvider = NotifierProvider<SeasonNotifier, Season>(
  SeasonNotifier.new,
);

class SeasonNotifier extends Notifier<Season> {
  @override
  Season build() => Season.current();

  void select(Season season) => state = season;
}
