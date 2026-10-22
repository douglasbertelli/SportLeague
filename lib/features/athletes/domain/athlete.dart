/// Posições do futebol oferecidas no cadastro do atleta.
const footballPositions = [
  'Goleiro',
  'Zagueiro',
  'Lateral',
  'Volante',
  'Meia',
  'Atacante',
];

/// Atleta de um time (tabela `team_players`). Pode ser só um nome cadastrado
/// pelo administrador ou estar vinculado a um usuário do app ([profileId]).
class Athlete {
  const Athlete({
    this.id,
    required this.teamId,
    required this.name,
    this.position,
    this.jerseyNumber,
    this.profileId,
    this.photoPath,
    this.photoUrl,
  });

  factory Athlete.fromMap(Map<String, dynamic> map) => Athlete(
    id: map['id'] as String,
    teamId: map['team_id'] as String,
    name: map['name'] as String,
    position: map['position'] as String?,
    jerseyNumber: map['jersey_number'] as int?,
    profileId: map['profile_id'] as String?,
    photoPath: map['photo_path'] as String?,
  );

  /// Nulo antes de o atleta ser salvo.
  final String? id;
  final String teamId;
  final String name;
  final String? position;
  final int? jerseyNumber;
  final String? profileId;

  /// Caminho da foto no bucket privado `athlete-photos`. Nulo em atletas
  /// cadastrados antes da foto; o formulário exige ao salvar.
  final String? photoPath;

  /// URL assinada e temporária da foto, gerada ao carregar (não é salva).
  final String? photoUrl;

  Athlete copyWith({
    String? photoPath,
    String? photoUrl,
    bool clearPhoto = false,
  }) => Athlete(
    id: id,
    teamId: teamId,
    name: name,
    position: position,
    jerseyNumber: jerseyNumber,
    profileId: profileId,
    photoPath: clearPhoto ? null : photoPath ?? this.photoPath,
    photoUrl: clearPhoto ? null : photoUrl ?? this.photoUrl,
  );

  Map<String, dynamic> toMap() => {
    'team_id': teamId,
    'name': name.trim(),
    'position': position,
    'jersey_number': jerseyNumber,
    'photo_path': photoPath,
  };
}
