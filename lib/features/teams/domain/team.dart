enum Sport {
  football('Futebol'),
  volleyball('Vôlei'),
  basketball('Basquete');

  const Sport(this.label);

  final String label;

  static Sport fromName(String value) =>
      Sport.values.firstWhere((sport) => sport.name == value);
}

/// Modalidades do futebol; um time pode jogar mais de uma.
enum Modality {
  futsal('Futsal'),
  society('Society'),
  field('Campo'),
  beach('Futebol de Areia');

  const Modality(this.label);

  final String label;

  static Modality fromName(String value) =>
      Modality.values.firstWhere((modality) => modality.name == value);
}

enum TeamGender {
  male('Masculino'),
  female('Feminino');

  const TeamGender(this.label);

  final String label;

  static TeamGender fromName(String value) =>
      TeamGender.values.firstWhere((gender) => gender.name == value);
}

enum AgeGroup {
  open('Livre', 'Sem restrição de idade'),
  youth('Base', '4 a 20 anos'),
  master('Master', 'Idade mínima 35 anos');

  const AgeGroup(this.label, this.description);

  final String label;
  final String description;

  static AgeGroup fromName(String value) =>
      AgeGroup.values.firstWhere((group) => group.name == value);
}

class Team {
  const Team({
    this.id,
    required this.ownerId,
    required this.name,
    this.sport = Sport.football,
    this.modalities = const {},
    this.gender,
    this.ageGroup = AgeGroup.open,
    this.foundedOn,
    this.logoUrl,
    this.description,
    this.city,
    this.state,
  });

  factory Team.fromMap(Map<String, dynamic> map) => Team(
    id: map['id'] as String,
    ownerId: map['owner_id'] as String,
    name: map['name'] as String,
    sport: Sport.fromName(map['sport'] as String),
    // Na ordem do enum, não na ordem em que foram marcadas.
    modalities: {
      for (final modality in Modality.values)
        if ((map['modalities'] as List? ?? const []).contains(modality.name))
          modality,
    },
    gender: switch (map['gender']) {
      final String name => TeamGender.fromName(name),
      _ => null,
    },
    ageGroup: AgeGroup.fromName(map['age_group'] as String? ?? 'open'),
    foundedOn: switch (map['founded_on']) {
      final String date => DateTime.parse(date),
      _ => null,
    },
    logoUrl: map['logo_url'] as String?,
    description: map['description'] as String?,
    city: map['city'] as String?,
    state: map['state'] as String?,
  );

  /// Nulo antes de o time ser salvo.
  final String? id;
  final String ownerId;
  final String name;
  final Sport sport;
  final Set<Modality> modalities;

  /// Nulo em times criados antes deste campo; o formulário exige ao salvar.
  final TeamGender? gender;
  final AgeGroup ageGroup;

  /// Só a data (sem hora).
  final DateTime? foundedOn;
  final String? logoUrl;
  final String? description;
  final String? city;
  final String? state;

  /// "Cidade/UF", só a cidade ou nulo.
  String? get location => switch ((city, state)) {
    (final city?, final state?) => '$city/$state',
    (final city?, null) => city,
    _ => null,
  };

  /// "Futsal, Society · Masculino · Base", para listas.
  String get summary => [
    if (modalities.isNotEmpty) modalities.map((m) => m.label).join(', '),
    ?gender?.label,
    ageGroup.label,
  ].join(' · ');

  Team copyWith({String? logoUrl, bool clearLogo = false}) => Team(
    id: id,
    ownerId: ownerId,
    name: name,
    sport: sport,
    modalities: modalities,
    gender: gender,
    ageGroup: ageGroup,
    foundedOn: foundedOn,
    logoUrl: clearLogo ? null : logoUrl ?? this.logoUrl,
    description: description,
    city: city,
    state: state,
  );

  Map<String, dynamic> toMap() => {
    'owner_id': ownerId,
    'name': name.trim(),
    'sport': sport.name,
    'modalities': [
      for (final modality in Modality.values)
        if (modalities.contains(modality)) modality.name,
    ],
    'gender': gender?.name,
    'age_group': ageGroup.name,
    'founded_on': switch (foundedOn) {
      final date? =>
        '${date.year.toString().padLeft(4, '0')}-'
            '${date.month.toString().padLeft(2, '0')}-'
            '${date.day.toString().padLeft(2, '0')}',
      null => null,
    },
    'logo_url': logoUrl,
    'description': _blankToNull(description),
    'city': _blankToNull(city),
    'state': _blankToNull(state)?.toUpperCase(),
  };
}

String? _blankToNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
