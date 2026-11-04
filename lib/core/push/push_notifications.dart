import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/profile/data/profile_repository.dart';
import '../router/app_router.dart';
import '../router/routes.dart';
import '../supabase/supabase_providers.dart';

/// Push só no Android e no iOS, e só com o Firebase iniciado (nos testes e
/// no desktop, não).
bool get pushSupported =>
    !kIsWeb &&
    (Platform.isAndroid || Platform.isIOS) &&
    Firebase.apps.isNotEmpty;

/// Liga o aparelho à conta para receber push: pede a permissão, guarda o
/// token no Supabase (e o renovado, quando o Firebase trocar) e tira o token
/// ao sair da conta.
class PushRegistration {
  PushRegistration(this._client);

  final SupabaseClient _client;
  StreamSubscription<String>? _refresh;

  Future<void> register() async {
    if (!pushSupported) return;
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      // O token clássico do FCM, que a Edge Function `send-push` usa na API
      // HTTP v1. O register()/onRegistered novo devolve o ID de instalação
      // (FID), outro alvo de envio; trocar exige mudar a função junto.
      // ignore: deprecated_member_use
      final token = await messaging.getToken();
      if (token != null) await _save(token);
      // ignore: deprecated_member_use
      _refresh ??= messaging.onTokenRefresh.listen(_save);
    } catch (error) {
      // Sem push o app continua funcionando (as notificações ficam no sino).
      debugPrint('Push: não foi possível registrar o aparelho: $error');
    }
  }

  Future<void> _save(String token) => _client.rpc(
    'register_device_token',
    params: {
      'p_token': token,
      'p_platform': Platform.isIOS ? 'ios' : 'android',
    },
  );

  Future<void> unregister() async {
    if (!pushSupported) return;
    await _refresh?.cancel();
    _refresh = null;
    try {
      // ignore: deprecated_member_use
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _client.rpc(
          'unregister_device_token',
          params: {'p_token': token},
        );
      }
    } catch (error) {
      debugPrint('Push: não foi possível tirar o aparelho: $error');
    }
  }
}

final pushRegistrationProvider = Provider<PushRegistration>(
  (ref) => PushRegistration(ref.watch(supabaseClientProvider)),
);

/// Registra o aparelho quando alguém entra e, ao tocar num push, abre as
/// notificações (depois do login e do perfil carregados, se o app estava
/// fechado).
class PushNotificationsListener extends ConsumerStatefulWidget {
  const PushNotificationsListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PushNotificationsListener> createState() =>
      _PushNotificationsListenerState();
}

class _PushNotificationsListenerState
    extends ConsumerState<PushNotificationsListener> {
  StreamSubscription<RemoteMessage>? _opened;

  /// Um push tocado antes do perfil carregar.
  var _pendingOpen = false;

  @override
  void initState() {
    super.initState();
    if (!pushSupported) return;

    ref.listenManual<String?>(currentUserIdProvider, (previous, userId) {
      if (userId != null && userId != previous) {
        ref.read(pushRegistrationProvider).register();
      }
    }, fireImmediately: true);

    ref.listenManual(currentProfileProvider, (_, profile) {
      if (_pendingOpen && profile.value != null) _openNotifications();
    });

    _opened = FirebaseMessaging.onMessageOpenedApp.listen(
      (_) => _openNotifications(),
    );
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) _openNotifications();
    });
  }

  void _openNotifications() {
    if (!mounted) return;
    if (ref.read(currentProfileProvider).value == null) {
      _pendingOpen = true;
      return;
    }
    _pendingOpen = false;
    ref.read(routerProvider).push(Routes.notifications);
  }

  @override
  void dispose() {
    _opened?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
