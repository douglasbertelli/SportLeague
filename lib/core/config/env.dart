/// Configuração lida em tempo de compilação via `--dart-define` ou
/// `--dart-define-from-file=env.json`.
abstract final class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Client IDs do Google Cloud para o login nativo com Google. O "Web" é o
  /// mesmo configurado no provedor Google do Supabase; o "iOS" só é usado no
  /// iPhone.
  static const googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
  );
  static const googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
  );

  /// Chave pública do SDK do Adapty (App settings > General > API keys).
  /// Sem ela, o app não vende a assinatura (mostra "em breve").
  static const adaptyPublicKey = String.fromEnvironment('ADAPTY_PUBLIC_KEY');

  /// Placement do Adapty com o produto do Premium.
  static const adaptyPlacementId = String.fromEnvironment(
    'ADAPTY_PLACEMENT_ID',
    defaultValue: 'premium',
  );

  /// Endereço do site (sportleague-web), usado nos links compartilhados.
  static const webUrl = String.fromEnvironment('WEB_URL');

  /// Endereço do site para links compartilhados (perfil público, convite):
  /// o [webUrl] ou, sem ele, o site de produção.
  static String get siteUrl =>
      webUrl.isEmpty ? 'https://app.sportleague.com.br' : webUrl;

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
