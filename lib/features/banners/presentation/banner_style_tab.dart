import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../domain/banner_design.dart';
import 'banner_canvas.dart';
import 'banner_photo_tile.dart';

/// Cores oferecidas: as do time primeiro, depois o branco, os pretos e as
/// cores do app.
List<Color> bannerPalette(BannerStyle teamStyle) {
  final colors = <Color>[
    teamStyle.accent,
    teamStyle.background,
    Colors.white,
    const Color(0xFFF2F2F2),
    const Color(0xFF111111),
    Colors.black,
    for (final color in appColors) color.color,
  ];
  final seen = <int>{};
  return [
    for (final color in colors)
      if (seen.add(color.toARGB32())) color,
  ];
}

/// Combinações prontas de fundo, destaque e texto a partir das cores do
/// time.
List<({String label, Color background, Color accent, Color text})>
bannerColorPresets(BannerStyle team) {
  const light = Color(0xFFF2F2F2);
  const dark = Color(0xFF111111);
  // No fundo claro, um destaque claro some: usa o fundo do time.
  final lightAccent = team.accent.computeLuminance() > 0.45
      ? team.background
      : team.accent;
  return [
    (
      label: 'Time',
      background: team.background,
      accent: team.accent,
      text: team.text,
    ),
    (
      label: 'Invertido',
      background: team.accent,
      accent: team.onAccent,
      text: team.onAccent,
    ),
    (label: 'Claro', background: light, accent: lightAccent, text: dark),
    (
      label: 'Escuro',
      background: Colors.black,
      accent: team.accent,
      text: Colors.white,
    ),
    (
      label: 'Mono',
      background: team.background,
      accent: Colors.white,
      text: Colors.white,
    ),
  ];
}

/// Qual cor a paleta está mudando.
enum _ColorTarget {
  background('Fundo'),
  accent('Destaque'),
  text('Texto');

  const _ColorTarget(this.label);

  final String label;
}

/// A aba Estilo do editor: combinações de cores, as três cores (uma paleta
/// só, para a cor escolhida), o desenho e a imagem do fundo, as fontes e o
/// que mostrar.
class BannerStyleTab extends StatefulWidget {
  const BannerStyleTab({
    super.key,
    required this.style,
    required this.teamStyle,
    required this.backgroundPhoto,
    required this.onPickBackground,
    required this.onChanged,
  });

  final BannerStyle style;
  final BannerStyle teamStyle;
  final ImageProvider? backgroundPhoto;
  final VoidCallback onPickBackground;
  final ValueChanged<BannerStyle> onChanged;

  @override
  State<BannerStyleTab> createState() => _BannerStyleTabState();
}

class _BannerStyleTabState extends State<BannerStyleTab> {
  _ColorTarget _colorTarget = _ColorTarget.background;
  bool _titleFont = true;

  BannerStyle get _style => widget.style;

  void _change(BannerStyle style) => widget.onChanged(style);

  Color _colorOf(_ColorTarget target) => switch (target) {
    _ColorTarget.background => _style.background,
    _ColorTarget.accent => _style.accent,
    _ColorTarget.text => _style.text,
  };

  void _setColor(Color color) => _change(switch (_colorTarget) {
    _ColorTarget.background => _style.copyWith(background: color),
    _ColorTarget.accent => _style.copyWith(accent: color),
    _ColorTarget.text => _style.copyWith(text: color),
  });

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
        heading('Combinações'),
        SizedBox(
          height: 76,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final preset in bannerColorPresets(widget.teamStyle))
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _PresetCard(
                    label: preset.label,
                    colors: [preset.background, preset.accent, preset.text],
                    selected:
                        preset.background == _style.background &&
                        preset.accent == _style.accent &&
                        preset.text == _style.text,
                    onTap: () => _change(
                      _style.copyWith(
                        background: preset.background,
                        accent: preset.accent,
                        text: preset.text,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),

        heading('Cores'),
        Row(
          children: [
            for (final target in _ColorTarget.values) ...[
              if (target != _ColorTarget.background) const SizedBox(width: 8),
              Expanded(
                child: _ColorSlot(
                  label: target.label,
                  color: _colorOf(target),
                  selected: target == _colorTarget,
                  onTap: () => setState(() => _colorTarget = target),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        _ColorRow(
          label: 'Cor ${_colorTarget.label.toLowerCase()}',
          colors: bannerPalette(widget.teamStyle),
          selected: _colorOf(_colorTarget),
          onSelected: _setColor,
        ),

        heading('Fundo'),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: BannerPattern.values.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final pattern = BannerPattern.values[index];
              return _PatternThumb(
                style: _style.copyWith(pattern: pattern),
                selected: pattern == _style.pattern,
                onTap: () => _change(_style.copyWith(pattern: pattern)),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        BannerPhotoTile(
          photo: widget.backgroundPhoto,
          icon: Icons.wallpaper_outlined,
          title: 'Imagem de fundo',
          emptySubtitle: 'Uma foto atrás de tudo, escurecida',
          onTap: widget.onPickBackground,
        ),
        if (widget.backgroundPhoto != null)
          _LabeledSlider(
            label: 'Escurecer',
            value: _style.backgroundDim,
            max: 0.9,
            valueLabel: '${(_style.backgroundDim * 100).round()}%',
            onChanged: (value) =>
                _change(_style.copyWith(backgroundDim: value)),
          ),

        heading('Fontes'),
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: true, label: Text('Título')),
            ButtonSegment(value: false, label: Text('Textos')),
          ],
          selected: {_titleFont},
          onSelectionChanged: (selected) =>
              setState(() => _titleFont = selected.first),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 76,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: BannerFont.values.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final font = BannerFont.values[index];
              final current = _titleFont ? _style.titleFont : _style.bodyFont;
              return _FontCard(
                font: font,
                selected: font == current,
                onTap: () => _change(
                  _titleFont
                      ? _style.copyWith(titleFont: font)
                      : _style.copyWith(bodyFont: font),
                ),
              );
            },
          ),
        ),
        _LabeledSlider(
          label: 'Tamanho',
          value: _titleFont ? _style.titleScale : _style.bodyScale,
          min: BannerStyle.minScale,
          max: BannerStyle.maxScale,
          divisions: 14,
          valueLabel:
              '${((_titleFont ? _style.titleScale : _style.bodyScale) * 100).round()}%',
          onChanged: (value) => _change(
            _titleFont
                ? _style.copyWith(titleScale: value)
                : _style.copyWith(bodyScale: value),
          ),
        ),

        heading('Mostrar'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilterChip(
              avatar: const Icon(Icons.shield_outlined),
              label: const Text('Escudos'),
              selected: _style.showLogo,
              onSelected: (value) => _change(_style.copyWith(showLogo: value)),
            ),
            FilterChip(
              avatar: const Icon(Icons.verified_outlined),
              label: const Text('Marca SportLeague'),
              selected: _style.showBrand,
              onSelected: (value) => _change(_style.copyWith(showBrand: value)),
            ),
          ],
        ),
      ],
    );
  }
}

/// Uma combinação: as três cores em faixas e o nome.
class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.label,
    required this.colors,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final List<Color> colors;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Combinação $label',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          width: 64,
          child: Column(
            children: [
              Container(
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected ? scheme.primary : scheme.outlineVariant,
                    width: selected ? 3 : 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: ColoredBox(
                    color: colors[0],
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(width: 30, height: 6, color: colors[1]),
                          const SizedBox(height: 4),
                          Container(width: 22, height: 4, color: colors[2]),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fundo, destaque ou texto: a cor atual; tocar escolhe qual a paleta muda.
class _ColorSlot extends StatelessWidget {
  const _ColorSlot({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: scheme.outline),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.labelLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ColorRow extends StatelessWidget {
  const _ColorRow({
    required this.label,
    required this.colors,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final List<Color> colors;
  final Color selected;
  final ValueChanged<Color> onSelected;

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outline;
    // A cor atual aparece mesmo se não estiver na paleta (salva antes).
    final options = colors.any((c) => c.toARGB32() == selected.toARGB32())
        ? colors
        : [selected, ...colors];
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final color = options[index];
          final isSelected = color.toARGB32() == selected.toARGB32();
          final check =
              ThemeData.estimateBrightnessForColor(color) == Brightness.dark
              ? Colors.white
              : Colors.black;
          return Semantics(
            button: true,
            selected: isSelected,
            label: '$label ${index + 1}',
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => onSelected(color),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? check : outline,
                    width: isSelected ? 3 : 1,
                  ),
                ),
                child: isSelected
                    ? Icon(Icons.check, size: 20, color: check)
                    : null,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Miniatura do fundo com as cores atuais e o nome embaixo.
class _PatternThumb extends StatelessWidget {
  const _PatternThumb({
    required this.style,
    required this.selected,
    required this.onTap,
  });

  final BannerStyle style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Fundo ${style.pattern.label}',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: SizedBox(
          width: 60,
          child: Column(
            children: [
              Container(
                width: 56,
                height: 70,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected ? scheme.primary : scheme.outlineVariant,
                    width: selected ? 3 : 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  // Desenha no tamanho do banner e encolhe, para a miniatura
                  // ficar igual ao resultado.
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: 180,
                      height: 225,
                      child: CustomPaint(painter: BannerPatternPainter(style)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                style.pattern.label,
                style: Theme.of(context).textTheme.labelSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fonte com "Aa" grande e o nome embaixo.
class _FontCard extends StatelessWidget {
  const _FontCard({
    required this.font,
    required this.selected,
    required this.onTap,
  });

  final BannerFont font;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Fonte ${font.family}',
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
          child: SizedBox(
            width: 84,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Aa',
                  style: font.apply(
                    TextStyle(fontSize: 26, color: scheme.onSurface),
                  ),
                ),
                const SizedBox(height: 2),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    font.family,
                    style: Theme.of(context).textTheme.labelSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.label,
    required this.value,
    required this.valueLabel,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.divisions,
  });

  final String label;
  final double value;
  final String valueLabel;
  final ValueChanged<double> onChanged;
  final double min;
  final double max;
  final int? divisions;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(
        width: 84,
        child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
      ),
      Expanded(
        child: Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          label: valueLabel,
          onChanged: onChanged,
        ),
      ),
      SizedBox(
        width: 44,
        child: Text(
          valueLabel,
          textAlign: TextAlign.end,
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ),
    ],
  );
}
