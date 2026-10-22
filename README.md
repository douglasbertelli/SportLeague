# SportLeague

Aplicativo para conectar times esportivos e marcar amistosos e campeonatos.
Começa pelo **futebol**; vôlei, basquete e outros esportes virão depois.

## Stack

- Flutter + [Riverpod](https://riverpod.dev) (estado) + [go_router](https://pub.dev/packages/go_router) (navegação)
- [Supabase](https://supabase.com) (Auth + Postgres com RLS)
- [ViaCEP](https://viacep.com.br) para preenchimento de endereço

## Configuração

1. No painel do Supabase, abra **SQL Editor** e execute os arquivos de
   `supabase/migrations/` em ordem (ou `supabase db push` com a Supabase CLI).
2. Copie `env.example.json` para `env.json` e preencha com a URL e a anon key do
   projeto (**Project Settings → API**). O `env.json` não é versionado.
3. Rode o app:

   ```sh
   flutter pub get
   flutter run --dart-define-from-file=env.json
   ```

> Por padrão o Supabase exige confirmação de e-mail. Depois do cadastro o
> usuário confirma pelo link recebido e faz login.

### Login com Google e Apple

O login social entra na conta existente ou cria uma nova. Como no cadastro por
e-mail, no primeiro acesso o app abre **Escolha seu perfil** antes do endereço
(e pede o nome se o provedor não enviou um).

| Plataforma | Google                         | Apple                            |
| ---------- | ------------------------------ | -------------------------------- |
| Android    | Nativo (`google_sign_in`)      | Navegador (OAuth do Supabase)    |
| iOS        | Nativo (`google_sign_in`)      | Nativo (`sign_in_with_apple`)    |
| Demais     | Navegador (OAuth do Supabase)  | Navegador (OAuth do Supabase)    |

O retorno do navegador usa o deep link `com.sportleague.sportleague://login-callback`.

**Supabase** (Authentication):

1. **URL Configuration → Redirect URLs**: adicione
   `com.sportleague.sportleague://login-callback`.
2. **Sign In / Providers → Google**: ative, informe o Client ID e o Client
   Secret do client **Web** e, em *Authorized Client IDs*, os client IDs Web,
   Android e iOS separados por vírgula. Ative **Skip nonce checks** (o SDK do
   Google no iOS envia um nonce que o app não controla).
3. **Sign In / Providers → Apple**: ative e informe o Services ID, o Team ID,
   o Key ID e a chave `.p8` (necessários para o login pelo navegador no
   Android). Em *Client IDs*, inclua também o bundle ID `com.sportleague.sportLeague`.

**Google Cloud** (APIs & Services → Credentials), três OAuth client IDs:

- **Web**: o redirect autorizado é
  `https://<projeto>.supabase.co/auth/v1/callback`. É o `GOOGLE_WEB_CLIENT_ID`.
- **Android**: pacote `com.sportleague.sport_league` e o SHA-1 da chave de
  assinatura. Para a chave de debug:

  ```sh
  keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
  ```

  Na publicação, cadastre também o SHA-1 da chave de release / Play App Signing.
- **iOS**: bundle ID `com.sportleague.sportLeague`. É o `GOOGLE_IOS_CLIENT_ID`;
  adicione também o *iOS URL scheme* (client ID invertido) em
  `CFBundleURLTypes` no `ios/Runner/Info.plist`.

**Apple Developer**: ative *Sign in with Apple* no App ID
`com.sportleague.sportLeague` e adicione a capability **Sign in with Apple**
no target Runner pelo Xcode. Para o login pelo navegador (Android), crie um
Services ID com o retorno `https://<projeto>.supabase.co/auth/v1/callback`.

Por fim, preencha `GOOGLE_WEB_CLIENT_ID` e `GOOGLE_IOS_CLIENT_ID` no
`env.json`. Sem o client ID Web, o botão do Google avisa que o login não está
configurado.

## Fluxo atual

1. **Cadastro** com nome, e-mail e senha, ou **login social** com Google ou Apple.
2. **Login** e recuperação de senha.
3. **Escolha do perfil** (obrigatória no primeiro acesso):
   - **Administrador**: cria e gerencia times e jogadores.
   - **Jogador**: entra em times por busca ou convite.
4. **Cadastro de endereço** (obrigatório no primeiro acesso), com busca por CEP.
5. **Home** com as ações de cada perfil. O administrador tem a barra inferior
   **Início, Jogos, Atletas e Perfil**:
   - cria **um ou mais times** (Meus times) e escolhe o **time ativo** no título;
   - **Atletas** e **Jogos** mostram e cadastram só os dados do time ativo —
     cada time tem os seus;
   - jogo: adversário, data e hora, local, amistoso ou campeonato e placar
     (preenchido depois do jogo).

   Convites e a home do jogador: próxima etapa.

## Estrutura

```
lib/
  core/        config, router, supabase, tema, utilitários e widgets comuns
  features/
    auth/      cadastro, login, seleção de perfil
    profile/   modelo de perfil (papel e plano)
    address/   endereço + consulta de CEP
    home/      tela inicial (barra inferior do administrador)
    teams/     times do administrador e time ativo
    athletes/  atletas de cada time
    games/     jogos de cada time
    splash/    carregamento inicial
supabase/
  migrations/  schema do banco (tabelas, RLS e triggers)
```

## Banco de dados

| Tabela          | Descrição                                                        |
| --------------- | ---------------------------------------------------------------- |
| `profiles`      | Criado automaticamente no cadastro; papel (`admin`/`player`) e plano (`free`/`premium`) |
| `addresses`     | Um endereço por perfil, visível só para o dono                   |
| `teams`         | Times; apenas administradores criam, e cada um pode ter vários   |
| `team_players`  | Atletas do time (com ou sem conta no app); só o dono do time altera |
| `games`         | Jogos do time; só o dono altera, e só o dono e os atletas do time veem |
| `team_invites`  | Convites do administrador e solicitações do jogador              |

O plano não pode ser alterado pelo app; ele é alterado pelo backend de
pagamentos (`service_role`). O papel também não, exceto uma única vez: toda
conta nova começa sem papel até o usuário escolher.

## Testes

```sh
flutter test
```
