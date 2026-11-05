import 'package:flutter_test/flutter_test.dart';
import 'package:sport_league/features/plans/domain/plan_status.dart';
import 'package:sport_league/features/profile/domain/profile.dart';

void main() {
  final free = PlanStatus.fromMap({
    'plan': 'free',
    'quotas': {
      'teams': 1,
      'championships': 1,
      'advanced_formats': 0,
      'dues': 0,
      // Funcionalidade que esta versão do app não conhece: ignorada.
      'future_thing': 3,
    },
    'usage': {'teams': 1, 'championships': 0},
  });

  test('lê o plano, os limites e o uso', () {
    expect(free.plan, SubscriptionPlan.free);
    expect(free.quota(PlanFeature.teams), 1);
    expect(free.quotas.length, 4);
  });

  test('limite zero bloqueia; limite atingido impede criar mais', () {
    expect(free.has(PlanFeature.dues), isFalse);
    expect(free.has(PlanFeature.advancedFormats), isFalse);
    expect(free.has(PlanFeature.teams), isTrue);
    expect(free.canAdd(PlanFeature.teams), isFalse);
    expect(free.canAdd(PlanFeature.championships), isTrue);
  });

  test('sem limite (nulo ou sem linha) libera tudo', () {
    final premium = PlanStatus.fromMap({
      'plan': 'premium',
      'quotas': {'teams': 5, 'championships': null},
      'usage': {'teams': 4, 'championships': 30},
    });
    expect(premium.canAdd(PlanFeature.teams), isTrue);
    expect(premium.canAdd(PlanFeature.championships), isTrue);
    expect(premium.has(PlanFeature.dues), isTrue);
    expect(PlanStatus.unrestricted.canAdd(PlanFeature.teams), isTrue);
  });

  test('descreve os limites', () {
    expect(describeQuota(PlanFeature.teams, 1), '1 time');
    expect(describeQuota(PlanFeature.teams, 5), '5 times');
    expect(describeQuota(PlanFeature.championships, null), 'Ilimitado');
    expect(describeQuota(PlanFeature.dues, 0), 'Não incluso');
    expect(describeQuota(PlanFeature.dues, null), 'Incluso');
  });

  test('reconhece o erro de limite do banco', () {
    expect(
      planLimitFeature('PostgrestException(message: plan_limit:dues, ...)'),
      PlanFeature.dues,
    );
    expect(
      planLimitFeature('plan_limit:advanced_formats'),
      PlanFeature.advancedFormats,
    );
    expect(planLimitFeature('outro erro'), isNull);
  });

  test('teste do Premium: vale o Premium, assinado o Gratuito', () {
    final trial = PlanStatus.fromMap({
      'plan': 'premium',
      'paid_plan': 'free',
      'trial_ends_at': '2026-11-20T12:00:00Z',
      'trial_available': false,
      'quotas': {'dues': null},
    });
    expect(trial.plan, SubscriptionPlan.premium);
    expect(trial.paidPlan, SubscriptionPlan.free);
    expect(trial.onTrial, isTrue);
    expect(trial.has(PlanFeature.dues), isTrue);
    expect(free.onTrial, isFalse);
    expect(free.trialAvailable, isFalse);
  });

  test('preço: R\$ 30 com 1 time e R\$ 10 por time a mais', () {
    final premium = PlanPrice.fromMap({
      'plan': 'premium',
      'monthly_cents': 3000,
      'extra_team_cents': 1000,
      'trial_days': 15,
    });
    expect(premium.totalFor(0), 3000);
    expect(premium.totalFor(1), 3000);
    expect(premium.totalFor(4), 6000);
    expect(premium.trialDays, 15);
    expect(premium.isFree, isFalse);
    expect(
      PlanPrice.fromMap({
        'plan': 'free',
        'monthly_cents': 0,
        'extra_team_cents': 0,
        'trial_days': null,
      }).isFree,
      isTrue,
    );
  });
}
