/// Pix copia-e-cola (BR Code estático, padrão EMV do Banco Central) para
/// pagar direto na chave do time: o app só monta o código; o dinheiro vai do
/// banco de quem paga para a conta da chave.
///
/// [amountCents] nulo deixa o valor em aberto (quem paga digita).
String pixPayload({
  required String key,
  required String name,
  String city = 'BRASIL',
  int? amountCents,
  String txid = '***',
}) {
  String field(String id, String value) =>
      '$id${value.length.toString().padLeft(2, '0')}$value';

  final account = field('00', 'br.gov.bcb.pix') + field('01', key.trim());
  final payload = StringBuffer()
    ..write(field('00', '01'))
    ..write(field('26', account))
    ..write(field('52', '0000'))
    ..write(field('53', '986'));
  if (amountCents != null && amountCents > 0) {
    payload.write(field('54', (amountCents / 100).toStringAsFixed(2)));
  }
  payload
    ..write(field('58', 'BR'))
    ..write(field('59', _clean(name, 25, fallback: 'TIME')))
    ..write(field('60', _clean(city, 15, fallback: 'BRASIL')))
    ..write(
      field('62', field('05', _clean(txid, 25, fallback: '***', keep: '*'))),
    )
    ..write('6304');
  final text = payload.toString();
  return '$text${_crc16(text)}';
}

/// Sem acentos, só letras, números e espaço (o que os bancos aceitam) e
/// no tamanho máximo.
String _clean(
  String value,
  int max, {
  required String fallback,
  String keep = '',
}) {
  const from = 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑáàâãäéèêëíìîïóòôõöúùûüçñ';
  const to = 'AAAAAEEEEIIIIOOOOOUUUUCNaaaaaeeeeiiiiooooouuuucn';
  final buffer = StringBuffer();
  for (final char in value.split('')) {
    final index = from.indexOf(char);
    final plain = index >= 0 ? to[index] : char;
    if (RegExp('[A-Za-z0-9 ]').hasMatch(plain) || keep.contains(plain)) {
      buffer.write(plain);
    }
  }
  final cleaned = buffer.toString().trim().replaceAll(RegExp(' +'), ' ');
  if (cleaned.isEmpty) return fallback;
  return cleaned.length > max ? cleaned.substring(0, max).trim() : cleaned;
}

/// CRC16-CCITT (polinômio 0x1021, início 0xFFFF), em 4 dígitos hexadecimais.
String _crc16(String text) {
  var crc = 0xFFFF;
  for (final unit in text.codeUnits) {
    crc ^= unit << 8;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 0x8000) != 0 ? ((crc << 1) ^ 0x1021) : (crc << 1);
      crc &= 0xFFFF;
    }
  }
  return crc.toRadixString(16).toUpperCase().padLeft(4, '0');
}
