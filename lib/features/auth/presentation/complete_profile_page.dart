import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/form_page.dart';
import '../../../core/widgets/loading_button.dart';
import '../../profile/data/profile_repository.dart';
import '../../profile/domain/profile.dart';
import '../data/auth_repository.dart';
import 'role_selector.dart';

/// Etapa logo depois de criar a conta (por e-mail, Google ou Apple): escolha
/// do tipo de perfil. Pede também o nome quando o cadastro não trouxe um.
class CompleteProfilePage extends ConsumerStatefulWidget {
  const CompleteProfilePage({super.key});

  @override
  ConsumerState<CompleteProfilePage> createState() =>
      _CompleteProfilePageState();
}

class _CompleteProfilePageState extends ConsumerState<CompleteProfilePage> {
  final _formKey = GlobalKey<FormState>();
  late final bool _askName;
  late final TextEditingController _nameController;
  UserRole? _role;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _askName = ref.read(currentProfileProvider).value?.needsName ?? false;
    // A Apple envia o nome só no app e depois que o perfil já foi criado.
    final metadataName = ref
        .read(supabaseClientProvider)
        .auth
        .currentUser
        ?.userMetadata?['full_name'];
    _nameController = TextEditingController(
      text: metadataName is String ? metadataName.trim() : null,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final form = _formKey.currentState!;
    if (!form.validate()) return;
    form.save();

    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    setState(() => _loading = true);
    try {
      await ref
          .read(profileRepositoryProvider)
          .completeProfile(
            userId: userId,
            role: _role!,
            fullName: _askName ? _nameController.text : null,
          );
      // Com o perfil completo, o router segue para o cadastro de endereço.
      ref.invalidate(currentProfileProvider);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FormPage(
      appBar: AppBar(
        title: const Text('Escolha seu perfil'),
        actions: [
          TextButton.icon(
            onPressed: _loading
                ? null
                : () => ref.read(authRepositoryProvider).signOut(),
            icon: const Icon(Icons.logout),
            label: const Text('Sair'),
          ),
        ],
      ),
      children: [
        Text(
          'Como você vai usar o SportLeague?',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 16),
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_askName) ...[
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Nome completo'),
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.name],
                  validator: Validators.fullName,
                ),
                const SizedBox(height: 24),
              ],
              RoleSelector(onSaved: (role) => _role = role),
            ],
          ),
        ),
        const SizedBox(height: 24),
        LoadingButton(
          label: 'Continuar',
          loading: _loading,
          onPressed: _submit,
        ),
      ],
    );
  }
}
