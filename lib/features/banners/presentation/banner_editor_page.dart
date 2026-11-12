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
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/empty_state.dart';
import '../../athletes/data/athlete_repository.dart';
import '../../athletes/domain/athlete.dart';
import '../../games/data/lineup_repository.dart';
import '../../games/data/player_stats_repository.dart';
import '../../games/presentation/share_result.dart' show capturePng;
import '../../plans/domain/plan_status.dart';
import '../../plans/presentation/plan_gate.dart';
import '../../teams/data/team_repository.dart';
import '../../teams/domain/team.dart';
import '../domain/banner_design.dart';
import 'banner_canvas.dart';
import 'banner_style_tab.dart';

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
              body: const EmptyState(
                icon: Icons.shield_outlined,
                title: 'Nenhum time ativo',
                message: 'Escolha ou crie um time para montar os banners.',
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
        final texts = defaultTexts(
          template,
          teamName: _team.name,
          teamId: _team.id,
          instagram: _team.instagram,
          game: widget.args?.game,
        );
        return {
          for (final field in template.fields)
            field: TextEditingController(text: texts[field] ?? '')
              ..addListener(() => setState(() {})),
        };
      });

  BannerTexts get _texts => {
    for (final MapEntry(:key, :value) in _fieldsOf(_template).entries)
      key: value.text,
  };

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
                  _TemplateTab(
                    template: _template,
                    format: _style.format,
                    onTemplate: (template) =>
                        setState(() => _template = template),
                    onFormat: (format) =>
                        _setStyle(_style.copyWith(format: format)),
                  ),
                  _TextsTab(
                    template: _template,
                    controllers: _fieldsOf(_template),
                    team: _team,
                    gameId: game?.id,
                    featuredPhoto: _featuredPhoto,
                    onPickPhoto: _pickPhoto,
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

class _TemplateTab extends StatelessWidget {
  const _TemplateTab({
    required this.template,
    required this.format,
    required this.onTemplate,
    required this.onFormat,
  });

  final BannerTemplate template;
  final BannerFormat format;
  final ValueChanged<BannerTemplate> onTemplate;
  final ValueChanged<BannerFormat> onFormat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Formato', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<BannerFormat>(
          showSelectedIcon: false,
          segments: [
            for (final format in BannerFormat.values)
              ButtonSegment(
                value: format,
                label: Text('${format.label} ${format.ratio}'),
              ),
          ],
          selected: {format},
          onSelectionChanged: (selected) => onFormat(selected.first),
        ),
        const SizedBox(height: 20),
        Text('Modelo', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.4,
          children: [
            for (final option in BannerTemplate.values)
              _TemplateCard(
                template: option,
                selected: option == template,
                onTap: () => onTemplate(option),
              ),
          ],
        ),
      ],
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.template,
    required this.selected,
    required this.onTap,
  });

  final BannerTemplate template;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? colors.primaryContainer : colors.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected ? colors.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(template.icon, color: colors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        template.label,
                        style: Theme.of(context).textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        template.description,
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
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

class _TextsTab extends ConsumerWidget {
  const _TextsTab({
    required this.template,
    required this.controllers,
    required this.team,
    required this.gameId,
    required this.featuredPhoto,
    required this.onPickPhoto,
    required this.onAthletePhoto,
  });

  final BannerTemplate template;
  final Map<BannerField, TextEditingController> controllers;
  final Team team;
  final String? gameId;
  final ImageProvider? featuredPhoto;
  final Future<void> Function({required bool featured}) onPickPhoto;
  final ValueChanged<String?> onAthletePhoto;

  Future<List<Athlete>> _athletes(WidgetRef ref) =>
      ref.read(activeAthletesProvider(team.id!).future);

  /// Os convocados: a escalação do jogo (titulares primeiro) ou o elenco.
  Future<void> _fillNames(
    BuildContext context,
    WidgetRef ref, {
    required bool lineup,
  }) async {
    try {
      final athletes = await _athletes(ref);
      List<String> names;
      if (lineup) {
        final entries = [
          for (final entry in await ref.read(
            gameLineupProvider(gameId!).future,
          ))
            if (entry.teamId == team.id) entry,
        ]..sort((a, b) => (b.starter ? 1 : 0) - (a.starter ? 1 : 0));
        final byId = {for (final athlete in athletes) athlete.id: athlete};
        names = [
          for (final entry in entries)
            if (byId[entry.athleteId] case final athlete?) _nameOf(athlete),
        ];
        if (names.isEmpty && context.mounted) {
          showErrorSnackBar(context, 'A escalação deste jogo está vazia.');
          return;
        }
      } else {
        names = [for (final athlete in athletes) _nameOf(athlete)];
      }
      if (context.mounted) {
        controllers[BannerField.names]?.text = names.join('\n');
      }
    } catch (_) {
      if (context.mounted) {
        showErrorSnackBar(context, 'Não foi possível carregar os atletas.');
      }
    }
  }

  static String _nameOf(Athlete athlete) => switch (athlete.jerseyNumber) {
    final number? => '$number · ${athlete.displayName}',
    null => athlete.displayName,
  };

  /// O aniversariante escolhido no elenco: o nome e a foto.
  Future<void> _pickAthlete(BuildContext context, WidgetRef ref) async {
    List<Athlete> athletes;
    try {
      athletes = await _athletes(ref);
    } catch (_) {
      if (context.mounted) {
        showErrorSnackBar(context, 'Não foi possível carregar os atletas.');
      }
      return;
    }
    if (!context.mounted) return;
    final athlete = await showAppSheet<Athlete>(
      context,
      builder: (sheetContext) => AppSheet(
        title: 'Aniversariante',
        body: athletes.isEmpty
            ? const Text('O time ainda não tem atletas.')
            : ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.5,
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final athlete in athletes)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          foregroundImage: switch (athlete.photoUrl) {
                            final url? => NetworkImage(url),
                            null => null,
                          },
                          child: Text(
                            athlete.displayName.isEmpty
                                ? '?'
                                : athlete.displayName[0].toUpperCase(),
                          ),
                        ),
                        title: Text(athlete.displayName),
                        onTap: () => Navigator.of(sheetContext).pop(athlete),
                      ),
                  ],
                ),
              ),
        actions: const [SheetBackButton(label: 'Fechar')],
      ),
    );
    if (athlete == null || !context.mounted) return;
    controllers[BannerField.person]?.text = athlete.displayName;
    onAthletePhoto(athlete.photoUrl);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (template == BannerTemplate.callUp)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (gameId != null)
                  ActionChip(
                    avatar: const Icon(Icons.format_list_numbered),
                    label: const Text('Usar a escalação do jogo'),
                    onPressed: () => _fillNames(context, ref, lineup: true),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.groups_outlined),
                  label: const Text('Usar o elenco todo'),
                  onPressed: () => _fillNames(context, ref, lineup: false),
                ),
              ],
            ),
          ),
        if (template == BannerTemplate.birthday)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: ActionChip(
              avatar: const Icon(Icons.person_search_outlined),
              label: const Text('Escolher atleta do elenco'),
              onPressed: () => _pickAthlete(context, ref),
            ),
          ),
        for (final field in template.fields)
          if (controllers[field] case final controller?)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: field.lines,
                keyboardType: field.number
                    ? TextInputType.number
                    : field.lines > 1
                    ? TextInputType.multiline
                    : TextInputType.text,
                inputFormatters: field.number
                    ? [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(2),
                      ]
                    : null,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: field.label,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
        const SizedBox(height: 4),
        if (template.featuredPhoto)
          _PhotoTile(
            icon: Icons.add_a_photo_outlined,
            title: template == BannerTemplate.birthday
                ? 'Foto do aniversariante'
                : 'Foto do time campeão',
            selected: featuredPhoto != null,
            onTap: () => onPickPhoto(featured: true),
          ),
      ],
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(selected ? 'Toque para trocar ou remover' : 'Nenhuma'),
    trailing: selected
        ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary)
        : const Icon(Icons.chevron_right),
    onTap: onTap,
  );
}
