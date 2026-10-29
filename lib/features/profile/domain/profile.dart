enum UserRole {
  admin('Administrador', 'Cria e gerencia times e jogadores'),
  player('Jogador', 'Entra em times por busca ou convite'),
  coach('Técnico', 'Acompanha os times, monta a escalação e a súmula');

  const UserRole(this.label, this.description);

  final String label;
  final String description;

  static UserRole fromName(String value) =>
      UserRole.values.firstWhere((role) => role.name == value);
}

enum SubscriptionPlan {
  free('Gratuito'),
  premium('Premium');

  const SubscriptionPlan(this.label);

  final String label;

  static SubscriptionPlan fromName(String value) =>
      SubscriptionPlan.values.firstWhere((plan) => plan.name == value);
}

/// Pé dominante do jogador.
enum PreferredFoot {
  right('Direito'),
  left('Esquerdo'),
  both('Os dois');

  const PreferredFoot(this.label);

  final String label;

  static PreferredFoot fromName(String value) =>
      PreferredFoot.values.firstWhere((foot) => foot.name == value);
}

class Profile {
  const Profile({
    required this.id,
    required this.fullName,
    this.role,
    required this.plan,
    this.phone,
    this.avatarUrl,
    this.birthDate,
    this.preferredPosition,
    this.preferredFoot,
    this.heightCm,
    this.code,
    this.coverUrl,
    this.nickname,
  });

  factory Profile.fromMap(Map<String, dynamic> map) => Profile(
    id: map['id'] as String,
    fullName: map['full_name'] as String,
    role: switch (map['role']) {
      final String name => UserRole.fromName(name),
      _ => null,
    },
    plan: SubscriptionPlan.fromName(map['plan'] as String),
    phone: map['phone'] as String?,
    avatarUrl: map['avatar_url'] as String?,
    birthDate: switch (map['birth_date']) {
      final String date => DateTime.parse(date),
      _ => null,
    },
    preferredPosition: map['preferred_position'] as String?,
    preferredFoot: switch (map['preferred_foot']) {
      final String name => PreferredFoot.fromName(name),
      _ => null,
    },
    heightCm: map['height_cm'] as int?,
    code: map['code'] as String?,
    coverUrl: map['cover_url'] as String?,
    nickname: map['nickname'] as String?,
  );

  /// Nome usado pelo trigger `handle_new_user` quando o cadastro não traz um
  /// nome (por exemplo, Apple pelo navegador).
  static const placeholderName = 'Usuário';

  final String id;
  final String fullName;

  /// Nulo até o usuário escolher, logo depois de criar a conta.
  final UserRole? role;
  final SubscriptionPlan plan;
  final String? phone;
  final String? avatarUrl;

  /// Dados de atleta, que o jogador preenche no Perfil.
  final DateTime? birthDate;
  final String? preferredPosition;
  final PreferredFoot? preferredFoot;
  final int? heightCm;

  /// Código pessoal: JG + 6 do jogador, TC + 6 do técnico (nulo para o
  /// administrador). O administrador convida pelo código.
  final String? code;

  /// Capa do perfil do jogador: a imagem larga atrás da foto.
  final String? coverUrl;

  /// Apelido do jogador, o nome mostrado no perfil dele.
  final String? nickname;

  /// O apelido, ou o nome completo sem apelido.
  String get displayName => nickname ?? fullName;

  /// Idade completa em [today] (hoje, por padrão).
  int? age([DateTime? today]) {
    final birth = birthDate;
    if (birth == null) return null;
    final now = today ?? DateTime.now();
    final hadBirthday =
        now.month > birth.month ||
        (now.month == birth.month && now.day >= birth.day);
    return now.year - birth.year - (hadBirthday ? 0 : 1);
  }

  bool get hasAthleteData =>
      birthDate != null ||
      preferredPosition != null ||
      preferredFoot != null ||
      heightCm != null;

  bool get needsRole => role == null;
  bool get needsName => fullName == placeholderName;
  bool get isAdmin => role == UserRole.admin;
  bool get isCoach => role == UserRole.coach;
  bool get isPlayer => role == UserRole.player;

  /// Administrador ou técnico: usa o app pelo time ativo (Início, Jogos,
  /// Atletas).
  bool get hasTeamHome => isAdmin || isCoach;
  bool get isPremium => plan == SubscriptionPlan.premium;
}
