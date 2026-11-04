import 'package:intl/intl.dart';

/// Mensalidade do time: o valor por mês, o dia do vencimento e a chave PIX
/// (opcional). Cobrada a partir de [startMonth].
class TeamDues {
  const TeamDues({
    required this.teamId,
    required this.amountCents,
    required this.dueDay,
    this.pixKey,
    this.startMonth,
  });

  factory TeamDues.fromMap(Map<String, dynamic> map) => TeamDues(
    teamId: map['team_id'] as String,
    amountCents: map['amount_cents'] as int,
    dueDay: map['due_day'] as int,
    pixKey: map['pix_key'] as String?,
    startMonth: DateTime.parse(map['start_month'] as String),
  );

  final String teamId;
  final int amountCents;

  /// Dia do vencimento, de 1 a 28 (existe em todos os meses).
  final int dueDay;
  final String? pixKey;

  /// Primeiro mês cobrado (dia 1). Nulo antes de salvar: o banco usa o mês
  /// atual.
  final DateTime? startMonth;

  /// O que o app grava (o mês de início fica com o banco).
  Map<String, dynamic> toMap() {
    final pix = pixKey?.trim();
    return {
      'team_id': teamId,
      'amount_cents': amountCents,
      'due_day': dueDay,
      'pix_key': pix == null || pix.isEmpty ? null : pix,
    };
  }

  /// Dia do vencimento no [month].
  DateTime dueDate(DateTime month) => DateTime(month.year, month.month, dueDay);

  /// Em aberto e já passou do vencimento (no dia, ainda não está atrasado).
  bool isLate(DateTime month, DateTime today) =>
      DateTime(today.year, today.month, today.day).isAfter(dueDate(month));

  /// Os meses cobrados, do início até [today]: o mais novo no fim.
  List<DateTime> monthsUntil(DateTime today) {
    final start = startMonth ?? firstOfMonth(today);
    final last = firstOfMonth(today);
    return [
      for (
        var month = start;
        !month.isAfter(last);
        month = DateTime(month.year, month.month + 1)
      )
        month,
    ];
  }
}

/// Dia 1 do mês de [date].
DateTime firstOfMonth(DateTime date) => DateTime(date.year, date.month);

/// "Novembro de 2026".
String formatMonth(DateTime month) {
  final text = DateFormat("MMMM 'de' y", 'pt_BR').format(month);
  return text[0].toUpperCase() + text.substring(1);
}

/// "novembro".
String monthName(DateTime month) => DateFormat('MMMM', 'pt_BR').format(month);

/// Chave de um pagamento: o atleta e o mês ("a1|2026-11").
String duePaymentKey(String athleteId, DateTime month) =>
    '$athleteId|${month.year}-${month.month.toString().padLeft(2, '0')}';

/// Pagamentos da mensalidade do time ([duePaymentKey]).
typedef DuePayments = Set<String>;
