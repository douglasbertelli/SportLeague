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
  static const newAthlete = '/home/athletes/new';

  /// Recebe o `Athlete` em `extra`.
  static const editAthlete = '/home/athletes/edit';
  static const newGame = '/home/games/new';

  /// Recebe o `Game` em `extra`.
  static const editGame = '/home/games/edit';
}
