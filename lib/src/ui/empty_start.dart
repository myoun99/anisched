/// What a view shows before the document has any work: a way in (register)
/// and, where offered (the web preview), the sample data to look around.
library;

import 'package:flutter/material.dart';

import 'text/strings.dart';
import 'theme.dart';

class EmptyStart extends StatelessWidget {
  const EmptyStart({super.key, required this.onRegister, this.onSample});

  final VoidCallback onRegister;

  /// Fills the document with example work; null hides the button.
  final VoidCallback? onSample;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ColoredBox(
      color: c.panel,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 14,
            children: [
              Icon(Icons.inbox_outlined, size: 40, color: c.faint),
              Text(
                S.emptyStart.t,
                textAlign: TextAlign.center,
                style: TextStyle(color: c.muted),
              ),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    key: const Key('empty-register'),
                    onPressed: onRegister,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(S.register.t),
                  ),
                  if (onSample != null)
                    OutlinedButton.icon(
                      key: const Key('empty-sample'),
                      onPressed: onSample,
                      icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                      label: Text(S.loadSample.t),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
