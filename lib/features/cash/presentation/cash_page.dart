import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/empty_state.dart';
import '../../fundraisers/domain/fundraiser.dart' show formatMoney, parseMoney;
import '../../fundraisers/presentation/fundraisers_page.dart'
    show fundraiserTeamsProvider;
import '../../teams/data/team_repository.dart';
import '../../teams/domain/team.dart';
import '../../teams/presentation/team_logo.dart';
import '../data/cash_repository.dart';
import '../domain/team_cash.dart';
import 'receipts_section.dart';

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

/// Caixa do time: saldo, entradas e saídas. O dono lança; mensalidades e
/// vaquinhas pagas entram sozinhas; todos do time veem.
class CashPage extends ConsumerStatefulWidget {
  const CashPage({super.key});

  @override
  ConsumerState<CashPage> createState() => _CashPageState();
}

class _CashPageState extends ConsumerState<CashPage> {
  String? _teamId;

  @override
  Widget build(BuildContext context) {
    final teams = ref.watch(fundraiserTeamsProvider);
    final selectedId = ref.watch(selectedTeamProvider).value?.id;
    return Scaffold(
      appBar: AppBar(title: const Text('Caixa')),
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
              icon: Icons.account_balance_wallet_outlined,
              title: 'Nenhum time',
              message: 'O caixa fica no time. Entre num time para ver.',
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
              Expanded(child: _TeamCash(team: team)),
            ],
          );
        },
      ),
    );
  }
}

class _TeamCash extends ConsumerWidget {
  const _TeamCash({required this.team});

  final Team team;

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final added = await showAppSheet<bool>(
      context,
      builder: (_) => _EntrySheet(teamId: team.id!),
    );
    if (added ?? false) ref.invalidate(teamCashProvider(team.id!));
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    CashEntry entry,
  ) async {
    final confirmed = await confirmDelete(
      context,
      title: 'Apagar o lançamento?',
      message:
          '${entry.category} · ${formatMoney(entry.amountCents)} sai do caixa.',
    );
    if (!confirmed) return;
    try {
      await ref.read(cashRepositoryProvider).deleteEntry(entry.id);
      ref.invalidate(teamCashProvider(team.id!));
    } catch (error) {
      if (context.mounted) {
        showErrorSnackBar(context, friendlyErrorMessage(error));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = teamCashProvider(team.id!);
    final cash = ref.watch(provider);
    final canManage = cash.value?.canManage ?? false;
    final locked = cash.value?.locked ?? false;

    return Scaffold(
      floatingActionButton: canManage && !locked
          ? FloatingActionButton.extended(
              heroTag: null,
              onPressed: () => _add(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('Lançar'),
            )
          : null,
      body: cash.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: TextButton.icon(
            onPressed: () => ref.invalidate(provider),
            icon: const Icon(Icons.refresh),
            label: const Text('Erro ao carregar o caixa. Tentar novamente'),
          ),
        ),
        data: (cash) {
          if (cash.locked) {
            return EmptyState(
              icon: Icons.lock_outline,
              title: 'Caixa do plano Premium',
              message: cash.canManage
                  ? 'Com o Premium, você controla as entradas e saídas do '
                        'time, e as mensalidades e vaquinhas pagas entram '
                        'sozinhas.'
                  : 'O administrador do time ainda não ativou o caixa.',
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.refresh(provider.future),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                _BalanceCard(cash: cash),
                const SizedBox(height: 8),
                // Comprovantes esperando o dono (mensalidade e vaquinhas).
                ReceiptsSection(
                  teamId: team.id!,
                  isOwner: cash.canManage,
                  allKinds: true,
                ),
                const SizedBox(height: 8),
                if (cash.entries.isEmpty)
                  Text(
                    cash.canManage
                        ? 'Nenhum lançamento ainda. Toque em "Lançar" para '
                              'registrar uma entrada ou saída.'
                        : 'Nenhum lançamento ainda.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                for (final (index, entry) in cash.entries.indexed) ...[
                  // Um título por mês.
                  if (index == 0 ||
                      cash.entries[index - 1].day.month != entry.day.month ||
                      cash.entries[index - 1].day.year != entry.day.year)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
                      child: Text(
                        '${_monthNames[entry.day.month - 1]} ${entry.day.year}',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                  _EntryTile(
                    entry: entry,
                    onDelete: cash.canManage && !entry.auto
                        ? () => _delete(context, ref, entry)
                        : null,
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.cash});

  final TeamCash cash;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final negative = cash.balanceCents < 0;
    Widget total(String label, int cents, Color color) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          Text(
            formatMoney(cents),
            style: theme.textTheme.titleMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Saldo', style: theme.textTheme.titleSmall),
            Text(
              formatMoney(cash.balanceCents),
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: negative ? colors.error : colors.primary,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                total('Entradas', cash.totalInCents, colors.primary),
                total('Saídas', cash.totalOutCents, colors.error),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, this.onDelete});

  final CashEntry entry;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final day =
        '${entry.day.day.toString().padLeft(2, '0')}/'
        '${entry.day.month.toString().padLeft(2, '0')}';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: entry.isIn
            ? colors.primaryContainer
            : colors.errorContainer,
        child: Icon(
          entry.isIn ? Icons.south_west : Icons.north_east,
          size: 18,
          color: entry.isIn
              ? colors.onPrimaryContainer
              : colors.onErrorContainer,
        ),
      ),
      title: Text(entry.category),
      subtitle: Text(
        [day, ?entry.description, if (entry.auto) 'automático'].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${entry.isIn ? '+' : '−'} ${formatMoney(entry.amountCents)}',
            style: theme.textTheme.titleSmall?.copyWith(
              color: entry.isIn ? colors.primary : colors.error,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (onDelete != null)
            IconButton(
              tooltip: 'Apagar lançamento',
              visualDensity: VisualDensity.compact,
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, size: 20),
            ),
        ],
      ),
    );
  }
}

/// Lançamento do dono: entrada ou saída, categoria, valor, data e
/// descrição.
class _EntrySheet extends ConsumerStatefulWidget {
  const _EntrySheet({required this.teamId});

  final String teamId;

  @override
  ConsumerState<_EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends ConsumerState<_EntrySheet> {
  final _amount = TextEditingController();
  final _description = TextEditingController();
  final _category = TextEditingController();
  bool _isIn = false;
  DateTime _day = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    _category.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final cents = parseMoney(_amount.text);
    final category = _category.text.trim();
    if (category.length < 2) {
      showErrorSnackBar(context, 'Escolha ou escreva a categoria.');
      return;
    }
    if (cents == null || cents <= 0) {
      showErrorSnackBar(context, 'Informe o valor.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(cashRepositoryProvider)
          .addEntry(
            teamId: widget.teamId,
            isIn: _isIn,
            category: category,
            amountCents: cents,
            day: _day,
            description: _description.text,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) showErrorSnackBar(context, friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = _isIn ? cashInCategories : cashOutCategories;
    return AppSheet(
      title: 'Lançar no caixa',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                icon: Icon(Icons.north_east),
                label: Text('Saída'),
              ),
              ButtonSegment(
                value: true,
                icon: Icon(Icons.south_west),
                label: Text('Entrada'),
              ),
            ],
            selected: {_isIn},
            onSelectionChanged: (value) => setState(() {
              _isIn = value.single;
              _category.clear();
            }),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in categories)
                ChoiceChip(
                  label: Text(option),
                  selected: _category.text == option,
                  onSelected: (_) => setState(() => _category.text = option),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _category,
            maxLength: 30,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Categoria'),
            onChanged: (_) => setState(() {}),
          ),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Valor',
              prefixText: 'R\$ ',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            maxLength: 120,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Descrição (opcional)',
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: const Text('Data'),
            subtitle: Text(
              '${_day.day.toString().padLeft(2, '0')}/'
              '${_day.month.toString().padLeft(2, '0')}/${_day.year}',
            ),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _day,
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (picked != null) setState(() => _day = picked);
            },
          ),
        ],
      ),
      actions: [
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.check),
          label: Text(_isIn ? 'Lançar entrada' : 'Lançar saída'),
        ),
        const SheetBackButton(),
      ],
    );
  }
}
