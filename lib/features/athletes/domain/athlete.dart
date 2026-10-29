/// Posições do futebol oferecidas no cadastro do atleta.
const footballPositions = [
  'Goleiro',
  'Zagueiro',
  'Lateral',
  'Volante',
  'Meia',
  'Atacante',
  'Centroavante',
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
    this.profilePhotoUrl,
    this.profileNickname,
    this.profileFullName,
  });

  factory Athlete.fromMap(Map<String, dynamic> map) => Athlete(
    id: map['id'] as String,
    teamId: map['team_id'] as String,
    name: map['name'] as String,
    position: map['position'] as String?,
    jerseyNumber: map['jersey_number'] as int?,
    profileId: map['profile_id'] as String?,
    photoPath: map['photo_path'] as String?,
    profilePhotoUrl: switch (map['profile']) {
      {'avatar_url': final String url} => url,
      _ => null,
    },
    profileNickname: switch (map['profile']) {
      {'nickname': final String nickname} => nickname,
      _ => null,
    },
    profileFullName: switch (map['profile']) {
      {'full_name': final String fullName} => fullName,
      _ => null,
    },
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

  /// URL da foto mostrada, gerada ao carregar (não é salva): a assinada da
  /// foto do atleta ou, sem ela, a foto do perfil do jogador vinculado.
  final String? photoUrl;

  /// Foto do perfil do jogador vinculado ([profileId]), a que ele mesmo envia
  /// no app. Quem entra pelo convite chega sem foto de atleta e usa esta.
  final String? profilePhotoUrl;

  /// Apelido que o jogador vinculado escolheu no perfil dele.
  final String? profileNickname;

  /// Nome completo do perfil do jogador vinculado.
  final String? profileFullName;

  /// Nome mostrado nas telas. Do jogador vinculado, o que ele escolheu no
  /// perfil (o apelido ou, sem ele, o nome completo), que só ele altera; do
  /// atleta sem conta, o nome cadastrado no time ([name]).
  String get displayName => profileNickname ?? profileFullName ?? name;

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
    profilePhotoUrl: profilePhotoUrl,
    profileNickname: profileNickname,
    profileFullName: profileFullName,
  );

  Map<String, dynamic> toMap() => {
    'team_id': teamId,
    'name': name.trim(),
    'position': position,
    'jersey_number': jerseyNumber,
    'photo_path': photoPath,
  };
}
