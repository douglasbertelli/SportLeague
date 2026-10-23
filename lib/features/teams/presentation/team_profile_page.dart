import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_sheet.dart';
import '../data/team_repository.dart';
import '../domain/team.dart';
import 'team_logo.dart';

/// Perfil de um time da plataforma, para o adversário: capa, dados, mando,
/// contatos e as fotos dos uniformes (para saber as cores da camisa).
class TeamProfilePage extends ConsumerWidget {
  const TeamProfilePage({super.key, required this.teamId});

  final String teamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final team = ref.watch(teamByIdProvider(teamId));
    return Scaffold(
      appBar: AppBar(title: Text(team.value?.name ?? 'Time')),
      body: team.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: TextButton.icon(
            onPressed: () => ref.invalidate(teamByIdProvider(teamId)),
            icon: const Icon(Icons.refresh),
            label: const Text('Erro ao carregar o time. Tentar novamente'),
          ),
        ),
        data: (team) => team == null
            ? const Center(child: Text('Este time não existe mais.'))
            : _Profile(team: team),
      ),
    );
  }
}

class _Profile extends StatelessWidget {
  const _Profile({required this.team});

  final Team team;

  void _showImage(BuildContext context, String url, String label) {
    showAppSheet<void>(
      context,
      builder: (context) => AppSheet(
        title: label,
        body: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Semantics(
            label: label,
            image: true,
            // Pinça para ampliar.
            child: InteractiveViewer(
              child: Image.network(
                url,
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.broken_image_outlined, size: 64),
              ),
            ),
          ),
        ),
        actions: const [SheetBackButton(label: 'Fechar')],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final mutedStyle = theme.textTheme.bodyMedium?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final foundedOn = team.foundedOn;
    final contacts = [
      if (team.phone case final phone?)
        (Icons.phone_outlined, 'Telefone', formatPhone(phone)),
      if (team.instagram case final instagram?)
        (Icons.camera_alt_outlined, 'Instagram', '@$instagram'),
      if (team.facebook case final facebook?)
        (Icons.facebook, 'Facebook', facebook),
      if (team.youtube case final youtube?)
        (Icons.smart_display_outlined, 'YouTube', youtube),
      if (team.website case final website?) (Icons.language, 'Site', website),
    ];

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: switch (team.coverUrl) {
            final url? => Semantics(
              label: 'Capa do ${team.name}',
              image: true,
              child: Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    ColoredBox(color: colors.surfaceContainerHigh),
              ),
            ),
            null => ColoredBox(
              color: colors.surfaceContainerHigh,
              child: Icon(
                Icons.shield_outlined,
                size: 64,
                color: colors.onSurfaceVariant,
              ),
            ),
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            children: [
              TeamLogo(team: team, radius: 28),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(team.name, style: theme.textTheme.titleLarge),
                    Text(team.summary, style: mutedStyle),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        ListTile(
          leading: const Icon(Icons.stadium_outlined),
          title: Text('Joga como: ${team.playsAs.label}'),
          subtitle: Text(team.playsAs.description),
        ),
        if (team.location case final location?)
          ListTile(
            leading: const Icon(Icons.location_city_outlined),
            title: Text(location),
          ),
        if (foundedOn != null)
          ListTile(
            leading: const Icon(Icons.cake_outlined),
            title: Text(
              'Fundado em '
              '${MaterialLocalizations.of(context).formatMediumDate(foundedOn)}',
            ),
          ),
        if (team.description case final description?)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(description),
          ),
        if (team.kitUrls.isNotEmpty) ...[
          const _SectionTitle('Uniformes'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.count(
              crossAxisCount: maxKits,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 3 / 4,
              children: [
                for (final (index, url) in team.kitUrls.indexed)
                  Semantics(
                    button: true,
                    label: 'Uniforme ${index + 1}',
                    excludeSemantics: true,
                    child: Material(
                      borderRadius: BorderRadius.circular(12),
                      clipBehavior: Clip.antiAlias,
                      color: colors.surfaceContainerHighest,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            url,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Icon(
                              Icons.broken_image_outlined,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          Material(
                            type: MaterialType.transparency,
                            child: InkWell(
                              onTap: () => _showImage(
                                context,
                                url,
                                'Uniforme ${index + 1}',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (contacts.isNotEmpty) ...[
          const _SectionTitle('Contato'),
          for (final (icon, label, value) in contacts)
            ListTile(
              leading: Icon(icon),
              title: SelectableText(value),
              subtitle: Text(label),
            ),
        ],
      ],
    );
  }
}

/// "(19) 99999-8888" ou "(19) 3333-4444".
String formatPhone(String digits) {
  if (digits.length < 10) return digits;
  final area = digits.substring(0, 2);
  final number = digits.substring(2);
  final split = number.length - 4;
  return '($area) ${number.substring(0, split)}-${number.substring(split)}';
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}
