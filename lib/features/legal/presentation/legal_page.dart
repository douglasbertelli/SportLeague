import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/maps/open_in_maps.dart' show launchExternalUrlProvider;
import '../../../core/router/routes.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/simple_markdown.dart';
import '../../auth/data/auth_repository.dart';
import '../../profile/data/profile_repository.dart';

/// Documentos legais do app, guardados como Markdown em `legal/`.
enum LegalDocument {
  privacy(
    'Política de Privacidade',
    'legal/politica-de-privacidade.md',
    Routes.privacy,
  ),
  terms('Termos de Uso', 'legal/termos-de-uso.md', Routes.terms);

  const LegalDocument(this.title, this.asset, this.route);

  final String title;
  final String asset;
  final String route;
}

/// Data da versão atual dos documentos: quem aceitou antes dela aceita de
/// novo (ao mudar os textos, atualize aqui).
final legalVersion = DateTime.utc(2026, 11, 8);

/// Texto do documento (do pacote do app).
final legalTextProvider = FutureProvider.family<String, LegalDocument>(
  (ref, document) => rootBundle.loadString(document.asset),
);

/// Mostra a Política de Privacidade ou os Termos de Uso.
class LegalPage extends ConsumerWidget {
  const LegalPage({super.key, required this.document});

  final LegalDocument document;

  void _openLink(BuildContext context, WidgetRef ref, String target) {
    for (final other in LegalDocument.values) {
      if (target.endsWith(other.asset.split('/').last)) {
        context.push(other.route);
        return;
      }
    }
    if (Uri.tryParse(target) case final uri? when uri.hasScheme) {
      ref.read(launchExternalUrlProvider)(uri);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = ref.watch(legalTextProvider(document));
    return Scaffold(
      appBar: AppBar(title: Text(document.title)),
      body: text.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: TextButton.icon(
            onPressed: () => ref.invalidate(legalTextProvider(document)),
            icon: const Icon(Icons.refresh),
            label: const Text('Erro ao abrir o documento. Tentar novamente'),
          ),
        ),
        data: (markdown) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          child: SelectionArea(
            child: SimpleMarkdown(
              markdown,
              onLink: (target) => _openLink(context, ref, target),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Li e aceito os Termos de Uso e a Política de Privacidade", com os links.
class LegalAcceptance extends StatelessWidget {
  const LegalAcceptance({
    super.key,
    required this.accepted,
    required this.onChanged,
  });

  final bool accepted;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final link = TextStyle(
      color: theme.colorScheme.primary,
      decoration: TextDecoration.underline,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(value: accepted, onChanged: (value) => onChanged(value!)),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Wrap(
              children: [
                GestureDetector(
                  onTap: () => onChanged(!accepted),
                  child: const Text('Li e aceito os '),
                ),
                GestureDetector(
                  onTap: () => context.push(Routes.terms),
                  child: Text('Termos de Uso', style: link),
                ),
                const Text(' e a '),
                GestureDetector(
                  onTap: () => context.push(Routes.privacy),
                  child: Text('Política de Privacidade', style: link),
                ),
                const Text('.'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Pede o aceite dos Termos e da Política a quem ainda não aceitou a versão
/// atual (contas antigas ou depois de uma atualização dos textos).
class AcceptTermsPage extends ConsumerStatefulWidget {
  const AcceptTermsPage({super.key});

  @override
  ConsumerState<AcceptTermsPage> createState() => _AcceptTermsPageState();
}

class _AcceptTermsPageState extends ConsumerState<AcceptTermsPage> {
  bool _accepted = false;
  bool _saving = false;

  Future<void> _accept() async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(profileRepositoryProvider).acceptTerms(userId);
      // Com o aceite, o app segue para o início.
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
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.policy_outlined,
                  size: 56,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Termos de Uso e Política de Privacidade',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(
                  'Para continuar usando o SportLeague, leia e aceite os '
                  'Termos de Uso e a Política de Privacidade. Eles explicam '
                  'como o app funciona e como cuidamos dos seus dados, '
                  'conforme a LGPD.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                LegalAcceptance(
                  accepted: _accepted,
                  onChanged: (value) => setState(() => _accepted = value),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _accepted && !_saving ? _accept : null,
                  child: const Text('Aceitar e continuar'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _saving
                      ? null
                      : () => ref.read(authRepositoryProvider).signOut(),
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
