import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Apitos da partida (assets/sounds, gerados por tool/generate_whistles.dart).
enum Whistle {
  /// Início de cada tempo: um apito.
  start('sounds/whistle_start.wav'),

  /// Fim do 1º tempo: curto e longo.
  halfTime('sounds/whistle_half.wav'),

  /// Fim de jogo: dois curtos e um longo.
  fullTime('sounds/whistle_final.wav');

  const Whistle(this.asset);

  final String asset;
}

typedef PlayWhistle = Future<void> Function(Whistle whistle);

/// Toca um apito, interrompendo o anterior. Falha de áudio não atrapalha o
/// app (o apito é só um enfeite). Substituível nos testes.
final playWhistleProvider = Provider<PlayWhistle>((ref) {
  final player = AudioPlayer();
  ref.onDispose(player.dispose);
  return (whistle) async {
    try {
      await player.stop();
      await player.play(AssetSource(whistle.asset));
    } catch (_) {}
  };
});
