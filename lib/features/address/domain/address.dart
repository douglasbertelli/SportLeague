class Address {
  const Address({
    this.id,
    required this.profileId,
    required this.zipCode,
    required this.street,
    required this.number,
    this.complement,
    required this.neighborhood,
    required this.city,
    required this.state,
    this.country = 'BR',
  });

  factory Address.fromMap(Map<String, dynamic> map) => Address(
    id: map['id'] as String?,
    profileId: map['profile_id'] as String,
    zipCode: map['zip_code'] as String,
    street: map['street'] as String,
    number: map['number'] as String,
    complement: map['complement'] as String?,
    neighborhood: map['neighborhood'] as String,
    city: map['city'] as String,
    state: map['state'] as String,
    country: map['country'] as String? ?? 'BR',
  );

  final String? id;
  final String profileId;
  final String zipCode;
  final String street;
  final String number;
  final String? complement;
  final String neighborhood;
  final String city;
  final String state;
  final String country;

  Map<String, dynamic> toMap() => {
    'profile_id': profileId,
    'zip_code': zipCode,
    'street': street,
    'number': number,
    'complement': complement,
    'neighborhood': neighborhood,
    'city': city,
    'state': state.toUpperCase(),
    'country': country,
  };
}

/// Resultado da consulta de CEP (campos preenchidos automaticamente).
class ZipCodeLookup {
  const ZipCodeLookup({
    required this.street,
    required this.neighborhood,
    required this.city,
    required this.state,
  });

  final String street;
  final String neighborhood;
  final String city;
  final String state;
}
