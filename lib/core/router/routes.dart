abstract final class Routes {
  static const splash = '/splash';
  static const login = '/login';
  static const signUp = '/signup';
  static const onboardingProfile = '/onboarding/profile';
  static const onboardingAddress = '/onboarding/address';

  /// Conta marcada para exclusão (inativa por 7 dias): reativar ou sair.
  static const accountInactive = '/account-inactive';

  /// Documentos legais (abertos também sem login).
  static const privacy = '/privacy';
  static const terms = '/terms';

  /// Aceite dos Termos e da Política (contas sem o aceite da versão atual).
  static const acceptTerms = '/accept-terms';

  static const home = '/home';
  static const editAddress = '/home/address';

  /// Dados de atleta do jogador (aba Perfil); recebe o `Profile` em `extra`.
  static const athleteData = '/home/athlete-data';

  /// Código pessoal do jogador ou do técnico (aba Config).
  static const myCode = '/home/my-code';

  /// Central de notificações (sino do topo).
  static const notifications = '/home/notifications';
  static const teams = '/home/teams';
  static const newTeam = '/home/teams/new';

  /// Recebe o `Team` em `extra`.
  static const editTeam = '/home/teams/edit';

  /// Perfil de um time (capa, contatos e uniformes); recebe o id em `extra`.
  static const teamProfile = '/home/teams/profile';

  /// Pesquisa de times da plataforma.
  static const teamSearch = '/home/teams/search';

  /// Convites do time ativo (administrador): código e pedidos.
  static const teamInvites = '/home/invites';

  /// Convites do jogador: entrar com código, times e pedidos.
  static const playerInvites = '/home/my-invites';

  /// Pesquisa de jogadores do app para convidar ao time ativo.
  static const invitePlayer = '/home/invites/player';
  static const newAthlete = '/home/athletes/new';

  /// Recebe o `Athlete` em `extra`.
  static const editAthlete = '/home/athletes/edit';

  /// Números do atleta. Recebe o `Athlete` em `extra`.
  static const athleteProfile = '/home/athletes/profile';
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

  /// Vaquinhas do time (menu lateral).
  static const fundraisers = '/home/fundraisers';

  /// Cria ou edita a vaquinha; recebe `FundraiserArgs` em `extra`.
  static const fundraiserForm = '/home/fundraisers/form';

  /// Uma vaquinha e quem pagou; recebe `FundraiserArgs` em `extra`.
  static const fundraiser = '/home/fundraisers/detail';

  /// Mensalidade do time (menu lateral).
  static const dues = '/home/dues';

  /// Financeiro do administrador: plano, valor mensal e pagamentos.
  static const finance = '/home/finance';

  /// Planos (Gratuito e Premium) e o que cada um libera.
  static const plans = '/home/plans';

  /// Campeonatos do usuário (menu lateral).
  static const championships = '/home/championships';

  /// Cria ou edita (antes de começar); recebe o `Championship` em `extra`
  /// para editar.
  static const championshipForm = '/home/championships/form';

  /// Um campeonato; recebe o id em `extra`.
  static const championship = '/home/championships/detail';

  /// Escolha de um time para o campeonato; recebe
  /// `ChampionshipTeamPickerArgs` em `extra`.
  static const championshipTeamPicker = '/home/championships/pick-team';
}
