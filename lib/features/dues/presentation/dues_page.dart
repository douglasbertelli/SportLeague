import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/empty_state.dart';
import '../../athletes/data/athlete_repository.dart';
import '../../athletes/domain/athlete.dart';
import '../../fundraisers/domain/fundraiser.dart' show formatMoney, parseMoney;
import '../../fundraisers/presentation/fundraisers_page.dart'
    show fundraiserTeamsProvider;
import '../../games/presentation/game_sheet_page.dart' show AthleteAvatar;
import '../../plans/data/plan_repository.dart';
import '../../plans/domain/plan_status.dart';
import '../../plans/presentation/plan_gate.dart';
import '../../teams/data/team_repository.dart';
import '../../teams/domain/team.dart';
import '../../teams/presentation/team_logo.dart';
import '../data/dues_repository.dart';
import '../domain/team_dues.dart';

/// Mensalidade do time. Abre no time ativo; quem está em mais de um time
/// troca pelos chips do topo. O administrador (dono) configura o valor, o
/// vencimento e a chave PIX e marca quem pagou cada mês; o técnico e os
/// atletas acompanham.
class DuesPage extends ConsumerStatefulWidget {
  const DuesPage({super.key, this.today});

  /// "Hoje" (para os testes); nulo usa o relógio.
  final DateTime? today;

  @override
  ConsumerState<DuesPage> createState() => _DuesPageState();
}

class _DuesPageState extends ConsumerState<DuesPage> {
  String? _teamId;

  @override
  Widget build(BuildContext context) {
    final teams = ref.watch(fundraiserTeamsProvider);
    final selectedId = ref.watch(selectedTeamProvider).value?.id;

    return Scaffold(
      appBar: AppBar(title: const Text('Mensalidade')),
      body: teams.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: TextButton.icon(
            onPressed: () => ref.invalidate(fundraiserTeamsProvider),
            icon: const Icon(Icons.refresh),
            label: const Text('Erro ao carregar os times. Tentar novamente'),
          ),
        ),
        data: (teams) {
          if (teams.isEmpty) {
            return const EmptyState(
              icon: Icons.payments_outlined,
              title: 'Nenhum time',
              message: 'A mensalidade fica no time. Entre num time para ver.',
            );
          }
          final team =
              teams.where((team) => team.id == _teamId).firstOrNull ??
              teams.where((team) => team.id == selectedId).firstOrNull ??
              teams.first;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (teams.length > 1)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: [
                      for (final option in teams)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            avatar: TeamLogo(team: option, radius: 12),
                            label: Text(option.name),
                            selected: option.id == team.id,
                            onSelected: (_) =>
                                setState(() => _teamId = option.id),
                          ),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: _TeamDues(
                  key: ValueKey(team.id),
                  team: team,
                  today: widget.today ?? DateTime.now(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TeamDues extends ConsumerStatefulWidget {
  const _TeamDues({super.key, required this.team, required this.today});

  final Team team;
  final DateTime today;

  @override
  ConsumerState<_TeamDues> createState() => _TeamDuesState();
}

class _TeamDuesState extends ConsumerState<_TeamDues> {
  /// Mês na tela; nulo = o mês atual.
  DateTime? _month;

  /// Atletas com o pagamento sendo salvo.
  final _saving = <String>{};

  String get _teamId => widget.team.id!;

  Future<void> _configure(TeamDues? current) async {
    final saved = await showDuesForm(
      context,
      ref,
      teamId: _teamId,
      current: current,
    );
    if (saved) ref.invalidate(teamDuesProvider(_teamId));
  }

  Future<void> _remove() async {
    final confirmed = await confirmDelete(
      context,
      title: 'Parar de cobrar?',
      message:
          'A mensalidade do ${widget.team.name} e os pagamentos marcados '
          'serão apagados.',
    );
    if (!confirmed) return;
    try {
      await ref.read(duesRepositoryProvider).delete(_teamId);
      ref
        ..invalidate(teamDuesProvider(_teamId))
        ..invalidate(duePaymentsProvider(_teamId));
    } catch (error) {
      if (mounted) showErrorSnackBar(context, friendlyErrorMessage(error));
    }
  }

  Future<void> _setPaid(Athlete athlete, DateTime month, bool paid) async {
    setState(() => _saving.add(athlete.id!));
    try {
      await ref
          .read(duesRepositoryProvider)
          .setPaid(
            teamId: _teamId,
            athleteId: athlete.id!,
            month: month,
            paid: paid,
          );
      ref.invalidate(duePaymentsProvider(_teamId));
      await ref.read(duePaymentsProvider(_teamId).future);
    } catch (error) {
      if (mounted) showErrorSnackBar(context, friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving.remove(athlete.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOwner = widget.team.ownerId == ref.watch(currentUserIdProvider);
    // O plano do dono não libera a mensalidade: o que existe continua
    // visível, mas configurar e marcar pagamentos fica bloqueado.
    final locked =
        isOwner &&
        !(ref.watch(planStatusProvider).value ?? PlanStatus.unrestricted).has(
          PlanFeature.dues,
        );
    final dues = ref.watch(teamDuesProvider(_teamId));
    final athletes = ref.watch(teamAthletesProvider(_teamId));
    final payments = ref.watch(duePaymentsProvider(_teamId));

    void retry() => ref
      ..invalidate(teamDuesProvider(_teamId))
      ..invalidate(teamAthletesProvider(_teamId))
      ..invalidate(duePaymentsProvider(_teamId));

    return switch ((dues, athletes, payments)) {
      (AsyncValue(hasError: true), _, _) ||
      (_, AsyncValue(hasError: true), _) ||
      (_, _, AsyncValue(hasError: true)) => Center(
        child: TextButton.icon(
          onPressed: retry,
          icon: const Icon(Icons.refresh),
          label: const Text('Erro ao carregar. Tentar novamente'),
        ),
      ),
      (AsyncData(value: null), _, _) => EmptyState(
        icon: Icons.payments_outlined,
        title: 'Sem mensalidade',
        message: isOwner
            ? 'Cobre um valor por mês dos atletas e marque quem pagou. '
                  'Quem não pagou recebe lembrete no vencimento.'
                  '${locked ? '\n\nRecurso do plano Premium.' : ''}'
            : 'Quando o administrador configurar a mensalidade do time, ela '
                  'aparece aqui.',
        action: isOwner
            ? FilledButton.icon(
                onPressed: locked
                    ? () => showPremiumSheet(context, PlanFeature.dues)
                    : () => _configure(null),
                icon: Icon(
                  locked ? Icons.workspace_premium_outlined : Icons.add,
                ),
                label: const Text('Configurar mensalidade'),
              )
            : null,
      ),
      (
        AsyncData(value: final dues?),
        AsyncData(value: final athletes),
        AsyncData(value: final payments),
      ) =>
        _content(dues, athletes, payments, isOwner: isOwner, locked: locked),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }

  Widget _content(
    TeamDues dues,
    List<Athlete> athletes,
    DuePayments payments, {
    required bool isOwner,
    required bool locked,
  }) {
    void premium() => showPremiumSheet(context, PlanFeature.dues);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final months = dues.monthsUntil(widget.today);
    final month = months.contains(_month) ? _month! : months.last;
    final index = months.indexOf(month);
    bool paid(Athlete athlete, DateTime month) =>
        payments.contains(duePaymentKey(athlete.id!, month));

    final paidCount = athletes.where((a) => paid(a, month)).length;
    final expected = athletes.length * dues.amountCents;
    final raised = paidCount * dues.amountCents;

    // O atleta logado (se for atleta do time): os meses que ele deve.
    final userId = ref.watch(currentUserIdProvider);
    final me = athletes.where((a) => a.profileId == userId).firstOrNull;
    final myOpen = me == null
        ? const <DateTime>[]
        : [
            for (final m in months)
              if (!paid(me, m) && dues.isLate(m, widget.today)) m,
          ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Icon(Icons.payments_outlined, color: colors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${formatMoney(dues.amountCents)} por mês',
                        style: theme.textTheme.titleMedium,
                      ),
                      Text(
                        'Vence todo dia ${dues.dueDay}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      if (dues.pixKey case final pix?) ...[
                        const SizedBox(height: 8),
                        _PixKey(pix: pix),
                      ],
                    ],
                  ),
                ),
                if (isOwner)
                  PopupMenuButton<bool>(
                    tooltip: 'Ações da mensalidade',
                    onSelected: (edit) => edit
                        ? (locked ? premium() : _configure(dues))
                        : _remove(),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: true, child: Text('Editar')),
                      PopupMenuItem(
                        value: false,
                        child: Text('Parar de cobrar'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        if (locked) ...[
          const SizedBox(height: 8),
          Card(
            color: colors.tertiaryContainer,
            child: ListTile(
              leading: Icon(
                Icons.workspace_premium_outlined,
                color: colors.onTertiaryContainer,
              ),
              title: const Text('Mensalidade pausada'),
              subtitle: const Text(
                'A mensalidade é do plano Premium. Os pagamentos continuam '
                'aqui, mas marcar, editar e os lembretes estão pausados.',
              ),
              textColor: colors.onTertiaryContainer,
              onTap: () => context.push(Routes.plans),
            ),
          ),
        ],
        if (me != null) ...[
          const SizedBox(height: 8),
          Card(
            color: myOpen.isEmpty
                ? colors.secondaryContainer
                : colors.errorContainer,
            child: ListTile(
              leading: Icon(
                myOpen.isEmpty ? Icons.check_circle_outline : Icons.warning,
                color: myOpen.isEmpty
                    ? colors.onSecondaryContainer
                    : colors.onErrorContainer,
              ),
              title: Text(
                myOpen.isEmpty
                    ? 'Sua mensalidade está em dia'
                    : myOpen.length == 1
                    ? 'Você tem 1 mês em atraso'
                    : 'Você tem ${myOpen.length} meses em atraso',
              ),
              subtitle: myOpen.isEmpty
                  ? null
                  : Text(myOpen.map(monthName).join(', ')),
              textColor: myOpen.isEmpty
                  ? colors.onSecondaryContainer
                  : colors.onErrorContainer,
            ),
          ),
        ],
        const SizedBox(height: 16),
        // Mês na tela, com as setas para os anteriores.
        Row(
          children: [
            IconButton(
              tooltip: 'Mês anterior',
              onPressed: index > 0
                  ? () => setState(() => _month = months[index - 1])
                  : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                formatMonth(month),
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
            ),
            IconButton(
              tooltip: 'Próximo mês',
              onPressed: index < months.length - 1
                  ? () => setState(() => _month = months[index + 1])
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text('Arrecadado no mês', style: theme.textTheme.bodyMedium),
        Text(
          formatMoney(raised),
          style: theme.textTheme.headlineMedium?.copyWith(
            color: colors.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          'de ${formatMoney(expected)} · $paidCount de ${athletes.length} '
          'pagaram',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: expected == 0 ? 0 : raised / expected,
            minHeight: 8,
          ),
        ),
        const SizedBox(height: 24),
        if (athletes.isEmpty)
          Text(
            'O time ainda não tem atletas.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        for (final athlete in athletes)
          _AthleteDueTile(
            athlete: athlete,
            isMe: athlete.id == me?.id,
            status: paid(athlete, month)
                ? _DueStatus.paid
                : dues.isLate(month, widget.today)
                ? _DueStatus.late
                : _DueStatus.open,
            saving: _saving.contains(athlete.id),
            onChanged: !isOwner
                ? null
                : locked
                ? (_) => premium()
                : (value) => _setPaid(athlete, month, value),
          ),
      ],
    );
  }
}

/// A chave PIX com o botão de copiar.
class _PixKey extends StatelessWidget {
  const _PixKey({required this.pix});

  final String pix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'PIX: ',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
                TextSpan(text: pix),
              ],
            ),
            style: theme.textTheme.bodyMedium,
          ),
        ),
        IconButton(
          tooltip: 'Copiar chave PIX',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.copy, size: 18),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: pix));
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  const SnackBar(content: Text('Chave PIX copiada')),
                );
            }
          },
        ),
      ],
    );
  }
}

enum _DueStatus {
  paid('Pago'),
  open('Em aberto'),
  late('Atrasado');

  const _DueStatus(this.label);

  final String label;
}

class _AthleteDueTile extends StatelessWidget {
  const _AthleteDueTile({
    required this.athlete,
    required this.isMe,
    required this.status,
    required this.saving,
    required this.onChanged,
  });

  final Athlete athlete;
  final bool isMe;
  final _DueStatus status;
  final bool saving;

  /// Nulo para quem só acompanha: mostra a situação.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final onChanged = this.onChanged;
    final paid = status == _DueStatus.paid;
    final subtitle = [
      if (isMe) 'Você',
      if (athlete.jerseyNumber case final number?) 'Nº $number',
      ?athlete.position,
    ].join(' · ');

    return Card(
      child: ListTile(
        leading: AthleteAvatar(
          name: athlete.displayName,
          photoUrl: athlete.photoUrl,
        ),
        title: Text(athlete.displayName),
        subtitle: subtitle.isEmpty ? null : Text(subtitle),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              status.label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: switch (status) {
                  _DueStatus.paid => colors.primary,
                  _DueStatus.late => colors.error,
                  _DueStatus.open => colors.onSurfaceVariant,
                },
              ),
            ),
            if (onChanged != null) ...[
              const SizedBox(width: 8),
              Switch(value: paid, onChanged: saving ? null : onChanged),
            ],
          ],
        ),
        onTap: onChanged == null || saving ? null : () => onChanged(!paid),
      ),
    );
  }
}

/// Configura (ou edita) a mensalidade num bottom sheet: o valor, o dia do
/// vencimento e a chave PIX. `true` se salvou.
Future<bool> showDuesForm(
  BuildContext context,
  WidgetRef ref, {
  required String teamId,
  TeamDues? current,
}) async {
  final saved = await showAppSheet<bool>(
    context,
    builder: (_) => _DuesForm(teamId: teamId, current: current),
  );
  return saved ?? false;
}

class _DuesForm extends ConsumerStatefulWidget {
  const _DuesForm({required this.teamId, this.current});

  final String teamId;
  final TeamDues? current;

  @override
  ConsumerState<_DuesForm> createState() => _DuesFormState();
}

class _DuesFormState extends ConsumerState<_DuesForm> {
  final _formKey = GlobalKey<FormState>();
  late final _amount = TextEditingController(
    text: switch (widget.current?.amountCents) {
      final cents? => formatMoney(cents).replaceAll(r'R$', '').trim(),
      null => '',
    },
  );
  late final _pix = TextEditingController(text: widget.current?.pixKey);
  late var _dueDay = widget.current?.dueDay ?? 10;
  var _loading = false;

  @override
  void dispose() {
    _amount.dispose();
    _pix.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ref
          .read(duesRepositoryProvider)
          .save(
            TeamDues(
              teamId: widget.teamId,
              amountCents: parseMoney(_amount.text)!,
              dueDay: _dueDay,
              pixKey: _pix.text,
            ),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) showErrorSnackBar(context, friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: AppSheet(
        title: widget.current == null
            ? 'Configurar mensalidade'
            : 'Editar mensalidade',
        message: 'Cada atleta do time paga esse valor por mês.',
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _amount,
              decoration: const InputDecoration(
                labelText: 'Valor por mês',
                prefixText: r'R$ ',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (value) => switch (parseMoney(value ?? '')) {
                null => 'Informe o valor',
                <= 0 => 'O valor precisa ser maior que zero',
                _ => null,
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: _dueDay,
              decoration: const InputDecoration(
                labelText: 'Dia do vencimento',
                helperText: 'Até o dia 28, que existe em todos os meses',
              ),
              items: [
                for (var day = 1; day <= 28; day++)
                  DropdownMenuItem(value: day, child: Text('Dia $day')),
              ],
              onChanged: (day) => setState(() => _dueDay = day ?? _dueDay),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _pix,
              decoration: const InputDecoration(
                labelText: 'Chave PIX (opcional)',
                helperText: 'Aparece para os atletas copiarem',
              ),
              maxLength: 120,
            ),
          ],
        ),
        actions: [
          FilledButton.icon(
            onPressed: _loading ? null : _save,
            icon: _loading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: const Text('Salvar'),
          ),
          const SheetBackButton(),
        ],
      ),
    );
  }
}
