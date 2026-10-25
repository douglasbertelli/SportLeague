import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/game.dart';

/// Pedido para a aba Jogos abrir numa aba de dentro (Pendentes, Realizados…),
/// vindo de um aviso do Início. [seq] muda a cada pedido, para repetir o
/// mesmo pedido funcionar depois de o usuário trocar de aba.
typedef GamesTabRequest = ({GameStage stage, int seq});

final gamesTabRequestProvider =
    NotifierProvider<GamesTabRequestNotifier, GamesTabRequest?>(
      GamesTabRequestNotifier.new,
    );

class GamesTabRequestNotifier extends Notifier<GamesTabRequest?> {
  @override
  GamesTabRequest? build() => null;

  void open(GameStage stage) =>
      state = (stage: stage, seq: (state?.seq ?? 0) + 1);
}
