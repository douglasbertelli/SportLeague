import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/error_messages.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/form_page.dart';
import '../../../core/widgets/loading_button.dart';
import '../../teams/data/team_repository.dart';
import '../data/game_repository.dart';
import '../domain/game.dart';
import 'games_tab.dart';

/// Marca um jogo para o time ativo ou edita/exclui um existente. O placar é
/// opcional: os dois campos juntos ou nenhum.
class GameFormPage extends ConsumerStatefulWidget {
  const GameFormPage({super.key, this.game});

  final Game? game;

  @override
  ConsumerState<GameFormPage> createState() => _GameFormPageState();
}

class _GameFormPageState extends ConsumerState<GameFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final _opponentController = TextEditingController(
    text: widget.game?.opponent,
  );
  late final _locationController = TextEditingController(
    text: widget.game?.location,
  );
  late final _teamScoreController = TextEditingController(
    text: widget.game?.teamScore?.toString(),
  );
  late final _opponentScoreController = TextEditingController(
    text: widget.game?.opponentScore?.toString(),
  );
  late DateTime? _scheduledAt = widget.game?.scheduledAt;
  late GameType _type = widget.game?.type ?? GameType.friendly;
  bool _dateMissing = false;
  bool _loading = false;

  bool get _isEditing => widget.game != null;

  @override
  void dispose() {
    _opponentController.dispose();
    _locationController.dispose();
    _teamScoreController.dispose();
    _opponentScoreController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final initial = _scheduledAt ?? DateTime(now.year, now.month, now.day, 15);
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return;
    setState(() {
      _scheduledAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      _dateMissing = false;
    });
  }

  String? _validateScore(String? value, TextEditingController other) {
    final empty = value == null || value.isEmpty;
    if (empty != other.text.isEmpty) return 'Preencha os dois placares';
    return null;
  }

  Future<void> _save() async {
    final valid = _formKey.currentState!.validate();
    setState(() => _dateMissing = _scheduledAt == null);
    if (_loading || !valid || _scheduledAt == null) return;

    final teamId =
        widget.game?.teamId ?? ref.read(selectedTeamProvider).value?.id;
    if (teamId == null) return;

    final game = Game(
      id: widget.game?.id,
      teamId: teamId,
      opponent: _opponentController.text,
      scheduledAt: _scheduledAt!,
      location: _locationController.text,
      type: _type,
      teamScore: int.tryParse(_teamScoreController.text),
      opponentScore: int.tryParse(_opponentScoreController.text),
    );
    final repository = ref.read(gameRepositoryProvider);
    await _run(
      teamId,
      () => _isEditing ? repository.update(game) : repository.create(game),
    );
  }

  Future<void> _delete() async {
    final game = widget.game!;
    final confirmed = await confirmDelete(
      context,
      title: 'Excluir jogo?',
      message: 'O jogo contra ${game.opponent} será excluído.',
    );
    if (!confirmed) return;
    await _run(
      game.teamId,
      () => ref.read(gameRepositoryProvider).delete(game.id!),
    );
  }

  Future<void> _run(String teamId, Future<void> Function() action) async {
    setState(() => _loading = true);
    try {
      await action();
      ref.invalidate(teamGamesProvider(teamId));
      if (mounted) context.pop();
    } catch (error) {
      if (mounted) showErrorSnackBar(context, friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final teamName = ref.watch(selectedTeamProvider).value?.name;
    final scheduledAt = _scheduledAt;
    final scoreFormatters = [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(3),
    ];

    return FormPage(
      appBar: AppBar(
        title: Text(_isEditing ? 'Editar jogo' : 'Novo jogo'),
        actions: [
          if (_isEditing)
            IconButton(
              tooltip: 'Excluir jogo',
              icon: const Icon(Icons.delete_outline),
              onPressed: _loading ? null : _delete,
            ),
        ],
      ),
      children: [
        if (!_isEditing && teamName != null) ...[
          Text('Time: $teamName', style: theme.textTheme.titleSmall),
          const SizedBox(height: 16),
        ],
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<GameType>(
                segments: [
                  for (final type in GameType.values)
                    ButtonSegment(value: type, label: Text(type.label)),
                ],
                selected: {_type},
                onSelectionChanged: (selection) =>
                    setState(() => _type = selection.first),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _opponentController,
                decoration: const InputDecoration(labelText: 'Adversário'),
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                maxLength: 80,
                validator: (value) =>
                    Validators.name(value, message: 'Informe o adversário'),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: _pickDateTime,
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Data e hora',
                    suffixIcon: const Icon(Icons.event),
                    errorText: _dateMissing ? 'Escolha a data e a hora' : null,
                  ),
                  isEmpty: scheduledAt == null,
                  child: Text(
                    scheduledAt == null
                        ? ''
                        : formatGameDate(context, scheduledAt),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _locationController,
                decoration: const InputDecoration(
                  labelText: 'Local (opcional)',
                ),
                textCapitalization: TextCapitalization.sentences,
                maxLength: 160,
              ),
              const SizedBox(height: 8),
              Text(
                'Placar (depois do jogo)',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _teamScoreController,
                      decoration: InputDecoration(
                        labelText: teamName ?? 'Seu time',
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: scoreFormatters,
                      validator: (value) =>
                          _validateScore(value, _opponentScoreController),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                    child: Text('x'),
                  ),
                  Expanded(
                    child: TextFormField(
                      controller: _opponentScoreController,
                      decoration: const InputDecoration(
                        labelText: 'Adversário',
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: scoreFormatters,
                      validator: (value) =>
                          _validateScore(value, _teamScoreController),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        LoadingButton(
          label: _isEditing ? 'Salvar' : 'Marcar jogo',
          loading: _loading,
          onPressed: _save,
        ),
      ],
    );
  }
}
