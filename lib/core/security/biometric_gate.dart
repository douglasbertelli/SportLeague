import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/data/biometric_sign_in.dart';
import '../supabase/supabase_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import 'biometrics.dart';

/// Com "Entrar com biometria" ligado, cobre o app com a tela de desbloqueio
/// ao abrir e ao voltar depois de [relockAfter] fora dele. O app fica montado
/// por baixo (não perde o estado); só aparece depois da digital ou do rosto.
class BiometricGate extends ConsumerStatefulWidget {
  const BiometricGate({
    super.key,
    required this.child,
    this.relockAfter = const Duration(minutes: 1),
  });

  final Widget child;
  final Duration relockAfter;

  @override
  ConsumerState<BiometricGate> createState() => _BiometricGateState();
}

class _BiometricGateState extends ConsumerState<BiometricGate>
    with WidgetsBindingObserver {
  /// Ao abrir o app, começa bloqueado se a opção já estava ligada (ligar
  /// durante o uso não bloqueia na hora).
  late bool _locked = ref.read(biometricLockProvider);

  /// O pedido da biometria tira o app do primeiro plano; isso não conta como
  /// sair do app.
  bool _authenticating = false;
  DateTime? _leftAt;

  bool get _showLock =>
      _locked &&
      ref.read(biometricLockProvider) &&
      ref.read(currentUserIdProvider) != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _showLock) _unlock();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_authenticating) return;
    switch (state) {
      case AppLifecycleState.paused || AppLifecycleState.hidden:
        _leftAt ??= DateTime.now();
      case AppLifecycleState.resumed:
        final leftAt = _leftAt;
        _leftAt = null;
        if (leftAt != null &&
            DateTime.now().difference(leftAt) >= widget.relockAfter) {
          setState(() => _locked = true);
          if (_showLock) _unlock();
        }
      default:
        break;
    }
  }

  Future<void> _unlock() async {
    if (_authenticating) return;
    _authenticating = true;
    final ok = await ref
        .read(biometricsProvider)
        .authenticate('Desbloqueie o SportLeague');
    _authenticating = false;
    if (ok && mounted) setState(() => _locked = false);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(currentUserIdProvider, (previous, next) {
      // Quem acabou de entrar já se identificou: não bloqueia por cima.
      if (previous != next) setState(() => _locked = false);
      // Saiu de vez (não guardou a conta para a biometria): a biometria
      // desliga e volta a ser oferecida no próximo login.
      if (previous != null &&
          next == null &&
          ref.read(biometricParkingProvider) == null) {
        ref.read(biometricLockProvider.notifier).reset();
      }
    });
    // Entrou com a senha, Google ou Apple com uma conta guardada: a guardada
    // sai da espera; se for outra conta, a biometria desliga.
    ref.listen(authEventsProvider, (_, next) {
      final state = next.value;
      final parked = ref.read(biometricParkingProvider);
      if (state == null ||
          parked == null ||
          state.event != AuthChangeEvent.signedIn) {
        return;
      }
      ref.read(biometricParkingProvider.notifier).clear();
      if (state.session?.user.id != parked.userId) {
        ref.read(biometricLockProvider.notifier).reset();
      }
    });
    ref.watch(biometricLockProvider);
    ref.watch(currentUserIdProvider);
    final locked = _showLock;
    return Stack(
      children: [
        TickerMode(
          enabled: !locked,
          child: ExcludeSemantics(excluding: locked, child: widget.child),
        ),
        if (locked)
          Positioned.fill(
            child: _LockScreen(
              onUnlock: _unlock,
              // Vai para o login, com a conta guardada para a biometria.
              onUsePassword: () => signOutOrPark(ref),
            ),
          ),
      ],
    );
  }
}

class _LockScreen extends StatelessWidget {
  const _LockScreen({required this.onUnlock, required this.onUsePassword});

  final VoidCallback onUnlock;
  final VoidCallback onUsePassword;

  @override
  Widget build(BuildContext context) {
    // Como a tela de login: o verde da marca (a cor do time ainda nem carregou
    // ao abrir o app), no modo claro ou escuro escolhido.
    final theme = Theme.of(context).brightness == Brightness.dark
        ? AppTheme.dark()
        : AppTheme.light();
    return Theme(data: theme, child: _content(theme));
  }

  Widget _content(ThemeData theme) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppLogo(width: 140),
                const SizedBox(height: 32),
                Icon(
                  Icons.fingerprint,
                  size: 64,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'SportLeague bloqueado',
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Use a digital, o rosto ou o PIN do celular para entrar.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: onUnlock,
                  icon: const Icon(Icons.lock_open),
                  label: const Text('Desbloquear'),
                ),
                const SizedBox(height: 8),
                // Sem a biometria: sai da conta e entra com a senha.
                TextButton(
                  onPressed: onUsePassword,
                  child: const Text('Entrar com a senha'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
