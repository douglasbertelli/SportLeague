import 'package:flutter/material.dart';

/// Layout padrão de formulários: rolável, centralizado e com largura máxima.
class FormPage extends StatelessWidget {
  const FormPage({
    super.key,
    required this.children,
    this.appBar,
    this.alignTop = false,
  });

  final List<Widget> children;
  final PreferredSizeWidget? appBar;

  /// Conteúdo no topo em vez de centralizado na vertical (formulários em
  /// abas, em que cada aba tem uma altura).
  final bool alignTop;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBar,
      body: SafeArea(
        child: Align(
          alignment: alignTop ? Alignment.topCenter : Alignment.center,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
