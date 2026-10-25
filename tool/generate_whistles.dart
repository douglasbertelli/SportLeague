// Gera os apitos do relógio da partida (assets/sounds/*.wav), sintetizados
// aqui para não depender de áudio de terceiros. Rodar com:
//   dart run tool/generate_whistles.dart
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

const _sampleRate = 22050;

/// Um sopro de apito: tom de ~3 kHz com o "trinado" da bolinha (variação
/// rápida de frequência e volume), um pouco de sopro e entrada/saída suaves.
List<double> _blow(double seconds, Random random) {
  final count = (seconds * _sampleRate).round();
  final samples = List<double>.filled(count, 0);
  var phase = 0.0;
  for (var i = 0; i < count; i++) {
    final t = i / _sampleRate;
    final trill = sin(2 * pi * 32 * t);
    final frequency = 2950 + 140 * trill;
    phase += 2 * pi * frequency / _sampleRate;
    final tone = sin(phase) + 0.25 * sin(2 * phase);
    final breath = (random.nextDouble() * 2 - 1) * 0.08;
    final attack = min(1.0, t / 0.015);
    final release = min(1.0, (seconds - t) / 0.06);
    final volume = (0.8 + 0.2 * trill) * attack * release;
    samples[i] = (tone + breath) * volume * 0.55;
  }
  return samples;
}

List<double> _silence(double seconds) =>
    List<double>.filled((seconds * _sampleRate).round(), 0);

Uint8List _wav(List<double> samples) {
  final data = ByteData(44 + samples.length * 2);
  void ascii(int offset, String text) {
    for (var i = 0; i < text.length; i++) {
      data.setUint8(offset + i, text.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + samples.length * 2, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little); // PCM
  data.setUint16(22, 1, Endian.little); // mono
  data.setUint32(24, _sampleRate, Endian.little);
  data.setUint32(28, _sampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, samples.length * 2, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    final value = (samples[i].clamp(-1.0, 1.0) * 32767).round();
    data.setInt16(44 + i * 2, value, Endian.little);
  }
  return data.buffer.asUint8List();
}

void main() {
  final random = Random(7);
  final sounds = {
    // Início de cada tempo: um apito.
    'whistle_start': [..._blow(0.7, random)],
    // Fim do 1º tempo: curto e longo.
    'whistle_half': [
      ..._blow(0.3, random),
      ..._silence(0.15),
      ..._blow(0.9, random),
    ],
    // Fim de jogo: dois curtos e um longo.
    'whistle_final': [
      ..._blow(0.3, random),
      ..._silence(0.15),
      ..._blow(0.3, random),
      ..._silence(0.15),
      ..._blow(1.2, random),
    ],
  };
  for (final MapEntry(key: name, value: samples) in sounds.entries) {
    File('assets/sounds/$name.wav').writeAsBytesSync(_wav(samples));
  }
}
