import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/app_sheet.dart';
import 'app_color_provider.dart';

/// Item do Perfil com a cor atual (do time ativo, se houver); abre a escolha
/// das cores.
class AppColorTile extends ConsumerWidget {
  const AppColorTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final team = ref.watch(colorTeamProvider);
    final current = ref.watch(appColorProvider);
    return ListTile(
      leading: const Icon(Icons.palette_outlined),
      title: Text(team == null ? 'Cor do app' : 'Cor do time'),
      subtitle: Text(
        team == null ? current.name : '${current.name} · ${team.name}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Swatch(color: current.color, size: 24),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: () =>
          showAppSheet<void>(context, builder: (_) => const _AppColorSheet()),
    );
  }
}

/// As cores; tocar já aplica no app inteiro (a própria folha muda de cor),
/// para comparar antes de fechar, e salva no time ativo.
class _AppColorSheet extends ConsumerWidget {
  const _AppColorSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(appColorProvider);
    final team = ref.watch(colorTeamProvider);
    return AppSheet(
      title: team == null ? 'Cor do app' : 'Cor do ${team.name}',
      message: team == null
          ? 'Ela muda o app inteiro, no modo claro e no escuro.'
          : 'Cada time tem a sua cor: o app fica com ela enquanto este time '
                'estiver ativo, no modo claro e no escuro.',
      body: Wrap(
        spacing: 12,
        runSpacing: 12,
        alignment: WrapAlignment.center,
        children: [
          for (final color in appColors)
            Semantics(
              button: true,
              selected: color.id == current.id,
              label: color.name,
              excludeSemantics: true,
              child: Tooltip(
                message: color.name,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () =>
                      ref.read(appColorProvider.notifier).select(color),
                  child: _Swatch(
                    color: color.color,
                    size: 48,
                    selected: color.id == current.id,
                  ),
                ),
              ),
            ),
        ],
      ),
      actions: [
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.check),
          label: Text('Pronto · ${current.name}'),
        ),
      ],
    );
  }
}

/// Bolinha da cor; a escolhida tem borda e um ✓.
class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.size,
    this.selected = false,
  });

  final Color color;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    // ✓ branco nas cores escuras e preto nas claras.
    final onColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected
              ? Theme.of(context).colorScheme.onSurface
              : Theme.of(context).colorScheme.outlineVariant,
          width: selected ? 3 : 1,
        ),
      ),
      child: selected ? Icon(Icons.check, color: onColor) : null,
    );
  }
}
