import 'package:flutter/material.dart';

import 'text/strings.dart';

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
    required this.restDay,
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

  /// Days off on the charts — rest weekdays, the user's own days off and
  /// holidays alike (the user's rule: one colour): a faint wash over the
  /// column, the full colour on the day's number. Today keeps its red.
  final Color restDay;

  // Restrained neutrals with a faint cool bias, one indigo accent; status
  // colours tuned so each reads on both grounds (checked ≥ 3:1 against
  // the panel in both modes).
  static const light = AppColors(
    page: Color(0xFFF4F5F7),
    panel: Color(0xFFFFFFFF),
    panelAlt: Color(0xFFF8F9FA),
    line: Color(0xFFE4E6EB),
    muted: Color(0xFF666B78),
    faint: Color(0xFF9CA1AC),
    selected: Color(0xFFE6EAFB),
    hover: Color(0xFFF1F2F5),
    scrollThumb: Color(0xFFC3C7D0),
    scrollTrack: Color(0x00000000),
    received: Color(0xFF8A909C),
    working: Color(0xFF3B6FE0),
    submitted: Color(0xFFB7791F),
    retake: Color(0xFFD1453B),
    done: Color(0xFF2F9461),
    restDay: Color(0xFF3B78E0),
  );

  static const dark = AppColors(
    page: Color(0xFF0E0F12),
    panel: Color(0xFF16171B),
    panelAlt: Color(0xFF1B1D22),
    line: Color(0xFF2A2C33),
    muted: Color(0xFF8F94A0),
    faint: Color(0xFF5E636D),
    selected: Color(0xFF262B44),
    hover: Color(0xFF1F2126),
    scrollThumb: Color(0xFF3B3E47),
    scrollTrack: Color(0x00000000),
    received: Color(0xFF8E94A1),
    working: Color(0xFF6E97F5),
    submitted: Color(0xFFE0A642),
    retake: Color(0xFFF0706A),
    done: Color(0xFF52C08A),
    restDay: Color(0xFF6E9EF5),
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
      restDay: l(restDay, other.restDay),
    );
  }
}

/// Light, dark or the system's choice. Kept while the app runs; saved
/// with the device settings once the data lane stores it.
final themeModeSetting = ValueNotifier<ThemeMode>(ThemeMode.system);

/// Font stack: BIZ UDPGothic for Latin and Japanese, Nanum Gothic for
/// Hangul, Noto Sans SC for Simplified Chinese. In Chinese, Noto Sans SC
/// leads so shared Han characters take their Chinese forms.
abstract final class AppFonts {
  static const family = 'BIZUDPGothic';
  static const fallback = <String>['NanumGothic', 'NotoSansSC'];

  static String familyFor(Lang lang) =>
      lang == Lang.zhHans ? 'NotoSansSC' : family;

  static List<String> fallbackFor(Lang lang) =>
      lang == Lang.zhHans ? const ['BIZUDPGothic', 'NanumGothic'] : fallback;
}

abstract final class AppTheme {
  static const _accentLight = Color(0xFF4F5BD5);
  static const _accentDark = Color(0xFF8D96FA);

  static ThemeData light([Lang? lang]) => _build(Brightness.light, lang);
  static ThemeData dark([Lang? lang]) => _build(Brightness.dark, lang);

  static ThemeData _build(Brightness brightness, Lang? lang) {
    final l = lang ?? appLang.value;
    final isDark = brightness == Brightness.dark;
    final c = isDark ? AppColors.dark : AppColors.light;
    final accent = isDark ? _accentDark : _accentLight;
    final ink = isDark ? const Color(0xFFE6E7EB) : const Color(0xFF1A1C22);
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
      fontFamily: AppFonts.familyFor(l),
      fontFamilyFallback: AppFonts.fallbackFor(l),
      scaffoldBackgroundColor: c.panelAlt,
      dividerColor: c.line,
      extensions: [c],
      scrollbarTheme: ScrollbarThemeData(
        thumbVisibility: const WidgetStatePropertyAll(true),
        trackVisibility: const WidgetStatePropertyAll(true),
        thumbColor: WidgetStatePropertyAll(c.scrollThumb),
        trackColor: WidgetStatePropertyAll(c.scrollTrack),
        trackBorderColor: const WidgetStatePropertyAll(Color(0x00000000)),
        thickness: const WidgetStatePropertyAll(6),
        radius: const Radius.circular(3),
      ),
      splashFactory: NoSplash.splashFactory,
      highlightColor: c.hover,
      hoverColor: c.hover,
      popupMenuTheme: PopupMenuThemeData(
        color: c.panel,
        surfaceTintColor: const Color(0x00000000),
        elevation: 8,
        shadowColor: const Color(0x33000000),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: c.line),
        ),
        textStyle: TextStyle(fontSize: 13, color: ink),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.panel,
        surfaceTintColor: const Color(0x00000000),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: c.line),
        ),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: c.panel,
        surfaceTintColor: const Color(0x00000000),
        headerBackgroundColor: c.panelAlt,
        headerForegroundColor: ink,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: c.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: c.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: accent, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          // The app's fonts named again: a button's own text style
          // replaces the theme's, family and fallbacks included.
          textStyle: TextStyle(
            fontWeight: FontWeight.w700,
            fontFamily: AppFonts.familyFor(l),
            fontFamilyFallback: AppFonts.fallbackFor(l),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          side: BorderSide(color: c.line),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        side: BorderSide(color: c.faint, width: 1.4),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: ink,
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: TextStyle(color: c.panel, fontSize: 12),
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
