import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../domain/address.dart';

/// Consulta de CEP usando a API pública do ViaCEP.
class ZipCodeService {
  ZipCodeService(this._client);

  final http.Client _client;

  /// Retorna `null` se o CEP não existir.
  Future<ZipCodeLookup?> lookup(String zipCode) async {
    final digits = zipCode.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 8) return null;

    final response = await _client.get(
      Uri.parse('https://viacep.com.br/ws/$digits/json/'),
    );
    if (response.statusCode != 200) return null;

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (body['erro'] != null) return null;

    return ZipCodeLookup(
      street: body['logradouro'] as String? ?? '',
      neighborhood: body['bairro'] as String? ?? '',
      city: body['localidade'] as String? ?? '',
      state: body['uf'] as String? ?? '',
    );
  }
}

final zipCodeServiceProvider = Provider<ZipCodeService>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return ZipCodeService(client);
});
