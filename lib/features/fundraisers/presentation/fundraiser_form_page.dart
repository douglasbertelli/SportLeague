import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/error_messages.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/form_page.dart';
import '../../../core/widgets/loading_button.dart';
import '../../athletes/data/athlete_repository.dart';
import '../../teams/domain/team.dart';
import '../data/fundraiser_repository.dart';
import '../domain/fundraiser.dart';
import 'fundraisers_page.dart';

/// Cria ou edita a vaquinha: o item (Bola, Colete, Uniforme ou Outros, com o
/// que vai ser comprado) e o valor, por pessoa ou o total do produto
/// (dividido entre as pessoas).
class FundraiserFormPage extends ConsumerStatefulWidget {
  const FundraiserFormPage({super.key, required this.team, this.fundraiser});

  final Team team;
  final Fundraiser? fundraiser;

  @override
  ConsumerState<FundraiserFormPage> createState() => _FundraiserFormPageState();
}

class _FundraiserFormPageState extends ConsumerState<FundraiserFormPage> {
  final _formKey = GlobalKey<FormState>();
  late var _item = widget.fundraiser?.item ?? FundraiserItem.ball;
  late var _amountType = widget.fundraiser?.amountType ?? AmountType.perPerson;
  late final _description = TextEditingController(
    text: widget.fundraiser?.description,
  );
  late final _amount = TextEditingController(
    text: switch (widget.fundraiser?.amountCents) {
      final cents? => formatMoney(cents).replaceAll(r'R$', '').trim(),
      null => '',
    },
  );
  var _loading = false;

  bool get _isEditing => widget.fundraiser != null;

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    final fundraiser = Fundraiser(
      id: widget.fundraiser?.id,
      teamId: widget.team.id!,
      item: _item,
      description: _item == FundraiserItem.other
          ? _description.text.trim()
          : null,
      amountCents: parseMoney(_amount.text)!,
      amountType: _amountType,
      closed: widget.fundraiser?.closed ?? false,
      createdAt: widget.fundraiser?.createdAt,
    );
    try {
      final repository = ref.read(fundraiserRepositoryProvider);
      if (_isEditing) {
        await repository.update(fundraiser);
      } else {
        await repository.create(fundraiser);
      }
      ref.invalidate(teamFundraisersProvider(widget.team.id!));
      if (mounted) context.pop(fundraiser);
    } catch (error) {
      if (mounted) showErrorSnackBar(context, friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Explica o valor e, com ele digitado, mostra a conta: quanto cada um paga
  /// (valor total) ou quanto a vaquinha junta (por pessoa).
  String _helper() {
    final people = switch (ref.watch(teamAthletesProvider(widget.team.id!))) {
      AsyncValue(value: final athletes?) => fundraiserPeople(
        athletes,
        widget.team.ownerId,
      ),
      _ => null,
    };
    final cents = parseMoney(_amount.text);
    if (people == null || cents == null || cents <= 0) {
      return switch (_amountType) {
        AmountType.perPerson =>
          'Cada atleta e o administrador pagam esse valor',
        AmountType.total =>
          'Dividido entre o administrador e os atletas do time',
      };
    }
    final preview = Fundraiser(
      teamId: widget.team.id!,
      item: _item,
      amountCents: cents,
      amountType: _amountType,
    );
    final peopleLabel = people == 1 ? '1 pessoa' : '$people pessoas';
    return switch (_amountType) {
      AmountType.perPerson =>
        'Cada um paga esse valor · total de '
            '${formatMoney(preview.goalCents(people))} ($peopleLabel)',
      AmountType.total =>
        'Dividido por $peopleLabel: '
            '${formatMoney(preview.shareCents(people))} por pessoa',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FormPage(
      alignTop: true,
      appBar: AppBar(
        title: Text(_isEditing ? 'Editar vaquinha' : 'Nova vaquinha'),
      ),
      children: [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Para que é a vaquinha?', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final item in FundraiserItem.values)
                    ChoiceChip(
                      avatar: Icon(fundraiserIcon(item), size: 18),
                      label: Text(item.label),
                      selected: item == _item,
                      onSelected: _loading
                          ? null
                          : (_) => setState(() => _item = item),
                    ),
                ],
              ),
              if (_item == FundraiserItem.other) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _description,
                  enabled: !_loading,
                  autofocus: !_isEditing,
                  maxLength: 60,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'O que vai ser comprado?',
                    hintText: 'Ex.: Rede do gol, troféu, confraternização',
                  ),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'Informe o que vai ser comprado'
                      : null,
                ),
              ],
              const SizedBox(height: 24),
              Text('Como informar o valor?', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<AmountType>(
                showSelectedIcon: false,
                segments: [
                  for (final type in AmountType.values)
                    ButtonSegment(value: type, label: Text(type.label)),
                ],
                selected: {_amountType},
                onSelectionChanged: _loading
                    ? null
                    : (selection) =>
                          setState(() => _amountType = selection.single),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amount,
                enabled: !_loading,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: switch (_amountType) {
                    AmountType.perPerson => 'Valor por pessoa',
                    AmountType.total => 'Valor total do produto',
                  },
                  prefixText: r'R$ ',
                  helperText: _helper(),
                  helperMaxLines: 2,
                ),
                validator: (value) => switch (parseMoney(value ?? '')) {
                  null => 'Informe o valor',
                  final cents when cents <= 0 =>
                    'O valor deve ser maior que zero',
                  _ => null,
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        LoadingButton(
          label: _isEditing ? 'Salvar' : 'Criar vaquinha',
          loading: _loading,
          onPressed: _save,
        ),
      ],
    );
  }
}
