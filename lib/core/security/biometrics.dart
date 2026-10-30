import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../storage/preferences_provider.dart';

/// Biometria do aparelho (digital ou rosto, com o PIN do celular como
/// alternativa). Separada para os testes trocarem por uma falsa.
class Biometrics {
  Biometrics([LocalAuthentication? auth])
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  /// O aparelho tem biometria cadastrada.
  Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported() &&
          await _auth.canCheckBiometrics &&
          (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Pede a digital ou o rosto. `false` se a pessoa cancelou ou falhou.
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }
}

final biometricsProvider = Provider<Biometrics>((ref) => Biometrics());

/// Se o aparelho tem biometria cadastrada (sem ela, a opção não aparece).
final biometricsAvailableProvider = FutureProvider<bool>(
  (ref) => ref.watch(biometricsProvider).isAvailable(),
);

/// "Entrar com biometria": com ela ligada, o app pede a digital ou o rosto
/// ao abrir, e o "Sair" guarda a conta para voltar com a biometria. Vale para
/// este aparelho; desliga ao sair de vez ou ao entrar com outra conta.
class BiometricLock extends Notifier<bool> {
  static const _key = 'biometric_lock';

  /// O convite para ligar já foi mostrado nesta conta (uma vez só).
  static const offeredKey = 'biometric_offered';

  @override
  bool build() => ref.watch(sharedPreferencesProvider).getBool(_key) ?? false;

  Future<void> set(bool enabled) async {
    final preferences = ref.read(sharedPreferencesProvider);
    await preferences.setBool(_key, enabled);
    await preferences.setBool(offeredKey, true);
    state = enabled;
  }

  /// Ao sair da conta: desliga e volta a oferecer no próximo login.
  Future<void> reset() async {
    final preferences = ref.read(sharedPreferencesProvider);
    await preferences.remove(_key);
    await preferences.remove(offeredKey);
    state = false;
  }
}

final biometricLockProvider = NotifierProvider<BiometricLock, bool>(
  BiometricLock.new,
);

/// A conta que saiu com a biometria ligada: a sessão fica guardada no cofre e
/// a tela de login mostra "Entrar como [name]".
typedef ParkedAccount = ({String userId, String name});

class BiometricParking extends Notifier<ParkedAccount?> {
  static const _userKey = 'biometric_parked_user';
  static const _nameKey = 'biometric_parked_name';

  @override
  ParkedAccount? build() {
    final preferences = ref.watch(sharedPreferencesProvider);
    final userId = preferences.getString(_userKey);
    if (userId == null) return null;
    return (userId: userId, name: preferences.getString(_nameKey) ?? '');
  }

  Future<void> park({required String userId, required String name}) async {
    final preferences = ref.read(sharedPreferencesProvider);
    await preferences.setString(_userKey, userId);
    await preferences.setString(_nameKey, name);
    state = (userId: userId, name: name);
  }

  Future<void> clear() async {
    final preferences = ref.read(sharedPreferencesProvider);
    await preferences.remove(_userKey);
    await preferences.remove(_nameKey);
    state = null;
  }
}

final biometricParkingProvider =
    NotifierProvider<BiometricParking, ParkedAccount?>(BiometricParking.new);
