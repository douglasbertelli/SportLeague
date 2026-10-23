import '../../venues/domain/venue.dart';

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
  beach('Areia'),
  challenge('Desafio');

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

/// Faixa de idade. Base e Master têm os limites escolhidos pelo
/// administrador, dentro de [minAllowed] e [maxAllowed].
enum AgeGroup {
  open('Livre'),
  youth('Base', minAllowed: 3, maxAllowed: 25, defaultMin: 4, defaultMax: 20),
  master('Master', minAllowed: 30, maxAllowed: 80, defaultMin: 35);

  const AgeGroup(
    this.label, {
    this.minAllowed,
    this.maxAllowed,
    this.defaultMin,
    this.defaultMax,
  });

  final String label;

  /// Limites que o administrador pode escolher (nulos na Livre).
  final int? minAllowed;
  final int? maxAllowed;

  /// Valores sugeridos ao escolher a faixa.
  final int? defaultMin;
  final int? defaultMax;

  bool get hasMinAge => this != AgeGroup.open;
  bool get hasMaxAge => this == AgeGroup.youth;

  /// "Sem restrição de idade", "13 a 15 anos" ou "A partir de 35 anos".
  String describe({int? minAge, int? maxAge}) => switch (this) {
    AgeGroup.open => 'Sem restrição de idade',
    AgeGroup.youth => '${minAge ?? defaultMin} a ${maxAge ?? defaultMax} anos',
    AgeGroup.master => 'A partir de ${minAge ?? defaultMin} anos',
  };

  static AgeGroup fromName(String value) =>
      AgeGroup.values.firstWhere((group) => group.name == value);
}

/// Como o time aceita jogar amistosos.
enum PlaysAs {
  home('Mandante', 'Recebe os jogos na sua quadra ou campo'),
  away('Visitante', 'Não tem onde receber; joga fora'),
  both('Ambos', 'Joga em casa ou fora');

  const PlaysAs(this.label, this.description);

  final String label;
  final String description;

  /// Se aceita jogar como mandante ([home] verdadeiro) ou visitante.
  bool accepts({required bool home}) => switch (this) {
    PlaysAs.both => true,
    PlaysAs.home => home,
    PlaysAs.away => !home,
  };

  static PlaysAs fromName(String value) =>
      PlaysAs.values.firstWhere((playsAs) => playsAs.name == value);
}

/// No máximo quantas fotos de uniforme o time pode ter.
const maxKits = 3;

class Team {
  const Team({
    this.id,
    required this.ownerId,
    required this.name,
    this.sport = Sport.football,
    this.modalities = const {},
    this.gender,
    this.ageGroup = AgeGroup.open,
    this.minAge,
    this.maxAge,
    this.foundedOn,
    this.logoUrl,
    this.description,
    this.city,
    this.state,
    this.playsAs = PlaysAs.both,
    this.phone,
    this.instagram,
    this.facebook,
    this.youtube,
    this.website,
    this.coverUrl,
    this.kitUrls = const [],
    this.homeVenue,
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
    minAge: map['min_age'] as int?,
    maxAge: map['max_age'] as int?,
    foundedOn: switch (map['founded_on']) {
      final String date => DateTime.parse(date),
      _ => null,
    },
    logoUrl: map['logo_url'] as String?,
    description: map['description'] as String?,
    city: map['city'] as String?,
    state: map['state'] as String?,
    playsAs: PlaysAs.fromName(map['plays_as'] as String? ?? 'both'),
    phone: map['phone'] as String?,
    instagram: map['instagram'] as String?,
    facebook: map['facebook'] as String?,
    youtube: map['youtube'] as String?,
    website: map['website'] as String?,
    coverUrl: map['cover_url'] as String?,
    kitUrls: [...?(map['kit_urls'] as List?)?.cast<String>()],
    homeVenue: switch (map['home_venue']) {
      final Map<String, dynamic> venue => Venue.fromMap(venue),
      _ => null,
    },
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

  /// Idade mínima (Base e Master) e máxima (Base).
  final int? minAge;
  final int? maxAge;

  /// "13 a 15 anos", "A partir de 35 anos"...
  String get ageRange => ageGroup.describe(minAge: minAge, maxAge: maxAge);

  /// Só a data (sem hora).
  final DateTime? foundedOn;
  final String? logoUrl;
  final String? description;
  final String? city;
  final String? state;
  final PlaysAs playsAs;

  /// Só os dígitos, com DDD.
  final String? phone;

  /// Usuário, sem o "@".
  final String? instagram;

  /// Endereços (ou usuário, no Facebook e YouTube), como digitados.
  final String? facebook;
  final String? youtube;
  final String? website;

  /// Imagem de capa e fotos dos uniformes (até [maxKits]), para o adversário
  /// reconhecer o time e as cores da camisa.
  final String? coverUrl;
  final List<String> kitUrls;

  /// Local onde o time joga como mandante; vem preenchido ao marcar
  /// amistoso. Carregado junto com o time (select com home_venue).
  final Venue? homeVenue;

  /// Se tem algum contato para mostrar.
  bool get hasContacts =>
      phone != null ||
      instagram != null ||
      facebook != null ||
      youtube != null ||
      website != null;

  /// "Cidade/UF", só a cidade ou nulo.
  String? get location => switch ((city, state)) {
    (final city?, final state?) => '$city/$state',
    (final city?, null) => city,
    _ => null,
  };

  /// "Society · Masculino · Base 13-15", para listas.
  String get summary => [
    if (modalities.isNotEmpty) modalities.map((m) => m.label).join(', '),
    ?gender?.label,
    switch (ageGroup) {
      AgeGroup.open => ageGroup.label,
      AgeGroup.youth =>
        'Base ${minAge ?? ageGroup.defaultMin}-'
            '${maxAge ?? ageGroup.defaultMax}',
      AgeGroup.master => 'Master ${minAge ?? ageGroup.defaultMin}+',
    },
  ].join(' · ');

  Team copyWith({
    String? logoUrl,
    bool clearLogo = false,
    String? coverUrl,
    bool clearCover = false,
    List<String>? kitUrls,
    Venue? homeVenue,
    bool clearHomeVenue = false,
  }) => Team(
    id: id,
    ownerId: ownerId,
    name: name,
    sport: sport,
    modalities: modalities,
    gender: gender,
    ageGroup: ageGroup,
    minAge: minAge,
    maxAge: maxAge,
    foundedOn: foundedOn,
    logoUrl: clearLogo ? null : logoUrl ?? this.logoUrl,
    description: description,
    city: city,
    state: state,
    playsAs: playsAs,
    phone: phone,
    instagram: instagram,
    facebook: facebook,
    youtube: youtube,
    website: website,
    coverUrl: clearCover ? null : coverUrl ?? this.coverUrl,
    kitUrls: kitUrls ?? this.kitUrls,
    homeVenue: clearHomeVenue ? null : homeVenue ?? this.homeVenue,
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
    'min_age': ageGroup.hasMinAge ? minAge ?? ageGroup.defaultMin : null,
    'max_age': ageGroup.hasMaxAge ? maxAge ?? ageGroup.defaultMax : null,
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
    'plays_as': playsAs.name,
    'phone': switch (phone?.replaceAll(RegExp(r'\D'), '')) {
      final digits? when digits.isNotEmpty => digits,
      _ => null,
    },
    'instagram': _blankToNull(instagram?.trim().replaceFirst('@', '')),
    'facebook': _blankToNull(facebook),
    'youtube': _blankToNull(youtube),
    'website': _blankToNull(website),
    'cover_url': coverUrl,
    'kit_urls': kitUrls,
    'home_venue_id': homeVenue?.id,
  };
}

String? _blankToNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
