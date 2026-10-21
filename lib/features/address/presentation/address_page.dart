import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/form_page.dart';
import '../../../core/widgets/loading_button.dart';
import '../../auth/data/auth_repository.dart';
import '../data/address_repository.dart';
import '../data/zip_code_service.dart';
import '../domain/address.dart';

class AddressPage extends ConsumerStatefulWidget {
  const AddressPage({super.key, this.isOnboarding = false});

  /// No onboarding o router segue para a home após salvar; na edição, a
  /// página é fechada.
  final bool isOnboarding;

  @override
  ConsumerState<AddressPage> createState() => _AddressPageState();
}

class _AddressPageState extends ConsumerState<AddressPage> {
  final _formKey = GlobalKey<FormState>();
  final _zipCodeController = TextEditingController();
  final _streetController = TextEditingController();
  final _numberController = TextEditingController();
  final _complementController = TextEditingController();
  final _neighborhoodController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _numberFocus = FocusNode();
  bool _loading = false;
  bool _searchingZipCode = false;

  @override
  void initState() {
    super.initState();
    final current = ref.read(myAddressProvider).value;
    if (current != null) {
      _zipCodeController.text = current.zipCode;
      _streetController.text = current.street;
      _numberController.text = current.number;
      _complementController.text = current.complement ?? '';
      _neighborhoodController.text = current.neighborhood;
      _cityController.text = current.city;
      _stateController.text = current.state;
    }
  }

  @override
  void dispose() {
    _zipCodeController.dispose();
    _streetController.dispose();
    _numberController.dispose();
    _complementController.dispose();
    _neighborhoodController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _numberFocus.dispose();
    super.dispose();
  }

  Future<void> _lookupZipCode(String value) async {
    if (value.length != 8) return;
    setState(() => _searchingZipCode = true);
    try {
      final result = await ref.read(zipCodeServiceProvider).lookup(value);
      if (!mounted) return;
      if (result == null) {
        _showMessage('CEP não encontrado. Preencha o endereço manualmente.');
        return;
      }
      _streetController.text = result.street;
      _neighborhoodController.text = result.neighborhood;
      _cityController.text = result.city;
      _stateController.text = result.state;
      _numberFocus.requestFocus();
    } catch (_) {
      _showMessage('Não foi possível consultar o CEP. Preencha manualmente.');
    } finally {
      if (mounted) setState(() => _searchingZipCode = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    setState(() => _loading = true);
    try {
      final complement = _complementController.text.trim();
      await ref
          .read(addressRepositoryProvider)
          .save(
            Address(
              profileId: userId,
              zipCode: _zipCodeController.text,
              street: _streetController.text.trim(),
              number: _numberController.text.trim(),
              complement: complement.isEmpty ? null : complement,
              neighborhood: _neighborhoodController.text.trim(),
              city: _cityController.text.trim(),
              state: _stateController.text.trim(),
            ),
          );
      ref.invalidate(myAddressProvider);
      if (!widget.isOnboarding && mounted) {
        _showMessage('Endereço atualizado.');
        context.pop();
      }
    } catch (error) {
      _showMessage(friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return FormPage(
      appBar: AppBar(
        title: const Text('Seu endereço'),
        actions: [
          if (widget.isOnboarding)
            IconButton(
              tooltip: 'Sair',
              icon: const Icon(Icons.logout),
              onPressed: () => ref.read(authRepositoryProvider).signOut(),
            ),
        ],
      ),
      children: [
        Text(
          'Usamos seu endereço para encontrar times e jogos perto de você.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 24),
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _zipCodeController,
                decoration: InputDecoration(
                  labelText: 'CEP',
                  counterText: '',
                  suffixIcon: _searchingZipCode
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 8,
                autofillHints: const [AutofillHints.postalCode],
                onChanged: _lookupZipCode,
                validator: Validators.zipCode,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _streetController,
                decoration: const InputDecoration(labelText: 'Rua'),
                textCapitalization: TextCapitalization.words,
                validator: Validators.required,
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _numberController,
                      focusNode: _numberFocus,
                      decoration: const InputDecoration(labelText: 'Número'),
                      validator: Validators.required,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _complementController,
                      decoration: const InputDecoration(
                        labelText: 'Complemento (opcional)',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _neighborhoodController,
                decoration: const InputDecoration(labelText: 'Bairro'),
                textCapitalization: TextCapitalization.words,
                validator: Validators.required,
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _cityController,
                      decoration: const InputDecoration(labelText: 'Cidade'),
                      textCapitalization: TextCapitalization.words,
                      validator: Validators.required,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _stateController,
                      decoration: const InputDecoration(
                        labelText: 'UF',
                        counterText: '',
                      ),
                      textCapitalization: TextCapitalization.characters,
                      maxLength: 2,
                      validator: Validators.state,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        LoadingButton(
          label: 'Salvar endereço',
          loading: _loading,
          onPressed: _submit,
        ),
      ],
    );
  }
}
