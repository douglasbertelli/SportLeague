import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../athletes/data/athlete_repository.dart';
import '../../athletes/domain/athlete.dart';
import '../../games/data/lineup_repository.dart';
import '../../teams/domain/team.dart';
import '../domain/banner_design.dart';
import 'banner_photo_tile.dart';

/// Títulos prontos de cada modelo, para tocar e usar.
const bannerTitleSuggestions = <BannerTemplate, List<String>>{
  BannerTemplate.gameDay: [
    'DIA DE JOGO',
    'É HOJE!',
    'JOGO MARCADO',
    'BORA, TIME!',
  ],
  BannerTemplate.result: ['FIM DE JOGO', 'VITÓRIA!', 'GOLEADA!', 'RESULTADO'],
  BannerTemplate.callUp: ['CONVOCADOS', 'RELACIONADOS', 'ESCALAÇÃO'],
  BannerTemplate.birthday: ['PARABÉNS!', 'FELIZ ANIVERSÁRIO', 'HOJE TEM BOLO!'],
  BannerTemplate.champion: [
    'CAMPEÃO!',
    'É CAMPEÃO!',
    'TÍTULO!',
    'VICE-CAMPEÃO',
  ],
  BannerTemplate.notice: ['AVISO', 'ATENÇÃO', 'COMUNICADO', 'TREINO'],
};

/// Grupos de campos da aba, na ordem.
enum _Section {
  titles('Títulos', [BannerField.title, BannerField.subtitle]),
  match('Partida', [
    BannerField.team,
    BannerField.opponent,
    BannerField.teamScore,
    BannerField.opponentScore,
    BannerField.date,
    BannerField.time,
    BannerField.place,
  ]),
  content('Conteúdo', [
    BannerField.highlight,
    BannerField.names,
    BannerField.person,
    BannerField.message,
  ]),
  footer('Rodapé', [BannerField.footer]);

  const _Section(this.label, this.fields);

  final String label;
  final List<BannerField> fields;
}

/// A aba Textos do editor: os campos do modelo em grupos (títulos, partida,
/// conteúdo, rodapé), com títulos prontos, placar com − e +, data e horário
/// pelo calendário e pelo relógio, convocados e aniversariante do elenco.
class BannerTextsTab extends ConsumerWidget {
  const BannerTextsTab({
    super.key,
    required this.template,
    required this.controllers,
    required this.team,
    required this.gameId,
    required this.featuredPhoto,
    required this.onPickFeaturedPhoto,
    required this.onAthletePhoto,
    required this.onReset,
  });

  final BannerTemplate template;
  final Map<BannerField, TextEditingController> controllers;
  final Team team;
  final String? gameId;
  final ImageProvider? featuredPhoto;
  final VoidCallback onPickFeaturedPhoto;
  final ValueChanged<String?> onAthletePhoto;

  /// Volta os textos do modelo aos iniciais.
  final VoidCallback onReset;

  Future<List<Athlete>> _athletes(WidgetRef ref) =>
      ref.read(activeAthletesProvider(team.id!).future);

  static String _nameOf(Athlete athlete) => switch (athlete.jerseyNumber) {
    final number? => '$number · ${athlete.displayName}',
    null => athlete.displayName,
  };

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

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date != null) controllers[BannerField.date]?.text = bannerDate(date);
  }

  Future<void> _pickTime(BuildContext context) async {
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 20, minute: 0),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (time != null) {
      controllers[BannerField.time]?.text = bannerTime(
        DateTime(2000, 1, 1, time.hour, time.minute),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    Widget heading(String text, {Widget? trailing}) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(text, style: theme.textTheme.titleSmall)),
          ?trailing,
        ],
      ),
    );

    final children = <Widget>[];
    for (final section in _Section.values) {
      final fields = [
        for (final field in section.fields)
          if (controllers.containsKey(field)) field,
      ];
      final hasPhoto = section == _Section.content && template.featuredPhoto;
      if (fields.isEmpty && !hasPhoto) continue;
      children.add(
        heading(
          section.label,
          trailing: section == _Section.titles
              ? TextButton.icon(
                  onPressed: onReset,
                  icon: const Icon(Icons.restart_alt, size: 18),
                  label: const Text('Restaurar'),
                )
              : null,
        ),
      );
      for (final field in fields) {
        // O placar vai junto, numa linha só.
        if (field == BannerField.opponentScore) continue;
        if (field == BannerField.teamScore) {
          children.add(
            _ScoreRow(
              team: controllers[BannerField.team]!,
              opponent: controllers[BannerField.opponent]!,
              teamScore: controllers[BannerField.teamScore]!,
              opponentScore: controllers[BannerField.opponentScore]!,
            ),
          );
          continue;
        }
        children.add(_fieldWidget(context, ref, field));
      }
      if (hasPhoto) {
        children.add(
          BannerPhotoTile(
            photo: featuredPhoto,
            icon: Icons.add_a_photo_outlined,
            title: template == BannerTemplate.birthday
                ? 'Foto do aniversariante'
                : 'Foto do time campeão',
            emptySubtitle: template == BannerTemplate.birthday
                ? 'Aparece no centro, num círculo'
                : 'Aparece no lugar do troféu',
            onTap: onPickFeaturedPhoto,
          ),
        );
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: children,
    );
  }

  Widget _fieldWidget(BuildContext context, WidgetRef ref, BannerField field) {
    final controller = controllers[field]!;
    switch (field) {
      case BannerField.title:
        return _Field(
          controller: controller,
          field: field,
          capitalization: TextCapitalization.characters,
          below: _Suggestions(
            options: bannerTitleSuggestions[template] ?? const [],
            controller: controller,
          ),
        );
      case BannerField.date:
        return _Field(
          controller: controller,
          field: field,
          icon: Icons.calendar_month_outlined,
          action: IconButton(
            tooltip: 'Escolher no calendário',
            icon: const Icon(Icons.edit_calendar_outlined),
            onPressed: () => _pickDate(context),
          ),
        );
      case BannerField.time:
        return _Field(
          controller: controller,
          field: field,
          icon: Icons.schedule,
          action: IconButton(
            tooltip: 'Escolher o horário',
            icon: const Icon(Icons.more_time),
            onPressed: () => _pickTime(context),
          ),
        );
      case BannerField.place:
        return _Field(
          controller: controller,
          field: field,
          icon: Icons.place_outlined,
        );
      case BannerField.footer:
        return _Field(
          controller: controller,
          field: field,
          icon: Icons.alternate_email,
        );
      case BannerField.names:
        return _Field(
          controller: controller,
          field: field,
          above: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (gameId != null)
                ActionChip(
                  avatar: const Icon(Icons.format_list_numbered),
                  label: const Text('Escalação do jogo'),
                  onPressed: () => _fillNames(context, ref, lineup: true),
                ),
              ActionChip(
                avatar: const Icon(Icons.groups_outlined),
                label: const Text('Elenco todo'),
                onPressed: () => _fillNames(context, ref, lineup: false),
              ),
            ],
          ),
          counter: (text) {
            final count = text
                .split('\n')
                .where((line) => line.trim().isNotEmpty)
                .length;
            return switch (count) {
              0 => 'Nenhum convocado',
              1 => '1 convocado',
              _ => '$count convocados',
            };
          },
        );
      case BannerField.person:
        return _Field(
          controller: controller,
          field: field,
          icon: Icons.person_outline,
          action: IconButton(
            tooltip: 'Escolher atleta do elenco',
            icon: const Icon(Icons.person_search_outlined),
            onPressed: () => _pickAthlete(context, ref),
          ),
        );
      case BannerField.team || BannerField.opponent:
        return _Field(
          controller: controller,
          field: field,
          icon: Icons.shield_outlined,
        );
      default:
        return _Field(controller: controller, field: field);
    }
  }
}

/// Um campo de texto, com ícone, ação no fim, algo antes e depois e um
/// contador opcional.
class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.field,
    this.icon,
    this.action,
    this.above,
    this.below,
    this.counter,
    this.capitalization = TextCapitalization.sentences,
  });

  final TextEditingController controller;
  final BannerField field;
  final IconData? icon;
  final Widget? action;
  final Widget? above;
  final Widget? below;
  final String Function(String text)? counter;
  final TextCapitalization capitalization;

  @override
  Widget build(BuildContext context) {
    final multiline = field.lines > 1;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (above != null) ...[above!, const SizedBox(height: 8)],
          TextField(
            controller: controller,
            minLines: multiline ? 2 : 1,
            maxLines: field.lines,
            keyboardType: multiline
                ? TextInputType.multiline
                : TextInputType.text,
            textCapitalization: capitalization,
            decoration: InputDecoration(
              labelText: field.label,
              border: const OutlineInputBorder(),
              prefixIcon: icon == null ? null : Icon(icon),
              suffixIcon: action,
              helperText: counter?.call(controller.text),
            ),
          ),
          if (below != null) ...[const SizedBox(height: 6), below!],
        ],
      ),
    );
  }
}

/// Títulos prontos: tocar troca o título.
class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.options, required this.controller});

  final List<String> options;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 36,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: options.length,
      separatorBuilder: (_, _) => const SizedBox(width: 6),
      itemBuilder: (context, index) {
        final option = options[index];
        return ChoiceChip(
          label: Text(option),
          visualDensity: VisualDensity.compact,
          selected: controller.text.trim() == option,
          onSelected: (_) => controller.text = option,
        );
      },
    ),
  );
}

/// O placar numa linha: os dois times com − e + no meio.
class _ScoreRow extends StatelessWidget {
  const _ScoreRow({
    required this.team,
    required this.opponent,
    required this.teamScore,
    required this.opponentScore,
  });

  final TextEditingController team;
  final TextEditingController opponent;
  final TextEditingController teamScore;
  final TextEditingController opponentScore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: _ScoreStepper(name: team, score: teamScore),
            ),
            Text('×', style: theme.textTheme.headlineSmall),
            Expanded(
              child: _ScoreStepper(name: opponent, score: opponentScore),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScoreStepper extends StatelessWidget {
  const _ScoreStepper({required this.name, required this.score});

  final TextEditingController name;
  final TextEditingController score;

  void _add(int delta) {
    final value = (int.tryParse(score.text) ?? 0) + delta;
    score.text = '${value.clamp(0, 99)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = name.text.trim().isEmpty ? 'Time' : name.text.trim();
    return Column(
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: 'Menos um gol de $label',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: () => _add(-1),
            ),
            SizedBox(
              width: 40,
              child: TextField(
                controller: score,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                style: theme.textTheme.headlineSmall,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(2),
                ],
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  semanticCounterText: '',
                  hintText: '0',
                  labelText: null,
                  hintStyle: theme.textTheme.headlineSmall,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Mais um gol de $label',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () => _add(1),
            ),
          ],
        ),
      ],
    );
  }
}
