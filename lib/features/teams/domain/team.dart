import '../../venues/domain/venue.dart';

enum Sport {
  football('Futebol'),
  volleyball('Vôlei'),
  basketball('Basquete');

  const Sport(this.label);

  final String label;

  static Sport fromName(String value) =>
      Sport.values.firstWhere((sport) => sport.name == value);

  /// Nulo para um esporte que esta versão do app não conhece (de uma versão
  /// mais nova): o que vem do banco usa esta, para não quebrar.
  static Sport? tryFromName(String? value) =>
      Sport.values.where((sport) => sport.name == value).firstOrNull;
}

/// Modalidades; cada uma é de um esporte ([sport]). Como os jogos só
/// acontecem entre times da mesma modalidade, o esporte de um jogo ou
/// campeonato sai da modalidade. As do vôlei existem no código, mas só
/// aparecem quando o vôlei entrar em `supportedSports`.
enum Modality {
  futsal('Futsal', Sport.football),
  society('Society', Sport.football),
  field('Campo', Sport.football),
  beach('Areia', Sport.football),
  challenge('Desafio', Sport.football),
  volleyballIndoor('Quadra', Sport.volleyball, 'volleyball_indoor'),
  volleyballBeach('Praia', Sport.volleyball, 'volleyball_beach');

  const Modality(this.label, this.sport, [this._key]);

  final String label;
  final Sport sport;
  final String? _key;

  /// Valor no banco (`team_modality`): o nome do enum, ou a chave própria
  /// quando o nome não serve ("volleyball_indoor").
  String get key => _key ?? name;

  /// "Vôlei · Praia", para as listas que misturam esportes (a "Areia" do
  /// futebol e a "Praia" do vôlei lado a lado).
  String get fullLabel => '${sport.label} · $label';

  /// Modalidades do [sport], na ordem do enum.
  static List<Modality> of(Sport sport) => [
    for (final modality in values)
      if (modality.sport == sport) modality,
  ];

  static Modality fromName(String value) =>
      Modality.values.firstWhere((modality) => modality.key == value);

  /// Nula para uma modalidade que esta versão do app não conhece (de um
  /// esporte novo): o que vem do banco usa esta, para não quebrar.
  static Modality? tryFromName(String? value) =>
      Modality.values.where((modality) => modality.key == value).firstOrNull;
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
    this.inactiveAt,
  });

  factory Team.fromMap(Map<String, dynamic> map) => Team(
    id: map['id'] as String,
    ownerId: map['owner_id'] as String,
    name: map['name'] as String,
    // Esporte desconhecido (de uma versão mais nova) vira futebol só para não
    // quebrar; as listas já tiram esses times (isSupportedSportRow).
    sport: Sport.tryFromName(map['sport'] as String?) ?? Sport.football,
    // Na ordem do enum, não na ordem em que foram marcadas.
    modalities: {
      for (final modality in Modality.values)
        if ((map['modalities'] as List? ?? const []).contains(modality.key))
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
    inactiveAt: switch (map['inactive_at']) {
      final String at => DateTime.parse(at).toLocal(),
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

  /// Quando o time foi inativado (some das buscas e da troca de time; o
  /// histórico fica). Nulo no time ativo.
  final DateTime? inactiveAt;

  bool get isActive => inactiveAt == null;

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

  /// "Futebol · Society · Masculino · Base 13-15", para listas. O esporte vem
  /// primeiro para distinguir os times de cada esporte.
  String get summary => [
    sport.label,
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
    inactiveAt: inactiveAt,
  );

  Map<String, dynamic> toMap() => {
    'owner_id': ownerId,
    'name': name.trim(),
    'sport': sport.name,
    'modalities': [
      for (final modality in Modality.values)
        if (modalities.contains(modality)) modality.key,
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
