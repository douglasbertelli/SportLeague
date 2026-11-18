import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/error_messages.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/form_page.dart';
import '../../../core/widgets/loading_button.dart';
import '../data/auth_repository.dart';

/// Esqueci minha senha (sem login): o e-mail da conta e o envio do link. O
/// link abre a página Nova senha do site; depois a pessoa volta e entra com a
/// senha nova. Recebe em [email] o que já estava digitado no login.
class ForgotPasswordPage extends ConsumerStatefulWidget {
  const ForgotPasswordPage({super.key, this.email});

  final String? email;

  @override
  ConsumerState<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends ConsumerState<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.email ?? '');
  bool _loading = false;

  /// O e-mail para onde o link foi (mostra a confirmação).
  String? _sentTo;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    // Em "Enviar de novo" o formulário já saiu da tela (currentState nulo) e
    // o e-mail é o mesmo já validado no primeiro envio.
    final resend = _sentTo != null;
    if (!resend && !_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final email = _sentTo ?? _email.text.trim();
      await ref.read(authRepositoryProvider).sendPasswordReset(email);
      if (!mounted) return;
      setState(() => _sentTo = email);
      if (resend) showErrorSnackBar(context, 'Enviamos o link de novo.');
    } catch (error) {
      if (mounted) showErrorSnackBar(context, friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyLarge?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final sentTo = _sentTo;

    return FormPage(
      appBar: AppBar(title: const Text('Esqueci minha senha')),
      children: sentTo == null
          ? [
              Icon(
                Icons.lock_reset,
                size: 56,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Informe o e-mail da sua conta. Vamos mandar um link para '
                'você criar uma senha nova.',
                textAlign: TextAlign.center,
                style: muted,
              ),
              const SizedBox(height: 24),
              Form(
                key: _formKey,
                child: TextFormField(
                  controller: _email,
                  decoration: const InputDecoration(labelText: 'E-mail'),
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.send,
                  onFieldSubmitted: (_) => _send(),
                  validator: Validators.email,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 52,
                child: LoadingButton(
                  label: 'Enviar link',
                  loading: _loading,
                  onPressed: _send,
                ),
              ),
            ]
          : [
              Icon(
                Icons.mark_email_read_outlined,
                size: 56,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Confira o seu e-mail',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Se existir uma conta com $sentTo, enviamos um link para criar '
                'uma senha nova. Abra o link neste celular, crie a senha e '
                'volte aqui para entrar. Não chegou? Veja a caixa de spam.',
                textAlign: TextAlign.center,
                style: muted,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => context.pop(),
                child: const Text('Voltar para entrar'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _loading ? null : _send,
                child: const Text('Enviar de novo'),
              ),
            ],
    );
  }
}
