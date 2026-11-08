import '../../profile/domain/profile.dart';

/// Situação de um pagamento da assinatura.
enum PaymentStatus {
  pending('Pendente'),
  paid('Pago'),
  failed('Falhou'),
  refunded('Estornado');

  const PaymentStatus(this.label);

  final String label;

  static PaymentStatus fromName(String name) =>
      values.where((status) => status.name == name).firstOrNull ?? pending;
}

/// Um pagamento da assinatura (tabela `subscription_payments`), gravado
/// pelo backend de pagamentos.
class SubscriptionPayment {
  const SubscriptionPayment({
    required this.id,
    required this.plan,
    required this.amountCents,
    required this.teams,
    required this.periodStart,
    required this.periodEnd,
    required this.status,
    this.method,
    this.paidAt,
  });

  factory SubscriptionPayment.fromMap(Map<String, dynamic> map) =>
      SubscriptionPayment(
        id: map['id'] as String,
        plan: SubscriptionPlan.fromName(map['plan'] as String),
        amountCents: (map['amount_cents'] as num).toInt(),
        teams: (map['teams'] as num).toInt(),
        periodStart: DateTime.parse(map['period_start'] as String),
        periodEnd: DateTime.parse(map['period_end'] as String),
        status: PaymentStatus.fromName(map['status'] as String),
        method: map['method'] as String?,
        paidAt: switch (map['paid_at']) {
          final String at => DateTime.parse(at).toLocal(),
          _ => null,
        },
      );

  final String id;
  final SubscriptionPlan plan;
  final int amountCents;

  /// Times cobrados no período.
  final int teams;
  final DateTime periodStart;
  final DateTime periodEnd;
  final PaymentStatus status;
  final String? method;
  final DateTime? paidAt;
}

/// Resumo dos pagamentos: o total pago e o último pago.
({int totalPaidCents, SubscriptionPayment? lastPaid}) summarizePayments(
  List<SubscriptionPayment> payments,
) {
  final paid = [
    for (final payment in payments)
      if (payment.status == PaymentStatus.paid) payment,
  ]..sort((a, b) => b.periodStart.compareTo(a.periodStart));
  return (
    totalPaidCents: paid.fold(0, (sum, p) => sum + p.amountCents),
    lastPaid: paid.firstOrNull,
  );
}
