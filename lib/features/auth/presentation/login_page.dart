import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/security/biometrics.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_logo.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/form_page.dart';
import '../../../core/widgets/loading_button.dart';
import '../../../core/widgets/theme_mode_button.dart';
import '../data/auth_repository.dart';
import '../data/biometric_sign_in.dart';
import 'social_sign_in_buttons.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;

  /// Com a conta guardada, mostra o formulário para entrar com outra.
  bool _useOtherAccount = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ref
          .read(authRepositoryProvider)
          .signIn(
            email: _emailController.text,
            password: _passwordController.text,
          );
      // O redirecionamento é feito pelo router ao detectar a nova sessão.
    } catch (error) {
      _showMessage(friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _emailController.text;
    if (Validators.email(email) != null) {
      _showMessage('Informe um e-mail válido para recuperar a senha.');
      return;
    }
    try {
      await ref.read(authRepositoryProvider).sendPasswordReset(email);
      _showMessage('Enviamos um link de recuperação para $email.');
    } catch (error) {
      _showMessage(friendlyErrorMessage(error));
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Volta para a conta guardada com a digital, o rosto ou o PIN.
  Future<void> _biometricSignIn() async {
    setState(() => _loading = true);
    try {
      // Entrando, o router leva para o Início sozinho.
      await signInWithBiometrics(ref);
    } catch (error) {
      _showMessage(friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgetBiometrics() async {
    final confirmed = await confirmAction(
      context,
      title: 'Remover a biometria deste aparelho?',
      message:
          'Para entrar de novo, use o e-mail e a senha (ou Google/Apple). Dá '
          'para ligar a biometria outra vez em Perfil ou Config.',
      confirmLabel: 'Remover',
      cancelLabel: 'Voltar',
    );
    if (!confirmed) return;
    try {
      await forgetBiometrics(ref);
    } catch (error) {
      _showMessage(friendlyErrorMessage(error));
    }
  }

  @override
  void initState() {
    super.initState();
    // Com uma conta guardada, já pede a biometria ao abrir.
    if (ref.read(biometricParkingProvider) != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _biometricSignIn();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final parked = ref.watch(biometricParkingProvider);
    // Com a conta guardada, a tela mostra só a biometria; o formulário
    // aparece em "Usar outra conta".
    final showForm = parked == null || _useOtherAccount;
    return FormPage(
      appBar: AppBar(actions: const [ThemeModeButton()]),
      children: [
        const AppLogo(width: 140),
        const SizedBox(height: 48),
        if (showForm) ..._form(context) else ..._biometric(context, parked),
      ],
    );
  }

  /// Volta para a conta guardada: o nome, a biometria e, discretos, outra
  /// conta ou remover a biometria.
  List<Widget> _biometric(BuildContext context, ParkedAccount parked) {
    final theme = Theme.of(context);
    return [
      Text(
        parked.name.isEmpty ? 'Bem-vindo de volta' : 'Olá, ${parked.name}',
        style: theme.textTheme.headlineSmall,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 8),
      Text(
        'Entre com a digital, o rosto ou o PIN do celular.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 32),
      FilledButton.icon(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        onPressed: _loading ? null : _biometricSignIn,
        icon: _loading
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.fingerprint),
        label: const Text('Entrar com biometria'),
      ),
      const SizedBox(height: 16),
      TextButton(
        onPressed: _loading
            ? null
            : () => setState(() => _useOtherAccount = true),
        child: const Text('Usar outra conta'),
      ),
      TextButton(
        style: TextButton.styleFrom(
          foregroundColor: theme.colorScheme.onSurfaceVariant,
        ),
        onPressed: _loading ? null : _forgetBiometrics,
        child: const Text('Remover biometria deste aparelho'),
      ),
    ];
  }

  /// E-mail e senha, Google/Apple lado a lado e o link para criar conta.
  List<Widget> _form(BuildContext context) {
    final parked = ref.read(biometricParkingProvider);
    return [
      Form(
        key: _formKey,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'E-mail',
                  prefixIcon: Icon(Icons.mail_outline),
                ),
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.next,
                validator: Validators.email,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: 'Senha',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    tooltip: _obscurePassword
                        ? 'Mostrar senha'
                        : 'Ocultar senha',
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility
                          : Icons.visibility_off,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                obscureText: _obscurePassword,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                validator: (value) =>
                    Validators.required(value, message: 'Informe sua senha'),
              ),
            ],
          ),
        ),
      ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: _loading ? null : _forgotPassword,
          child: const Text('Esqueci minha senha'),
        ),
      ),
      const SizedBox(height: 8),
      SizedBox(
        height: 52,
        child: LoadingButton(
          label: 'Entrar',
          loading: _loading,
          onPressed: _submit,
        ),
      ),
      const SizedBox(height: 24),
      SocialSignInButtons(enabled: !_loading, compact: true),
      const SizedBox(height: 24),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('Não tem conta?'),
          TextButton(
            onPressed: _loading ? null : () => context.push(Routes.signUp),
            child: const Text('Criar conta'),
          ),
        ],
      ),
      // Veio de "Usar outra conta": volta para a biometria.
      if (parked != null)
        TextButton.icon(
          onPressed: _loading
              ? null
              : () => setState(() => _useOtherAccount = false),
          icon: const Icon(Icons.fingerprint),
          label: Text(
            parked.name.isEmpty
                ? 'Voltar para a biometria'
                : 'Entrar como ${parked.name}',
          ),
        ),
    ];
  }
}
