import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../invites/data/invite_repository.dart';
import '../data/profile_repository.dart';

/// Meu código (Perfil do jogador e do técnico): o código pessoal, JG ou TC,
/// com Compartilhar, Copiar e Gerar outro. O administrador digita o código
/// em Convidar para chamar para o time.
class MyCodePage extends ConsumerStatefulWidget {
  const MyCodePage({super.key});

  @override
  ConsumerState<MyCodePage> createState() => _MyCodePageState();
}

class _MyCodePageState extends ConsumerState<MyCodePage> {
  bool _saving = false;

  Future<void> _regenerate() async {
    final confirmed = await confirmAction(
      context,
      title: 'Gerar outro código?',
      message:
          'O código atual deixa de valer: quem ainda não te convidou vai '
          'precisar do novo. Os times em que você já está continuam.',
      confirmLabel: 'Gerar outro',
      confirmIcon: Icons.autorenew,
    );
    if (!confirmed) return;
    setState(() => _saving = true);
    try {
      await ref.read(profileRepositoryProvider).regenerateCode();
      ref.invalidate(currentProfileProvider);
    } catch (error) {
      if (mounted) showErrorSnackBar(context, friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = ref.watch(currentProfileProvider).value;
    final code = profile?.code;
    final role = (profile?.isCoach ?? false) ? 'técnico' : 'jogador';

    return Scaffold(
      appBar: AppBar(title: const Text('Meu código')),
      body: code == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
              children: [
                Icon(
                  Icons.qr_code_2,
                  size: 64,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Mande para o administrador do time: em Convidar, ele '
                  'digita o código e te chama como $role.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: SelectableText(
                        code,
                        semanticsLabel: 'Código ${code.split('').join(' ')}',
                        style: theme.textTheme.headlineLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 4,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => ref.read(shareTextProvider)(
                    'Meu código no SportLeague: $code. Use em Convidar para '
                    'me chamar para o seu time.',
                  ),
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Compartilhar'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(88, 48),
                        ),
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: code));
                          if (context.mounted) {
                            showErrorSnackBar(context, 'Código copiado.');
                          }
                        },
                        icon: const Icon(Icons.copy),
                        label: const Text('Copiar'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(88, 48),
                        ),
                        onPressed: _saving ? null : _regenerate,
                        icon: const Icon(Icons.autorenew),
                        label: const Text('Gerar outro'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
