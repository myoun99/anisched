import 'package:flutter/material.dart';

import '../core/clock.dart';
import '../core/size_class.dart';
import '../models/progress.dart';
import '../services/catalogue_store.dart';
import 'theme.dart';
import 'views/sheet_view.dart';

/// The four ways of looking at the same work. All four stay in the app;
/// the user switches between them.
enum AppView {
  board('보드'),
  timeline('타임라인'),
  sheet('시트'),
  today('오늘');

  const AppView(this.label);

  final String label;
}

/// App frame: a top bar, the current view, and the view switcher — in the
/// top bar on medium and wide screens, along the bottom on narrow ones.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    this.initialView = AppView.board,
    this.store,
    this.clock = systemClock,
  });

  final AppView initialView;

  /// The user's catalogue; null shows empty views.
  final CatalogueStore? store;

  /// Source of "now" for deadlines; injectable for tests.
  final Clock clock;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late AppView _view = widget.initialView;
  late final List<PartGroup> _groups = widget.store?.partGroups() ?? const [];
  late final int _dayStart = widget.store?.settings.dayStartMinutes ?? 0;

  void _select(AppView v) {
    if (v != _view) setState(() => _view = v);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = ScreenLayout.of(
          constraints.maxWidth,
          constraints.maxHeight,
        );
        final narrow = layout.size == SizeClass.narrow;
        final switcher = ViewSwitcher(
          key: Key(narrow ? 'view-switch-bottom' : 'view-switch-top'),
          current: _view,
          onSelect: _select,
          expand: narrow,
        );
        return Scaffold(
          body: SafeArea(
            bottom: !narrow,
            child: Column(
              children: [
                _TopBar(trailing: narrow ? null : switcher),
                Expanded(
                  child: IndexedStack(
                    index: _view.index,
                    sizing: StackFit.expand,
                    children: [
                      for (final v in AppView.values)
                        if (v == AppView.sheet)
                          SheetView(
                            parts: _groups,
                            now: widget.clock(),
                            dayStartMinutes: _dayStart,
                            layout: layout,
                            paceOf: widget.store?.paceOf,
                          )
                        else
                          ViewSlot(view: v, layout: layout),
                    ],
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: narrow ? _BottomBar(child: switcher) : null,
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({this.trailing});

  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.panel,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: SizedBox(
        height: 52,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              const Text(
                'Anisched',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.panel,
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: SizedBox(height: 44, child: child),
        ),
      ),
    );
  }
}

/// Row of view buttons. The current one is marked by its fill colour only.
class ViewSwitcher extends StatelessWidget {
  const ViewSwitcher({
    super.key,
    required this.current,
    required this.onSelect,
    this.expand = false,
  });

  final AppView current;
  final ValueChanged<AppView> onSelect;

  /// Stretch the buttons to share the full width (bottom bar).
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final buttons = [
      for (final v in AppView.values)
        _ViewButton(
          key: Key('view-tab-${v.name}'),
          view: v,
          selected: v == current,
          onTap: () => onSelect(v),
        ),
    ];
    return Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      spacing: 4,
      children: [
        for (final b in buttons)
          if (expand) Expanded(child: b) else b,
      ],
    );
  }
}

class _ViewButton extends StatelessWidget {
  const _ViewButton({
    super.key,
    required this.view,
    required this.selected,
    required this.onTap,
  });

  final AppView view;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final ink = Theme.of(context).colorScheme.onSurface;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? c.selected : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          hoverColor: c.hover,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40, minWidth: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Center(
                widthFactor: 1,
                child: Text(
                  view.label,
                  style: TextStyle(
                    fontSize: 14,
                    color: selected ? ink : c.muted,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Space reserved for one view until it is built from the data lane's
/// models. It shows only the view's name.
class ViewSlot extends StatelessWidget {
  const ViewSlot({super.key, required this.view, required this.layout});

  final AppView view;
  final ScreenLayout layout;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ColoredBox(
      color: c.panelAlt,
      child: Center(
        child: Text(view.label, style: TextStyle(fontSize: 20, color: c.faint)),
      ),
    );
  }
}
