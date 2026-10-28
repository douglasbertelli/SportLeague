import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/form_page.dart';
import '../../../core/widgets/loading_button.dart';
import '../../athletes/domain/athlete.dart';
import '../data/profile_repository.dart';
import '../domain/profile.dart';

/// O jogador preenche os próprios dados de atleta: nascimento, posição
/// preferida, pé dominante e altura. Todos são opcionais.
class AthleteDataPage extends ConsumerStatefulWidget {
  const AthleteDataPage({super.key, required this.profile});

  final Profile profile;

  @override
  ConsumerState<AthleteDataPage> createState() => _AthleteDataPageState();
}

class _AthleteDataPageState extends ConsumerState<AthleteDataPage> {
  final _formKey = GlobalKey<FormState>();
  late final _heightController = TextEditingController(
    text: widget.profile.heightCm?.toString(),
  );
  late DateTime? _birthDate = widget.profile.birthDate;
  late String? _position = widget.profile.preferredPosition;
  late PreferredFoot? _foot = widget.profile.preferredFoot;
  bool _loading = false;

  @override
  void dispose() {
    _heightController.dispose();
    super.dispose();
  }

  Future<void> _pickBirthDate() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(today.year - 20),
      firstDate: DateTime(1900),
      lastDate: today,
      initialEntryMode: DatePickerEntryMode.input,
      helpText: 'Data de nascimento',
    );
    if (picked != null) setState(() => _birthDate = picked);
  }

  /// Escolha da posição num bottom sheet; "Sem posição" limpa.
  Future<void> _pickPosition(List<String> positions) async {
    final choice = await showAppSheet<({String? position})>(
      context,
      builder: (context) => AppSheet(
        title: 'Posição preferida',
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final position in [...positions, null])
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  position == null
                      ? Icons.remove_circle_outline
                      : Icons.sports_soccer,
                ),
                title: Text(position ?? 'Sem posição'),
                trailing: position == _position
                    ? const Icon(Icons.check)
                    : null,
                selected: position == _position,
                onTap: () => Navigator.of(context).pop((position: position)),
              ),
          ],
        ),
        actions: const [SheetBackButton()],
      ),
    );
    if (choice != null) setState(() => _position = choice.position);
  }

  Future<void> _save() async {
    if (_loading || !_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ref
          .read(profileRepositoryProvider)
          .updateAthleteData(
            userId: widget.profile.id,
            birthDate: _birthDate,
            preferredPosition: _position,
            preferredFoot: _foot,
            heightCm: int.tryParse(_heightController.text),
          );
      ref.invalidate(currentProfileProvider);
      if (mounted) context.pop();
    } catch (error) {
      if (mounted) showErrorSnackBar(context, friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final birthDate = _birthDate;
    final positions = [
      ...footballPositions,
      // Mantém uma posição antiga que não está mais na lista.
      if (_position != null && !footballPositions.contains(_position))
        _position!,
    ];

    return FormPage(
      appBar: AppBar(title: const Text('Dados de atleta')),
      children: [
        Text(
          'Os times em que você joga veem esses dados.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                onTap: _loading ? null : _pickBirthDate,
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Data de nascimento',
                    suffixIcon: birthDate == null
                        ? const Icon(Icons.calendar_today_outlined)
                        : IconButton(
                            tooltip: 'Limpar data de nascimento',
                            icon: const Icon(Icons.clear),
                            onPressed: _loading
                                ? null
                                : () => setState(() => _birthDate = null),
                          ),
                  ),
                  isEmpty: birthDate == null,
                  child: Text(
                    birthDate == null
                        ? ''
                        : DateFormat('dd/MM/yyyy').format(birthDate),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: _loading ? null : () => _pickPosition(positions),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Posição preferida',
                    suffixIcon: Icon(Icons.expand_more),
                  ),
                  isEmpty: _position == null,
                  child: Text(_position ?? ''),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _heightController,
                enabled: !_loading,
                decoration: const InputDecoration(
                  labelText: 'Altura',
                  suffixText: 'cm',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(3),
                ],
                validator: (value) {
                  if (value == null || value.isEmpty) return null;
                  final height = int.parse(value);
                  return height < 100 || height > 230
                      ? 'Entre 100 e 230 cm'
                      : null;
                },
              ),
              const SizedBox(height: 16),
              Text(
                'Pé dominante',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              SegmentedButton<PreferredFoot>(
                segments: [
                  for (final foot in PreferredFoot.values)
                    ButtonSegment(value: foot, label: Text(foot.label)),
                ],
                selected: {?_foot},
                emptySelectionAllowed: true,
                showSelectedIcon: false,
                onSelectionChanged: _loading
                    ? null
                    : (selection) =>
                          setState(() => _foot = selection.firstOrNull),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        LoadingButton(label: 'Salvar', loading: _loading, onPressed: _save),
      ],
    );
  }
}
