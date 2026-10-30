import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../athletes/data/athlete_repository.dart';
import '../../athletes/domain/athlete.dart';
import '../data/presence_repository.dart';
import '../domain/presence_answer.dart';
import 'game_sheet_page.dart';

/// O dono ou o técnico pede a confirmação de presença aos atletas com conta
/// (quem já respondeu não é avisado de novo).
Future<void> requestPresence(
  BuildContext context,
  WidgetRef ref, {
  required String gameId,
  required String teamId,
}) async {
  try {
    final sent = await ref
        .read(presenceRepositoryProvider)
        .request(gameId, teamId);
    ref.invalidate(gamePresenceProvider((gameId: gameId, teamId: teamId)));
    if (!context.mounted) return;
    showErrorSnackBar(context, switch (sent) {
      0 =>
        'Nenhum atleta para avisar: todos já responderam ou nenhum '
            'tem conta no app.',
      1 => 'Pedido enviado para 1 atleta.',
      _ => 'Pedido enviado para $sent atletas.',
    });
  } catch (error) {
    if (context.mounted) {
      showErrorSnackBar(context, friendlyErrorMessage(error));
    }
  }
}

/// "Você vai?" com Sim / Não / Talvez: o atleta responde (e pode mudar até o
/// jogo começar). [onAnswered] roda depois da resposta salva.
class PresenceButtons extends ConsumerStatefulWidget {
  const PresenceButtons({
    super.key,
    required this.gameId,
    required this.teamId,
    this.onAnswered,
  });

  final String gameId;
  final String teamId;
  final VoidCallback? onAnswered;

  @override
  ConsumerState<PresenceButtons> createState() => _PresenceButtonsState();
}

class _PresenceButtonsState extends ConsumerState<PresenceButtons> {
  bool _saving = false;

  Future<void> _answer(PresenceAnswer answer) async {
    setState(() => _saving = true);
    try {
      await ref
          .read(presenceRepositoryProvider)
          .answer(widget.gameId, widget.teamId, answer);
      ref.invalidate(myPresenceProvider);
      widget.onAnswered?.call();
    } catch (error) {
      if (mounted) showErrorSnackBar(context, friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final answer = ref.watch(myPresenceProvider).value?[widget.gameId];
    return SegmentedButton<PresenceAnswer>(
      emptySelectionAllowed: true,
      showSelectedIcon: false,
      segments: [
        for (final option in PresenceAnswer.values)
          ButtonSegment(
            value: option,
            icon: Icon(option.icon),
            label: Text(option.label),
          ),
      ],
      selected: {?answer},
      onSelectionChanged: _saving
          ? null
          : (selection) {
              // Tocar na resposta atual não muda nada.
              if (selection.isNotEmpty) _answer(selection.first);
            },
    );
  }
}

/// Resumo das respostas do time no jogo, para o dono e o técnico: quantos
/// confirmaram, uma barra com a proporção e uma pílula colorida por resposta
/// (Sim, Não, Talvez, Sem resposta); tocar abre a lista com as fotos. Some
/// enquanto ninguém foi chamado.
class PresenceSummary extends ConsumerWidget {
  const PresenceSummary({
    super.key,
    required this.gameId,
    required this.teamId,
  });

  final String gameId;
  final String teamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries =
        ref
            .watch(gamePresenceProvider((gameId: gameId, teamId: teamId)))
            .value ??
        const <PresenceEntry>[];
    if (entries.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    int count(PresenceAnswer? answer) =>
        entries.where((entry) => entry.answer == answer).length;
    final confirmed = count(PresenceAnswer.yes);
    // Cada resposta com a sua cor; a barra mostra a proporção.
    final parts = [
      for (final answer in [...PresenceAnswer.values, null])
        (
          label: answer?.label ?? 'Sem resposta',
          icon: answer?.icon ?? Icons.schedule,
          count: count(answer),
          color: presenceColor(colors, answer),
        ),
    ];
    final description = [
      for (final part in parts) '${part.count} ${part.label.toLowerCase()}',
    ].join(', ');

    return Semantics(
      button: true,
      label: 'Presença: $description',
      excludeSemantics: true,
      child: Material(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _showList(context, entries),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.how_to_reg_outlined,
                      size: 20,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 8),
                    Text('Presença', style: theme.textTheme.titleSmall),
                    const Spacer(),
                    Text(
                      '$confirmed de ${entries.length} '
                      '${confirmed == 1 ? 'confirmado' : 'confirmados'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: colors.onSurfaceVariant,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Barra empilhada com a proporção de cada resposta.
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    height: 6,
                    child: Row(
                      children: [
                        for (final part in parts)
                          if (part.count > 0)
                            Expanded(
                              flex: part.count,
                              child: ColoredBox(color: part.color),
                            ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final part in parts)
                      _CountPill(
                        icon: part.icon,
                        label: part.label,
                        count: part.count,
                        color: part.color,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showList(BuildContext context, List<PresenceEntry> entries) =>
      showAppSheet<void>(
        context,
        builder: (_) => _PresenceList(teamId: teamId, entries: entries),
      );
}

/// Pílula de uma resposta: ícone, número e rótulo na cor dela (apagada
/// quando é zero).
class _CountPill extends StatelessWidget {
  const _CountPill({
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
  });

  final IconData icon;
  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = count == 0 ? colors.onSurfaceVariant : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: count == 0
            ? colors.surfaceContainerHighest
            : color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: foreground),
          const SizedBox(width: 4),
          Text(
            '$count $label',
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: foreground, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Cor de cada resposta (a mesma no resumo e na lista).
Color presenceColor(ColorScheme colors, PresenceAnswer? answer) =>
    switch (answer) {
      PresenceAnswer.yes => colors.primary,
      PresenceAnswer.no => colors.error,
      PresenceAnswer.maybe => colors.tertiary,
      null => colors.outline,
    };

/// Cor do texto sobre a cor da resposta.
Color _onPresenceColor(ColorScheme colors, PresenceAnswer? answer) =>
    switch (answer) {
      PresenceAnswer.yes => colors.onPrimary,
      PresenceAnswer.no => colors.onError,
      PresenceAnswer.maybe => colors.onTertiary,
      null => colors.surface,
    };

/// Filtro da lista: todas as respostas ou uma só ([answer] nulo = sem
/// resposta).
typedef _Filter = ({bool all, PresenceAnswer? answer});

/// Quem respondeu o quê: filtros por resposta no topo e, abaixo, um grupo
/// por resposta com a foto (e o selo da resposta), o apelido, a posição e a
/// camisa de cada atleta.
class _PresenceList extends ConsumerStatefulWidget {
  const _PresenceList({required this.teamId, required this.entries});

  final String teamId;
  final List<PresenceEntry> entries;

  @override
  ConsumerState<_PresenceList> createState() => _PresenceListState();
}

class _PresenceListState extends ConsumerState<_PresenceList> {
  _Filter _filter = (all: true, answer: null);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    // A foto (do atleta ou do perfil), o apelido, a posição e a camisa vêm
    // do elenco do time.
    final athletes = {
      for (final athlete
          in ref.watch(teamAthletesProvider(widget.teamId)).value ??
              const <Athlete>[])
        athlete.id: athlete,
    };
    final entries = widget.entries;
    int count(PresenceAnswer? answer) =>
        entries.where((entry) => entry.answer == answer).length;
    final confirmed = count(PresenceAnswer.yes);
    const answers = [...PresenceAnswer.values, null];

    final groups = [
      for (final answer in answers)
        if (_filter.all || _filter.answer == answer)
          (
            answer: answer,
            people: [
              for (final entry in entries)
                if (entry.answer == answer)
                  (
                    name: athletes[entry.athleteId]?.displayName ?? entry.name,
                    athlete: athletes[entry.athleteId],
                  ),
            ]..sort((a, b) => a.name.compareTo(b.name)),
          ),
    ];

    return AppSheet(
      title: 'Presença',
      message:
          '$confirmed de ${entries.length} '
          '${confirmed == 1 ? 'confirmado' : 'confirmados'}',
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Filtros: Todos e um por resposta, com o número de cada.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(
                  label: 'Todos (${entries.length})',
                  icon: Icons.groups_outlined,
                  color: colors.primary,
                  selected: _filter.all,
                  onSelected: () =>
                      setState(() => _filter = (all: true, answer: null)),
                ),
                for (final answer in answers)
                  _FilterChip(
                    label:
                        '${answer?.label ?? 'Sem resposta'} (${count(answer)})',
                    icon: answer?.icon ?? Icons.schedule,
                    color: presenceColor(colors, answer),
                    selected: !_filter.all && _filter.answer == answer,
                    onSelected: () =>
                        setState(() => _filter = (all: false, answer: answer)),
                  ),
              ],
            ),
          ),
          for (final group in groups)
            if (group.people.isNotEmpty)
              _PresenceGroup(answer: group.answer, people: group.people),
          if (groups.every((group) => group.people.isEmpty))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Ninguém por aqui.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
      actions: const [SheetBackButton(label: 'Fechar')],
    );
  }
}

/// Filtro com o ícone e a cor da resposta.
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(
      avatar: Icon(icon, size: 18, color: color),
      label: Text(label),
      showCheckmark: false,
      selected: selected,
      selectedColor: color.withValues(alpha: 0.18),
      side: BorderSide(
        color: selected ? color : Theme.of(context).colorScheme.outlineVariant,
      ),
      onSelected: (_) => onSelected(),
    ),
  );
}

/// Grupo de uma resposta: faixa colorida com o número e os atletas.
class _PresenceGroup extends StatelessWidget {
  const _PresenceGroup({required this.answer, required this.people});

  final PresenceAnswer? answer;
  final List<({String name, Athlete? athlete})> people;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final color = presenceColor(colors, answer);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: color.withValues(alpha: 0.12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(answer?.icon ?? Icons.schedule, size: 20, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    answer?.label ?? 'Sem resposta',
                    style: theme.textTheme.titleSmall?.copyWith(color: color),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${people.length}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: _onPresenceColor(colors, answer),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (final (index, person) in people.indexed) ...[
            if (index > 0) const Divider(height: 1, indent: 72),
            ListTile(
              leading: _BadgedAvatar(
                name: person.name,
                photoUrl: person.athlete?.photoUrl,
                answer: answer,
              ),
              title: Text(
                person.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: switch (_details(person.athlete)) {
                final details? => Text(details),
                null => null,
              },
            ),
          ],
        ],
      ),
    );
  }

  /// "Atacante · Camisa 10", com o que o atleta tiver.
  static String? _details(Athlete? athlete) {
    final details = [
      ?athlete?.position,
      if (athlete?.jerseyNumber case final number?) 'Camisa $number',
    ];
    return details.isEmpty ? null : details.join(' · ');
  }
}

/// Foto do atleta com o selo da resposta no canto.
class _BadgedAvatar extends StatelessWidget {
  const _BadgedAvatar({
    required this.name,
    required this.photoUrl,
    required this.answer,
  });

  final String name;
  final String? photoUrl;
  final PresenceAnswer? answer;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        AthleteAvatar(name: name, photoUrl: photoUrl, radius: 22),
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            padding: const EdgeInsets.all(1.5),
            decoration: BoxDecoration(
              color: colors.surface,
              shape: BoxShape.circle,
            ),
            child: Icon(
              answer?.icon ?? Icons.schedule,
              size: 16,
              color: presenceColor(colors, answer),
            ),
          ),
        ),
      ],
    );
  }
}
