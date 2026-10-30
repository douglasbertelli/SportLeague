import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/theme_mode_provider.dart';

const _options = [
  (mode: ThemeMode.dark, label: 'Escuro', icon: Icons.dark_mode_outlined),
  (mode: ThemeMode.light, label: 'Claro', icon: Icons.light_mode_outlined),
  (
    mode: ThemeMode.system,
    label: 'Padrão do sistema',
    icon: Icons.brightness_auto_outlined,
  ),
];

/// Botão de AppBar que abre a escolha do tema (escuro, claro ou sistema).
class ThemeModeButton extends ConsumerWidget {
  const ThemeModeButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(themeModeProvider);
    return IconButton(
      tooltip: 'Tema',
      icon: Icon(_options.firstWhere((o) => o.mode == current).icon),
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => const _ThemeModeSheet(),
      ),
    );
  }
}

/// Item "Tema" do Perfil (administrador e técnico) e do Config (jogador):
/// mostra o tema atual e abre a mesma escolha do botão.
class ThemeModeTile extends ConsumerWidget {
  const ThemeModeTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(themeModeProvider);
    final option = _options.firstWhere((o) => o.mode == current);
    return ListTile(
      leading: Icon(option.icon),
      title: const Text('Tema'),
      subtitle: Text(option.label),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => const _ThemeModeSheet(),
      ),
    );
  }
}

class _ThemeModeSheet extends ConsumerWidget {
  const _ThemeModeSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(themeModeProvider);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final option in _options)
            ListTile(
              leading: Icon(option.icon),
              title: Text(option.label),
              trailing: option.mode == current ? const Icon(Icons.check) : null,
              selected: option.mode == current,
              onTap: () {
                ref.read(themeModeProvider.notifier).setMode(option.mode);
                Navigator.of(context).pop();
              },
            ),
        ],
      ),
    );
  }
}
