enum Sport {
  football('Futebol'),
  volleyball('Vôlei'),
  basketball('Basquete');

  const Sport(this.label);

  final String label;

  static Sport fromName(String value) =>
      Sport.values.firstWhere((sport) => sport.name == value);
}

class Team {
  const Team({
    this.id,
    required this.ownerId,
    required this.name,
    this.sport = Sport.football,
    this.description,
    this.city,
    this.state,
  });

  factory Team.fromMap(Map<String, dynamic> map) => Team(
    id: map['id'] as String,
    ownerId: map['owner_id'] as String,
    name: map['name'] as String,
    sport: Sport.fromName(map['sport'] as String),
    description: map['description'] as String?,
    city: map['city'] as String?,
    state: map['state'] as String?,
  );

  /// Nulo antes de o time ser salvo.
  final String? id;
  final String ownerId;
  final String name;
  final Sport sport;
  final String? description;
  final String? city;
  final String? state;

  /// "Cidade/UF", só a cidade ou nulo.
  String? get location => switch ((city, state)) {
    (final city?, final state?) => '$city/$state',
    (final city?, null) => city,
    _ => null,
  };

  Map<String, dynamic> toMap() => {
    'owner_id': ownerId,
    'name': name.trim(),
    'sport': sport.name,
    'description': _blankToNull(description),
    'city': _blankToNull(city),
    'state': _blankToNull(state)?.toUpperCase(),
  };
}

String? _blankToNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
