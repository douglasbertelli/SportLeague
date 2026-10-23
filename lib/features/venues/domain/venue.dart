/// Local onde as partidas acontecem (quadra, campo, arena). Compartilhado
/// entre os administradores; só quem cadastrou ([createdBy]) altera.
class Venue {
  const Venue({
    this.id,
    this.createdBy,
    required this.name,
    required this.zipCode,
    required this.street,
    required this.number,
    this.complement,
    required this.neighborhood,
    required this.city,
    required this.state,
    this.photoUrl,
  });

  factory Venue.fromMap(Map<String, dynamic> map) => Venue(
    id: map['id'] as String?,
    createdBy: map['created_by'] as String?,
    name: map['name'] as String,
    zipCode: map['zip_code'] as String,
    street: map['street'] as String,
    number: map['number'] as String,
    complement: map['complement'] as String?,
    neighborhood: map['neighborhood'] as String,
    city: map['city'] as String,
    state: map['state'] as String,
    photoUrl: map['photo_url'] as String?,
  );

  /// Nulo antes de ser salvo.
  final String? id;

  /// Administrador que cadastrou; nulo se a conta foi excluída.
  final String? createdBy;
  final String name;

  /// Só os 8 dígitos.
  final String zipCode;
  final String street;
  final String number;
  final String? complement;
  final String neighborhood;
  final String city;
  final String state;
  final String? photoUrl;

  /// "Rua das Flores, 120, Bloco B - Centro".
  String get streetLine {
    final complement = this.complement;
    final hasComplement = complement != null && complement.isNotEmpty;
    return '$street, $number${hasComplement ? ', $complement' : ''} - '
        '$neighborhood';
  }

  /// "Campinas/SP".
  String get cityLine => '$city/$state';

  /// Endereço completo em uma linha.
  String get address => '$streetLine, $cityLine';

  Venue copyWith({String? id, String? photoUrl, bool removePhoto = false}) =>
      Venue(
        id: id ?? this.id,
        createdBy: createdBy,
        name: name,
        zipCode: zipCode,
        street: street,
        number: number,
        complement: complement,
        neighborhood: neighborhood,
        city: city,
        state: state,
        photoUrl: removePhoto ? null : photoUrl ?? this.photoUrl,
      );

  Map<String, dynamic> toMap() {
    final complement = this.complement?.trim();
    return {
      'created_by': createdBy,
      'name': name.trim(),
      'zip_code': zipCode.replaceAll(RegExp(r'\D'), ''),
      'street': street.trim(),
      'number': number.trim(),
      'complement': complement == null || complement.isEmpty
          ? null
          : complement,
      'neighborhood': neighborhood.trim(),
      'city': city.trim(),
      'state': state.trim().toUpperCase(),
      'photo_url': photoUrl,
    };
  }
}
