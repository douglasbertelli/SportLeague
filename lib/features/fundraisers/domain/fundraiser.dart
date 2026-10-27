import 'package:intl/intl.dart';

import '../../athletes/domain/athlete.dart';
import '../../teams/domain/team.dart';

/// Argumentos das telas da vaquinha: o time e a vaquinha (nula ao criar).
typedef FundraiserArgs = ({Team team, Fundraiser? fundraiser});

/// O que a vaquinha vai comprar.
enum FundraiserItem {
  ball('Bola'),
  bib('Colete'),
  kit('Uniforme'),
  other('Outros');

  const FundraiserItem(this.label);

  final String label;

  static FundraiserItem fromName(String value) =>
      values.firstWhere((item) => item.name == value);
}

/// Como o administrador informa o valor da vaquinha.
enum AmountType {
  /// Cada pessoa paga o valor digitado.
  perPerson('per_person', 'Valor por pessoa'),

  /// O valor digitado é o total do produto, dividido entre as pessoas.
  total('total', 'Valor total');

  const AmountType(this.dbName, this.label);

  final String dbName;
  final String label;

  static AmountType fromDbName(String? value) => values.firstWhere(
    (type) => type.dbName == value,
    orElse: () => perPerson,
  );
}

/// Vaquinha do time: o dono define o valor (por pessoa ou o total, dividido)
/// e marca quem pagou.
class Fundraiser {
  const Fundraiser({
    this.id,
    required this.teamId,
    required this.item,
    this.description,
    required this.amountCents,
    this.amountType = AmountType.perPerson,
    this.closed = false,
    this.createdAt,
  });

  factory Fundraiser.fromMap(Map<String, dynamic> map) => Fundraiser(
    id: map['id'] as String,
    teamId: map['team_id'] as String,
    item: FundraiserItem.fromName(map['item'] as String),
    description: map['description'] as String?,
    amountCents: map['amount_cents'] as int,
    amountType: AmountType.fromDbName(map['amount_type'] as String?),
    closed: map['closed'] as bool,
    createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
  );

  final String? id;
  final String teamId;
  final FundraiserItem item;

  /// O que vai ser comprado, em "Outros".
  final String? description;

  /// Valor digitado, em centavos: o de cada pessoa ou o total do produto
  /// ([amountType]).
  final int amountCents;
  final AmountType amountType;

  /// Quanto cada um dos [people] paga. No valor total, a divisão arredonda
  /// o centavo para cima, para o total ser alcançado.
  int shareCents(int people) => switch (amountType) {
    AmountType.perPerson => amountCents,
    AmountType.total => people <= 0 ? amountCents : (amountCents / people).ceil(),
  };

  /// Quanto a vaquinha junta quando todos os [people] pagam.
  int goalCents(int people) => switch (amountType) {
    AmountType.perPerson => amountCents * people,
    AmountType.total => amountCents,
  };

  /// Encerrada: sai da lista das abertas e não muda mais.
  final bool closed;
  final DateTime? createdAt;

  /// "Bola", ou o texto digitado em "Outros".
  String get title => switch (item) {
    FundraiserItem.other => description ?? item.label,
    _ => item.label,
  };

  Map<String, dynamic> toMap() => {
    'team_id': teamId,
    'item': item.name,
    'description': item == FundraiserItem.other ? description?.trim() : null,
    'amount_cents': amountCents,
    'amount_type': amountType.dbName,
    'closed': closed,
  };

  Fundraiser copyWith({bool? closed}) => Fundraiser(
    id: id,
    teamId: teamId,
    item: item,
    description: description,
    amountCents: amountCents,
    amountType: amountType,
    closed: closed ?? this.closed,
    createdAt: createdAt,
  );
}

/// Quem paga a vaquinha: um atleta do time ou o administrador (dono).
class FundraiserParticipant {
  const FundraiserParticipant({
    this.athleteId,
    this.profileId,
    required this.name,
    this.photoUrl,
    this.subtitle,
  }) : assert((athleteId == null) != (profileId == null));

  /// Atleta do time; nulo para o administrador.
  final String? athleteId;

  /// Perfil do administrador; nulo para os atletas.
  final String? profileId;
  final String name;
  final String? photoUrl;

  /// "Administrador", posição do atleta etc.
  final String? subtitle;

  /// Identifica o participante nos pagamentos.
  String get key => athleteId ?? 'profile:$profileId';
}

/// Pagamentos da vaquinha: a chave ([FundraiserParticipant.key]) de quem
/// pagou.
typedef FundraiserPayments = Set<String>;

/// Quantas pessoas pagam: os atletas do time e o administrador, que conta
/// uma vez só se também for atleta.
int fundraiserPeople(List<Athlete> athletes, String ownerId) =>
    athletes.length +
    (athletes.any((athlete) => athlete.profileId == ownerId) ? 0 : 1);

final _currency = NumberFormat.currency(
  locale: 'pt_BR',
  symbol: r'R$',
  decimalDigits: 2,
);

/// "R$ 25,00".
String formatMoney(int cents) => _currency.format(cents / 100);

/// Lê "25", "25,5", "1.250,00" ou "R$ 25,00" em centavos. Nulo se não for
/// um valor.
int? parseMoney(String text) {
  var value = text.replaceAll(r'R$', '').replaceAll(RegExp(r'\s'), '');
  if (value.isEmpty) return null;
  if (value.contains(',')) {
    value = value.replaceAll('.', '').replaceAll(',', '.');
  }
  final parsed = double.tryParse(value);
  if (parsed == null || parsed.isNaN || parsed.isInfinite) return null;
  return (parsed * 100).round();
}
