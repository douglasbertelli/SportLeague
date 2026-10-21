enum UserRole {
  admin('Administrador', 'Cria e gerencia times e jogadores'),
  player('Jogador', 'Entra em times por busca ou convite');

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

class Profile {
  const Profile({
    required this.id,
    required this.fullName,
    this.role,
    required this.plan,
    this.phone,
    this.avatarUrl,
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
  );

  final String id;
  final String fullName;

  /// Nulo em contas criadas por login social até o usuário escolher.
  final UserRole? role;
  final SubscriptionPlan plan;
  final String? phone;
  final String? avatarUrl;

  bool get needsRole => role == null;
  bool get isAdmin => role == UserRole.admin;
  bool get isPremium => plan == SubscriptionPlan.premium;
}
