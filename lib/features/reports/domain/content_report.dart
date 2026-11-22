/// O que pode ser denunciado: conteúdo criado por outras pessoas e visível
/// fora de quem o criou.
enum ReportTarget {
  team('o time'),
  venue('o local'),
  athlete('o atleta');

  const ReportTarget(this.label);

  /// Com artigo, para "Denunciar o time".
  final String label;
}

/// Motivo da denúncia. O [name] é o valor gravado no banco.
enum ReportReason {
  offensive('Ofensivo, discriminatório ou de ódio'),
  sexual('Nudez ou conteúdo sexual'),
  violence('Violência ou ameaça'),
  spam('Spam, golpe ou propaganda'),
  fake('Falso ou se passando por outra pessoa'),
  other('Outro motivo');

  const ReportReason(this.label);

  final String label;
}
