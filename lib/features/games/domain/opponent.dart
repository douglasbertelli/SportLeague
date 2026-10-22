import '../../teams/domain/team.dart';

/// Time fictício: adversário que não está na plataforma, salvo pelo
/// administrador para reutilizar em outros jogos da mesma modalidade.
class GuestTeam {
  const GuestTeam({
    this.id,
    required this.ownerId,
    required this.name,
    required this.modality,
  });

  factory GuestTeam.fromMap(Map<String, dynamic> map) => GuestTeam(
    id: map['id'] as String,
    ownerId: map['owner_id'] as String,
    name: map['name'] as String,
    modality: Modality.fromName(map['modality'] as String),
  );

  final String? id;
  final String ownerId;
  final String name;
  final Modality modality;

  Map<String, dynamic> toMap() => {
    'owner_id': ownerId,
    'name': name.trim(),
    'modality': modality.name,
  };
}

/// Adversário escolhido para o jogo.
sealed class Opponent {
  const Opponent();

  String get name;
}

/// Time cadastrado na plataforma.
class RegisteredOpponent extends Opponent {
  const RegisteredOpponent(this.team);

  final Team team;

  @override
  String get name => team.name;
}

/// Time fictício do administrador.
class GuestOpponent extends Opponent {
  const GuestOpponent(this.guest);

  final GuestTeam guest;

  @override
  String get name => guest.name;
}

/// Adversário de um jogo já salvo, conhecido só pelos ids e pelo nome.
class SavedOpponent extends Opponent {
  const SavedOpponent({required this.name, this.teamId, this.guestId});

  @override
  final String name;
  final String? teamId;
  final String? guestId;
}
