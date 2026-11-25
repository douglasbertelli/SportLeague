/// Caixa do time (função team_cash): saldo, totais e lançamentos.
class TeamCash {
  const TeamCash({
    this.locked = false,
    this.canManage = false,
    this.balanceCents = 0,
    this.totalInCents = 0,
    this.totalOutCents = 0,
    this.entries = const [],
  });

  factory TeamCash.fromMap(Map<String, dynamic> map) => TeamCash(
    locked: map['locked'] as bool? ?? false,
    canManage: map['can_manage'] as bool? ?? false,
    balanceCents: (map['balance'] as num?)?.toInt() ?? 0,
    totalInCents: (map['total_in'] as num?)?.toInt() ?? 0,
    totalOutCents: (map['total_out'] as num?)?.toInt() ?? 0,
    entries: [
      for (final row in map['entries'] as List<dynamic>? ?? const [])
        CashEntry.fromMap(row as Map<String, dynamic>),
    ],
  );

  /// O dono do time não tem o Premium: o caixa fica fechado.
  final bool locked;

  /// O dono: lança e apaga.
  final bool canManage;
  final int balanceCents;
  final int totalInCents;
  final int totalOutCents;
  final List<CashEntry> entries;
}

/// Categorias sugeridas ao lançar (o dono pode escrever outra).
const cashOutCategories = [
  'Campo',
  'Árbitro',
  'Uniforme',
  'Bola',
  'Colete',
  'Confraternização',
  'Inscrição',
  'Outros',
];
const cashInCategories = ['Patrocínio', 'Doação', 'Venda', 'Outros'];

class CashEntry {
  const CashEntry({
    required this.id,
    required this.day,
    required this.isIn,
    required this.category,
    required this.amountCents,
    this.description,
    this.auto = false,
  });

  factory CashEntry.fromMap(Map<String, dynamic> map) => CashEntry(
    id: map['id'] as String,
    day: DateTime.parse(map['day'] as String),
    isIn: map['kind'] == 'in',
    category: map['category'] as String,
    amountCents: (map['amount'] as num?)?.toInt() ?? 0,
    description: map['description'] as String?,
    auto: map['auto'] as bool? ?? false,
  );

  /// Id do lançamento do dono; nos automáticos, uma chave (não apaga).
  final String id;
  final DateTime day;
  final bool isIn;
  final String category;
  final int amountCents;
  final String? description;

  /// Mensalidade ou vaquinha paga: entra sozinha (não dá para apagar daqui).
  final bool auto;
}

enum ReceiptStatus { pending, approved, rejected }

/// Comprovante de pagamento (mensalidade ou vaquinha) enviado pelo atleta.
class PaymentReceipt {
  const PaymentReceipt({
    required this.id,
    required this.isDues,
    required this.payer,
    required this.imagePath,
    required this.createdAt,
    this.month,
    this.fundraiserId,
    this.fundraiserTitle,
    this.mine = false,
    this.status = ReceiptStatus.pending,
    this.note,
  });

  factory PaymentReceipt.fromMap(Map<String, dynamic> map) => PaymentReceipt(
    id: map['id'] as String,
    isDues: map['kind'] == 'dues',
    payer: map['payer'] as String? ?? 'Alguém',
    imagePath: map['image_path'] as String,
    createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
    month: switch (map['month']) {
      final String month => DateTime.parse(month),
      _ => null,
    },
    fundraiserId: map['fundraiser_id'] as String?,
    fundraiserTitle: map['fundraiser'] as String?,
    mine: map['mine'] as bool? ?? false,
    status: ReceiptStatus.values.byName(map['status'] as String),
    note: map['note'] as String?,
  );

  final String id;
  final bool isDues;
  final String payer;
  final String imagePath;
  final DateTime createdAt;
  final DateTime? month;
  final String? fundraiserId;
  final String? fundraiserTitle;
  final bool mine;
  final ReceiptStatus status;

  /// Motivo da recusa.
  final String? note;
}
