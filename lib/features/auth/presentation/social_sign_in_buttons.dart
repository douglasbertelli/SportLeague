import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/error_messages.dart';
import '../data/auth_repository.dart';

enum _Provider { google, apple }

/// Botões "Continuar com Google/Apple". Entram na conta existente ou criam uma
/// nova; o router leva ao completar cadastro quando falta o tipo de perfil.
class SocialSignInButtons extends ConsumerStatefulWidget {
  const SocialSignInButtons({super.key, this.enabled = true});

  /// Desabilita os botões enquanto outra ação da tela está em andamento.
  final bool enabled;

  @override
  ConsumerState<SocialSignInButtons> createState() =>
      _SocialSignInButtonsState();
}

class _SocialSignInButtonsState extends ConsumerState<SocialSignInButtons> {
  _Provider? _loading;

  Future<void> _signIn(_Provider provider) async {
    setState(() => _loading = provider);
    try {
      final auth = ref.read(authRepositoryProvider);
      await switch (provider) {
        _Provider.google => auth.signInWithGoogle(),
        _Provider.apple => auth.signInWithApple(),
      };
      // O redirecionamento é feito pelo router ao detectar a nova sessão.
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
    } finally {
      if (mounted) setState(() => _loading = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled && _loading == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _OrDivider(),
        const SizedBox(height: 16),
        _SocialButton(
          label: 'Continuar com Google',
          icon: const _BrandMark('assets/images/google.svg'),
          loading: _loading == _Provider.google,
          onPressed: enabled ? () => _signIn(_Provider.google) : null,
        ),
        const SizedBox(height: 12),
        _SocialButton(
          label: 'Continuar com Apple',
          // A maçã ocupa menos o quadro que o G; um pouco maior equilibra.
          icon: const _BrandMark('assets/images/apple.svg', size: 24),
          loading: _loading == _Provider.apple,
          onPressed: enabled ? () => _signIn(_Provider.apple) : null,
        ),
      ],
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.label,
    required this.icon,
    required this.loading,
    required this.onPressed,
  });

  final String label;
  final Widget icon;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: loading
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : icon,
      label: Text(label),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('ou', style: Theme.of(context).textTheme.bodySmall),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}

/// Ícone da marca (Google, Apple: Font Awesome Free, licença CC BY 4.0,
/// créditos no arquivo), na cor do texto do tema (branco no escuro).
class _BrandMark extends StatelessWidget {
  const _BrandMark(this.asset, {this.size = 20});

  final String asset;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      asset,
      width: size,
      height: size,
      excludeFromSemantics: true,
      theme: SvgTheme(currentColor: Theme.of(context).colorScheme.onSurface),
    );
  }
}
