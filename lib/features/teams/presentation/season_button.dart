import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_sheet.dart';
import '../domain/season.dart';

/// Botão com a temporada das estatísticas ("Temporada 2026", "Outubro de
/// 2026"); abre a escolha do ano e do mês. Vale para todas as telas.
class SeasonButton extends ConsumerWidget {
  const SeasonButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final season = ref.watch(seasonProvider);
    return ActionChip(
      avatar: const Icon(Icons.calendar_month_outlined, size: 18),
      label: Text(season.label),
      tooltip: 'Escolher a temporada',
      onPressed: () =>
          showAppSheet<void>(context, builder: (_) => const _SeasonSheet()),
    );
  }
}

class _SeasonSheet extends ConsumerStatefulWidget {
  const _SeasonSheet();

  @override
  ConsumerState<_SeasonSheet> createState() => _SeasonSheetState();
}

class _SeasonSheetState extends ConsumerState<_SeasonSheet> {
  late int _year = ref.read(seasonProvider).year;

  void _pick(int? month) {
    ref.read(seasonProvider.notifier).select(Season(_year, month));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = ref.watch(seasonProvider);
    final thisYear = DateTime.now().year;

    return AppSheet(
      title: 'Temporada',
      message:
          'Os números do time e dos atletas contam só os jogos do '
          'período escolhido.',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Ano', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var year = thisYear; year > thisYear - 5; year--)
                ChoiceChip(
                  label: Text('$year'),
                  selected: year == _year,
                  onSelected: (_) => setState(() => _year = year),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Período', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Ano inteiro'),
                selected: current == Season(_year),
                onSelected: (_) => _pick(null),
              ),
              for (var month = 1; month <= 12; month++)
                ChoiceChip(
                  label: Text(monthName(month).substring(0, 3)),
                  tooltip: monthName(month),
                  selected: current == Season(_year, month),
                  onSelected: (_) => _pick(month),
                ),
            ],
          ),
        ],
      ),
      actions: const [SheetBackButton(label: 'Fechar')],
    );
  }
}
