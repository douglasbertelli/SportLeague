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
import '../../../core/widgets/empty_state.dart';
import '../../games/data/player_stats_repository.dart';
import '../../games/presentation/share_result.dart' show capturePng;
import '../../plans/domain/plan_status.dart';
import '../../plans/presentation/plan_gate.dart';
import '../../teams/data/team_repository.dart';
import '../../teams/domain/team.dart';
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

  Team get _team => widget.team;

  @override
  void initState() {
    super.initState();
    final game = widget.args?.game;
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
    game: widget.args?.game,
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

  /// No resultado, os gols e o craque da súmula (se já foi lançada).
  Future<void> _fillHighlight() async {
    final game = widget.args?.game;
    if (game?.id == null || !game!.hasScore) return;
    try {
      final stats = await ref.read(gameStatsProvider(game.id!).future);
      final mine = stats.where((s) => s.teamId == _team.id).toList();
      final scorers = [
        for (final s
            in mine.where((s) => s.goals > 0).toList()
              ..sort((a, b) => b.goals.compareTo(a.goals)))
          '${s.athleteName ?? 'Atleta'}${s.goals > 1 ? ' (${s.goals})' : ''}',
      ];
      final best = mine.where((s) => s.bestPlayer).firstOrNull?.athleteName;
      final text = [
        if (scorers.isNotEmpty) 'Gols: ${scorers.join(', ')}',
        if (best != null) 'Craque do jogo: $best',
      ].join('\n');
      final controller = _fieldsOf(
        BannerTemplate.result,
      )[BannerField.highlight]!;
      if (mounted && controller.text.isEmpty) controller.text = text;
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
    final game = widget.args?.game;
    final canvas = BannerCanvas(
      template: _template,
      style: _style,
      texts: _texts,
      teamName: _team.name,
      teamLogoUrl: _team.logoUrl,
      opponentLogoUrl: game?.opponentLogoFor(_team.id!),
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
                    opponentLogoUrl: game?.opponentLogoFor(_team.id!),
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
