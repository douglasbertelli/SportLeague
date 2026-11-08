import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../auth/data/biometric_sign_in.dart';
import '../data/profile_repository.dart';
import '../domain/profile.dart';

/// "20/11/2026".
String _date(DateTime at) =>
    '${at.day.toString().padLeft(2, '0')}/'
    '${at.month.toString().padLeft(2, '0')}/${at.year}';

/// "Excluir conta", no fim do perfil.
class DeleteAccountButton extends ConsumerWidget {
  const DeleteAccountButton({super.key, required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) => TextButton.icon(
    style: TextButton.styleFrom(
      foregroundColor: Theme.of(context).colorScheme.error,
    ),
    onPressed: () => deleteAccount(context, ref, profile),
    icon: const Icon(Icons.delete_forever_outlined),
    label: const Text('Excluir conta'),
  );
}

/// Confirma (digitando EXCLUIR), pede a exclusão e sai da conta.
Future<void> deleteAccount(
  BuildContext context,
  WidgetRef ref,
  Profile profile,
) async {
  final confirmed = await showAppSheet<bool>(
    context,
    builder: (_) => _ConfirmDeletionSheet(profile: profile),
  );
  if (confirmed != true || !context.mounted) return;
  try {
    await ref.read(profileRepositoryProvider).requestDeletion();
    // Sai de vez neste aparelho (e esquece a conta guardada da biometria).
    await forgetBiometrics(ref);
  } catch (error) {
    if (context.mounted) {
      showErrorSnackBar(context, friendlyErrorMessage(error));
    }
  }
}

class _ConfirmDeletionSheet extends StatefulWidget {
  const _ConfirmDeletionSheet({required this.profile});

  final Profile profile;

  @override
  State<_ConfirmDeletionSheet> createState() => _ConfirmDeletionSheetState();
}

class _ConfirmDeletionSheetState extends State<_ConfirmDeletionSheet> {
  static const _word = 'EXCLUIR';
  final _typed = TextEditingController();

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  bool get _ready => _typed.text.trim().toUpperCase() == _word;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final admin = widget.profile.isAdmin;
    final lost = [
      'Seu perfil, foto, código e estatísticas',
      if (admin) ...[
        'Seus times, com atletas, jogos, escalações e estatísticas',
        'Campeonatos, mensalidades e vaquinhas dos seus times',
      ] else
        'Seus vínculos com os times (o time continua, sem você)',
      'Notificações e convites',
    ];

    return AppSheet(
      title: 'Excluir conta?',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            color: colors.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: colors.onErrorContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Esta ação é irreversível. Depois da exclusão, não há '
                      'como recuperar a conta nem as informações.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onErrorContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('Será apagado:', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          for (final item in lost)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  '),
                  Expanded(child: Text(item)),
                ],
              ),
            ),
          const SizedBox(height: 12),
          Text(
            'A conta fica inativa por 7 dias e some para os outros usuários. '
            'Nesse prazo, se você entrar de novo, pode reativá-la. Depois dos '
            '7 dias, tudo é apagado de vez.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _typed,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Digite $_word para confirmar',
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: colors.error,
            foregroundColor: colors.onError,
          ),
          onPressed: _ready ? () => Navigator.of(context).pop(true) : null,
          icon: const Icon(Icons.delete_forever_outlined),
          label: const Text('Excluir minha conta'),
        ),
        const SheetBackButton(),
      ],
    );
  }
}

/// Aberta quando a conta está inativa (exclusão pedida): reativar ou sair.
class AccountInactivePage extends ConsumerStatefulWidget {
  const AccountInactivePage({super.key});

  @override
  ConsumerState<AccountInactivePage> createState() =>
      _AccountInactivePageState();
}

class _AccountInactivePageState extends ConsumerState<AccountInactivePage> {
  bool _busy = false;

  Future<void> _reactivate() async {
    setState(() => _busy = true);
    try {
      await ref.read(profileRepositoryProvider).cancelDeletion();
      // O perfil volta ativo e o app segue para o início.
      ref.invalidate(currentProfileProvider);
    } catch (error) {
      if (mounted) showErrorSnackBar(context, friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    setState(() => _busy = true);
    await forgetBiometrics(ref);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final date = ref.watch(currentProfileProvider).value?.deletionDate;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.person_off_outlined, size: 64, color: colors.error),
                const SizedBox(height: 16),
                Text(
                  'Conta marcada para exclusão',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(
                  date == null
                      ? 'Sua conta está inativa e será excluída em breve.'
                      : 'Sua conta está inativa e será excluída de vez em '
                            '${_date(date)}. Até lá, você pode reativá-la e '
                            'tudo volta como estava.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: _busy ? null : _reactivate,
                  icon: const Icon(Icons.restore),
                  label: const Text('Reativar conta'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _busy ? null : _signOut,
                  child: const Text('Sair'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
