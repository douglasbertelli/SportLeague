# SportLeague

Aplicativo para conectar times esportivos e marcar amistosos e campeonatos.
Começa pelo **futebol**; vôlei, basquete e outros esportes virão depois.

## Stack

- Flutter + [Riverpod](https://riverpod.dev) (estado) + [go_router](https://pub.dev/packages/go_router) (navegação)
- [Supabase](https://supabase.com) (Auth + Postgres com RLS)
- [ViaCEP](https://viacep.com.br) para preenchimento de endereço

## Configuração

1. No painel do Supabase, abra **SQL Editor** e execute
   `supabase/migrations/20261021000000_init.sql`
   (ou `supabase db push` com a Supabase CLI).
2. Copie `env.example.json` para `env.json` e preencha com a URL e a anon key do
   projeto (**Project Settings → API**). O `env.json` não é versionado.
3. Rode o app:

   ```sh
   flutter pub get
   flutter run --dart-define-from-file=env.json
   ```

> Por padrão o Supabase exige confirmação de e-mail. Depois do cadastro o
> usuário confirma pelo link recebido e faz login.

## Fluxo atual

1. **Cadastro** com nome, e-mail, senha e escolha obrigatória do perfil:
   - **Administrador**: cria e gerencia times e jogadores.
   - **Jogador**: entra em times por busca ou convite.
2. **Login** e recuperação de senha.
3. **Cadastro de endereço** (obrigatório no primeiro acesso), com busca por CEP.
4. **Home** com as ações de cada perfil (times, jogadores e convites: próxima etapa).

## Estrutura

```
lib/
  core/        config, router, supabase, tema, utilitários e widgets comuns
  features/
    auth/      cadastro, login, seleção de perfil
    profile/   modelo de perfil (papel e plano)
    address/   endereço + consulta de CEP
    home/      tela inicial
    splash/    carregamento inicial
supabase/
  migrations/  schema do banco (tabelas, RLS e triggers)
```

## Banco de dados

| Tabela          | Descrição                                                        |
| --------------- | ---------------------------------------------------------------- |
| `profiles`      | Criado automaticamente no cadastro; papel (`admin`/`player`) e plano (`free`/`premium`) |
| `addresses`     | Um endereço por perfil, visível só para o dono                   |
| `teams`         | Times; apenas administradores criam                              |
| `team_players`  | Jogadores do time (com ou sem conta no app)                      |
| `team_invites`  | Convites do administrador e solicitações do jogador              |

Papel e plano não podem ser alterados pelo app. O plano deve ser alterado pelo
backend de pagamentos (`service_role`).

## Testes

```sh
flutter test
```
