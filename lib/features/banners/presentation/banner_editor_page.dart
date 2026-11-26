import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/media/photo_picker.dart';
import '../../../core/media/picked_image.dart';
import '../../../core/router/routes.dart';
import '../../../core/storage/preferences_provider.dart';
import '../../../core/theme/app_color_provider.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/empty_state.dart';
import '../../games/data/game_repository.dart';
import '../../games/data/player_stats_repository.dart';
import '../../games/presentation/share_result.dart' show capturePng;
import '../../plans/domain/plan_status.dart';
import '../../games/domain/game.dart';
import '../../games/domain/player_stats.dart';
import '../../sports/domain/sport_rules.dart';
import '../../plans/presentation/plan_gate.dart';
import '../../teams/data/team_repository.dart';
import '../../teams/domain/team.dart';
import '../../teams/presentation/team_logo.dart';
import '../domain/banner_design.dart';
import 'banner_canvas.dart';
import 'banner_style_tab.dart';
import 'banner_template_tab.dart';
import 'banner_texts_tab.dart';

/// Se o administrador vê os Banners (menu e atalhos): sem time ativo (o
/// editor explica e leva a criar o time) ou sendo o dono do time ativo.
/// Quem decide se é administrador é quem chama.
final bannersVisibleProvider = Provider<bool>(
  (ref) =>
      ref.watch(selectedTeamProvider).value == null ||
      ref.watch(canManageTeamProvider),
);

/// Confere o Premium e abre o editor de banners do time ativo.
Future<void> openBannerEditor(
  BuildContext context,
  WidgetRef ref, {
  BannerArgs? args,
}) async {
  if (!await ensurePlanAllows(context, ref, PlanFeature.banners)) return;
  if (context.mounted) await context.push(Routes.banners, extra: args);
}

/// Salva a imagem na galeria do aparelho. Substituível nos testes.
final saveBannerProvider = Provider<Future<void> Function(Uint8List png)>(
  (ref) => (png) async {
    if (!await Gal.hasAccess()) await Gal.requestAccess();
    await Gal.putImageBytes(
      png,
      name: 'sportleague_banner_${DateTime.now().millisecondsSinceEpoch}',
    );
  },
);

/// Abre o compartilhamento do sistema com o banner. Substituível nos testes.
final shareBannerProvider =
    Provider<Future<void> Function(Uint8List png, String text)>(
      (ref) =>
          (png, text) async => SharePlus.instance.share(
            ShareParams(
              files: [XFile.fromData(png, mimeType: 'image/png')],
              fileNameOverrides: const ['banner.png'],
              text: text,
            ),
          ),
    );

/// Estilo do banner salvo no aparelho, por time.
String bannerStyleKey(String teamId) => 'banner_style.$teamId';

/// Editor de banners do time ativo: escolhe o modelo, edita os textos, as
/// cores, as fontes e as fotos, com a prévia ao vivo, e salva na galeria ou
/// compartilha a imagem (1080 px de largura).
class BannerEditorPage extends ConsumerWidget {
  const BannerEditorPage({super.key, this.args});

  final BannerArgs? args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final team = ref.watch(selectedTeamProvider);
    return team.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Banner')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => Scaffold(
        appBar: AppBar(title: const Text('Banner')),
        body: Center(
          child: TextButton.icon(
            onPressed: () => ref.invalidate(selectedTeamProvider),
            icon: const Icon(Icons.refresh),
            label: const Text('Erro ao carregar o time. Tentar novamente'),
          ),
        ),
      ),
      data: (team) => team == null
          ? Scaffold(
              appBar: AppBar(title: const Text('Banner')),
              body: EmptyState(
                icon: Icons.shield_outlined,
                title: 'Crie seu time primeiro',
                message:
                    'Os banners usam o nome, o escudo e as cores do time. '
                    'Crie um time (ou escolha um no topo da tela inicial) '
                    'para começar.',
                action: FilledButton.icon(
                  onPressed: () => context.push(Routes.newTeam),
                  icon: const Icon(Icons.add),
                  label: const Text('Criar time'),
                ),
              ),
            )
          : BannerEditor(key: ValueKey(team.id), team: team, args: args),
    );
  }
}

class BannerEditor extends ConsumerStatefulWidget {
  const BannerEditor({super.key, required this.team, this.args});

  final Team team;
  final BannerArgs? args;

  @override
  ConsumerState<BannerEditor> createState() => _BannerEditorState();
}

class _BannerEditorState extends ConsumerState<BannerEditor> {
  final _boundary = GlobalKey();
  final _controllers =
      <BannerTemplate, Map<BannerField, TextEditingController>>{};

  late BannerTemplate _template;
  late BannerStyle _style;
  late final BannerStyle _teamStyle;
  ImageProvider? _featuredPhoto;
  ImageProvider? _backgroundPhoto;
  bool _busy = false;

  /// O jogo que preenche os textos: o que abriu o editor, o próximo jogo do
  /// time (preenchido sozinho) ou o escolhido no campo Adversário.
  Game? _game;

  /// Os jogos do time, para escolher; nulo enquanto carrega.
  List<Game>? _games;

  Team get _team => widget.team;

  @override
  void initState() {
    super.initState();
    final game = _game = widget.args?.game;
    _template =
        widget.args?.template ??
        (game != null && game.hasScore
            ? BannerTemplate.result
            : BannerTemplate.gameDay);
    _teamStyle = BannerStyle.forTeam(ref.read(appColorProvider).color);
    _style = BannerStyle.fromJson(
      ref.read(sharedPreferencesProvider).getString(bannerStyleKey(_team.id!)),
      _teamStyle,
    );
    _fillHighlight();
    // Mantém os jogos carregados enquanto o editor está aberto. Sem jogo, o
    // banner já vem com o próximo.
    ref.listenManual(teamGamesProvider(_team.id!), (_, next) {
      final games = next.value;
      if (games == null || !mounted) return;
      setState(() => _games = games);
      if (_game == null) {
        final next = nextBannerGame(games, DateTime.now(), template: _template);
        if (next != null) _applyGame(next, onlyUntouched: true);
      }
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    for (final fields in _controllers.values) {
      for (final controller in fields.values) {
        controller.dispose();
      }
    }
    super.dispose();
  }

  /// Os campos do modelo, criados (com os textos iniciais) na primeira vez
  /// que ele é aberto. Trocar de modelo e voltar mantém o que foi editado.
  Map<BannerField, TextEditingController> _fieldsOf(BannerTemplate template) =>
      _controllers.putIfAbsent(template, () {
        final texts = _defaultsOf(template);
        return {
          for (final field in template.fields)
            field: TextEditingController(text: texts[field] ?? '')
              ..addListener(() => setState(() {})),
        };
      });

  BannerTexts get _texts => _textsOf(_template);

  BannerTexts _defaultsOf(BannerTemplate template) => defaultTexts(
    template,
    teamName: _team.name,
    teamId: _team.id,
    instagram: _team.instagram,
    game: _game,
  );

  /// Os textos do [template]: os editados ou, se ainda não foi aberto, os
  /// iniciais (as miniaturas da aba Modelo não criam os campos).
  BannerTexts _textsOf(BannerTemplate template) =>
      switch (_controllers[template]) {
        final fields? => {
          for (final MapEntry(:key, :value) in fields.entries) key: value.text,
        },
        null => _defaultsOf(template),
      };

  /// Volta os textos do modelo atual aos iniciais.
  void _resetTexts() {
    final defaults = _defaultsOf(_template);
    for (final MapEntry(:key, :value) in _fieldsOf(_template).entries) {
      value.text = defaults[key] ?? '';
    }
  }

  /// Troca o jogo do banner e reescreve os campos que vêm dele em todos os
  /// modelos já abertos. Com [onlyUntouched], só os que ainda estão com o
  /// texto inicial (o que o administrador escreveu fica).
  void _applyGame(Game game, {bool onlyUntouched = false}) {
    final before = {
      for (final template in _controllers.keys) template: _defaultsOf(template),
    };
    setState(() => _game = game);
    for (final MapEntry(key: template, value: fields) in _controllers.entries) {
      final defaults = _defaultsOf(template);
      for (final field in bannerGameFields) {
        final controller = fields[field];
        if (controller == null) continue;
        if (onlyUntouched && controller.text != before[template]![field]) {
          continue;
        }
        controller.text = defaults[field] ?? '';
      }
    }
    _fillHighlight();
  }

  /// O jogo escolhido na lista dos jogos do time.
  Future<void> _pickGame() async {
    final games = _games;
    if (games == null) {
      showErrorSnackBar(context, 'Os jogos do time ainda estão carregando.');
      return;
    }
    final (:upcoming, :played) = bannerGames(games, DateTime.now());
    final teamId = _team.id!;
    final empty = upcoming.isEmpty && played.isEmpty;
    final game = await showAppSheet<Game>(
      context,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        Widget header(String text) => Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(text, style: theme.textTheme.labelLarge),
        );
        Widget tile(Game game) => ListTile(
          contentPadding: EdgeInsets.zero,
          selected: game.id != null && game.id == _game?.id,
          leading: TeamLogo.url(logoUrl: game.opponentLogoFor(teamId)),
          title: Text(game.opponentNameFor(teamId)),
          subtitle: Text(
            [
              bannerDate(game.scheduledAt),
              bannerTime(game.scheduledAt),
              ?game.resultLabelFor(teamId),
            ].join(' · '),
          ),
          onTap: () => Navigator.of(sheetContext).pop(game),
        );
        return AppSheet(
          title: 'Escolher jogo',
          message: empty
              ? 'O time ainda não tem jogos marcados.'
              : 'O adversário, o escudo, a data e o local vêm do jogo.',
          body: empty
              ? null
              : ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.5,
                  ),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      if (upcoming.isNotEmpty) ...[
                        header('Próximos jogos'),
                        for (final game in upcoming) tile(game),
                      ],
                      if (played.isNotEmpty) ...[
                        header('Realizados'),
                        for (final game in played.take(10)) tile(game),
                      ],
                    ],
                  ),
                ),
          actions: const [SheetBackButton(label: 'Fechar')],
        );
      },
    );
    if (game == null || !mounted) return;
    // O destaque é do jogo anterior; o da súmula do novo vem a seguir.
    _controllers[BannerTemplate.result]?[BannerField.highlight]?.text = '';
    _applyGame(game);
  }

  /// O escudo do adversário: o do jogo escolhido, enquanto o nome no campo
  /// for o dele (um adversário digitado à mão não tem escudo).
  String? _opponentLogoOf(BannerTemplate template) {
    final game = _game;
    if (game == null) return null;
    final typed = _textsOf(template)[BannerField.opponent]?.trim();
    if (typed != null && typed != game.opponentNameFor(_team.id!)) return null;
    return game.opponentLogoFor(_team.id!);
  }

  /// No resultado, os gols e o craque da súmula (se já foi lançada).
  Future<void> _fillHighlight() async {
    final game = _game;
    if (game?.id == null || !game!.hasScore) return;
    try {
      final stats = await ref.read(gameStatsProvider(game.id!).future);
      final mine = stats.where((s) => s.teamId == _team.id).toList();
      final scoring = game.rules.scoringStatKey;
      final scorers = scorerNames(mine, scoring);
      final best = mine.where((s) => s.bestPlayer).firstOrNull?.athleteName;
      final text = [
        if (scorers.isNotEmpty)
          '${game.rules.stat(scoring)?.label ?? 'Gols'}: ${scorers.join(', ')}',
        if (best != null) 'Craque do jogo: $best',
      ].join('\n');
      final controller = _fieldsOf(
        BannerTemplate.result,
      )[BannerField.highlight]!;
      if (mounted && _game == game && controller.text.isEmpty) {
        controller.text = text;
      }
    } catch (_) {
      // Sem a súmula, o destaque fica para o administrador escrever.
    }
  }

  void _setStyle(BannerStyle style) {
    setState(() => _style = style);
    ref
        .read(sharedPreferencesProvider)
        .setString(bannerStyleKey(_team.id!), style.toJson());
  }

  /// A imagem do banner em 1080 px de largura, com as fontes já baixadas.
  Future<Uint8List?> _render() async {
    try {
      await GoogleFonts.pendingFonts();
    } catch (_) {
      // Sem internet a fonte cai na padrão; o banner sai assim mesmo.
    }
    // Um quadro para a prévia redesenhar com as fontes carregadas.
    await WidgetsBinding.instance.endOfFrame;
    return capturePng(_boundary);
  }

  Future<void> _export({required bool share}) async {
    setState(() => _busy = true);
    try {
      final png = await _render();
      if (!mounted) return;
      if (png == null) {
        showErrorSnackBar(context, 'Não foi possível gerar a imagem.');
        return;
      }
      if (share) {
        final title = _texts[BannerField.title]?.trim() ?? '';
        await ref.read(shareBannerProvider)(
          png,
          title.isEmpty ? _team.name : '${_team.name} · $title',
        );
      } else {
        await ref.read(saveBannerProvider)(png);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Banner salvo na galeria.')),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        showErrorSnackBar(
          context,
          share
              ? 'Não foi possível compartilhar o banner.'
              : 'Não foi possível salvar o banner na galeria.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickPhoto({required bool featured}) async {
    final current = featured ? _featuredPhoto : _backgroundPhoto;
    final choice = await chooseImage(
      context,
      ref,
      noun: featured ? 'a foto' : 'a imagem de fundo',
      canRemove: current != null,
      maxSize: largeImageSize,
    );
    if (choice == null || !mounted) return;
    final image = switch (choice) {
      ImagePicked(:final image) => MemoryImage(image.bytes),
      ImageRemoved() => null,
    };
    setState(() {
      if (featured) {
        _featuredPhoto = image;
      } else {
        _backgroundPhoto = image;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final game = _game;
    final canvas = BannerCanvas(
      template: _template,
      style: _style,
      texts: _texts,
      teamName: _team.name,
      teamLogoUrl: _team.logoUrl,
      opponentLogoUrl: _opponentLogoOf(_template),
      featuredPhoto: _featuredPhoto,
      backgroundPhoto: _backgroundPhoto,
    );
    final previewHeight = (MediaQuery.sizeOf(context).height * 0.4).clamp(
      220.0,
      420.0,
    );

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Banner'),
          actions: [
            IconButton(
              tooltip: 'Cores do time e padrão',
              icon: const Icon(Icons.restart_alt),
              onPressed: () => _setStyle(_teamStyle),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Modelo'),
              Tab(text: 'Textos'),
              Tab(text: 'Estilo'),
            ],
          ),
        ),
        body: Column(
          children: [
            // A prévia encolhe para caber; a imagem sai no tamanho real.
            Container(
              height: previewHeight,
              width: double.infinity,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              padding: const EdgeInsets.all(12),
              child: FittedBox(
                child: Material(
                  elevation: 4,
                  child: RepaintBoundary(key: _boundary, child: canvas),
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  BannerTemplateTab(
                    template: _template,
                    style: _style,
                    textsOf: _textsOf,
                    teamName: _team.name,
                    teamLogoUrl: _team.logoUrl,
                    opponentLogoOf: _opponentLogoOf,
                    featuredPhoto: _featuredPhoto,
                    backgroundPhoto: _backgroundPhoto,
                    onTemplate: (template) =>
                        setState(() => _template = template),
                    onFormat: (format) =>
                        _setStyle(_style.copyWith(format: format)),
                  ),
                  BannerTextsTab(
                    template: _template,
                    controllers: _fieldsOf(_template),
                    team: _team,
                    gameId: game?.id,
                    opponentLogoUrl: _opponentLogoOf(_template),
                    onPickGame: _pickGame,
                    featuredPhoto: _featuredPhoto,
                    onPickFeaturedPhoto: () => _pickPhoto(featured: true),
                    onReset: _resetTexts,
                    onAthletePhoto: (url) => setState(
                      () => _featuredPhoto = url == null
                          ? null
                          : NetworkImage(url),
                    ),
                  ),
                  BannerStyleTab(
                    style: _style,
                    teamStyle: _teamStyle,
                    backgroundPhoto: _backgroundPhoto,
                    onPickBackground: () => _pickPhoto(featured: false),
                    onChanged: _setStyle,
                  ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _export(share: false),
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Salvar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : () => _export(share: true),
                    icon: _busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.share_outlined),
                    label: const Text('Compartilhar'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
