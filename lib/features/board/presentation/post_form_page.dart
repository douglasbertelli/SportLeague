import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../games/presentation/game_card.dart'
    show formatGameDay, formatGameTime;
import '../../teams/domain/team.dart';
import '../data/board_repository.dart';
import '../domain/board_post.dart';

/// Publica um aviso ou uma enquete no mural do time.
class PostFormPage extends ConsumerStatefulWidget {
  const PostFormPage({super.key, required this.team, required this.kind});

  final Team team;
  final BoardPostKind kind;

  @override
  ConsumerState<PostFormPage> createState() => _PostFormPageState();
}

class _PostFormPageState extends ConsumerState<PostFormPage> {
  final _form = GlobalKey<FormState>();
  final _body = TextEditingController();
  final _options = [TextEditingController(), TextEditingController()];
  bool _multiple = false;
  bool _anonymous = false;
  bool _pinned = false;
  DateTime? _closesAt;
  bool _saving = false;

  bool get _isPoll => widget.kind == BoardPostKind.poll;

  @override
  void dispose() {
    _body.dispose();
    for (final option in _options) {
      option.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final initial = _closesAt ?? now.add(const Duration(days: 1));
    final day = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return;
    setState(
      () => _closesAt = DateTime(
        day.year,
        day.month,
        day.day,
        time.hour,
        time.minute,
      ),
    );
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final options = [
      for (final option in _options)
        if (option.text.trim().isNotEmpty) option.text.trim(),
    ];
    if (_isPoll && options.length < 2) {
      showErrorSnackBar(context, 'Preencha pelo menos duas opções.');
      return;
    }
    if (_closesAt case final closesAt? when !closesAt.isAfter(DateTime.now())) {
      showErrorSnackBar(context, 'O prazo precisa ser no futuro.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(boardRepositoryProvider)
          .create(
            teamId: widget.team.id!,
            kind: widget.kind,
            body: _body.text.trim(),
            options: options,
            multiple: _multiple,
            anonymous: _anonymous,
            closesAt: _closesAt,
            pinned: _pinned,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) showErrorSnackBar(context, friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final closesAt = _closesAt;
    return Scaffold(
      appBar: AppBar(title: Text(_isPoll ? 'Nova enquete' : 'Novo aviso')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Text(
              'Para todo o ${widget.team.name}: atletas, técnicos e você.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _body,
              autofocus: true,
              minLines: _isPoll ? 2 : 4,
              maxLines: 10,
              maxLength: 2000,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: _isPoll ? 'Pergunta' : 'Aviso',
                hintText: _isPoll
                    ? 'Ex.: Churrasco sábado ou domingo?'
                    : 'Ex.: Treino de quinta mudou para as 20h.',
                alignLabelWithHint: true,
              ),
              validator: (value) => (value ?? '').trim().isEmpty
                  ? (_isPoll ? 'Escreva a pergunta.' : 'Escreva o aviso.')
                  : null,
            ),
            if (_isPoll) ...[
              const SizedBox(height: 8),
              Text('Opções', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              for (final (index, option) in _options.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextFormField(
                    controller: option,
                    maxLength: 120,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: 'Opção ${index + 1}',
                      counterText: '',
                      suffixIcon: _options.length > 2
                          ? IconButton(
                              tooltip: 'Tirar opção ${index + 1}',
                              icon: const Icon(Icons.close),
                              onPressed: () => setState(() {
                                _options.removeAt(index).dispose();
                              }),
                            )
                          : null,
                    ),
                  ),
                ),
              if (_options.length < 10)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () =>
                        setState(() => _options.add(TextEditingController())),
                    icon: const Icon(Icons.add),
                    label: const Text('Adicionar opção'),
                  ),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Várias respostas'),
                subtitle: const Text('Cada um pode marcar mais de uma opção'),
                value: _multiple,
                onChanged: (value) => setState(() => _multiple = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Voto anônimo'),
                subtitle: const Text('Mostra só a contagem, sem quem votou'),
                value: _anonymous,
                onChanged: (value) => setState(() => _anonymous = value),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: const Text('Prazo para votar'),
                subtitle: Text(
                  closesAt == null
                      ? 'Sem prazo. Duas horas antes do prazo, quem não '
                            'votou recebe um lembrete.'
                      : '${formatGameDay(closesAt)} às '
                            '${formatGameTime(closesAt)}',
                ),
                trailing: closesAt == null
                    ? const Icon(Icons.chevron_right)
                    : IconButton(
                        tooltip: 'Tirar o prazo',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _closesAt = null),
                      ),
                onTap: _pickDeadline,
              ),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Fixar no topo'),
              subtitle: const Text('Fica em cima no mural (só um por vez)'),
              value: _pinned,
              onChanged: (value) => setState(() => _pinned = value),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.send),
              label: Text(_isPoll ? 'Publicar enquete' : 'Publicar aviso'),
            ),
          ],
        ),
      ),
    );
  }
}
