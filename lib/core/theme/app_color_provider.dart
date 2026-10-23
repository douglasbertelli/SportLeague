import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/preferences_provider.dart';
import 'app_colors.dart';

export 'app_colors.dart';

final appColorProvider = NotifierProvider<AppColorNotifier, AppColor>(
  AppColorNotifier.new,
);

/// Cor escolhida, salva no aparelho; o padrão é o verde.
class AppColorNotifier extends Notifier<AppColor> {
  static const _key = 'app_color';

  @override
  AppColor build() {
    final saved = ref.watch(sharedPreferencesProvider).getString(_key);
    return appColors.firstWhere(
      (color) => color.id == saved,
      orElse: () => appColors.first,
    );
  }

  Future<void> select(AppColor color) async {
    state = color;
    await ref.read(sharedPreferencesProvider).setString(_key, color.id);
  }
}
