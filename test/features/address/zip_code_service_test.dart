import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sport_league/features/address/data/zip_code_service.dart';
import 'package:sport_league/features/address/domain/address.dart';

void main() {
  test('preenche o endereço a partir do ViaCEP', () async {
    late Uri requested;
    final service = ZipCodeService(
      MockClient((request) async {
        requested = request.url;
        return http.Response(
          jsonEncode({
            'logradouro': 'Avenida Paulista',
            'bairro': 'Bela Vista',
            'localidade': 'São Paulo',
            'uf': 'SP',
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final result = await service.lookup('01310-100');

    expect(requested.path, '/ws/01310100/json/');
    expect(result?.street, 'Avenida Paulista');
    expect(result?.city, 'São Paulo');
    expect(result?.state, 'SP');
  });

  test('retorna null para CEP inexistente', () async {
    final service = ZipCodeService(
      MockClient((_) async => http.Response('{"erro": "true"}', 200)),
    );
    expect(await service.lookup('99999999'), isNull);
  });

  test('Address normaliza a UF ao salvar', () {
    const address = Address(
      profileId: 'u1',
      zipCode: '01310100',
      street: 'Avenida Paulista',
      number: '1000',
      neighborhood: 'Bela Vista',
      city: 'São Paulo',
      state: 'sp',
    );
    expect(address.toMap()['state'], 'SP');
    expect(Address.fromMap({...address.toMap(), 'id': 'a1'}).id, 'a1');
  });
}
