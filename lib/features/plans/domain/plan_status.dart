import '../../fundraisers/domain/fundraiser.dart' show formatMoney;
import '../../profile/domain/profile.dart';

/// Funcionalidades que dependem do plano. A chave é a da tabela
/// `plan_features` do banco, onde ficam os limites de cada plano.
enum PlanFeature {
  teams(
    'teams',
    'Times',
    'Times na sua conta, cada um com elenco, jogos, escalação, '
        'estatísticas e convites',
  ),
  championships(
    'championships',
    'Campeonatos',
    'Organizar campeonatos de pontos corridos, mata-mata ou grupos + '
        'mata-mata',
  ),
  dues('dues', 'Mensalidade', 'Controle da mensalidade com lembretes');

  const PlanFeature(this.key, this.label, this.description);

  final String key;
  final String label;
  final String description;

  static PlanFeature? fromKey(String key) =>
      values.where((feature) => feature.key == key).firstOrNull;
}

/// Limite de uma funcionalidade: nulo = sem limite, 0 = bloqueada.
typedef Quota = int?;

/// Plano do usuário, os limites dele e quanto já usa.
class PlanStatus {
  const PlanStatus({
    required this.plan,
    this.paidPlan,
    this.trialEndsAt,
    this.trialAvailable = false,
    this.quotas = const {},
    this.usage = const {},
  });

  factory PlanStatus.fromMap(Map<String, dynamic> map) {
    final quotas = <PlanFeature, Quota>{};
    (map['quotas'] as Map<String, dynamic>? ?? {}).forEach((key, value) {
      final feature = PlanFeature.fromKey(key);
      if (feature != null) quotas[feature] = (value as num?)?.toInt();
    });
    final usage = <PlanFeature, int>{};
    (map['usage'] as Map<String, dynamic>? ?? {}).forEach((key, value) {
      final feature = PlanFeature.fromKey(key);
      if (feature != null) usage[feature] = (value as num).toInt();
    });
    return PlanStatus(
      plan: SubscriptionPlan.fromName(map['plan'] as String),
      paidPlan: switch (map['paid_plan']) {
        final String name => SubscriptionPlan.fromName(name),
        _ => null,
      },
      trialEndsAt: switch (map['trial_ends_at']) {
        final String at => DateTime.parse(at).toLocal(),
        _ => null,
      },
      trialAvailable: map['trial_available'] == true,
      quotas: quotas,
      usage: usage,
    );
  }

  /// Sem restrição (enquanto carrega ou para quem não tem plano): o banco
  /// continua barrando o que não for permitido.
  static const unrestricted = PlanStatus(plan: SubscriptionPlan.free);

  /// O plano que vale agora (o Premium durante o teste).
  final SubscriptionPlan plan;

  /// O plano assinado (o Gratuito durante o teste).
  final SubscriptionPlan? paidPlan;

  /// Fim do teste do Premium em andamento.
  final DateTime? trialEndsAt;

  /// Ainda pode começar o teste (uma vez por conta).
  final bool trialAvailable;

  bool get onTrial => trialEndsAt != null;

  /// Sem chave = sem limite.
  final Map<PlanFeature, Quota> quotas;
  final Map<PlanFeature, int> usage;

  Quota quota(PlanFeature feature) => quotas[feature];

  /// A funcionalidade está liberada (o limite não é zero).
  bool has(PlanFeature feature) => (quota(feature) ?? 1) > 0;

  /// Ainda dá para criar mais um (times, campeonatos).
  bool canAdd(PlanFeature feature) {
    final limit = quota(feature);
    return limit == null || (usage[feature] ?? 0) < limit;
  }
}

/// Linha da tabela de planos (para a comparação).
class PlanFeatureRow {
  const PlanFeatureRow({
    required this.plan,
    required this.feature,
    required this.quota,
    this.description,
  });

  factory PlanFeatureRow.fromMap(Map<String, dynamic> map) => PlanFeatureRow(
    plan: SubscriptionPlan.fromName(map['plan'] as String),
    feature: PlanFeature.fromKey(map['feature'] as String),
    quota: (map['quota'] as num?)?.toInt(),
    description: map['description'] as String?,
  );

  final SubscriptionPlan plan;

  /// Nulo quando o banco tem uma funcionalidade que esta versão não conhece.
  final PlanFeature? feature;
  final Quota quota;

  /// Texto deste plano; nulo usa o texto padrão da funcionalidade.
  final String? description;
}

/// "Ilimitado", "Não incluso", "1 time"…
/// Times sem limite mostram o preço de cada time a mais ([extraTeamCents]),
/// para não parecer que mais times saem de graça.
String describeQuota(
  PlanFeature feature,
  Quota quota, {
  int extraTeamCents = 0,
}) {
  if (quota == 0) return 'Não incluso';
  return switch (feature) {
    PlanFeature.teams when quota != null =>
      quota == 1 ? '1 time' : '$quota times',
    PlanFeature.teams when extraTeamCents > 0 =>
      '+ ${formatMoney(extraTeamCents)}\npor time',
    PlanFeature.teams => 'Vários times',
    PlanFeature.championships when quota != null =>
      quota == 1 ? '1 por vez' : '$quota por vez',
    PlanFeature.championships => 'Ilimitado',
    _ => quota == null ? 'Incluso' : 'Até $quota',
  };
}

/// Mensagem quando o limite do plano é atingido.
String planLimitMessage(PlanFeature feature, Quota quota) => switch (feature) {
  PlanFeature.teams =>
    'Seu plano permite ${describeQuota(feature, quota).toLowerCase()}. '
        'Com o Premium você organiza mais times na mesma conta.',
  PlanFeature.championships when quota != null && quota > 0 =>
    'Seu plano permite '
        '${quota == 1 ? '1 campeonato' : '$quota campeonatos'} em andamento '
        'por vez. Finalize um ou passe para o Premium para ter mais.',
  PlanFeature.championships =>
    'Organizar campeonatos (pontos corridos, mata-mata ou grupos + '
        'mata-mata) é do plano Premium. Seu time continua participando dos '
        'campeonatos para os quais for convidado.',
  PlanFeature.dues =>
    'O controle da mensalidade, com lembretes automáticos para quem não '
        'pagou, é do plano Premium.',
};

/// Funcionalidade do erro `plan_limit:<chave>` que o banco devolve.
PlanFeature? planLimitFeature(String message) {
  final match = RegExp(r'plan_limit:([a-z_]+)').firstMatch(message);
  return match == null ? null : PlanFeature.fromKey(match.group(1)!);
}

/// Preço e teste grátis de um plano (tabela `plans`).
class PlanPrice {
  const PlanPrice({
    required this.plan,
    this.monthlyCents = 0,
    this.extraTeamCents = 0,
    this.trialDays,
  });

  factory PlanPrice.fromMap(Map<String, dynamic> map) => PlanPrice(
    plan: SubscriptionPlan.fromName(map['plan'] as String),
    monthlyCents: (map['monthly_cents'] as num).toInt(),
    extraTeamCents: (map['extra_team_cents'] as num).toInt(),
    trialDays: (map['trial_days'] as num?)?.toInt(),
  );

  final SubscriptionPlan plan;

  /// Mensalidade com o primeiro time.
  final int monthlyCents;

  /// Cada time a mais.
  final int extraTeamCents;

  /// Dias do teste grátis; nulo = sem teste.
  final int? trialDays;

  bool get isFree => monthlyCents == 0 && extraTeamCents == 0;

  /// Total por mês com [teams] times (o primeiro já está na mensalidade).
  int totalFor(int teams) =>
      monthlyCents + extraTeamCents * (teams > 1 ? teams - 1 : 0);
}
