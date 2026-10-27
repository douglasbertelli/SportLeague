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
   - **Técnico**: entra nos times com o código de convite ou pedindo pelo
     perfil do time (o dono aceita; o dono vê e tira os técnicos em
     Convites). Usa o app como o administrador, pelo time ativo (Início,
     Jogos, Atletas), mas só vê e acompanha: monta a **escalação** de cada
     jogo (titulares, quantos a modalidade põe em campo, e reservas) e lança
     a súmula; não edita o time, não marca jogos, não mexe no placar nem
     cadastra atletas.
4. **Cadastro de endereço** (obrigatório no primeiro acesso), com busca por CEP.
   Serve para enviar documentos, brindes e outros itens ao usuário, não para
   encontrar times.
5. **Home** com as ações de cada perfil. O administrador tem a barra inferior
   **Início, Jogos, Atletas e Perfil**. O Início mostra o **painel do time
   ativo** (seguidores, próximo jogo com quanto falta para a partida, convites pendentes, estatísticas e
   **últ. jogos**, com vitória, empate ou derrota em cada um) e os atalhos.
   Quando a partida começa, o card vira **Jogo em andamento** (com
   confetes ao zerar a contagem): quem marcou o jogo controla o **relógio**
   (inicia o 1º tempo com a duração de cada tempo, pausa, encerra o tempo,
   inicia o 2º e encerra o jogo, com **apito** em cada mudança de tempo —
   sons gerados por `tool/generate_whistles.dart`; o app avisa ao fim do
   tempo regulamentar e conta o acréscimo) e soma os gols no **placar ao vivo**; o adversário
   acompanha os dois. O jogo fica em **Marcados** até terminar (relógio
   encerrado ou 2 horas sem relógio rodando) e depois vai para Realizados,
   onde o adversário pode **contestar o placar** (placar na visão dele e o
   motivo); quem marcou vê o aviso no Início e no card e aceita ou mantém o
   dele. Na **súmula** do jogo (card do jogo ou "Súmula do jogo" no card do
   Início), cada time lança os dados dos seus atletas: quem jogou, gols,
   assistências, cartões e o craque; ao somar um gol no placar ao vivo, o app
   pergunta quem fez e quem deu a assistência. Os números aparecem no
   **perfil do atleta** (tocar no atleta) e na **Artilharia** e **Garçons**
   do perfil do time. As estatísticas do time e dos atletas são por
   **temporada**: o botão acima delas escolhe o ano (ano inteiro) ou um mês;
   começa no ano atual e vale para todas as telas:
   - cria **um ou mais times** (Meus times) e escolhe o **time ativo** no título.
     O cadastro tem quatro abas:
     **Time** (logo, nome, uma modalidade — Futsal, Society, Campo, Areia ou
     Desafio —, gênero e faixa de idade: Livre, Base com idade mínima e máxima
     ou Master com idade mínima), **Detalhes** (joga como mandante,
     visitante ou ambos, data de fundação e cidade/UF obrigatórias), **Contato** (telefone,
     Instagram, Facebook, YouTube e site, opcionais) e **Mídia** (capa e até 3
     fotos de uniforme, no Storage `team-logos`). Tocar no adversário no card
     do jogo abre o perfil dele, com os uniformes para não confundir as cores.
     A **lupa** no topo pesquisa os times da plataforma; o **perfil** tem duas
     abas: **Visão geral** (seguidores e seguindo — o time ativo pode
     **Seguir** —, estatísticas, últimos resultados e próximos jogos) e
     **Sobre o time** (joga como, cidade, local, fundação, uniformes e
     contatos);
   - **Atletas** e **Jogos** mostram e cadastram só os dados do time ativo —
     cada time tem os seus;
   - atleta: foto (obrigatória; Storage privado `athlete-photos`, visível só
     para o dono e os atletas do time), nome, posição e número;
   - amistoso: modalidade (uma das do time), adversário da **mesma
     modalidade** — um time da plataforma, pesquisado pelo nome, ou um time
     fictício criado pelo administrador e salvo para os próximos jogos —, jogar
     como **mandante** (padrão) ou **visitante**, data e hora e **local** (obrigatório, escolhido entre os cadastrados). O placar é lançado em outra tela. Contra um time da
     plataforma, o amistoso aparece também na aba Jogos do adversário
     ("Marcado por …").
   - **Locais** (Início): quadras e campos compartilhados entre os
     administradores, com endereço (CEP pelo ViaCEP) e foto opcional. Ao
     cadastrar um local, o app sugere os parecidos que já existem (mesmo CEP e
     número, ou nome parecido na mesma cidade). Ao marcar o amistoso, o local é
     escolhido na pesquisa ou cadastrado ali mesmo. O local cadastrado pode
     virar o **local do time** (também escolhido na aba Detalhes do time): no
     amistoso novo ele vem preenchido quando o time é mandante, e o do
     adversário da plataforma quando é visitante; dá para trocar.
   - **Disponibilidade** (Início): calendário com os dias e horários em que o
     time joga, avulsos ou recorrentes ("todo sábado às 15:00"). Dá para mudar o
     horário de um dia ou de todas as semanas e, num imprevisto, o
     recorrente pode sair só de um dia, sem apagar as outras semanas. O amistoso só
     pode ser marcado num horário livre de **quem joga em casa**: do próprio
     time como mandante, do adversário da plataforma como visitante (contra
     time fictício, sempre do próprio time); horário com amistoso
     pendente ou marcado fica ocupado. Horários recorrentes são no fuso de
     Brasília.
   - a aba Jogos tem as abas **Marcados, Pendentes, Cancelados e Realizados**
     (roláveis na horizontal). Contra time da plataforma, o amistoso fica
     pendente até o adversário **aceitar** ou **recusar**; contra time
     fictício já nasce marcado. Os dois times podem cancelar; marcado com a
     data passada vai para Realizados, onde quem marcou **lança o placar** (⋮).
     Se quem marcou muda a data ou o
     adversário, volta a ficar pendente.

   - **Perfil → Cor do time**: 28 cores, entre elas dois cinzas e o preto; o
     app inteiro, claro e escuro, muda na hora. **Cada time tem a sua**:
     trocar o time ativo troca a cor (time sem cor própria usa a geral). A
     escolha fica salva no aparelho, como o modo claro/escuro; sem time, é a
     **Cor do app**.

   - **Convites** (Início do administrador): o código do time para mandar aos
     jogadores (Compartilhar, Copiar, Gerar outro), **Convidar jogador do app**
     (pesquisa pelo nome; o jogador aceita ou recusa em Meus convites), os
     convites enviados e os **pedidos para entrar**,
     com Aceitar e Recusar.
   - O **jogador** entra num time com o código (Início → Meus convites), ou pede
     para entrar pelo perfil do time (Buscar times → **Pedir para entrar**).
     Aceito, ele vira atleta do time, ligado à conta dele.
   - **Menu lateral** (☰ no topo da home, depois do modo claro/escuro; abre
     pela direita), com as funcionalidades extras:
     - **Vaquinha**: cada time tem as suas, para Bola, Colete, Uniforme,
       Churrasco ou Outros (dizendo o que vai ser comprado). O administrador define o
       valor por pessoa ou o valor total do produto (o app divide pelo
       administrador e os atletas, arredondando o centavo para cima) e marca
       quem pagou (ele e os atletas, sim ou não); a
       vaquinha mostra o total arrecadado de quanto é esperado. O técnico e
       os atletas acompanham. Vaquinhas antigas são encerradas (e podem ser
       reabertas).

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
    venues/    locais das partidas (cadastro, pesquisa e foto)
    fundraisers/ vaquinhas do time e quem pagou
    splash/    carregamento inicial
supabase/
  migrations/  schema do banco (tabelas, RLS e triggers)
```

## Banco de dados

| Tabela          | Descrição                                                        |
| --------------- | ---------------------------------------------------------------- |
| `profiles`      | Criado automaticamente no cadastro; papel (`admin`/`player`/`coach`), plano (`free`/`premium`) e foto (o técnico envia a dele pelo Perfil, no Storage público `profile-photos`, cada um na própria pasta) |
| `addresses`     | Um endereço por perfil, visível só para o dono                   |
| `teams`         | Times; apenas administradores criam, e cada um pode ter vários. Modalidades (futsal, society, campo, areia, desafio), joga como (mandante, visitante, ambos — o amistoso só é marcado num mando que os dois times aceitam), gênero, faixa de idade (livre, base com idade mínima e máxima, master com idade mínima), fundação, contatos, local do time, logo, capa e até 3 uniformes |
| `team_players`  | Atletas do time (com ou sem conta no app), com foto; só o dono do time altera |
| `games`         | Amistosos do time, com modalidade e adversário (time da plataforma ou fictício) da mesma modalidade, e situação (pendente, marcado, cancelado). Só o time que marcou altera os dados; o adversário só aceita, recusa ou cancela; o dono e os atletas dos dois times veem (contra time da plataforma). O relógio da partida (`match_phase`, `clock_started_at`, `clock_elapsed`, `period_minutes`) muda pela função `game_clock`, com a hora do servidor |
| `team_availability` | Horários de jogo disponíveis de cada time (avulsos ou recorrentes por dia da semana); todos veem, só o dono altera. Os livres vêm da função `available_slots` |
| `team_availability_skips` | Dias pulados de um horário recorrente (imprevistos); só o dono altera |
| `team_follows`  | Time segue time (o dono do time que segue altera); todos veem. A função `team_profile_stats` devolve seguidores, estatísticas, últimos resultados e próximos jogos de qualquer time |
| `venues`        | Locais das partidas (nome, endereço com CEP e foto no Storage `venue-photos`); todos veem, só quem cadastrou altera. A função `similar_venues` sugere os parecidos antes de cadastrar |
| `guest_teams`   | Times fictícios (adversários fora da plataforma) de cada administrador; só ele vê |
| `team_invites`  | Pedidos do jogador para entrar no time (o dono aceita ou recusa; o jogador cancela) e convites; aceito, o jogador vira atleta do time. A entrada com código (`join_team_with_code`) fica registrada como pedido aceito |
| `team_invite_codes` | Código de convite de cada time; só o dono vê e gera outro (`regenerate_invite_code`) |
| `score_disputes` | Contestações do placar feitas pelo adversário depois do jogo (placar proposto e motivo); os dois times veem e quem marcou responde por `resolve_score_dispute` (aceitar muda o placar do jogo). Uma aberta por jogo |
| `game_player_stats` | Súmula: o que cada atleta fez num jogo (estar na súmula é ter jogado; gols, assistências, cartões, craque — um por time). Cada time lança os seus atletas, a partir de 1 hora antes do jogo; quem vê o jogo vê a súmula. `add_player_goal` soma um gol pelo placar ao vivo e `team_player_totals` dá os totais dos atletas (perfil do atleta e artilharia) |
| `team_coaches` | Técnicos de cada time (entram pelo convite aceito, com `kind = 'coach'` em `team_invites`); veem os jogos, as fotos dos atletas e lançam escalação e súmula (`private.is_team_staff`). Todos veem os técnicos (foto e nome no perfil do time); só o técnico ou o dono removem |
| `game_lineups` | Escalação: titulares e reservas de cada time no jogo; o dono ou o técnico montam antes e durante o jogo; quem vê o jogo vê a escalação |
| `fundraisers` | Vaquinhas do time: item (bola, colete, uniforme, churrasco ou outro, com o que vai ser comprado), valor em centavos (`amount_type`: por pessoa, ou o total do produto, que o app divide entre o dono e os atletas) e se está encerrada. Só o dono do time cria, altera e exclui; o dono, os técnicos e os atletas com conta veem (`private.is_team_member`) |
| `fundraiser_payments` | Quem pagou a vaquinha (um atleta do time ou o dono); sem linha, não pagou. Só o dono marca e desmarca |

O plano não pode ser alterado pelo app; ele é alterado pelo backend de
pagamentos (`service_role`). O papel também não, exceto uma única vez: toda
conta nova começa sem papel até o usuário escolher.

## Testes

```sh
flutter test
```
