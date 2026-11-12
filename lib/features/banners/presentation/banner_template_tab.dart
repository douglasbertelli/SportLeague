import 'package:flutter/material.dart';

import '../domain/banner_design.dart';
import 'banner_canvas.dart';

/// Onde cada formato costuma ser usado.
String bannerFormatHint(BannerFormat format) => switch (format) {
  BannerFormat.square => 'WhatsApp e posts',
  BannerFormat.feed => 'Feed do Instagram',
  BannerFormat.story => 'Stories e status',
};

/// A aba Modelo do editor: o formato (desenhado na proporção) e os modelos
/// como miniaturas do próprio banner, com o estilo, os textos e as fotos
/// atuais.
class BannerTemplateTab extends StatelessWidget {
  const BannerTemplateTab({
    super.key,
    required this.template,
    required this.style,
    required this.textsOf,
    required this.teamName,
    required this.onTemplate,
    required this.onFormat,
    this.teamLogoUrl,
    this.opponentLogoUrl,
    this.featuredPhoto,
    this.backgroundPhoto,
  });

  final BannerTemplate template;
  final BannerStyle style;

  /// Os textos de cada modelo (os editados ou os iniciais).
  final BannerTexts Function(BannerTemplate template) textsOf;
  final String teamName;
  final String? teamLogoUrl;
  final String? opponentLogoUrl;
  final ImageProvider? featuredPhoto;
  final ImageProvider? backgroundPhoto;
  final ValueChanged<BannerTemplate> onTemplate;
  final ValueChanged<BannerFormat> onFormat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(text, style: theme.textTheme.titleSmall),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        heading('Formato'),
        Row(
          children: [
            for (final format in BannerFormat.values) ...[
              if (format != BannerFormat.values.first) const SizedBox(width: 8),
              Expanded(
                child: _FormatCard(
                  format: format,
                  selected: format == style.format,
                  onTap: () => onFormat(format),
                ),
              ),
            ],
          ],
        ),
        heading('Modelo'),
        LayoutBuilder(
          builder: (context, constraints) {
            // Três por linha no celular; mais em telas largas.
            final columns = (constraints.maxWidth / 120).floor().clamp(3, 6);
            const spacing = 10.0;
            final width =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: 12,
              children: [
                for (final option in BannerTemplate.values)
                  SizedBox(
                    width: width,
                    child: _TemplateThumb(
                      template: option,
                      selected: option == template,
                      onTap: () => onTemplate(option),
                      preview: BannerCanvas(
                        template: option,
                        style: style,
                        texts: textsOf(option),
                        teamName: teamName,
                        teamLogoUrl: teamLogoUrl,
                        opponentLogoUrl: opponentLogoUrl,
                        featuredPhoto: featuredPhoto,
                        backgroundPhoto: backgroundPhoto,
                      ),
                      aspectRatio:
                          style.format.size.width / style.format.size.height,
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// O formato: um retângulo na proporção, o nome e onde se usa.
class _FormatCard extends StatelessWidget {
  const _FormatCard({
    required this.format,
    required this.selected,
    required this.onTap,
  });

  final BannerFormat format;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const height = 46.0;
    final width = height * format.size.width / format.size.height;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Formato ${format.label} ${format.ratio}',
      excludeSemantics: true,
      child: Material(
        color: selected ? scheme.secondaryContainer : scheme.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected ? scheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            child: Column(
              children: [
                SizedBox(
                  height: height,
                  child: Center(
                    child: Container(
                      width: width,
                      height: height,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: selected ? scheme.primary : scheme.outline,
                          width: 2,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        format.ratio,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(format.label, style: theme.textTheme.labelLarge),
                Text(
                  bannerFormatHint(format),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// O modelo como miniatura do banner, com o nome embaixo.
class _TemplateThumb extends StatelessWidget {
  const _TemplateThumb({
    required this.template,
    required this.selected,
    required this.onTap,
    required this.preview,
    required this.aspectRatio,
  });

  final BannerTemplate template;
  final bool selected;
  final VoidCallback onTap;
  final Widget preview;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Modelo ${template.label}',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected ? scheme.primary : scheme.outlineVariant,
                  width: selected ? 3 : 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(selected ? 9 : 11),
                child: AspectRatio(
                  aspectRatio: aspectRatio,
                  // Só a imagem: o toque vai para o cartão e a leitura de tela
                  // não lê os textos da miniatura.
                  child: AbsorbPointer(
                    child: ExcludeSemantics(child: FittedBox(child: preview)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  template.icon,
                  size: 16,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    template.label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: selected ? scheme.primary : null,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            Text(
              template.description,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
