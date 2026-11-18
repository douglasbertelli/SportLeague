import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// App instalado pelas lojas (Android/iOS). Aqui a assinatura só pode ser
/// vendida pela compra das lojas (Adapty), sem botão ou link para o site.
final bool isStoreApp = !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// O que é da assinatura pelo site (Asaas): o teste grátis sem cartão e o
/// Financeiro com as cobranças. Não aparece no app das lojas.
final bool billingVisible = !isStoreApp;
