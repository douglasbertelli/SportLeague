import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../athletes/data/athlete_repository.dart';
import '../../games/presentation/game_sheet_page.dart';
import '../../teams/domain/team.dart';
import '../data/fundraiser_repository.dart';
import '../domain/fundraiser.dart';
import 'fundraisers_page.dart';

/// Uma vaquinha: valor por pessoa, total arrecadado e a lista do
/// administrador e dos atletas com "Pago: sim ou não". Só o administrador
/// (dono do time) marca os pagamentos, edita, encerra e exclui.
class FundraiserPage extends ConsumerStatefulWidget {
  const FundraiserPage({
    super.key,
    required this.team,
    required this.fundraiser,
  });

  final Team team;
  final Fundraiser fundraiser;

  @override
  ConsumerState<FundraiserPage> createState() => _FundraiserPageState();
}

enum _Action { edit, close, reopen, delete }

class _FundraiserPageState extends ConsumerState<FundraiserPage> {
  /// Participantes com o pagamento sendo salvo.
  final _saving = <String>{};

  /// A versão mais nova (depois de editar ou encerrar).
  Fundraiser get _fundraiser =>
      ref
          .watch(teamFundraisersProvider(widget.team.id!))
          .value
          ?.where((fundraiser) => fundraiser.id == widget.fundraiser.id)
          .firstOrNull ??
      widget.fundraiser;

  Future<void> _setPaid(FundraiserParticipant participant, bool paid) async {
    final id = widget.fundraiser.id!;
    setState(() => _saving.add(participant.key));
    try {
      await ref
          .read(fundraiserRepositoryProvider)
          .setPaid(id, participant, paid: paid);
      ref.invalidate(fundraiserPaymentsProvider(id));
      await ref.read(fundraiserPaymentsProvider(id).future);
    } catch (error) {
      if (mounted) showErrorSnackBar(context, friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving.remove(participant.key));
    }
  }

  Future<void> _run(_Action action) async {
    final fundraiser = _fundraiser;
    final repository = ref.read(fundraiserRepositoryProvider);
    switch (action) {
      case _Action.edit:
        await context.push(
          Routes.fundraiserForm,
          extra: (team: widget.team, fundraiser: fundraiser),
        );
        return;
      case _Action.delete:
        final confirmed = await confirmDelete(
          context,
          title: 'Excluir vaquinha?',
          message:
              'A vaquinha "${fundraiser.title}" e os pagamentos marcados '
              'serão apagados.',
        );
        if (!confirmed) return;
      case _Action.close || _Action.reopen:
        break;
    }
    try {
      if (action == _Action.delete) {
        await repository.delete(fundraiser.id!);
      } else {
        await repository.update(
          fundraiser.copyWith(closed: action == _Action.close),
        );
      }
      ref.invalidate(teamFundraisersProvider(widget.team.id!));
      if (action == _Action.delete && mounted) context.pop();
    } catch (error) {
      if (mounted) showErrorSnackBar(context, friendlyErrorMessage(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final fundraiser = _fundraiser;
    final isOwner = widget.team.ownerId == ref.watch(currentUserIdProvider);
    final athletes = ref.watch(teamAthletesProvider(widget.team.id!));
    final owner = ref.watch(teamOwnerProvider(widget.team.ownerId));
    final payments = ref.watch(fundraiserPaymentsProvider(fundraiser.id!));

    return Scaffold(
      appBar: AppBar(
        title: Text(fundraiser.title),
        actions: [
          if (isOwner)
            PopupMenuButton<_Action>(
              tooltip: 'Ações da vaquinha',
              onSelected: _run,
              itemBuilder: (_) => [
                const PopupMenuItem(value: _Action.edit, child: Text('Editar')),
                if (fundraiser.closed)
                  const PopupMenuItem(
                    value: _Action.reopen,
                    child: Text('Reabrir'),
                  )
                else
                  const PopupMenuItem(
                    value: _Action.close,
                    child: Text('Encerrar'),
                  ),
                const PopupMenuItem(
                  value: _Action.delete,
                  child: Text('Excluir'),
                ),
              ],
            ),
        ],
      ),
      body: switch ((athletes, owner, payments)) {
        (
          AsyncValue(value: final athletes?),
          AsyncValue(value: final owner?),
          AsyncValue(value: final payments?),
        ) =>
          _content(
            context,
            fundraiser: fundraiser,
            isOwner: isOwner,
            payments: payments,
            participants: [
              // O administrador primeiro; se ele também é atleta, aparece
              // uma vez só, como atleta.
              if (!athletes.any((a) => a.profileId == widget.team.ownerId))
                FundraiserParticipant(
                  profileId: widget.team.ownerId,
                  name: owner.name,
                  photoUrl: owner.photoUrl,
                  subtitle: 'Administrador',
                ),
              for (final athlete in athletes)
                FundraiserParticipant(
                  athleteId: athlete.id,
                  name: athlete.displayName,
                  photoUrl: athlete.photoUrl,
                  subtitle: [
                    if (athlete.profileId == widget.team.ownerId)
                      'Administrador',
                    if (athlete.jerseyNumber case final number?) 'Nº $number',
                    ?athlete.position,
                  ].join(' · '),
                ),
            ],
          ),
        (AsyncValue(hasError: true), _, _) ||
        (_, AsyncValue(hasError: true), _) ||
        (_, _, AsyncValue(hasError: true)) => Center(
          child: TextButton.icon(
            onPressed: () => ref
              ..invalidate(teamAthletesProvider(widget.team.id!))
              ..invalidate(teamOwnerProvider(widget.team.ownerId))
              ..invalidate(fundraiserPaymentsProvider(fundraiser.id!)),
            icon: const Icon(Icons.refresh),
            label: const Text('Erro ao carregar. Tentar novamente'),
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _content(
    BuildContext context, {
    required Fundraiser fundraiser,
    required bool isOwner,
    required FundraiserPayments payments,
    required List<FundraiserParticipant> participants,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final paidCount = participants
        .where((participant) => payments.contains(participant.key))
        .length;
    final people = participants.length;
    final share = fundraiser.shareCents(people);
    // No valor total, o arredondamento da divisão pode passar uns centavos.
    final raised = paidCount * share;
    final expected = fundraiser.goalCents(people);
    final canMark = isOwner && !fundraiser.closed;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      fundraiserIcon(fundraiser.item),
                      color: colors.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${formatMoney(share)} por pessoa',
                            style: theme.textTheme.titleMedium,
                          ),
                          if (fundraiser.amountType == AmountType.total)
                            Text(
                              'Total de ${formatMoney(fundraiser.amountCents)} '
                              'dividido por $people '
                              '${people == 1 ? 'pessoa' : 'pessoas'}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (fundraiser.closed)
                      const Chip(
                        label: Text('Encerrada'),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Total arrecadado', style: theme.textTheme.bodyMedium),
                Text(
                  formatMoney(raised),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'de ${formatMoney(expected)} · $paidCount de '
                  '${participants.length} pagaram',
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
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 24, 0, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'Participantes',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Text(
                'Pago',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        for (final participant in participants)
          _ParticipantTile(
            participant: participant,
            paid: payments.contains(participant.key),
            saving: _saving.contains(participant.key),
            onChanged: canMark ? (paid) => _setPaid(participant, paid) : null,
          ),
      ],
    );
  }
}

class _ParticipantTile extends StatelessWidget {
  const _ParticipantTile({
    required this.participant,
    required this.paid,
    required this.saving,
    required this.onChanged,
  });

  final FundraiserParticipant participant;
  final bool paid;
  final bool saving;

  /// Nulo para quem só acompanha: mostra "Sim" ou "Não".
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final subtitle = participant.subtitle;
    final onChanged = this.onChanged;

    return Card(
      child: ListTile(
        leading: AthleteAvatar(
          name: participant.name,
          photoUrl: participant.photoUrl,
        ),
        title: Text(participant.name),
        subtitle: subtitle == null || subtitle.isEmpty ? null : Text(subtitle),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              paid ? 'Sim' : 'Não',
              style: theme.textTheme.labelLarge?.copyWith(
                color: paid ? colors.primary : colors.onSurfaceVariant,
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
