import 'package:flutter/material.dart';

/// Layout padrão de formulários: rolável, centralizado e com largura máxima.
class FormPage extends StatelessWidget {
  const FormPage({super.key, required this.children, this.appBar});

  final List<Widget> children;
  final PreferredSizeWidget? appBar;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBar,
      body: SafeArea(
        child: Center(
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
