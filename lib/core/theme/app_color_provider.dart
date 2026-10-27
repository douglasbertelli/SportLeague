import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/preferences_provider.dart';
import 'app_colors.dart';

export 'app_colors.dart';

/// Time cuja cor o app usa (o time ativo do administrador); nulo sem time.
/// O app liga ao time ativo em `main.dart`; aqui fica sem time, para o core
/// não depender dos times.
final colorTeamProvider = Provider<({String id, String name})?>((ref) => null);

/// Sem ninguém logado (login, cadastro, abertura): o app fica no verde da
/// marca, combinando com o logo. O app liga à sessão em `main.dart`.
final signedOutProvider = Provider<bool>((ref) => false);

final appColorProvider = NotifierProvider<AppColorNotifier, AppColor>(
  AppColorNotifier.new,
);

/// Cor do app, salva no aparelho: cada time tem a sua. Time sem cor própria
/// (e quem não tem time) usa a cor geral, a escolhida antes de existir a cor
/// por time; o padrão é o verde.
class AppColorNotifier extends Notifier<AppColor> {
  static const _key = 'app_color';

  static String _teamKey(String teamId) => '$_key.$teamId';

  @override
  AppColor build() {
    if (ref.watch(signedOutProvider)) return appColors.first;
    final preferences = ref.watch(sharedPreferencesProvider);
    final team = ref.watch(colorTeamProvider);
    final saved =
        (team == null ? null : preferences.getString(_teamKey(team.id))) ??
        preferences.getString(_key);
    return appColors.firstWhere(
      (color) => color.id == saved,
      orElse: () => appColors.first,
    );
  }

  /// Salva a cor do time atual (ou a geral, sem time).
  Future<void> select(AppColor color) async {
    state = color;
    final team = ref.read(colorTeamProvider);
    await ref
        .read(sharedPreferencesProvider)
        .setString(team == null ? _key : _teamKey(team.id), color.id);
  }
}
