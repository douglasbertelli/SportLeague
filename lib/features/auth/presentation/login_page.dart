import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_logo.dart';
import '../../../core/widgets/form_page.dart';
import '../../../core/widgets/loading_button.dart';
import '../data/auth_repository.dart';

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

  @override
  Widget build(BuildContext context) {
    return FormPage(
      children: [
        const AppLogo(),
        const SizedBox(height: 32),
        Form(
          key: _formKey,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(labelText: 'E-mail'),
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
        LoadingButton(label: 'Entrar', loading: _loading, onPressed: _submit),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: _loading ? null : () => context.push(Routes.signUp),
          child: const Text('Criar conta'),
        ),
      ],
    );
  }
}
