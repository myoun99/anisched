import 'package:flutter/material.dart';

/// Colours that sit outside Material's scheme: work statuses and the
/// neutrals the mock-ups use. Read with `AppColors.of(context)`.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.page,
    required this.panel,
    required this.panelAlt,
    required this.line,
    required this.muted,
    required this.faint,
    required this.selected,
    required this.hover,
    required this.scrollThumb,
    required this.scrollTrack,
    required this.received,
    required this.working,
    required this.submitted,
    required this.retake,
    required this.done,
  });

  final Color page;
  final Color panel;
  final Color panelAlt;
  final Color line;
  final Color muted;
  final Color faint;

  /// Fill for the selected item. Selection is shown by colour only.
  final Color selected;
  final Color hover;
  final Color scrollThumb;
  final Color scrollTrack;

  // Status colours: received → working → submitted → retake → done.
  final Color received;
  final Color working;
  final Color submitted;
  final Color retake;
  final Color done;

  static const light = AppColors(
    page: Color(0xFFE9ECF1),
    panel: Color(0xFFFFFFFF),
    panelAlt: Color(0xFFF5F7FA),
    line: Color(0xFFDDE1E8),
    muted: Color(0xFF687184),
    faint: Color(0xFF9AA2B1),
    selected: Color(0xFFDBE5FF),
    hover: Color(0xFFEEF2F8),
    scrollThumb: Color(0xFFB4BCCB),
    scrollTrack: Color(0xFFECEFF3),
    received: Color(0xFF8E97A7),
    working: Color(0xFF2A6BE0),
    submitted: Color(0xFFC08410),
    retake: Color(0xFFD2433B),
    done: Color(0xFF2C9558),
  );

  static const dark = AppColors(
    page: Color(0xFF101318),
    panel: Color(0xFF1A1E26),
    panelAlt: Color(0xFF20252E),
    line: Color(0xFF2D333E),
    muted: Color(0xFF949DB0),
    faint: Color(0xFF6C7486),
    selected: Color(0xFF283A66),
    hover: Color(0xFF232935),
    scrollThumb: Color(0xFF4A5263),
    scrollTrack: Color(0xFF1F242C),
    received: Color(0xFF7F889A),
    working: Color(0xFF5B8FF0),
    submitted: Color(0xFFE0A63A),
    retake: Color(0xFFEE6A62),
    done: Color(0xFF4CBA7B),
  );

  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>() ?? light;

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      page: l(page, other.page),
      panel: l(panel, other.panel),
      panelAlt: l(panelAlt, other.panelAlt),
      line: l(line, other.line),
      muted: l(muted, other.muted),
      faint: l(faint, other.faint),
      selected: l(selected, other.selected),
      hover: l(hover, other.hover),
      scrollThumb: l(scrollThumb, other.scrollThumb),
      scrollTrack: l(scrollTrack, other.scrollTrack),
      received: l(received, other.received),
      working: l(working, other.working),
      submitted: l(submitted, other.submitted),
      retake: l(retake, other.retake),
      done: l(done, other.done),
    );
  }
}

/// Font stack: BIZ UDPGothic for Latin and Japanese, Nanum Gothic for Hangul.
abstract final class AppFonts {
  static const family = 'BIZUDPGothic';
  static const fallback = <String>['NanumGothic'];
}

abstract final class AppTheme {
  static const _accentLight = Color(0xFF2A57C9);
  static const _accentDark = Color(0xFF7F9DFF);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final c = isDark ? AppColors.dark : AppColors.light;
    final accent = isDark ? _accentDark : _accentLight;
    final ink = isDark ? const Color(0xFFE5E8EE) : const Color(0xFF1C2230);
    final scheme =
        ColorScheme.fromSeed(
          seedColor: accent,
          brightness: brightness,
        ).copyWith(
          primary: accent,
          onPrimary: c.panel,
          surface: c.panel,
          onSurface: ink,
          outline: c.line,
          outlineVariant: c.line,
        );
    final base = ThemeData(
      colorScheme: scheme,
      brightness: brightness,
      fontFamily: AppFonts.family,
      fontFamilyFallback: AppFonts.fallback,
      scaffoldBackgroundColor: c.panelAlt,
      dividerColor: c.line,
      extensions: [c],
      scrollbarTheme: ScrollbarThemeData(
        thumbVisibility: const WidgetStatePropertyAll(true),
        trackVisibility: const WidgetStatePropertyAll(true),
        thumbColor: WidgetStatePropertyAll(c.scrollThumb),
        trackColor: WidgetStatePropertyAll(c.scrollTrack),
        thickness: const WidgetStatePropertyAll(8),
        radius: const Radius.circular(4),
      ),
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(bodyColor: ink, displayColor: ink),
    );
  }
}

/// Scrollbars are always visible, on every platform and input device.
class AlwaysScrollbarBehavior extends MaterialScrollBehavior {
  const AlwaysScrollbarBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return Scrollbar(
      controller: details.controller,
      thumbVisibility: true,
      trackVisibility: true,
      child: child,
    );
  }
}
