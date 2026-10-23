abstract final class Routes {
  static const splash = '/splash';
  static const login = '/login';
  static const signUp = '/signup';
  static const onboardingProfile = '/onboarding/profile';
  static const onboardingAddress = '/onboarding/address';
  static const home = '/home';
  static const editAddress = '/home/address';
  static const teams = '/home/teams';
  static const newTeam = '/home/teams/new';

  /// Recebe o `Team` em `extra`.
  static const editTeam = '/home/teams/edit';

  /// Perfil de um time (capa, contatos e uniformes); recebe o id em `extra`.
  static const teamProfile = '/home/teams/profile';

  /// Pesquisa de times da plataforma.
  static const teamSearch = '/home/teams/search';
  static const newAthlete = '/home/athletes/new';

  /// Recebe o `Athlete` em `extra`.
  static const editAthlete = '/home/athletes/edit';
  static const newGame = '/home/games/new';

  /// Recebe o `Game` em `extra`.
  static const editGame = '/home/games/edit';

  /// Recebe `(teamId:, modality:)` em `extra`; devolve o `Opponent` no `pop`.
  static const pickOpponent = '/home/games/opponent';

  /// Calendário de disponibilidade do time ativo.
  static const availability = '/home/availability';

  /// Locais das partidas (cadastro e pesquisa).
  static const venues = '/home/venues';

  /// Recebe o nome já digitado (`String`) em `extra`; devolve o `Venue` salvo
  /// ou o existente escolhido no `pop`.
  static const newVenue = '/home/venues/new';

  /// Recebe o `Venue` em `extra`.
  static const editVenue = '/home/venues/edit';

  /// Escolha do local do amistoso; devolve o `Venue` no `pop`.
  static const pickVenue = '/home/games/venue';

  /// Escolha do local do time, no formulário do time; devolve o `Venue`.
  static const pickTeamVenue = '/home/teams/venue';
}
