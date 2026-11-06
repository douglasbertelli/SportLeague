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

### Notificações push

As notificações do sino também chegam como push no Android e no iOS, pelo
**Firebase Cloud Messaging**. Ao entrar, o app pede a permissão e guarda o
ID de instalação do Firebase (FID, por `register()`/`onRegistered`) em
`device_tokens` (`kind = 'fid'`); ao sair, tira. A função envia com o campo
`fid` da API HTTP v1 (e com `token` para aparelhos com o app antigo, até
atualizarem; ao registrar o FID, o token antigo do aparelho sai). Cada notificação nova
dispara o gatilho `notifications_send_push`, que chama a Edge Function
`send-push` (`supabase/functions/send-push`); ela envia pelo FCM, marca
`pushed_at` (não repete o push) e apaga os tokens de apps desinstalados.
Tocar no push abre as Notificações.

**Lembretes automáticos** (`20261104020000_game_reminders.sql`): de 10 em
10 minutos o `pg_cron` roda `private.send_game_reminders()`, que avisa o dono,
os técnicos e os atletas com conta dos dois times de cada jogo marcado:
**Jogo amanhã/hoje** entre 20 e 24 horas antes (só jogos marcados com mais de
um dia de antecedência) e **Jogo daqui a pouco** entre 1 e 2 horas antes. O
atleta que ainda não respondeu a presença recebe o lembrete com Sim / Não /
Talvez; quem respondeu Não não é lembrado. Cada lembrete sai uma vez por data
do jogo (`private.game_reminders`); remarcado, o jogo ganha lembretes novos.

O app já está ligado ao projeto Firebase (`lib/firebase_options.dart` e
`android/app/google-services.json`, gerados pelo `flutterfire configure`).
No Supabase:

1. Rode a migration `20261104010000_push_notifications.sql`.
2. Guarde a URL do projeto no Vault (SQL Editor), uma vez:

   ```sql
   select vault.create_secret('https://<projeto>.supabase.co', 'project_url');
   ```

3. Publique a função sem exigir login (ela mesma se protege):
   `supabase functions deploy send-push --no-verify-jwt`.
4. Em **Edge Functions → Secrets**, crie `FIREBASE_SERVICE_ACCOUNT` com o JSON
   da conta de serviço (Firebase → Configurações do projeto → Contas de
   serviço → Gerar nova chave privada). Não versione esse arquivo.

No **iOS**, falta ainda: enviar a chave APNs (`.p8`) em Firebase →
Configurações do projeto → Cloud Messaging e ligar a capability **Push
Notifications** no target Runner pelo Xcode.

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
   - a aba Jogos tem as abas **Marcados, Pendentes, Realizados e Cancelados**
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
     (pesquisa pelo nome, ou pelo **código pessoal** do jogador, JG, ou do
     técnico, TC, que fica em Config › Meu código, com Compartilhar, Copiar e Gerar
     outro; o convidado aceita ou recusa em Meus convites), os
     convites enviados e os **pedidos para entrar**,
     com Aceitar e Recusar.
   - O **jogador** entra num time com o código (Início → Meus convites), ou pede
     para entrar pelo perfil do time (Buscar times → **Pedir para entrar**).
     Aceito, ele vira atleta do time, ligado à conta dele.
   - **Início do jogador**: no topo, a foto e o nome dele (sem o "Olá"); logo abaixo,
     os **números do próprio jogador** (Meus números: jogos, gols,
     assistências, cartões e craque, com a temporada e os chips de cada time
     ou **Geral**, todos somados) e depois o card do time e o próximo jogo
     (com o placar ao vivo), só para acompanhar: sem marcar jogos, mexer no
     placar ou montar a escalação. Tocar no chip de um time troca o time
     ativo, e o painel inteiro (e a cor do app) vai junto.
   - **Perfil do jogador**: a **capa** (imagem larga 16:9, enviada por
     ele, com a foto centralizada metade sobre a borda de baixo), a foto, o
     **apelido** (editado pelo lápis; sem apelido, o nome completo) e os
     dados de atleta (posição, pé dominante, altura e nascimento, com
     Editar). O resto fica na aba **Config** da barra inferior do jogador,
     a tela de **Configurações**: a conta (e-mail e tipo de perfil), o Nome,
     Meu código, a cor do time, o **Tema** (claro, escuro ou do sistema), o
     endereço e, à parte, o Sair.
   - **Perfil do administrador e do técnico** (sem a aba Config): a foto, o
     nome, o e-mail, o tipo de perfil (e o plano, só do administrador) e,
     num grupo, Meu código (técnico), a cor do time, o **Tema** (claro,
     escuro ou do sistema) e o endereço; o Sair à parte, mais abaixo. O tema
     não fica mais no topo da home (só na tela de login).
   - **Entrar com biometria** (Perfil e Config, só em aparelhos com digital
     ou rosto cadastrados; oferecido uma vez logo depois de entrar): ligado,
     o app abre numa tela de desbloqueio e pede a digital, o rosto ou o PIN
     do celular, também ao voltar depois de 1 minuto fora. Com ela ligada, o
     **Sair** guarda a conta: a tela de login mostra "Entrar como ..." e já
     pede a biometria (funciona também para quem entrou com Google ou Apple,
     sem guardar senha). "Remover biometria deste aparelho" sai de vez e
     desliga a biometria; entrar com outra conta também a desliga. A sessão
     do Supabase fica no cofre do aparelho (Keystore/Keychain), não nas
     preferências comuns.
   - **Central de notificações** (sino no topo, com o número de não lidas,
     em todos os perfis): convites e pedidos para entrar no time e as
     respostas; amistosos (convite, aceito, recusado, cancelado com o
     motivo, remarcado) e placar lançado; contestação do placar e a
     resposta; nova vaquinha e pagamento confirmado; mensalidade (criada,
     alterada, paga, vencimento e atraso); lembretes de jogo; campeonatos
     (convite, resposta, começo, jogo marcado e resultado). Separadas por time:
     a central mostra as do time ativo (e as de times de que o usuário não
     faz parte, como convites); com mais de um time, os chips do topo
     trocam o time e mostram as não lidas de cada um. Chegam ao vivo; tocar
     marca como lida e leva ao lugar de responder; arrastar apaga. O que
     pede ação tem botão no card (Responder convite, Ver pedido, Responder
     amistoso, Responder contestação, Conferir placar), que abre o time da
     notificação na página certa (os amistosos, na aba Jogos já em
     Pendentes ou Realizados).
   - **Confirmação de presença** nos jogos marcados: o administrador ou o
     técnico pede pelo ⋮ do card ("Pedir confirmação de presença") e os
     atletas com conta recebem a notificação (pedir de novo avisa só quem
     não respondeu). O atleta responde Sim, Não ou Talvez no card da
     notificação ou no Próximo jogo do Início, e pode mudar até o jogo
     começar. O card do jogo e o Próximo jogo mostram o resumo (sim · não ·
     talvez · sem resposta); tocar abre a lista, com a foto e o apelido de
     cada atleta.
   - **Pendências no Início**, em destaque no topo, para todos: o
     administrador vê os pedidos para entrar no time ativo (jogadores e
     técnicos); o jogador e o técnico, os convites de times para responder e
     os pedidos que ainda esperam o time. Tocar leva a responder. Puxar a
     tela para baixo, ou voltar ao app, busca de novo.
   - **Menu lateral** (☰ no topo da home, depois do sino; abre
     pela direita), com as funcionalidades extras:
     - **Campeonatos**: o administrador cria e escolhe o formato: **pontos
       corridos** (turno único ou turno e returno), **mata-mata** (4, 8, 16
       ou 32 times, empate nos pênaltis) ou **grupos + mata-mata** (2, 4 ou 8
       grupos, passa 1 ou 2 de cada, ida e volta opcional). Inscreve times da
       plataforma da modalidade (o dono de outro time recebe o convite e
       aceita ou recusa; os times dele entram confirmados) e times fictícios.
       "Gerar tabela" sorteia os grupos ou o chaveamento e cria as rodadas
       (todos contra todos, mando equilibrado, folga com número ímpar); os
       convites sem resposta caem. O organizador toca no jogo para marcar
       data, hora e local e lançar o placar (e os pênaltis no mata-mata). A
       página tem Classificação (P, J, V, E, D, SG; desempate por pontos,
       vitórias, saldo e gols marcados; os classificados dos grupos em
       destaque) ou Chaveamento, Jogos por rodada ou fase e Times. No
       mata-mata o vencedor entra sozinho na fase seguinte; nos grupos,
       "Gerar o mata-mata" cruza os classificados (1A x 2B, 1B x 2A). O
       campeão (vencedor da final ou líder dos pontos corridos, ao encerrar)
       aparece em destaque. Os times inscritos acompanham e recebem os avisos
       (uma vez por pessoa): convite e resposta, campeonato começou, jogo
       marcado e resultado. Com os dois times e a data, o jogo do campeonato
       entra na aba **Jogos** dos times da plataforma (faixa com o campeonato
       e a fase, que abre o campeonato), com relógio, placar ao vivo, súmula,
       escalação, presença e lembretes. O mandante da plataforma (ou o
       visitante, se o mandante é fictício) controla o relógio e lança o
       placar, que volta sozinho para a classificação e avança o mata-mata;
       a data, o local e o placar do organizador vão para o jogo. Os times
       não editam, cancelam nem contestam jogos de campeonato. A aba
       **Artilharia** mostra os artilheiros e os garçons do campeonato, da
       súmula de todos os jogos (`championship_player_totals`, para quem vê
       o campeonato). Na aba Times, o organizador toca num time fictício
       para enviar, trocar ou remover o **símbolo** (recorte em quadrado),
       que aparece na classificação, nos jogos e na artilharia. O ⋮ do topo
       abre um bottom sheet com Editar (antes da tabela) e Excluir. Com a
       tabela gerada, **Compartilhar** (para todos) gera uma imagem 4:5 do
       campeonato: a classificação (pontos corridos e grupos) ou a final
       (mata-mata) e, ao acabar, o campeão em destaque.
     - **Vaquinha**: cada time tem as suas, para Bola, Colete, Uniforme,
       Churrasco ou Outros (dizendo o que vai ser comprado). O administrador define o
       valor por pessoa ou o valor total do produto (o app divide pelo
       administrador e os atletas, arredondando o centavo para cima) e marca
       quem pagou (ele e os atletas, sim ou não); a
       vaquinha mostra o total arrecadado de quanto é esperado. O técnico e
       os atletas acompanham. Vaquinhas antigas são encerradas (e podem ser
       reabertas).
     - **Mensalidade**: o administrador configura o valor por mês, o dia do
       vencimento (1 a 28) e, opcional, a chave PIX, e marca mês a mês quais
       atletas pagaram (setas passam pelos meses, desde o primeiro cobrado).
       Cada atleta aparece como Pago, Em aberto ou Atrasado (depois do
       vencimento), com o total arrecadado do mês. O técnico e os atletas
       acompanham; o atleta vê no topo se está em dia ou quais meses deve e
       copia a chave PIX. Entra nas notificações: mensalidade criada e
       alterada (atletas e técnicos), pagamento confirmado (o atleta) e, todo
       dia às 9h, o lembrete de vencimento no dia e de atraso 3 dias depois
       para quem não pagou.

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
    dues/      mensalidade do time e quem pagou cada mês
    championships/ campeonatos (formatos, tabela, chaveamento e classificação)
    splash/    carregamento inicial
supabase/
  migrations/  schema do banco (tabelas, RLS e triggers)
```

## Banco de dados

| Tabela          | Descrição                                                        |
| --------------- | ---------------------------------------------------------------- |
| `profiles`      | Criado automaticamente no cadastro; papel (`admin`/`player`/`coach`), plano (`free`/`premium`), foto (o técnico e o jogador enviam a deles pelo Perfil, no Storage público `profile-photos`, cada um na própria pasta), capa do jogador (`cover_url`, na mesma pasta), apelido do jogador (`nickname`, até 40 caracteres, mostrado no perfil dele) e dados de atleta do jogador (nascimento, posição preferida, pé dominante e altura). Jogador e técnico têm um **código pessoal** (`code`: JG ou TC + 6), criado pelo banco com o papel e trocado só por `regenerate_my_code`; o administrador convida pelo código. A função `my_player_totals` dá os números do jogador logado em cada time em que é atleta (Meus números, no Início) |
| `addresses`     | Um endereço por perfil, visível só para o dono                   |
| `teams`         | Times; apenas administradores criam, e cada um pode ter vários. Modalidades (futsal, society, campo, areia, desafio), joga como (mandante, visitante, ambos — o amistoso só é marcado num mando que os dois times aceitam), gênero, faixa de idade (livre, base com idade mínima e máxima, master com idade mínima), fundação, contatos, local do time, logo, capa e até 3 uniformes |
| `team_players`  | Atletas do time (com ou sem conta no app), com foto; só o dono do time altera |
| `games`         | Amistosos do time, com modalidade e adversário (time da plataforma ou fictício) da mesma modalidade, e situação (pendente, marcado, cancelado). Só o time que marcou altera os dados; o adversário só aceita, recusa ou cancela. Quem cancela escreve o motivo (`cancel_reason`, 3 a 200 caracteres), que os dois times veem no card; o dono e os atletas dos dois times veem (contra time da plataforma). O relógio da partida (`match_phase`, `clock_started_at`, `clock_elapsed`, `period_minutes`) muda pela função `game_clock`, com a hora do servidor |
| `team_availability` | Horários de jogo disponíveis de cada time (avulsos ou recorrentes por dia da semana); todos veem, só o dono altera. Os livres vêm da função `available_slots` |
| `team_availability_skips` | Dias pulados de um horário recorrente (imprevistos); só o dono altera |
| `team_follows`  | Time segue time (o dono do time que segue altera); todos veem. A função `team_profile_stats` devolve seguidores, estatísticas, últimos resultados e próximos jogos de qualquer time |
| `venues`        | Locais das partidas (nome, endereço com CEP e foto no Storage `venue-photos`); todos veem, só quem cadastrou altera. A função `similar_venues` sugere os parecidos antes de cadastrar |
| `guest_teams`   | Times fictícios (adversários fora da plataforma) de cada administrador; só ele vê. Símbolo opcional (`logo_url`, no Storage `team-logos`, na pasta dele); as inscrições em campeonatos guardam uma cópia do nome e do símbolo, atualizada quando ele muda |
| `team_invites`  | Pedidos do jogador para entrar no time (o dono aceita ou recusa; o jogador cancela) e convites; aceito, o jogador vira atleta do time. A entrada com código (`join_team_with_code`) fica registrada como pedido aceito |
| `team_invite_codes` | Código de convite de cada time; só o dono vê e gera outro (`regenerate_invite_code`) |
| `score_disputes` | Contestações do placar feitas pelo adversário depois do jogo (placar proposto e motivo); os dois times veem e quem marcou responde por `resolve_score_dispute` (aceitar muda o placar do jogo). Uma aberta por jogo |
| `game_player_stats` | Súmula: o que cada atleta fez num jogo (estar na súmula é ter jogado; gols, assistências, cartões, craque — um por time). Cada time lança os seus atletas, a partir de 1 hora antes do jogo; quem vê o jogo vê a súmula. `add_player_goal` soma um gol pelo placar ao vivo e `team_player_totals` dá os totais dos atletas (perfil do atleta e artilharia) |
| `team_coaches` | Técnicos de cada time (entram pelo convite aceito, com `kind = 'coach'` em `team_invites`); veem os jogos, as fotos dos atletas e lançam escalação e súmula (`private.is_team_staff`). Todos veem os técnicos (foto e nome no perfil do time); só o técnico ou o dono removem |
| `game_lineups` | Escalação: titulares e reservas de cada time no jogo; o dono ou o técnico montam antes e durante o jogo; quem vê o jogo vê a escalação |
| `fundraisers` | Vaquinhas do time: item (bola, colete, uniforme, churrasco ou outro, com o que vai ser comprado), valor em centavos (`amount_type`: por pessoa, ou o total do produto, que o app divide entre o dono e os atletas) e se está encerrada. Só o dono do time cria, altera e exclui; o dono, os técnicos e os atletas com conta veem (`private.is_team_member`) |
| `game_presence` | Confirmação de presença: um registro por atleta chamado (`answer`: `yes`, `no` ou `maybe`; nulo = sem resposta). Escrita só pelas funções `request_presence` (dono ou técnico; avisa quem não respondeu) e `answer_presence` (o próprio atleta), com o jogo marcado e antes de começar; o dono, o técnico e o próprio atleta veem |
| `notifications` | Central de notificações: criadas por gatilhos do banco (`team_invites`, `games`, `score_disputes`, `fundraisers`, `fundraiser_payments`, `team_dues`, `team_due_payments`, `championship_teams`, `championships`, `championship_matches`) e pelos lembretes do `pg_cron` (jogos e mensalidade), nunca para quem fez a ação (menos no amistoso entre dois times do mesmo administrador, em que o outro time é avisado). Cada usuário só vê, marca como lida e apaga as dele; publicada no Realtime para o sino atualizar na hora |
| `fundraiser_payments` | Quem pagou a vaquinha (um atleta do time ou o dono); sem linha, não pagou. Só o dono marca e desmarca |
| `team_dues` | Mensalidade do time (uma por time): valor em centavos, dia do vencimento (1 a 28), chave PIX opcional e o primeiro mês cobrado. Só o dono configura, altera e remove; o dono, os técnicos e os atletas com conta veem. Criar ou alterar avisa os atletas e os técnicos |
| `team_due_payments` | Quem pagou a mensalidade de cada mês (atleta e dia 1 do mês); sem linha, em aberto. Só o dono marca (atletas do próprio time) e desmarca; marcar avisa o atleta. O `pg_cron` (`dues-reminders`, 9h de Brasília) lembra no vencimento e 3 dias depois quem não pagou |
| `championships` | Campeonatos: organizador (`owner_id`, um administrador), nome, modalidade, formato (`league`, `knockout` ou `groups`), turno e returno, grupos e classificados por grupo, e situação (`draft`, `running`, `finished`). Veem o organizador e os membros dos times da plataforma inscritos (`private.can_see_championship`); só o organizador altera |
| `championship_teams` | Times inscritos (da plataforma ou fictícios do organizador), com o nome guardado (os fictícios só o dono vê), a situação (`invited`, `accepted`, `declined`; o banco confirma os times do organizador e os fictícios) e o grupo sorteado. O dono do time convidado responde por `respond_championship_invite` |
| `championship_matches` | Jogos: fase (`league`, `group`, `knockout`), rodada, posição no chaveamento, grupo, mandante e visitante (nulos no mata-mata até a fase anterior acabar), data, local, placar e pênaltis. Só o organizador gera, marca e lança; marcar e lançar avisam os dois times. Com os dois times e a data vira um jogo em `games` (`type = 'championship'`, `championship_match_id`), sincronizado nos dois sentidos; no mata-mata o banco avança o vencedor e encerra o campeonato na final |

### Imagens no Storage

Buckets: `team-logos` (logo, capa e uniformes dos times e símbolo dos
fictícios), `athlete-photos` (privado), `profile-photos` (foto e capa) e
`venue-photos`, cada um na pasta de quem envia. Para não acumular arquivos:

- **Trocar** grava no mesmo caminho (sobrescreve); a URL ganha um `?t=` novo
  para o app não mostrar a imagem antiga do cache. Os uniformes, que têm um
  arquivo por foto, apagam os que saíram ao salvar o time.
- **Remover** a imagem e **excluir** time (com as fotos dos atletas), atleta
  ou local apagam os arquivos pelo app.
- **Limpeza diária** (`pg_cron` `storage-cleanup`, 4h de Brasília): a Edge
  Function `storage-cleanup` apaga os arquivos que nenhuma tabela usa mais
  (`storage_orphans`, só para a service role), criados há mais de um dia.
  Pega o que sobrou de uma falha de rede ou de exclusões em cascata feitas
  pelo banco (conta excluída). Publique-a com
  `supabase functions deploy storage-cleanup --no-verify-jwt`.

O plano não pode ser alterado pelo app; ele é alterado pelo backend de
pagamentos (`service_role`). O papel também não, exceto uma única vez: toda
conta nova começa sem papel até o usuário escolher.

### Planos (Gratuito e Premium)

O plano é do administrador e vale para os times dele; jogadores e técnicos
não têm plano. O que cada plano libera fica na tabela `plan_features`
(`plan`, `feature`, `quota`): `quota` nula = sem limite, 0 = bloqueado,
n = até n; sem linha = sem limite. Mudar um limite ou mover uma
funcionalidade de plano é alterar a linha: vale na hora, sem versão nova do
app (a tela Planos também lê dessa tabela). `description` é o texto do item
naquele plano na tela Planos; nulo usa o texto padrão do app. Item não
incluso (`quota` 0) não aparece no cartão daquele plano.

| Funcionalidade | Chave | Gratuito | Premium |
|---|---|---|---|
| Times na conta | `teams` | 1 | sem limite |
| Organizar campeonatos em andamento (todos os formatos) | `championships` | bloqueado | sem limite |
| Mensalidade | `dues` | bloqueada | liberada |

No Gratuito o time participa dos campeonatos para os quais for convidado;
só organizar é do Premium.

O banco barra (gatilhos com `private.require_feature`, erro
`plan_limit:<chave>`) e o app avisa antes (`plan_status()`, com o plano, os
limites e o uso). Quem perde o acesso não perde dados: o que existe continua
visível; só criar e editar fica bloqueado, e os lembretes de mensalidade
param. Uma funcionalidade nova que dependa do plano precisa do bloqueio no
código uma vez; depois, é só a tabela.

**Preço** (tabela `plans`): o Premium custa `monthly_cents` (R$ 30,00) por
mês com 1 time, mais `extra_team_cents` (R$ 15,00) por time a mais. A tela
Planos mostra o total com os times que o administrador já tem.

**Teste grátis**: `trial_days` (15) dias de Premium, uma vez por conta, para
o administrador no Gratuito; ele começa pelo app (`start_premium_trial()`,
guardado em `private.premium_trials`). Enquanto dura, o plano que vale é o
Premium (`private.effective_plan`). O cron `trial-reminders` (9h de
Brasília) avisa faltando até 3 dias e quando termina. Sem `trial_days`, o
teste some do app.

Ainda não há pagamento. Para trocar o plano de alguém à mão (no SQL Editor,
tudo de uma vez):

```sql
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
update public.profiles set plan = 'premium' where id = '<id do usuário>';
```

## Testes

```sh
flutter test
```
