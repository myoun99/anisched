/// The first frames: the app's name and a small spinner on the theme's
/// page colour while the document, its reader and the fonts get ready —
/// the same look the web page shows before Flutter's first frame, so one
/// runs into the other without a flash. Then the app itself.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'theme.dart';

class AppStart extends StatefulWidget {
  const AppStart({super.key, required this.load});

  /// Gets everything ready and gives the app to show.
  final Future<Widget> Function() load;

  @override
  State<AppStart> createState() => _AppStartState();
}

class _AppStartState extends State<AppStart> {
  Widget? _app;

  @override
  void initState() {
    super.initState();
    unawaited(
      widget.load().then((app) {
        if (mounted) setState(() => _app = app);
      }),
    );
  }

  @override
  Widget build(BuildContext context) => _app ?? const AppLoading();
}

/// The name and a spinner, light or dark as the system is.
class AppLoading extends StatelessWidget {
  const AppLoading({super.key});

  @override
  Widget build(BuildContext context) {
    final dark =
        MediaQuery.maybePlatformBrightnessOf(context) == Brightness.dark ||
        View.of(context).platformDispatcher.platformBrightness ==
            Brightness.dark;
    final c = dark ? AppColors.dark : AppColors.light;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        key: const Key('app-loading'),
        color: c.page,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 14,
            children: [
              Text(
                'Anisched',
                style: TextStyle(
                  fontSize: 15,
                  color: c.faint,
                  decoration: TextDecoration.none,
                ),
              ),
              SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: c.faint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
