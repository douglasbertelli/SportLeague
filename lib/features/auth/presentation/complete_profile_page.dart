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

/// Primeiro acesso de contas criadas com Google ou Apple: confirma o nome e
/// escolhe o tipo de perfil, que o login social não informa.
class CompleteProfilePage extends ConsumerStatefulWidget {
  const CompleteProfilePage({super.key});

  @override
  ConsumerState<CompleteProfilePage> createState() =>
      _CompleteProfilePageState();
}

class _CompleteProfilePageState extends ConsumerState<CompleteProfilePage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  UserRole? _role;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final metadataName = ref
        .read(supabaseClientProvider)
        .auth
        .currentUser
        ?.userMetadata?['full_name'];
    _nameController = TextEditingController(
      text: metadataName is String && metadataName.trim().isNotEmpty
          ? metadataName.trim()
          : ref.read(currentProfileProvider).value?.fullName,
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
            fullName: _nameController.text,
            role: _role!,
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
        title: const Text('Complete seu cadastro'),
        actions: [
          TextButton(
            onPressed: _loading
                ? null
                : () => ref.read(authRepositoryProvider).signOut(),
            child: const Text('Sair'),
          ),
        ],
      ),
      children: [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Nome completo'),
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.name],
                validator: Validators.fullName,
              ),
              const SizedBox(height: 24),
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
