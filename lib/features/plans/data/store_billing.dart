import 'package:adapty_flutter/adapty_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../presentation/billing_visibility.dart';

/// Compra do Premium pelas lojas (App Store / Google Play) via Adapty, só no
/// app Android/iOS. Quem libera o Premium é o servidor: o Adapty avisa o
/// webhook `adapty-webhook`, que acerta o plano no banco. O app só compra e
/// depois lê o plano de novo.
///
/// A pessoa é identificada no Adapty pelo id dela no Supabase
/// (customer_user_id); é assim que o webhook sabe de quem é a compra.
class StoreBilling {
  StoreBilling._();

  static final instance = StoreBilling._();

  /// Há loja e chave do Adapty neste build.
  static bool get available => isStoreApp && Env.adaptyPublicKey.isNotEmpty;

  Future<void>? _activation;
  String? _identified;

  Future<void> _activate() => _activation ??= Adapty().activate(
    configuration: AdaptyConfiguration(apiKey: Env.adaptyPublicKey)
      ..withLogLevel(kReleaseMode ? AdaptyLogLevel.error : AdaptyLogLevel.warn),
  );

  /// Liga a compra à conta que entrou (ou desliga ao sair).
  Future<void> setUser(String? userId) async {
    if (!available || userId == _identified) return;
    try {
      await _activate();
      if (userId == null) {
        await Adapty().logout();
      } else {
        await Adapty().identify(userId);
      }
      _identified = userId;
    } catch (error) {
      debugPrint('Adapty setUser: $error');
    }
  }

  /// Produto do Premium (com o preço da loja), ou nulo se não carregar.
  Future<AdaptyPaywallProduct?> premiumProduct() async {
    if (!available) return null;
    await _activate();
    final flow = await Adapty().getFlow(placementId: Env.adaptyPlacementId);
    final products = await Adapty().getPaywallProducts(flow: flow);
    return products.firstOrNull;
  }

  /// Compra pela loja. `true` se pagou; `false` se a pessoa desistiu.
  /// Pendente (ex.: aguardando aprovação) lança [StorePurchasePending].
  Future<bool> buy(AdaptyPaywallProduct product) async {
    await _activate();
    try {
      final result = await Adapty().makePurchase(product: product);
      return switch (result) {
        AdaptyPurchaseResultSuccess() => true,
        AdaptyPurchaseResultUserCancelled() => false,
        AdaptyPurchaseResultPending() => throw const StorePurchasePending(),
      };
    } on AdaptyError catch (error) {
      if (error.code == AdaptyErrorCode.paymentCancelled) return false;
      rethrow;
    }
  }

  /// Restaura compras feitas antes (outro aparelho, reinstalação). `true`
  /// se a loja tem uma assinatura valendo.
  Future<bool> restore() async {
    await _activate();
    final profile = await Adapty().restorePurchases();
    return profile.accessLevels.values.any((level) => level.isActive);
  }
}

class StorePurchasePending implements Exception {
  const StorePurchasePending();
}

/// Produto do Premium na loja. Nulo fora do app das lojas ou sem chave.
final premiumStoreProductProvider =
    FutureProvider.autoDispose<AdaptyPaywallProduct?>(
      (ref) => StoreBilling.instance.premiumProduct(),
    );

/// Mantém o Adapty com a conta que está no app.
class StoreBillingListener extends ConsumerStatefulWidget {
  const StoreBillingListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<StoreBillingListener> createState() =>
      _StoreBillingListenerState();
}

class _StoreBillingListenerState extends ConsumerState<StoreBillingListener> {
  @override
  void initState() {
    super.initState();
    if (StoreBilling.available) {
      StoreBilling.instance.setUser(ref.read(currentUserIdProvider));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (StoreBilling.available) {
      ref.listen(
        currentUserIdProvider,
        (_, userId) => StoreBilling.instance.setUser(userId),
      );
    }
    return widget.child;
  }
}
