import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// Planos, teste grátis e Financeiro só aparecem no Web. No app da Apple e
/// do Google a assinatura não pode ser vendida fora da compra das lojas,
/// nem com botão ou link para o site: lá o app só mostra o plano que vale.
final bool billingVisible = kIsWeb || !(Platform.isAndroid || Platform.isIOS);
