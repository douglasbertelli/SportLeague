import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/env.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../invites/data/invite_repository.dart';
import '../data/profile_repository.dart';
import '../domain/profile.dart';

/// Endereço do site, onde fica a página pública.
String get _webUrl => Env.siteUrl;

/// Perfil público (todos os papéis): ligar ou desligar a página do site com a
/// foto, os times e as estatísticas da temporada; escolher o nome de usuário
/// (link /@nome); copiar, compartilhar, abrir ou trocar os links. O mesmo do
/// painel Perfil público do site.
class PublicProfilePage extends ConsumerStatefulWidget {
  const PublicProfilePage({super.key});

  @override
  ConsumerState<PublicProfilePage> createState() => _PublicProfilePageState();
}

class _PublicProfilePageState extends ConsumerState<PublicProfilePage> {
  final _handle = TextEditingController();
  bool _saving = false;
  String? _handleError;

  /// O nome salvo que já está no campo (para não sobrescrever o que a pessoa
  /// digita a cada atualização do perfil).
  String? _loadedHandle;

  @override
  void dispose() {
    _handle.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _saving = true);
    try {
      await action();
      ref.invalidate(currentProfileProvider);
    } catch (error) {
      if (mounted) showErrorSnackBar(context, friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggle(bool enabled) => _run(
    () =>
        ref.read(profileRepositoryProvider).setPublicProfile(enabled: enabled),
  );

  Future<void> _newCode() async {
    final confirmed = await confirmAction(
      context,
      title: 'Trocar o link com código?',
      message:
          'O link com código atual para de funcionar. O link com o nome de '
          'usuário continua igual.',
      confirmLabel: 'Trocar',
      confirmIcon: Icons.autorenew,
    );
    if (!confirmed) return;
    await _run(
      () => ref
          .read(profileRepositoryProvider)
          .setPublicProfile(enabled: true, newLink: true),
    );
  }

  Future<void> _saveHandle(String value) async {
    setState(() {
      _saving = true;
      _handleError = null;
    });
    try {
      final saved = await ref
          .read(profileRepositoryProvider)
          .setPublicHandle(value);
      _loadedHandle = saved;
      _handle.text = saved ?? '';
      ref.invalidate(currentProfileProvider);
      if (mounted) {
        showErrorSnackBar(
          context,
          saved == null
              ? 'Nome de usuário removido.'
              : 'Nome de usuário salvo.',
        );
      }
    } on PostgrestException catch (error) {
      // As regras do nome vêm do banco: formato e nome já em uso.
      final known =
          error.message.contains('já está em uso') ||
          error.message.contains('Use de 3 a 30');
      setState(
        () =>
            _handleError = known ? error.message : friendlyErrorMessage(error),
      );
    } catch (error) {
      setState(() => _handleError = friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _removeHandle(String handle) async {
    final confirmed = await confirmAction(
      context,
      title: 'Remover o nome de usuário?',
      message: 'O link /@$handle para de funcionar.',
      confirmLabel: 'Remover',
      confirmIcon: Icons.delete_outline,
    );
    if (confirmed) await _saveHandle('');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = ref.watch(currentProfileProvider).value;
    if (profile != null && profile.publicHandle != _loadedHandle) {
      _loadedHandle = profile.publicHandle;
      _handle.text = profile.publicHandle ?? '';
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Perfil público')),
      body: profile == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                Text(
                  'Uma página no site com a sua foto, os seus times e as '
                  'estatísticas da temporada, para mandar a quem não usa o '
                  'app. Telefone, e-mail e endereço nunca aparecem.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: SwitchListTile(
                    title: const Text('Perfil público'),
                    subtitle: Text(
                      profile.publicEnabled
                          ? 'Quem tiver o link vê a página'
                          : 'Desligado: os links não abrem',
                    ),
                    value: profile.publicEnabled,
                    onChanged: _saving ? null : _toggle,
                  ),
                ),
                if (profile.publicEnabled && profile.publicSlug != null)
                  ..._links(context, profile),
              ],
            ),
    );
  }

  List<Widget> _links(BuildContext context, Profile profile) {
    final theme = Theme.of(context);
    final host = Uri.parse(_webUrl).host;
    final handle = profile.publicHandle;
    final codeUrl = '$_webUrl/p/${profile.publicSlug}';
    final handleUrl = handle == null ? null : '$_webUrl/@$handle';
    final mainUrl = handleUrl ?? codeUrl;
    final draft = _handle.text.trim().replaceFirst('@', '').toLowerCase();

    return [
      const SizedBox(height: 24),
      Text('Nome de usuário', style: theme.textTheme.titleSmall),
      const SizedBox(height: 8),
      TextField(
        controller: _handle,
        enabled: !_saving,
        autocorrect: false,
        enableSuggestions: false,
        textCapitalization: TextCapitalization.none,
        maxLength: 31,
        inputFormatters: [
          FilteringTextInputFormatter.deny(RegExp(r'\s')),
          TextInputFormatter.withFunction(
            (_, value) => value.copyWith(text: value.text.toLowerCase()),
          ),
        ],
        onChanged: (_) => setState(() => _handleError = null),
        onSubmitted: _saveHandle,
        decoration: InputDecoration(
          prefixText: '$host/@',
          hintText: 'seunome',
          counterText: '',
          errorText: _handleError,
          errorMaxLines: 3,
          helperText:
              'De 3 a 30 letras minúsculas, números, ponto ou sublinhado. '
              'O link com código continua valendo.',
          helperMaxLines: 3,
        ),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: FilledButton(
              onPressed: _saving || draft == (handle ?? '')
                  ? null
                  : () => _saveHandle(draft),
              child: const Text('Salvar nome'),
            ),
          ),
          if (handle != null) ...[
            const SizedBox(width: 12),
            TextButton(
              onPressed: _saving ? null : () => _removeHandle(handle),
              child: const Text('Remover'),
            ),
          ],
        ],
      ),
      const SizedBox(height: 24),
      if (handleUrl != null) _LinkCard(label: 'Seu link', url: handleUrl),
      _LinkCard(
        label: handleUrl == null ? 'Seu link' : 'Link com código',
        url: codeUrl,
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: () =>
            ref.read(shareTextProvider)('Meu perfil no SportLeague: $mainUrl'),
        icon: const Icon(Icons.share_outlined),
        label: const Text('Compartilhar'),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(88, 48)),
              onPressed: () => launchUrl(
                Uri.parse(mainUrl),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Ver página'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(88, 48)),
              onPressed: _saving ? null : _newCode,
              icon: const Icon(Icons.autorenew),
              label: const Text('Trocar código'),
            ),
          ),
        ],
      ),
    ];
  }
}

/// Um link com o botão de copiar.
class _LinkCard extends StatelessWidget {
  const _LinkCard({required this.label, required this.url});

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(label),
        subtitle: Text(url, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: IconButton(
          tooltip: 'Copiar',
          icon: const Icon(Icons.copy),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: url));
            if (context.mounted) showErrorSnackBar(context, 'Link copiado.');
          },
        ),
      ),
    );
  }
}
